import Foundation
import FoundationModels

/// Asks one Socratic question about a journal entry: not a coping
/// exercise matched to a mood, but a question that takes something the
/// writer wrote and opens it up ("If you could control your feelings for
/// her, would they still be real?").
///
/// Three on-device calls: (1) understand the entry (tone, what matters
/// most, a belief taken for granted); (2) write five candidate questions;
/// (3) choose the best. All five go in the notes so testing shows the
/// model's range, not just its pick.
///
/// Tried 2026-09-26 in the Mac harness, don't retry: concrete examples in
/// the @Guide descriptions get parroted back for every entry ("whether
/// feelings can be chosen" for a dead dog); asking for "the deeper
/// question about life" drifts to "What is the meaning of life?". Known
/// weak spots: it misreads who/what is where (friends "in Berlin"), asks
/// interviewer questions, and its choice step often misses its own best
/// candidate.
enum SocraticAsker {

    @Generable
    struct Understanding {
        @Guide(description: "How the writer actually seems to feel overall, in 2 to 5 plain words, judged from the whole entry. Don't assume distress they don't express.")
        var tone: String
        @Guide(description: "The specific thing in this entry that matters most to the writer, in one short concrete sentence using the entry's own particulars (people, events, wishes). Not a general question about life.")
        var heart: String
        @Guide(description: "A belief the writer shows in this entry and takes for granted, worth examining gently, addressed to them as you. Empty if there isn't one.")
        var belief: String
    }

    @Generable
    struct Candidates {
        @Guide(description: "Five different questions, each from a different angle.", .count(5))
        var questions: [String]
    }

    @Generable
    struct Choice {
        @Guide(description: "The number of the best question.")
        var number: Int
    }

    private static let understandInstructions = """
    You read a private journal entry the way a thoughtful, kind friend with \
    a philosopher's mind would: not looking for a problem to fix, but for \
    what really matters to the writer here. Read the whole entry before \
    deciding, and don't latch onto single phrases: "I'm not sure how it \
    will go" can be excitement, not worry.
    """

    /// Example questions shown to the model; candidates that copy one are
    /// dropped.
    private static let examples = [
        ("Got passed over for the promotion again. I've done the work, it should speak for itself.",
         "What would it mean for your work to speak for itself, and who is it speaking to?"),
        ("Started guitar lessons at 35. My fingers hurt and I'm terrible. Feels ridiculous at my age.",
         "At what age did you decide being a beginner becomes ridiculous?"),
        ("Argued with Dad about politics again. He never listens. I don't know why I bother.",
         "What are you hoping will happen when you bother?"),
        ("Finished my first marathon today. Weirdly empty now that it's over.",
         "If the training was the point, what exactly is over?"),
    ]

    private static let askInstructions = """
    You are like Socrates, or a wise monk, talking with someone who has just \
    shown you their journal. You ask a question that deepens their thinking \
    about their own life: it takes something they wrote and opens it up, so \
    they see it from somewhere they hadn't stood before. You are not a \
    therapist. You don't calm them down, fix the problem, or give coping \
    exercises. You're curious, and kind.

    Ways a good question can work: ask what one of their own words really \
    means to them; follow something they believe to where it leads; ask \
    whether they would really want what they're wishing for; turn it around \
    and ask what if the opposite were true; ask what they're really after; \
    ask who decided a rule they're living by.

    Examples, from other people's entries:
    \(examples.map { "Entry: \"\($0.0)\"\nQuestion: \($0.1)" }.joined(separator: "\n"))

    Rules:
    - Ask about their life, using the particulars of the entry (the people, \
    events, and wishes they wrote about), not about life in general.
    - Meet them in the mood they're in. If they're curious, be curious with \
    them. If they're grieving, be gentle, and never question whether a love \
    or a loss was real.
    - Never side with a harsh judgement they made about themselves (don't \
    ask whether they should have done better); question the judgement instead.
    - Read carefully who and what is where; don't get facts from the entry wrong.
    - Each question under 20 words, speaking to them as "you". Plain words.
    - No advice, no reassurance, no coping exercises, no "how does that make \
    you feel", no "have you considered".
    """

