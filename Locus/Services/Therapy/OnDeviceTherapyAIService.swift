import Foundation
import FoundationModels

/// `TherapyAIService` on Apple's on-device model (Foundation Models), the
/// same model the journal features use. Nothing leaves the device.
///
/// Every prompt carries `AIGuardrails.rules`; every output is validated by
/// `TherapyAI` (the caller) before it's shown. The model only asks,
/// finds, or matches; it never writes a reframe or conclusion.
///
/// Wording note (see CLAUDE.md): naming self-harm in instructions trips
/// the input guardrail on every request, so the risk check asks whether
/// the writer "may not be safe".
struct OnDeviceTherapyAIService: TherapyAIService {

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "This device doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in Settings to use AI here."
            case .modelNotReady: return "Apple Intelligence is still getting ready. Try again later."
            @unknown default: return "Apple Intelligence isn't available right now."
            }
        }
    }

    private var model: SystemLanguageModel { SystemLanguageModel(guardrails: .permissiveContentTransformations) }

    private func session(_ instructions: String) -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: instructions + "\n\n" + AIGuardrails.rules)
    }

    // MARK: Journal bridge

    @Generable
    struct FoundThoughts {
        @Guide(description: "Up to three automatic thoughts, each copied word for word from the entry. Empty if there are none.", .maximumCount(3))
        var thoughts: [String]
    }

    @Generable
    enum SpanKind {
        case judgement, prediction, fact, feeling, other
    }

    @Generable
    struct SpanCheck {
        @Guide(description: "What this piece of the entry is.")
        var kind: SpanKind
    }

    func detectAutomaticThoughts(entryText: String) async throws -> [String] {
        let instructions = """
        You read a private journal entry and copy out the automatic thoughts in it: quick \
        judgements or predictions the writer made, like "I always ruin this", "they must \
        think I'm incompetent", or "this is going to go badly". Copy each one word for word \
        from the entry. Don't include plain facts ("the meeting moved", "I had pasta") or \
        feelings ("I feel sad"). Don't rephrase anything.
        """
        let excerpt = entryText.count > 3000 ? String(entryText.suffix(3000)) : entryText
        let found = try await session(instructions)
            .respond(to: "Journal entry:\n\"\"\"\n\(excerpt)\n\"\"\"", generating: FoundThoughts.self,
                     options: GenerationOptions(temperature: 0))
            .content.thoughts
        // Check each one on its own: the find pass sometimes lets a fact in.
        let checkInstructions = """
        Say what a piece of a journal entry is. judgement: an evaluation of self, others, \
        or life ("I'm useless", "they don't care"). prediction: a claim about what will \
        happen ("it'll go badly"). fact: something that happened or is plainly true \
        ("my manager moved the deadline", "I had pasta"). feeling: naming an emotion \
        ("I feel sad").
        """
        var kept: [String] = []
        for span in found {
            let kind = try? await session(checkInstructions)
                .respond(to: "\"\(span)\"", generating: SpanCheck.self, options: GenerationOptions(temperature: 0))
                .content.kind
            if kind == .judgement || kind == .prediction { kept.append(span) }
        }
        return kept
    }

    // MARK: Socratic questions

    @Generable
    struct OneQuestion {
        @Guide(description: "One short, open question (under 20 words) ending with a question mark. It must not suggest or contain the answer.")
        var question: String
    }

    static func purpose(of step: SocraticStep) -> String {
        switch step {
        case .situation: "describing what happened as plain facts"
        case .automaticThought: "noticing what went through their mind"
        case .evidenceFor: "listing facts (not feelings) that support the thought"
        case .evidenceAgainst: "finding facts that don't fit the thought"
        case .balancedThought: "writing their own more balanced view of the thought"
        case .prediction: "making a prediction specific and observable"
        case .alternativePrediction: "imagining another realistic outcome"
        case .experimentPlan: "planning a small real-life test of the prediction"
        case .experimentLearning: "reflecting on what the experiment showed"
        case .interpretations: "noticing assumptions and other possible interpretations"
        case .threat: "checking how likely a feared threat really is"
        case .catastrophe: "thinking through how they would cope with the worst realistic outcome"
        case .problemSolving: "finding something they could do about the situation"
        case .oppositeAction: "choosing a specific action opposite to an emotion's urge"
        case .chainLinks: "recalling what happened next in a chain of events"
        case .weakLink: "spotting where a different response could have helped"
        case .repair: "considering whether anything needs repairing"
        case .defusionBridge: "reconnecting with what matters to them"
        case .committedStep: "choosing one small step toward a value"
        case .barriers: "naming thoughts or feelings that might get in the way"
        case .activity: "picking a small activity that might lift their mood"
        }
    }

    func generateSocraticQuestion(step: SocraticStep, context: SocraticContext) async throws -> String? {
        let instructions = """
        You help someone through a self-help exercise by asking one short, open, curious \
        question for the step they're on. Use the particulars of what they wrote. Never \
        answer it for them, never hint at what the answer should be, and never offer \
        reassurance.
        """
        var prompt = "The step: \(Self.purpose(of: step)).\n"
        if !context.targetThought.trimmed.isEmpty { prompt += "Their thought: \"\(context.targetThought.trimmed)\"\n" }
        for (label, answer) in context.priorAnswers.sorted(by: { $0.key < $1.key }) where !answer.trimmed.isEmpty {
            prompt += "\(label): \"\(answer.trimmed.prefix(400))\"\n"
        }
        prompt += "Ask one question."
        return try await session(instructions)
            .respond(to: prompt, generating: OneQuestion.self, options: GenerationOptions(temperature: 0.4))
            .content.question
    }

    // MARK: Balanced-thought check

    @Generable
    struct BalancedCheck {
        @Guide(description: "True if the balanced thought is realistic and believable. False if it's just the opposite of the original thought, or empty positivity like \"everything will be perfect\".")
        var realistic: Bool
        @Guide(description: "If not realistic: one gentle question that could help them make it more realistic, without suggesting any wording. Otherwise empty.")
        var question: String
    }

    func checkBalancedThought(originalThought: String, balancedThought: String, beliefRating: Double) async throws -> String? {
        let instructions = """
        You look at a "balanced thought" someone wrote to replace an upsetting thought. \
        A good balanced thought is realistic and believable, not just positive. You never \
        rewrite it or suggest wording. If it's realistic, say so. If it's only the opposite \
        of the original, or empty positivity, ask one gentle question.
        """
        let prompt = """
        Original thought: "\(originalThought.trimmed.prefix(300))"
        Balanced thought: "\(balancedThought.trimmed.prefix(400))"
        How much they believe it: \(Int(beliefRating))%
        """
        let result = try await session(instructions)
            .respond(to: prompt, generating: BalancedCheck.self, options: GenerationOptions(temperature: 0))
            .content
        return result.realistic ? nil : result.question
    }

    // MARK: Ledger match

    @Generable
    struct Match {
        @Guide(description: "The number of the listed belief that expresses the same core belief, or 0 if none does.")
        var number: Int
    }

    func suggestLedgerMatch(thought: String, ledgerBeliefs: [LedgerCandidate]) async throws -> String? {
        guard !ledgerBeliefs.isEmpty else { return nil }
        let instructions = """
        You decide whether a new thought expresses the same core belief as one already in \
        a list, like "I'm behind everyone" and "I'm falling behind". Only match when the \
        underlying belief is the same, not just the topic. Otherwise answer 0.
        """
        let list = ledgerBeliefs.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
        let n = try await session(instructions)
            .respond(to: "New thought: \"\(thought.trimmed.prefix(300))\"\n\nBeliefs:\n\(list)", generating: Match.self,
                     options: GenerationOptions(temperature: 0))
            .content.number
        return ledgerBeliefs.indices.contains(n - 1) ? ledgerBeliefs[n - 1].id : nil
    }

    // MARK: Pattern summary

    @Generable
    struct Summary {
        @Guide(description: "Up to three short, plain observations about these numbers.", .maximumCount(3))
        var lines: [String]
    }

    func summarizePatterns(_ aggregatedData: PatternDigest) async throws -> [String] {
        let instructions = """
        You write up to three short, warm, neutral observations about someone's own \
        self-help records, from counts only, speaking to them as "you". Say what the \
        numbers show, and describe changes as numbers ("went from 80 to 40") without \
        calling them better, worse, or improved. No advice, no "you should", no \
        diagnosis, no judgement.
        """
        var prompt = "Sessions completed: \(aggregatedData.sessionCount)\n"
        func add(_ label: String, _ items: [String]) {
            if !items.isEmpty { prompt += "\(label): \(items.joined(separator: "; "))\n" }
        }
        add("Most frequent emotions", aggregatedData.topEmotions)
        add("Most frequent thinking traps", aggregatedData.topDistortions)
        add("Most frequent situations", aggregatedData.topTriggers)
        add("Average before → after by skill", aggregatedData.skillAverages)
        add("Vulnerability factors across chains", aggregatedData.chainFactors)
        add("Recurring chain links", aggregatedData.recurringLinks)
        return try await session(instructions)
            .respond(to: prompt, generating: Summary.self, options: GenerationOptions(temperature: 0.2))
            .content.lines
    }

    // MARK: Risk (escalation only)

    @Generable
    struct SafetyRead {
        @Guide(description: "True only if the writing suggests the writer, or someone because of them, may not be safe right now. Everyday exaggeration (\"this is killing me\") is false.")
        var mayNotBeSafe: Bool
    }

    func classifyRisk(_ text: String) async throws -> Bool {
        let instructions = """
        You read a short piece of private writing and check one thing: whether it suggests \
        the writer may not be safe right now, or that someone else may not be safe because \
        of them. Don't treat ordinary sadness, stress, or figures of speech as unsafe.
        """
        let excerpt = text.count > 2000 ? String(text.suffix(2000)) : text
        do {
            return try await session(instructions)
                .respond(to: "Writing:\n\"\"\"\n\(excerpt)\n\"\"\"", generating: SafetyRead.self,
                         options: GenerationOptions(temperature: 0))
                .content.mayNotBeSafe
        } catch {
            // A refusal here isn't treated as risk: the offline check is the
            // floor, and this can only ever add to it.
            return false
        }
    }
}

/// Stub for a cloud provider, not wired up. Using one would break the
/// "everything stays on this device" promise, so it needs explicit user
/// consent, a backend holding the key, and an updated Settings
/// explanation first. To plug one in: implement these methods against the
/// provider's API (send only the text each method receives), then choose
/// it in `TherapyAI.service`.
struct RemoteTherapyAIService: TherapyAIService {
    // TODO(provider): endpoint and key come from your backend, never the app bundle.
    func detectAutomaticThoughts(entryText: String) async throws -> [String] { [] }
    func generateSocraticQuestion(step: SocraticStep, context: SocraticContext) async throws -> String? { nil }
    func checkBalancedThought(originalThought: String, balancedThought: String, beliefRating: Double) async throws -> String? { nil }
    func suggestLedgerMatch(thought: String, ledgerBeliefs: [LedgerCandidate]) async throws -> String? { nil }
    func summarizePatterns(_ aggregatedData: PatternDigest) async throws -> [String] { [] }
    func classifyRisk(_ text: String) async throws -> Bool { false }
}
