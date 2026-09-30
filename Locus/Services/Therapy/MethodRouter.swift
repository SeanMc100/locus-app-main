import Foundation

// Foundation-only (compiled into the Mac harness too).

/// What the entry or capture gives the router to go on, beyond the
/// triage answers.
struct EntryContext: Hashable, Sendable {
    var targetThought = ""
    var entryText = ""
}

struct MethodRecommendation: Hashable, Sendable {
    var tool: TherapyTool
    /// One line, shown under the recommendation.
    var reason: String
    /// When crisis skills come first: the tool the thought itself pointed
    /// to, offered once the intensity is down.
    var thenTool: TherapyTool?
}

/// "Help me choose": a deterministic router. Pure and isolated so it can
/// later be replaced or augmented by AI routing
/// (`TherapyAIService.recommendMethod`, not built yet).
enum MethodRouter {
    /// Intensity (0–10) at or above which crisis skills come first.
    static let crisisThreshold = 7

    static func recommendMethod(_ triageAnswers: TriageAnswers, _ entryContext: EntryContext) -> MethodRecommendation {
        let thoughtTool: TherapyTool
        let thoughtReason: String
        switch triageAnswers.thoughtKind {
        case .checkable:
            if looksLikePrediction(entryContext.targetThought) {
                thoughtTool = .behavioralExperiment
                thoughtReason = "It's a prediction about something that hasn't happened yet, so you can test it in real life."
            } else {
                thoughtTool = .thoughtRecord
                thoughtReason = "It's a specific thought you can check against the evidence."
            }
        case .loop:
            thoughtTool = .defusion
            thoughtReason = "Arguing with a loop tends to feed it. Unhooking from it works better."
        case .unsure:
            thoughtTool = .checkTheFacts
            thoughtReason = "It starts from naming the emotion, which helps when the thought isn't clear yet."
        }

        if triageAnswers.intensity >= crisisThreshold {
            return MethodRecommendation(
                tool: .crisisSkills,
                reason: "When a feeling is this strong, it's hard to reason with thoughts. Bring the intensity down first, then you can come back to this.",
                thenTool: thoughtTool)
        }
        return MethodRecommendation(tool: thoughtTool, reason: thoughtReason, thenTool: nil)
    }

    /// A rough, offline test for "this is about the future": will, going
    /// to, 'll, tomorrow… Only used to choose between the two CBT tools.
    static func looksLikePrediction(_ thought: String) -> Bool {
        let normalized = RiskDetector.normalize(thought)
        guard !normalized.isEmpty else { return false }
        let pattern = #"(?<![a-z'])(will|won't|wont|going to|gonna|is about to|are about to|tomorrow|next (week|time|month)|never going)(?![a-z])|[a-z]'ll(?![a-z])"#
        return normalized.range(of: pattern, options: .regularExpression) != nil
    }
}
