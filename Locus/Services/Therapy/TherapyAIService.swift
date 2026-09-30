import Foundation

// Foundation-only (compiled into the Mac harness with the on-device
// implementation).

/// What the Socratic question step knows: the thought, and the user's
/// answers so far (label -> answer). Only this goes to the model.
struct SocraticContext: Hashable, Sendable {
    var targetThought = ""
    var priorAnswers: [String: String] = [:]
}

struct LedgerCandidate: Hashable, Sendable {
    var id: String
    var text: String
}

/// Locally computed numbers for `summarizePatterns`. Counts and averages
/// only; no journal text.
struct PatternDigest: Codable, Hashable, Sendable {
    var topEmotions: [String] = []
    var topDistortions: [String] = []
    var topTriggers: [String] = []
    var skillAverages: [String] = []
    var chainFactors: [String] = []
    var recurringLinks: [String] = []
    var sessionCount = 0

    var isEmpty: Bool { sessionCount == 0 }
}

/// Every AI-powered skills feature goes through this interface. The app
/// works fully with `OfflineTherapyAIService`; AI enhances, never gates.
///
/// Implementations:
/// - `OfflineTherapyAIService`: used when AI is off or unavailable.
/// - `OnDeviceTherapyAIService`: Apple's on-device model (Foundation
///   Models), the same one the journal features use. Nothing leaves the
///   device.
/// - `RemoteTherapyAIService`: stub for a cloud provider, not wired up.
protocol TherapyAIService: Sendable {
    /// Up to 3 automatic thoughts, copied word for word from the entry.
    func detectAutomaticThoughts(entryText: String) async throws -> [String]
    /// One question for this step. Never an answer.
    func generateSocraticQuestion(step: SocraticStep, context: SocraticContext) async throws -> String?
    /// A gentle question if the balanced thought looks like toxic positivity
    /// or a pure opposite of the original; nil if it's fine. Never a rewrite.
    func checkBalancedThought(originalThought: String, balancedThought: String, beliefRating: Double) async throws -> String?
    /// The id of a ledger belief that seems to match, for the user to confirm.
    func suggestLedgerMatch(thought: String, ledgerBeliefs: [LedgerCandidate]) async throws -> String?
    /// Short natural-language lines about the user's own numbers.
    func summarizePatterns(_ aggregatedData: PatternDigest) async throws -> [String]
    /// True if the text may describe risk the offline check missed. Can
    /// only escalate (`RiskDetector.escalate`).
    func classifyRisk(_ text: String) async throws -> Bool

    // Hook for later, not built yet: AI routing to augment
    // `MethodRouter.recommendMethod`.
    // func recommendMethod(entryText: String, triageAnswers: TriageAnswers) async throws -> MethodRecommendation?
}

/// AI off or unavailable: nothing to add; the static question bank and
/// offline checks carry everything.
struct OfflineTherapyAIService: TherapyAIService {
    func detectAutomaticThoughts(entryText: String) async throws -> [String] { [] }
    func generateSocraticQuestion(step: SocraticStep, context: SocraticContext) async throws -> String? { nil }
    func checkBalancedThought(originalThought: String, balancedThought: String, beliefRating: Double) async throws -> String? { nil }
    func suggestLedgerMatch(thought: String, ledgerBeliefs: [LedgerCandidate]) async throws -> String? { nil }
    func summarizePatterns(_ aggregatedData: PatternDigest) async throws -> [String] { [] }
    func classifyRisk(_ text: String) async throws -> Bool { false }
}

/// Runs `operation`, giving up after `seconds` (the result is then nil).
/// Doesn't wait for the operation to notice cancellation.
func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async -> T) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let gate = OnceGate()
        let work = Task {
            let value = await operation()
            if gate.claim() { continuation.resume(returning: value) }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if gate.claim() {
                work.cancel()
                continuation.resume(returning: nil)
            }
        }
    }
}

private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
