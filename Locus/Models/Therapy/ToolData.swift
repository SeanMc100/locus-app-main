import Foundation

// What each tool records, stored as JSON in `TherapySession.payload`.
// Foundation-only (compiled into the Mac harness too).
//
// Adding a field later: make it optional (or give the struct a custom
// decoder), otherwise sessions saved before the change won't decode.

struct ThoughtRecordData: Codable, Hashable, Sendable {
    var situation = ""
    var emotionsBefore: [EmotionRating] = []
    /// Everything that went through their mind; blanks are ignored.
    var thoughts: [String] = [""]
    /// Index into `enteredThoughts` of the hot thought.
    var hotIndex = 0
    var beliefBefore: Double?
    var linkedBeliefID: String?
    var distortions: [String] = []
    var noDistortions = false
    var evidenceFor = ""
    var evidenceAgainst = ""
    /// Always user-written. Nothing in the app fills this in.
    var balancedThought = ""
    var balancedBelief: Double?
    /// They saw the "should feel believable" prompt and kept it anyway.
    var keptLowBelief = false
    var beliefAfter: Double?
    var emotionsAfter: [EmotionRating] = []
    var addedToPractice = false

    var enteredThoughts: [String] { thoughts.map(\.trimmed).filter { !$0.isEmpty } }

    var hotThought: String {
        let entered = enteredThoughts
        return entered.indices.contains(hotIndex) ? entered[hotIndex] : (entered.first ?? "")
    }
}

struct ExperimentData: Codable, Hashable, Sendable {
    var prediction = ""
    var linkedBeliefID: String?
    /// What they'd see or hear if it came true.
    var observable = ""
    var confidence: Double?
    var alternative = ""
    var alternativeConfidence: Double?
    var action = ""
    var when: Date?
    var observe = ""
    var safetyBehavior = ""
    var obstacles: [IfThen] = [IfThen()]
    var saveObstaclesAsPlans = false
    // Later, after the experiment.
    var outcome = ""
    var cameTrue: PredictionOutcome?
    /// "How bad was it, compared to what you expected?" 0–100 each.
    var severityExpected: Double?
    var severityActual: Double?
    var learning = ""
    var beliefAfter: Double?
}

enum ActivityCategory: String, Codable, CaseIterable, Sendable {
    case mastery, pleasure, custom

    var label: String {
        switch self {
        case .mastery: "Mastery"
        case .pleasure: "Pleasure"
        case .custom: "Your own"
        }
    }

    var detail: String {
        switch self {
        case .mastery: "A sense of accomplishment"
        case .pleasure: "Enjoyment or connection"
        case .custom: "Something else that helps"
        }
    }
}

struct ActivationData: Codable, Hashable, Sendable {
    /// 0–10.
    var moodBefore: Int?
    var energyBefore: Int?
    var activity = ""
    var category: ActivityCategory?
    var valueDomainID: String?
    var doNow: Bool?
    var when: Date?
    // After.
    var did: Bool?
    var mastery: Int?
    var pleasure: Int?
    var moodAfter: Int?
}

enum CrisisSkill: String, Codable, CaseIterable, Sendable {
    case tipp, stop
}

enum TippSkill: String, Codable, CaseIterable, Identifiable, Sendable {
    case temperature, exercise, breathing, muscles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .temperature: "Temperature"
        case .exercise: "Intense exercise"
        case .breathing: "Paced breathing"
        case .muscles: "Paired muscle relaxation"
        }
    }

    var summary: String {
        switch self {
        case .temperature: "Cold water on your face for about 30 seconds."
        case .exercise: "A short burst of vigorous movement."
        case .breathing: "Breathe out for longer than you breathe in."
        case .muscles: "Tense, then release, with each breath out."
        }
    }

    var symbol: String {
        switch self {
        case .temperature: "drop"
        case .exercise: "figure.run"
        case .breathing: "wind"
        case .muscles: "hand.raised"
        }
    }
}

struct CrisisData: Codable, Hashable, Sendable {
    /// 0–10.
    var intensityBefore: Int?
    var skill: CrisisSkill?
    var tippDone: [TippSkill] = []
    var observe = ""
    var proceed = ""
    var intensityAfter: Int?
}

struct CheckFactsData: Codable, Hashable, Sendable {
    var emotion: EmotionRating?
    var event = ""
    var interpretations = ""
    var otherInterpretations = ""
    var threat = ""
    var threatLikelihood: Double?
    var catastrophe = ""
    var coping = ""
    var fit: FactsFit?
    var problemSolving = ""
    var intensityAfter: Double?
    /// Marked later from the session detail: did the feared thing happen?
    /// Feeds prediction calibration alongside experiments.
    var threatHappened: PredictionOutcome?
}

struct OppositeActionData: Codable, Hashable, Sendable {
    var emotion: EmotionRating?
    var urge = ""
    /// Came from Check the Facts, which already asked whether it fits.
    var fromCheckFacts = false
    var fit: FactsFit?
    var problemSolving = ""
    var action = ""
    var doNow: Bool?
    var when: Date?
    var did: Bool?
    var intensityAfter: Double?
}

