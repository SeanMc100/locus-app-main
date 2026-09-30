import Foundation
import SwiftData

/// The app's entry point for AI. Applies the guardrails around every call:
/// off unless enabled; no call at all if the offline risk check flags the
/// input; minimum text sent; output validated; timeout with fallback.
@MainActor
enum TherapyAI {
    static let enabledKey = "skills.ai.enabled"
    static let timeout: Double = 8

    /// Off until the user turns it on in Settings.
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Why AI can't run even though it's on, or nil.
    static var unavailableReason: String? {
        OnDeviceTherapyAIService.unavailableReason
    }

    static var service: any TherapyAIService {
        guard isEnabled, unavailableReason == nil else { return OfflineTherapyAIService() }
        return OnDeviceTherapyAIService()
    }

    private static var isActive: Bool { isEnabled && unavailableReason == nil }

    static func automaticThoughts(in entry: String) async -> [String] {
        guard isActive, !RiskDetector.assess(entry).isRisk else { return [] }
        let service = service
        let found = await withTimeout(seconds: timeout * 2) {
            try? await service.detectAutomaticThoughts(entryText: entry)
        }
        return AIGuardrails.verbatimSpans((found ?? nil) ?? [], in: entry)
            .filter { !RiskDetector.assess($0).isRisk }
    }

    static func socraticQuestion(step: SocraticStep, context: SocraticContext) async -> String? {
        let input = ([context.targetThought] + context.priorAnswers.values).joined(separator: "\n")
        guard isActive, !RiskDetector.assess(input).isRisk else { return nil }
        let service = service
        let raw = await withTimeout(seconds: timeout) {
            try? await service.generateSocraticQuestion(step: step, context: context)
        }
        return (raw ?? nil).flatMap(AIGuardrails.cleanQuestion)
    }

    static func balancedThoughtQuestion(original: String, balanced: String, belief: Double) async -> String? {
        guard isActive, !RiskDetector.assess(original + "\n" + balanced).isRisk else { return nil }
        let service = service
        let raw = await withTimeout(seconds: timeout) {
            try? await service.checkBalancedThought(originalThought: original, balancedThought: balanced, beliefRating: belief)
        }
        return (raw ?? nil).flatMap(AIGuardrails.cleanQuestion)
    }

    static func suggestLedgerMatch(thought: String, beliefs: [LedgerBelief]) async -> LedgerBelief? {
        guard isActive, !thought.trimmed.isEmpty, !beliefs.isEmpty,
              !RiskDetector.assess(thought).isRisk else { return nil }
        let candidates = beliefs.prefix(30).map { LedgerCandidate(id: $0.idString, text: $0.canonicalText) }
        let service = service
        let id = await withTimeout(seconds: timeout) {
            try? await service.suggestLedgerMatch(thought: thought, ledgerBeliefs: Array(candidates))
        }
        guard let id = id ?? nil else { return nil }
        return beliefs.first { $0.idString == id }
    }

    static func summarize(_ digest: PatternDigest) async -> [String] {
        guard isActive, !digest.isEmpty else { return [] }
        let service = service
        let lines = await withTimeout(seconds: timeout * 2) {
            try? await service.summarizePatterns(digest)
        }
        let result: [String] = (lines ?? nil) ?? []
        let source = ([String(digest.sessionCount)] + digest.topEmotions + digest.topDistortions + digest.topTriggers
                      + digest.skillAverages + digest.chainFactors + digest.recurringLinks).joined(separator: " ")
        return Array(result.compactMap { AIGuardrails.cleanSummaryLine($0, source: source) }.prefix(3))
    }

    /// The offline check first; AI only ever adds to it.
    static func assessRisk(_ text: String) async -> RiskAssessment {
        let deterministic = RiskDetector.assess(text)
        guard isActive, !deterministic.isRisk, !text.trimmed.isEmpty else { return deterministic }
        let service = service
        let flagged = await withTimeout(seconds: timeout) {
            try? await service.classifyRisk(text)
        }
        return RiskDetector.escalate(deterministic, aiFlagged: (flagged ?? nil) ?? false)
    }
}
