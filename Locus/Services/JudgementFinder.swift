import Foundation
import FoundationModels
import NaturalLanguage
import SwiftUI

/// Uses the on-device model to find the judgements a journal entry adds on
/// top of what actually happened (verdicts, predictions, labels, …), as
/// exact quotes from the entry so they can be highlighted in place. It only
/// finds them; replacing them is the user's job.
///
/// Two passes, because the small on-device model is good at recall but
/// sloppy on its own: (1) find candidate quotes in the whole entry, then
/// (2) check each candidate on its own, dropping feelings, self-observations
/// ("I blame myself") and plain events
/// and trimming it to just the judgement. Tested 2026-09-25: asking for a
/// kind label per judgement made both passes worse, as did going sentence
/// by sentence, and asking the checker to split merged judgements.
enum JudgementFinder {

    @Generable
    struct Candidates {
        @Guide(description: "Exact quotes of every judgement in the entry, in order. Empty if none.")
        var judgements: [String]
    }

    @Generable
    enum QuoteType { case judgement, feeling, observation, event }

    @Generable
    struct Check {
        @Guide(description: "judgement if the words claim more than what happened; feeling if they only describe the writer's own emotion, mood, or sensation; observation if they only describe what the writer does in their own head (blaming themselves, replaying, overthinking, worrying); event if they only describe what happened")
        var type: QuoteType
        @Guide(description: "If judgement: the shortest exact part of the quote that is the judgement, copied word for word. Otherwise empty.")
        var core: String
    }

    private static let findInstructions = """
    You help people notice the judgements they add on top of events. You will \
    receive a private journal entry. Quote every phrase where the writer claims \
    more than what actually happened.

    A judgement is one of these:
    - a verdict that something is good, bad, terrible, or pointless ("life sucks")
    - a prediction stated as fact ("I'll be alone forever")
    - a label for a whole person ("I'm such a loser")
    - an all-or-nothing claim ("everyone else has it figured out", "diets never work")
    - a guess about what someone else thinks or feels ("she thinks I'm weird")
    - treating one event as proof of something bigger ("this proves I'm not good enough")
    - a rule about how things must be ("I should be married by now")

    NOT judgements, never quote these:
    - what happened ("I got turned down", "I went for a run")
    - the writer's own feelings, moods, or sensations ("I feel sad", "felt \
    calm", "I'm so happy", "I'm tired", "a bit anxious")
    - the writer noticing what they do in their own head ("I blame myself", \
    "I keep replaying it", "I tend to overthink"). These are honest \
    observations. Only quote a judgement inside them, e.g. in "I blame myself \
    because I'm useless" quote only "I'm useless".

    Example entry: "Work was awful. My boss moved the deadline and I felt \
    stressed. I'm always behind. He probably thinks I'm useless."
    Example output: ["Work was awful", "I'm always behind", "He probably thinks I'm useless"]

    Rules:
    - Copy each quote exactly from the entry. Never reword it.
    - Quote only the judgement words, not the whole sentence. Split two \
    judgements in one sentence into two quotes.
    """

    private static let checkInstructions = """
    You check one quote from a journal entry. Decide what it is:
    - judgement: claims more than what happened, e.g. a verdict ("life sucks"), \
    prediction ("I'll be alone forever"), label ("I'm a loser"), all-or-nothing \
    claim ("nobody cares"), guess at someone's thoughts ("she thinks I'm weird"), \
    treating one event as proof of something bigger, or a rule ("I should be \
    married by now").
    - feeling: only the writer's own emotion, mood, or sensation ("felt calm", \
    "I'm so happy", "a bit anxious", "I feel sad"). "I feel like [a claim]" \
    or "it feels like [a claim]" is a judgement, not a feeling.
    - observation: only the writer noticing what they do in their own head \
    ("I blame myself", "I keep replaying it", "I tend to overthink").
    - event: only what happened ("I got turned down", "5k in 28 min").
    If it's a judgement, also copy the shortest exact part that is the \
    judgement, leaving out any plain event before it.
    Examples:
    "I got turned down and it proves I'm unlovable" -> judgement, core "it proves I'm unlovable"
    "felt calm most of the day" -> feeling
    "I blame myself" -> observation
    "I blame myself because I'm useless" -> judgement, core "I'm useless"
    "I blame myself for ruining everything" -> judgement, core "ruining everything"
    "My boss, who clearly hates me" -> judgement, core "who clearly hates me"
    "it feels like proof nobody cares about me" -> judgement, core "it feels like proof nobody cares about me"
    "He didn't call back, he obviously doesn't care" -> judgement, core "he obviously doesn't care"
    "I feel like a failure" -> judgement, core "I feel like a failure"
    """

