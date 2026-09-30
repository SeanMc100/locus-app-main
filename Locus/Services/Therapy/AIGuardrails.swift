import Foundation

// Foundation-only (compiled into the Mac harness too).

/// Rules for every skills AI call. They're written into each prompt, and
/// enforced here on the output, since a prompt alone can't guarantee them.
enum AIGuardrails {
    /// Included in every prompt's instructions.
    static let rules = """
    Rules you always follow:
    - Ask questions. Never supply answers, balanced thoughts, reframes, \
    conclusions, diagnoses, or evidence on the writer's behalf.
    - Never treat a harsh thought about themselves as a fact, and never try \
    to argue them out of a feeling.
    - Warm, brief, plain language. One question at a time.
    - No clinical diagnosis, no medical or medication advice.
    """

    static let maxQuestionLength = 180

    /// A single, short question the app can show, or nil (the caller then
    /// falls back to the offline question bank).
    static func cleanQuestion(_ raw: String) -> String? {
        var q = raw.trimmed
        let quotes = CharacterSet(charactersIn: "\"'\u{201C}\u{201D}\u{2018}\u{2019}")
        q = q.trimmingCharacters(in: quotes.union(.whitespacesAndNewlines))
        // Drop a leading label the model sometimes adds.
        for prefix in ["Question:", "Q:", "- ", "1. "] where q.hasPrefix(prefix) {
            q = String(q.dropFirst(prefix.count)).trimmed
        }
        guard !q.isEmpty, q.count <= maxQuestionLength, q.hasSuffix("?") else { return nil }
        // One question only.
        guard q.filter({ $0 == "?" }).count == 1 else { return nil }
        guard !q.contains("\n") else { return nil }
        guard !looksLikeRewrite(q), !soundsClinical(q) else { return nil }
        guard !RiskDetector.assess(q).isRisk else { return nil }
        return q
    }

    /// Output that reads like the model supplying the answer: a rewritten
    /// thought, a reframe, reassurance, or a suggested conclusion.
    static func looksLikeRewrite(_ text: String) -> Bool {
        let t = RiskDetector.normalize(text)
        let markers = [
            "a more balanced", "balanced thought", "a better way to", "you could say", "you could think",
            "try thinking", "try telling yourself", "instead think", "instead you", "the truth is",
            "remember that", "remind yourself", "you are not", "you're not", "you are worthy",
            "you are enough", "you're enough", "it's okay to", "reframe", "you should",
            "a healthier", "what if you told yourself", "here's", "here is",
        ]
        return markers.contains { t.contains($0) }
    }

    static func soundsClinical(_ text: String) -> Bool {
        let t = RiskDetector.normalize(text)
        let markers = ["diagnos", "disorder", "medication", "medicine", "prescri", "dosage", "symptom of", "you have depression", "you have anxiety"]
        return markers.contains { t.contains($0) }
    }

    /// Candidate thoughts must be copied from the entry, word for word
    /// (the app highlights the user's own words, never paraphrases).
    static func verbatimSpans(_ candidates: [String], in entry: String, limit: Int = 3) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        let edges = CharacterSet(charactersIn: " .,;:!\"'\u{201C}\u{201D}").union(.whitespacesAndNewlines)
        for raw in candidates {
            let span = raw.trimmingCharacters(in: edges)
            let words = span.split(whereSeparator: \.isWhitespace).count
            guard (2...25).contains(words),
                  let range = entry.range(of: span, options: [.caseInsensitive, .diacriticInsensitive])
            else { continue }
            let exact = String(entry[range])
            let key = exact.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(exact)
            if out.count == limit { break }
        }
        return out
    }

    /// Pattern summaries: short plain statements about the user's own
    /// numbers, no advice, no diagnosis, no verdicts. `source` is the data
    /// the summary was written from: every number in a line must appear in
    /// it (the small model sometimes invents percentages).
    static func cleanSummaryLine(_ raw: String, source: String) -> String? {
        let s = raw.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "-•* "))
        guard !s.isEmpty, s.count <= 200, !soundsClinical(s), !RiskDetector.assess(s).isRisk else { return nil }
        let t = RiskDetector.normalize(s)
        let verdicts = ["you should", "you need to", "improv", "better", "worse", "progress", "great job", "well done", "failure"]
        guard !verdicts.contains(where: { t.contains($0) }) else { return nil }
        if s.contains("%") && !source.contains("%") { return nil }
        let sourceNumbers = Set(numbers(in: source))
        guard numbers(in: s).allSatisfy(sourceNumbers.contains) else { return nil }
        return s
    }

    private static func numbers(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isNumber }).map(String.init)
    }
}