enum ChainLinkKind: String, Codable, CaseIterable, Sendable {
    case thought, emotion, sensation, urge, action, event

    var label: String {
        switch self {
        case .thought: "Thought"
        case .emotion: "Emotion"
        case .sensation: "Body sensation"
        case .urge: "Urge"
        case .action: "Action"
        case .event: "Event"
        }
    }

    var symbol: String {
        switch self {
        case .thought: "text.bubble"
        case .emotion: "heart"
        case .sensation: "waveform.path.ecg"
        case .urge: "arrow.forward.circle"
        case .action: "hand.point.up"
        case .event: "calendar"
        }
    }
}

struct ChainLink: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var kind: ChainLinkKind
    var text: String
}

/// A link where they could respond differently next time.
struct WeakLink: Codable, Hashable, Sendable {
    var linkID: UUID
    /// A skill name from `TherapyCatalog.skills`, or empty.
    var skill = ""
    var custom = ""

    var response: String {
        [skill, custom.trimmed].filter { !$0.isEmpty }.joined(separator: ": ")
    }
}

struct ChainData: Codable, Hashable, Sendable {
    var problemBehavior = ""
    var promptingEvent = ""
    var vulnerabilities: [String] = []
    var vulnerabilityOther = ""
    var links: [ChainLink] = []
    var shortTerm = ""
    var longTerm = ""
    var weakLinks: [WeakLink] = []
    var planLinkID: UUID?
    var createdPlanID: String?
    var repair = ""
}

enum DefusionTechnique: String, Codable, CaseIterable, Identifiable, Sendable {
    case havingTheThought, nameTheStory, leaves, thankYourMind, sillyVoice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .havingTheThought: "“I'm having the thought that…”"
        case .nameTheStory: "Name the story"
        case .leaves: "Leaves on a stream"
        case .thankYourMind: "Thank your mind"
        case .sillyVoice: "Silly voice"
        }
    }

    var summary: String {
        switch self {
        case .havingTheThought: "Put a little space between you and the thought."
        case .nameTheStory: "Give the story your mind tells a name."
        case .leaves: "Place thoughts on leaves and watch them float away."
        case .thankYourMind: "Notice your mind is trying to protect you."
        case .sillyVoice: "Hear the thought in a playful way until it loosens."
        }
    }

    var symbol: String {
        switch self {
        case .havingTheThought: "text.quote"
        case .nameTheStory: "book.closed"
        case .leaves: "leaf"
        case .thankYourMind: "hands.clap"
        case .sillyVoice: "face.smiling"
        }
    }
}

struct DefusionData: Codable, Hashable, Sendable {
    var thought = ""
    var linkedBeliefID: String?
    /// How stuck/hooked (0–100), not how true.
    var hookedBefore: Double?
    var technique: DefusionTechnique?
    var techniquesUsed: [DefusionTechnique] = []
    var storyName = ""
    var leaves: [String] = []
    var hookedAfter: Double?
    var whatMatters = ""
}

struct CommittedActionData: Codable, Hashable, Sendable {
    var valueDomainID: String?
    var valueName = ""
    var step = ""
    var barriers = ""
    var willing: Bool?
    var doNow: Bool?
    var when: Date?
    var did: Bool?
    var howFelt = ""
}

struct ValuesCheckInData: Codable, Hashable, Sendable {
    /// Value domain id -> consistency 0–10 at this check-in.
    var ratings: [String: Int] = [:]
}

// MARK: - Supporting records

struct UrgeRating: Codable, Hashable, Identifiable, Sendable {
    var id: String { name }
    var name: String
    /// 0–5.
    var intensity: Int
    var acted: Bool
}

struct PlanFire: Codable, Hashable, Sendable {
    var date: Date
    var fired: Bool
}

struct ConsistencyPoint: Codable, Hashable, Sendable {
    var date: Date
    /// 0–10.
    var value: Int
}

enum BeliefRatingKind: String, Codable, Sendable {
    /// "How much do you believe this?" (thought records, experiments).
    case belief
    /// "How hooked do you feel?" (defusion; not a truth rating).
    case hooked
}

struct BeliefRatingPoint: Codable, Hashable, Sendable {
    var date: Date
    /// 0–100.
    var value: Double
    var kind: BeliefRatingKind
    var phase: EmotionPhase
    var sessionID: String
}

struct SafetyContact: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name = ""
    var phone = ""
}

enum PracticeRating: String, Codable, CaseIterable, Sendable {
    case stillBelieve, gettingThere, strong

    var label: String {
        switch self {
        case .stillBelieve: "Still believe it"
        case .gettingThere: "Getting there"
        case .strong: "Strong"
        }
    }
}

struct PracticeReview: Codable, Hashable, Sendable {
    var date: Date
    var rating: PracticeRating
}
