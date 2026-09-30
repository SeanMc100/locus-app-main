import Foundation
import FoundationModels
import NaturalLanguage

enum ExtractionError: LocalizedError {
    case unavailable(String)
    case nothingFound
    case blocked
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        case .nothingFound: "Apple Intelligence couldn't find any distinct items in this entry. Try writing a bit more, or add items by hand."
        case .blocked: "Apple Intelligence declined to process this entry. You can still add items by hand."
        case .failed(let message): message
        }
    }
}

/// Uses the on-device Apple Intelligence model to pull discrete items
/// (worries, situations, tasks, thoughts) out of a free-form journal entry.
/// It deliberately does not classify them; the user does that.
enum ItemExtractor {

    /// nil when the model is ready; otherwise a user-facing reason.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This device doesn't support Apple Intelligence. Locus needs an iPhone 15 Pro or newer."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in Settings > Apple Intelligence & Siri, then try again."
            case .modelNotReady:
                return "Apple Intelligence is still getting ready (it may be downloading). Try again in a few minutes."
            @unknown default:
                return "Apple Intelligence isn't available right now."
            }
        }
    }

    private static let instructions = """
    You help people practice separating what they can control from what they can't. \
    You will receive a private journal entry. Extract the distinct concerns, worries, \
    situations, tasks, goals, and thoughts the writer mentions.

    Rules:
    - Phrase each item as a "Whether..." or "Whether or not..." clause, so it \
    reads as a proposition someone could judge as in or out of their control \
    (e.g. "Whether I finish this on time", not "I need to finish this on time"; \
    "Whether people like me", not "People might not like me").
    - Write each item as a short, self-contained phrase of 3 to 12 words.
    - Keep the writer's perspective (use "I" and "my").
    - One idea per item. Merge only true duplicates (the same concern said twice). \
    Do not merge several distinct concerns into one broad or vague item just \
    because they're related or the entry ties them together — prefer more, \
    specific items over fewer, general ones.
    - Include things the writer could act on AND things outside their influence, \
    but do not label, judge, or sort them.
    - As well as what's explicitly stated, include the specific outcome the writer \
    seems to be hoping for or afraid of, if the entry clearly implies one, even if \
    they never wrote it in those words (e.g. an entry about feeling unlovable \
    implies the item "whether someone will love me"). Also include the specific \
    choice, action, or pattern the writer describes making or repeating, not just \
    how they feel about it (e.g. an entry about turning to a habit instead of \
    facing a need implies an item like "whether I turn to [that habit] instead of \
    dealing with [the need]"). Only surface an implied item when the entry makes \
    it reasonably clear — don't invent concerns the entry doesn't support, and \
    don't guess at causes, motives, or reasons why the writer feels something.
    - Do not give advice.
    - Output only the list: one item per line, each line starting with "- ".
    """

    /// Rough per-request character budget, leaving room in the
    /// on-device model's context window for instructions and output.
    private static let chunkLimit = 3000

    static func extract(from text: String) async throws -> [String] {
        if let reason = unavailableReason { throw ExtractionError.unavailable(reason) }

        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        var results: [String] = []
        var blockedChunks = 0
        let chunks = chunk(text, limit: chunkLimit)

        for piece in chunks {
            do {
                results += try await extractChunk(piece, model: model)
            } catch ExtractionError.blocked {
                blockedChunks += 1
            }
        }

        let unique = dedupe(results)
        if unique.isEmpty {
            throw blockedChunks == chunks.count ? ExtractionError.blocked : ExtractionError.nothingFound
        }
        return unique
    }

    private static func extractChunk(_ piece: String, model: SystemLanguageModel) async throws -> [String] {
        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            let response = try await session.respond(
                to: "Journal entry:\n\"\"\"\n\(piece)\n\"\"\"",
                options: GenerationOptions(temperature: 0.3)
            )
            return parse(response.content)
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize where piece.count > 600:
                // Split in half and try again.
                let halves = chunk(piece, limit: piece.count / 2)
                var items: [String] = []
                for half in halves { items += try await extractChunk(half, model: model) }
                return items
            case .guardrailViolation, .refusal:
                throw ExtractionError.blocked
            default:
                throw ExtractionError.failed("Apple Intelligence ran into a problem: \(error.localizedDescription)")
            }
        }
    }

    /// Turns the model's bulleted output into clean item strings.
    static func parse(_ output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .map { line -> String in
                var s = line.trimmingCharacters(in: .whitespaces)
                // Strip bullets like "- ", "• ", "* ", "1. ", "2) ".
                if let range = s.range(of: #"^(\s*([-•*–]|\d+[.)])\s*)+"#, options: .regularExpression) {
                    s.removeSubrange(range)
                }
                s = s.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if s.hasSuffix(".") { s.removeLast() }
                return s
            }
            .filter { !$0.isEmpty && !$0.hasSuffix(":") && $0.count <= 200 }
    }

    private static func dedupe(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { item in
            let key = item.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            return seen.insert(key).inserted
        }
    }

    /// Splits text into pieces of at most `limit` characters on sentence
    /// boundaries, hard-splitting any single sentence that is itself over
    /// `limit` (e.g. unpunctuated dictation) at word breaks.
    static func chunk(_ text: String, limit: Int) -> [String] {
        guard text.count > limit else { return [text] }

        var units: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            units += hardSplit(String(text[range]), limit: limit)
            return true
        }

        var chunks: [String] = []
        var current = ""
        for unit in units {
            if current.count + unit.count > limit, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += unit
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chunks.append(current) }
        return chunks
    }

    /// Breaks `text` into pieces of at most `limit` characters, preferring
    /// the last whitespace before each cut. Guarantees every piece is
    /// shorter than an over-limit input, so recursive retries terminate.
    private static func hardSplit(_ text: String, limit: Int) -> [String] {
        var pieces: [String] = []
        var rest = Substring(text)
        while rest.count > limit {
            let cut = rest.index(rest.startIndex, offsetBy: limit)
            let split = rest[..<cut].lastIndex(where: \.isWhitespace).map { rest.index(after: $0) } ?? cut
            pieces.append(String(rest[..<split]))
            rest = rest[split...]
        }
        if !rest.isEmpty { pieces.append(String(rest)) }
        return pieces
    }
}
