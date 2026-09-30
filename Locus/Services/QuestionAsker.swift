import Foundation
import FoundationModels

/// Picks one question to ask after a journal entry: the one most likely
/// to shift how the writer sees it, the way a Stoic teacher or a monk
/// might. It only asks; the writer does the thinking.
///
/// Three on-device calls: (1) read the entry: what kind of moment it is,
/// plus the belief most holding it up (the crux); (2) rank the moves from
/// `QuestionMoves` that fit, and take the least recently used of the top
/// three; (3) choose one of that move's hand-written questions, filling
/// `{crux}` with the writer's own words. Tested 2026-09-26: letting the
/// model write the question itself gave clumsy, sometimes off-topic
/// questions ("You can't keep up with anything. Do you think you can?");
/// choosing from written ones is reliable.
enum QuestionAsker {

    enum Approach { case socratic, moves }

    /// Testing (2026-09-26): `.socratic` (`SocraticAsker`, the model writes
    /// the question) replaced `.moves` (this file: matching the entry to a
    /// hand-written move) after real-device testing: moves read as
    /// in-the-moment coping exercises, not contemplation.
    static let approach: Approach = .socratic

    /// Show which move was picked and why, under the question and in
    /// history, while we're testing. Makes "no fit" gaps visible.
    static let showsDiagnostics = true

    /// How many recent sessions' moves to avoid repeating.
    static let rotationWindow = 3

    struct Asked: Hashable {
        var question: String
        /// `QuestionMove.id`, "socratic", or "none" when nothing fit.
        var moveID: String
        /// Short "state · move · crux" line for testing.
        var notes: String

        var isNoFit: Bool { moveID == "none" }
    }

    @Generable
    struct Reading {
        @Guide(description: "Which kind of moment the heart of the entry is.")
        var state: EntryState
        @Guide(description: "The belief or judgement (under 12 words), copied word for word from the entry, that most holds up how the writer feels. Never a plain fact or a feeling. Empty if there isn't one.")
        var crux: String
    }

    @Generable
    struct Ranking {
        @Guide(description: "In under 15 words: what this writer most needs to see differently.")
        var need: String
        @Guide(description: "The ids of the three question types that would best help them see it, best first, exactly as listed.")
        var ids: [String]
    }

    @Generable
    struct Choice {
        @Guide(description: "The number of the question that fits this entry best.")
        var number: Int
    }

    private static let readInstructions = """
    You read a private journal entry and say what kind of moment the writer \
    is in. Pick the one that fits the heart of the entry best:
    - urge: pulled toward doing something they may regret (a habit, a \
    compulsion, an angry message, quitting)
    - selfCriticism: attacking or labelling themselves
    - conflict: upset with, or about, another person
    - worry: anxious about something that might happen
    - regret: going over something past that they wish had gone differently
    - decision: torn between options
    - loss: grieving or sad about a real loss (a death, a breakup, a job, \
    their health)
    - overwhelm: too much at once, stretched thin
    - comparison: measuring themselves against other people
    - disappointment: something they hoped for didn't happen (a rejection, \
    a setback)
    - settled: calm, content, or an ordinary day with nothing weighing on them
    - crisis: the writer may not be safe right now
    - unclear: none of these fit
    Also copy the crux: the belief or judgement, word for word from the \
    entry, that most holds up how they feel ("I'm such a loser", "she'll \
    never forgive me", "he doesn't respect me"). Never a plain fact ("my \
    dog died") or a feeling ("I feel sad"). Leave it empty if there isn't one.
    """

    private static let rankInstructions = """
    You are a wise, warm teacher, like a Stoic philosopher or a monk, \
    reading a student's private journal entry. First say what they most \
    need to see differently. Then choose the kinds of question most likely \
    to help them see it: questions that meet them where they are, not ones \
    that would feel dismissive. Skip any type whose "avoid when" applies.
    """

    private static let chooseInstructions = """
    You are a wise, warm teacher, like a Stoic philosopher or a monk, \
    reading a student's private journal entry. Choose the one question \
    from the list that would most make them stop, think, and see this \
    differently. It must make sense for what they actually wrote: don't \
    choose a question about something the entry isn't about (for example, \
    envy when nobody is being compared, or "them" when there's no other \
    person).
    """

    /// Enough of a long entry for the model's context window, keeping the
    /// end, where entries usually land on what's weighing on the writer.
    private static let readLimit = 3000

    static func ask(about text: String, recentMoves: [String], recentQuestions: [String]) async throws -> Asked {
        if approach == .socratic {
            return try await SocraticAsker.ask(about: text, recentQuestions: recentQuestions)
        }
        if let reason = ItemExtractor.unavailableReason { throw ExtractionError.unavailable(reason) }
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let excerpt = text.count > readLimit ? "…" + String(text.suffix(readLimit)) : text
        let entryBlock = "Journal entry:\n\"\"\"\n\(excerpt)\n\"\"\""

        // 1. Read the entry. Note: naming self-harm in these instructions
        // trips the input guardrail on every entry, hence "may not be safe".
        let reading: Reading
        do {
            reading = try await LanguageModelSession(model: model, instructions: readInstructions)
                .respond(to: entryBlock, generating: Reading.self, options: GenerationOptions(temperature: 0))
                .content
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal:
                return noFit(notes: "reading blocked by guardrails")
            default:
                throw ExtractionError.failed("Apple Intelligence ran into a problem: \(error.localizedDescription)")
            }
        }
        let crux = cleanCrux(reading.crux, in: text)
        let state = "\(reading.state)"