    private static let chooseInstructions = """
    You are a wise and kind teacher. Choose the question that is most about \
    this writer's own situation, fits the mood they're in, and would keep \
    them thinking after they put the journal down. Never choose one that \
    would feel cold or hurtful to them.
    """

    private static let readLimit = 3000

    static func ask(about text: String, recentQuestions: [String]) async throws -> QuestionAsker.Asked {
        if let reason = ItemExtractor.unavailableReason { throw ExtractionError.unavailable(reason) }
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let excerpt = text.count > readLimit ? "…" + String(text.suffix(readLimit)) : text
        let entry = "Journal entry:\n\"\"\"\n\(excerpt)\n\"\"\""

        let understanding: Understanding
        do {
            understanding = try await LanguageModelSession(model: model, instructions: understandInstructions)
                .respond(to: entry, generating: Understanding.self, options: GenerationOptions(temperature: 0))
                .content
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal:
                return QuestionAsker.noFit(notes: "reading blocked by guardrails")
            default:
                throw ExtractionError.failed("Apple Intelligence ran into a problem: \(error.localizedDescription)")
            }
        }
        var context = entry + "\n\nThe writer seems: \(understanding.tone)\nWhat matters most to them here: \(understanding.heart)"
        if !understanding.belief.isEmpty { context += "\nSomething they take for granted: \(understanding.belief)" }
        var notes = "tone: \(understanding.tone)\nheart: \(understanding.heart)\nbelief: \(understanding.belief.isEmpty ? "–" : understanding.belief)"

        var prompt = context
        if !recentQuestions.isEmpty {
            prompt += "\n\nRecently asked, so don't repeat these:\n" + recentQuestions.map { "- \($0)" }.joined(separator: "\n")
        }
        let written = (try? await LanguageModelSession(model: model, instructions: askInstructions)
            .respond(to: prompt + "\n\nWrite five questions.", generating: Candidates.self,
                     options: GenerationOptions(temperature: 0.8))
            .content.questions) ?? []
        let candidates = written.compactMap(clean)
        guard !candidates.isEmpty else { return QuestionAsker.noFit(notes: "\(notes)\nno usable candidates") }

        var question = candidates[0]
        if candidates.count > 1 {
            let list = candidates.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            if let n = try? await LanguageModelSession(model: model, instructions: chooseInstructions)
                .respond(to: context + "\n\nQuestions:\n\(list)", generating: Choice.self,
                         options: GenerationOptions(temperature: 0))
                .content.number,
               candidates.indices.contains(n - 1) {
                question = candidates[n - 1]
            }
        }
        let others = candidates.filter { $0 != question }
        if !others.isEmpty { notes += "\nother candidates:\n" + others.map { "· \($0)" }.joined(separator: "\n") }
        return QuestionAsker.Asked(question: question, moveID: "socratic", notes: notes)
    }

    /// The candidate tidied, or nil if it isn't a single short question,
    /// copies an example, or slips into a banned therapy phrasing.
    private static func clean(_ raw: String) -> String? {
        var q = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \n\""))
        if let marker = q.range(of: #"^([-•*]|\d+[.)])\s*"#, options: .regularExpression) { q.removeSubrange(marker) }
        let words = q.split(whereSeparator: \.isWhitespace).count
        let lower = q.lowercased()
        guard (3...30).contains(words), q.hasSuffix("?"), q.filter({ $0 == "?" }).count <= 2,
              !examples.contains(where: { $0.1.lowercased() == lower }),
              !["have you considered", "how does that make you feel", "how do you feel"].contains(where: lower.contains)
        else { return nil }
        return q
    }
}