    private static let chunkLimit = 3000

    static func find(in text: String) async throws -> [String] {
        if let reason = ItemExtractor.unavailableReason { throw ExtractionError.unavailable(reason) }

        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        var candidates: [String] = []
        // Two find passes, unioned: a single pass randomly omits a clear
        // judgement about a third of the time, and the check pass below
        // filters out anything extra.
        for piece in ItemExtractor.chunk(text, limit: chunkLimit) + ItemExtractor.chunk(text, limit: chunkLimit) {
            let session = LanguageModelSession(model: model, instructions: findInstructions)
            do {
                let response = try await session.respond(
                    to: "Journal entry:\n\"\"\"\n\(piece)\n\"\"\"",
                    generating: Candidates.self,
                    options: GenerationOptions(temperature: 0.2)
                )
                candidates += response.content.judgements.flatMap(sentences)
            } catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .guardrailViolation, .refusal:
                    throw ExtractionError.blocked
                default:
                    throw ExtractionError.failed("Apple Intelligence ran into a problem: \(error.localizedDescription)")
                }
            }
        }

        var seen = Set<String>()
        candidates = candidates.filter { seen.insert(key($0)).inserted }

        var results: [String] = []
        for candidate in candidates {
            if let kept = await check(candidate, model: model) { results.append(kept) }
        }
        // Drop duplicates and any quote contained in a longer one (the two
        // passes often return the same judgement trimmed differently).
        return results.enumerated().filter { i, quote in
            !results.enumerated().contains { j, other in
                j != i && (key(other).contains(key(quote)) && (key(other) != key(quote) || j < i))
            }
        }.map(\.element)
    }

    private static func key(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?\"'"))
    }

    /// The trimmed judgement, or nil if the candidate is a feeling,
    /// observation, or event.
    /// If the check itself fails (e.g. a guardrail trips on one quote), keep
    /// the candidate as-is rather than failing the whole entry.
    private static func check(_ candidate: String, model: SystemLanguageModel) async -> String? {
        let session = LanguageModelSession(model: model, instructions: checkInstructions)
        let edges = CharacterSet(charactersIn: " .,;:!?\"'")
        let trimmed = candidate.trimmingCharacters(in: edges)
        guard let result = try? await session.respond(
            to: "Quote: \"\(candidate)\"",
            generating: Check.self,
            options: GenerationOptions(temperature: 0)
        ).content else { return trimmed }

        guard result.type == .judgement else { return nil }
        let core = result.core.trimmingCharacters(in: edges)
        guard !core.isEmpty, trimmed.localizedCaseInsensitiveContains(core) else { return trimmed }
        guard core.caseInsensitiveCompare(trimmed) != .orderedSame else { return trimmed }

        // The trim sometimes keeps the wrong part (e.g. "I blame myself" out
        // of "I blame myself for ruining everything"). Re-check the trimmed
        // part alone; if it's no longer a judgement, fall back to the whole
        // quote rather than lose a judgement the first check found.
        let recheck = LanguageModelSession(model: model, instructions: checkInstructions)
        let type = try? await recheck.respond(
            to: "Quote: \"\(core)\"",
            generating: Check.self,
            options: GenerationOptions(temperature: 0)
        ).content.type
        return type == nil || type == .judgement ? core : trimmed
    }

    // MARK: - Without judgements

    private static let repairInstructions = """
    You repair one sentence from a private journal entry after some words \
    were cut out of it. Fix only what the cut broke (a dangling joining word, \
    doubled punctuation, a missing comma) so it reads as a normal sentence. \
    Do not add any new words or ideas. Keep every remaining word exactly as \
    written, including spelling, slang, and lowercase. Output only the sentence.
    """

    /// The entry with the judgements cut out, changing as little of the
    /// writer's own wording as possible. Cutting and cleanup are done in
    /// code so nothing gets paraphrased; the model is only asked to repair
    /// a sentence that was cut in the middle, and its repair is rejected if
    /// it introduces any word that wasn't already in the sentence.
    static func withoutJudgements(_ text: String, quotes: [String]) async -> String {
        let cuts = JudgementHighlighter.locate(quotes, in: text).ranges
        guard !cuts.isEmpty else { return text }

        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        var kept: [String] = []
        for sentenceRange in sentenceRanges(in: text) {
            let sentence = String(text[sentenceRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let inside = cuts.compactMap { $0.clamped(to: sentenceRange) }.filter { !$0.isEmpty }
            guard !inside.isEmpty else {
                if !sentence.isEmpty { kept.append(sentence) }
                continue
            }

            var cut = String(text[sentenceRange])
            let offset = text.distance(from: text.startIndex, to: sentenceRange.lowerBound)
            for range in inside.reversed() {
                let lower = cut.index(cut.startIndex, offsetBy: text.distance(from: text.startIndex, to: range.lowerBound) - offset)
                let upper = cut.index(cut.startIndex, offsetBy: text.distance(from: text.startIndex, to: range.upperBound) - offset)
                cut.replaceSubrange(lower..<upper, with: " \u{2063} ")  // invisible marker for the gap
            }
            let (cleaned, cutInMiddle) = tidy(cut, like: sentence)
            guard let cleaned else { continue }  // nothing meaningful left

            if cutInMiddle, let repaired = await repair(cleaned, model: model) {
                kept.append(repaired)
            } else {
                kept.append(cleaned)
            }
        }
        return kept.joined(separator: " ")
    }

    /// Sentence ranges split on terminal punctuation or line breaks.
    /// NLTokenizer misses sentences that start lowercase ("…4 times. my
    /// body…"), which is common in quick journaling.
    private static func sentenceRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            let next = text.index(after: i)
            if c.isNewline || (".!?".contains(c) && (next == text.endIndex || text[next].isWhitespace)) {
                ranges.append(start..<next)
                start = next
            }
            i = next
        }
        if start < text.endIndex { ranges.append(start..<text.endIndex) }
        return ranges
    }

    /// Words left dangling at either side of a cut.
    private static let joiners: Set<String> = ["and", "but", "so", "because", "which", "that", "who", "or", "like", "for", "to", "of", "about", "with", "as", "since", "when", "then", "even", "though", "just", "also"]
    /// Extra words that only dangle at the end of what's left before a cut
    /// ("…instead of prepping, which is [cut]", "…and I [cut]").
    private static let trailingOnly: Set<String> = ["is", "was", "are", "were", "am", "be", "been", "it's", "it\u{2019}s", "i", "i'm", "i\u{2019}m", "im", "it", "feels", "seems", "really", "totally", "very", "such", "a", "the"]

    /// Removes the gap markers and whatever they left dangling. Returns nil
    /// if no real content remains, and whether a gap was mid-sentence
    /// (content on both sides), which may need a model repair.
    private static func tidy(_ cut: String, like original: String) -> (String?, Bool) {
        let marker: Character = "\u{2063}"
        let parts = cut.split(separator: marker, omittingEmptySubsequences: false).map(String.init)
        let edgeJunk = CharacterSet(charactersIn: " ,;:-\u{2013}\u{2014}").union(.whitespacesAndNewlines)
        let terminal = original.last.map { ".!?".contains($0) ? String($0) : "" } ?? ""

        func strip(_ s: String, leading: Bool, trailing: Bool) -> String {
            var words = s.trimmingCharacters(in: edgeJunk).split(separator: " ").map(String.init)
            func bare(_ w: String) -> String { w.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            while trailing, let last = words.last, joiners.contains(bare(last)) || trailingOnly.contains(bare(last)) { words.removeLast() }
            while leading, let first = words.first, joiners.contains(bare(first)) { words.removeFirst() }
            return words.joined(separator: " ").trimmingCharacters(in: edgeJunk.union(CharacterSet(charactersIn: ".!?")))
        }

        // A cut clause set off by commas on both sides ("My manager, [who
        // hates me], said…") closes up with a space; any other mid-sentence
        // gap gets a comma.
        var pieces: [String] = []
        var separators: [String] = []
        for (i, part) in parts.enumerated() {
            let piece = strip(part, leading: i > 0, trailing: i < parts.count - 1)
            guard piece.contains(where: \.isLetter) else { continue }
            if !pieces.isEmpty {
                let before = parts[i - 1].trimmingCharacters(in: .whitespaces)
                let after = part.trimmingCharacters(in: .whitespaces)
                separators.append(before.hasSuffix(",") && after.hasPrefix(",") ? " " : ", ")
            }
            pieces.append(piece)
        }
        guard !pieces.isEmpty,
              pieces.joined(separator: " ").split(separator: " ").count >= 2
        else { return (nil, false) }

        var result = pieces[0]
        for (separator, piece) in zip(separators, pieces.dropFirst()) { result += separator + piece }
        result += terminal
        if original.first?.isUppercase == true, let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }
        return (result, pieces.count > 1)
    }

    /// Asks the model to smooth a sentence cut in the middle; nil (keep the
    /// code-tidied version) if it fails or adds words the writer didn't use.
    private static func repair(_ sentence: String, model: SystemLanguageModel) async -> String? {
        let session = LanguageModelSession(model: model, instructions: repairInstructions)
        guard let output = try? await session.respond(
            to: "Sentence: \"\(sentence)\"",
            options: GenerationOptions(temperature: 0)
        ).content else { return nil }

        let repaired = output.trimmingCharacters(in: CharacterSet(charactersIn: " \"\n"))
        func words(_ s: String) -> [String] {
            s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "\u{2019}" }).map(String.init)
        }
        let allowed = Set(words(sentence))
        let out = words(repaired)
        guard !out.isEmpty, out.allSatisfy(allowed.contains), out.count >= words(sentence).count - 2 else { return nil }
        return repaired
    }

    /// The model sometimes returns several sentences as one quote; split
    /// them so each is checked (and trimmed) on its own.
    private static func sentences(_ quote: String) -> [String] {
        var result: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = quote
        tokenizer.enumerateTokens(in: quote.startIndex..<quote.endIndex) { range, _ in
            let s = quote[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { result.append(s) }
            return true
        }
        return result
    }
}

