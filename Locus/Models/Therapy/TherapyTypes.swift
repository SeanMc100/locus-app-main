import Foundation

// Foundation-only on purpose: these types are also compiled into the Mac
// test harness (see CLAUDE.md), so no SwiftUI or SwiftData here.

enum TherapyMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case cbt, dbt, act

    var id: String { rawValue }

    var name: String {
        switch self {
        case .cbt: "CBT"
        case .dbt: "DBT"
        case .act: "ACT"
        }
    }

    var headline: String {
        switch self {
        case .cbt: "Test the thought"
        case .dbt: "Regulate first"
        case .act: "Unhook and act on values"
        }
    }

    var useWhen: String {
        switch self {
        case .cbt: "When a specific thought or prediction is bothering you and you want to check if it's true."
        case .dbt: "When the feeling is intense and you need to bring it down, or you want to understand what led to a reaction."
        case .act: "When a thought keeps looping, arguing with it isn't working, and you want to move toward what matters."
        }
    }

    var tools: [TherapyTool] {
        TherapyTool.allCases.filter { $0.method == self }
    }
}

enum TherapyTool: String, Codable, CaseIterable, Identifiable, Sendable {
    case thoughtRecord, behavioralExperiment, behavioralActivation
    case crisisSkills, checkTheFacts, oppositeAction, chainAnalysis
    case defusion, valuesCheckIn, committedAction

    var id: String { rawValue }

    var method: TherapyMethod {
        switch self {
        case .thoughtRecord, .behavioralExperiment, .behavioralActivation: .cbt
        case .crisisSkills, .checkTheFacts, .oppositeAction, .chainAnalysis: .dbt
        case .defusion, .valuesCheckIn, .committedAction: .act
        }
    }

    var title: String {
        switch self {
        case .thoughtRecord: "Thought Record"
        case .behavioralExperiment: "Behavioral Experiment"
        case .behavioralActivation: "Behavioral Activation"
        case .crisisSkills: "Crisis Skills"
        case .checkTheFacts: "Check the Facts"
        case .oppositeAction: "Opposite Action"
        case .chainAnalysis: "Chain Analysis"
        case .defusion: "Defusion"
        case .valuesCheckIn: "Values Check-in"
        case .committedAction: "Committed Action"
        }
    }

    var useWhen: String {
        switch self {
        case .thoughtRecord: "Examine a thought that's bothering you."
        case .behavioralExperiment: "Test a prediction in real life."
        case .behavioralActivation: "Low energy or motivation; plan something that helps."
        case .crisisSkills: "The feeling is very intense right now."
        case .checkTheFacts: "Figure out if your emotion fits the situation."
        case .oppositeAction: "Act against an emotion urge that isn't helping."
        case .chainAnalysis: "Understand what led to a reaction you want to change."
        case .defusion: "Unhook from a sticky thought."
        case .valuesCheckIn: "Reconnect with what matters to you."
        case .committedAction: "Take a small step toward a value."
        }
    }

    var symbol: String {
        switch self {
        case .thoughtRecord: "list.bullet.rectangle"
        case .behavioralExperiment: "flask"
        case .behavioralActivation: "figure.walk"
        case .crisisSkills: "wind"
        case .checkTheFacts: "checkmark.seal"
        case .oppositeAction: "arrow.uturn.right"
        case .chainAnalysis: "link"
        case .defusion: "cloud"
        case .valuesCheckIn: "safari"
        case .committedAction: "arrow.up.forward"
        }
    }

    /// Tools that work on one specific thought, so a target thought from
    /// the journal or a capture carries straight in.
    var takesTargetThought: Bool {
        switch self {
        case .thoughtRecord, .behavioralExperiment, .defusion: true
        default: false
        }
    }
}

enum SessionStatus: String, Codable, Sendable {
    /// Being filled in; resumable from "In progress".
    case draft
    /// Planned and waiting on real life (an experiment, an activity, an
    /// action); a reminder brings the user back for the outcome.
    case pending
    case complete
}

enum EmotionPhase: String, Codable, Sendable {
    case before, after
}

/// One named emotion and how strong it is (0–100).
struct EmotionRating: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var family: EmotionFamily
    var word: String
    var intensity: Double
    var phase: EmotionPhase = .before
}

/// "Did it come true?" for predictions and feared outcomes.
enum PredictionOutcome: String, Codable, CaseIterable, Sendable {
    case yes, partly, no

    var label: String {
        switch self {
        case .yes: "Yes"
        case .partly: "Partly"
        case .no: "No"
        }
    }

    /// How much this counts as "came true" in calibration.
    var score: Double {
        switch self {
        case .yes: 1
        case .partly: 0.5
        case .no: 0
        }
    }
}

/// Check the Facts: does the emotion (and its intensity) fit the facts?
enum FactsFit: String, Codable, CaseIterable, Sendable {
    case fits, partly, doesnt

    var label: String {
        switch self {
        case .fits: "Fits"
        case .partly: "Partly fits"
        case .doesnt: "Doesn't fit"
        }
    }
}

/// "Help me choose" answers, stored with the session for patterns.
struct TriageAnswers: Codable, Hashable, Sendable {
    enum ThoughtKind: String, Codable, CaseIterable, Sendable {
        case checkable, loop, unsure

        var label: String {
            switch self {
            case .checkable: "A specific prediction or judgment I could check"
            case .loop: "A loop I keep going around"
            case .unsure: "I'm not sure, I just feel bad"
            }
        }

        var example: String? {
            switch self {
            case .checkable: "“The presentation will go badly,” “she's mad at me”"
            case .loop: "“I'm not good enough,” “what's the point”"
            case .unsure: nil
            }
        }
    }

    /// 0–10.
    var intensity: Int
    var thoughtKind: ThoughtKind
}

/// An "If ___, then I'll ___" pair (experiment obstacles, chain weak
/// links, if-then plans).
struct IfThen: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var trigger = ""
    var response = ""

    var isFilled: Bool {
        !trigger.trimmed.isEmpty && !response.trimmed.isEmpty
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