        // 2. Rank the moves that fit, then let novelty break the tie.
        let fitting = QuestionMoves.all.filter { $0.fits.contains(reading.state) }
        guard !fitting.isEmpty else { return noFit(notes: "\(state) · no move for this state · \(quoted(crux))") }
        let byAge = fitting.sorted { rank($0.id, in: recentMoves) > rank($1.id, in: recentMoves) }
        let fresh = byAge.filter { !recentMoves.prefix(rotationWindow).contains($0.id) }
        // Everything that fits was used lately: allow those, but never the
        // one from the very last session.
        let candidates = !fresh.isEmpty ? fresh
            : byAge.count > 1 ? byAge.filter { $0.id != recentMoves.first } : byAge

        var move = candidates[0]
        var need = ""
        if candidates.count > 1 {
            let menu = candidates.map { m in
                "- \(m.id): \(m.shift)" + (m.avoidWhen.isEmpty ? "" : " Avoid when \(m.avoidWhen).")
                    + " e.g. \"\(m.questions[0].text)\""
            }.joined(separator: "\n")
            if let ranking = try? await LanguageModelSession(model: model, instructions: rankInstructions)
                .respond(to: "\(entryBlock)\n\nQuestion types:\n\(menu)", generating: Ranking.self,
                         options: GenerationOptions(temperature: 0))
                .content {
                need = ranking.need
                let top = ranking.ids.prefix(3).compactMap { id in
                    candidates.first { $0.id.caseInsensitiveCompare(id.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }
                }
                // The first of the least recently used.
                if let oldest = top.map({ rank($0.id, in: recentMoves) }).max(),
                   let best = top.first(where: { rank($0.id, in: recentMoves) == oldest }) {
                    move = best
                }
            }
        }

        // 3. Choose the question.
        let notes = "\(state) · \(move.id) · \(quoted(crux))" + (need.isEmpty ? "" : " · needs: \(need)")
        var options = move.questions.filter { $0.suits(reading.state) }.compactMap { fill($0.text, crux: crux) }
        let unasked = options.filter { !recentQuestions.contains($0) }
        if !unasked.isEmpty { options = unasked }
        guard let first = options.first else { return noFit(notes: "\(notes) · no question in this move suits the state") }
        guard options.count > 1 else { return Asked(question: first, moveID: move.id, notes: notes) }

        let list = options.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let number = try? await LanguageModelSession(model: model, instructions: chooseInstructions)
            .respond(to: "\(entryBlock)\n\nQuestions:\n\(list)", generating: Choice.self,
                     options: GenerationOptions(temperature: 0))
            .content.number
        let question = number.flatMap { options.indices.contains($0 - 1) ? options[$0 - 1] : nil } ?? first
        return Asked(question: question, moveID: move.id, notes: notes)
    }

    /// For when there's nothing to go on: the reading was blocked, or the
    /// model isn't available and the user carries on anyway.
    static func noFit(notes: String) -> Asked {
        Asked(question: QuestionMoves.noFitQuestion, moveID: "none", notes: "no fit · \(notes)")
    }

    /// The question with `{crux}` filled in, or nil if it needs a crux and
    /// there isn't one.
    private static func fill(_ question: String, crux: String) -> String? {
        guard question.contains("{crux}") else { return question }
        return crux.isEmpty ? nil : question.replacingOccurrences(of: "{crux}", with: crux)
    }

    /// The crux as the writer wrote it (their spelling and punctuation),
    /// or "" if it's missing, too long to quote, a question, or not really
    /// in the entry.
    private static func cleanCrux(_ raw: String, in text: String) -> String {
        let edges = CharacterSet(charactersIn: " .,;:!\"'\u{201C}\u{201D}").union(.whitespacesAndNewlines)
        let trimmed = raw.trimmingCharacters(in: edges)
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard (1...15).contains(words.count),
              let range = JudgementHighlighter.locate([trimmed], in: text).ranges.first
        else { return "" }
        // A rhetorical question ("What have I even done with my life") reads
        // badly inside the questions that quote it.
        let asks: Set<String> = ["what", "why", "how", "who", "when", "where", "is", "am", "are", "do", "does", "did", "will", "can", "could", "should", "would"]
        let endsInQuestionMark = text[range.upperBound...].first == "?"
        if endsInQuestionMark || asks.contains(words[0].lowercased()) { return "" }
        return String(text[range]).trimmingCharacters(in: edges)
    }

    /// Higher = used longer ago (never used ranks highest).
    private static func rank(_ id: String, in recentMoves: [String]) -> Int {
        recentMoves.firstIndex(of: id) ?? Int.max
    }

    private static func quoted(_ crux: String) -> String {
        crux.isEmpty ? "no crux" : "crux “\(crux)”"
    }
}