/// Locates judgement quotes in entry text and renders them highlighted.
/// Matching tolerates case and smart-vs-straight punctuation differences,
/// since the model often normalizes "don’t" to "don't".
enum JudgementHighlighter {

    static let color = Color(red: 1, green: 0.86, blue: 0.35).opacity(0.55)

    /// Non-overlapping ranges for the quotes found in `text`, in text
    /// order, plus the quotes that couldn't be located.
    static func locate(_ quotes: [String], in text: String) -> (ranges: [Range<String.Index>], unmatched: [String]) {
        // One-for-one Character replacement keeps offsets aligned with `text`.
        let haystack = normalize(text)
        var ranges: [Range<String.Index>] = []
        var unmatched: [String] = []

        for quote in quotes {
            let needle = normalize(quote).trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?\"'"))
            guard !needle.isEmpty,
                  let found = haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive])
            else {
                unmatched.append(quote)
                continue
            }
            let start = text.index(text.startIndex, offsetBy: haystack.distance(from: haystack.startIndex, to: found.lowerBound))
            let end = text.index(start, offsetBy: haystack.distance(from: found.lowerBound, to: found.upperBound))
            let range = start..<end
            if !ranges.contains(where: { $0.overlaps(range) }) { ranges.append(range) }
        }
        return (ranges.sorted { $0.lowerBound < $1.lowerBound }, unmatched)
    }

    static func attributed(_ text: String, highlighting quotes: [String]) -> AttributedString {
        var result = AttributedString(text)
        for range in locate(quotes, in: text).ranges {
            if let attributedRange = Range(range, in: result) {
                result[attributedRange].backgroundColor = color
            }
        }
        return result
    }

    private static func normalize(_ s: String) -> String {
        String(s.map { c -> Character in
            switch c {
            case "\u{2018}", "\u{2019}", "\u{02BC}": "'"
            case "\u{201C}", "\u{201D}": "\""
            case "\u{2013}", "\u{2014}": "-"
            default: c
            }
        })
    }
}
