import Foundation
import SwiftData

// Skills data. Lives in its own local-only store (`TherapyStore`), never
// synced to iCloud, unlike `JournalEntry`. Links to journal entries are by
// `JournalEntry.linkID`, since the two stores can't hold relationships to
// each other.

/// One run of a tool: a thought record, an experiment, a crisis skill…
/// Scalar fields are what lists and insights query; the tool's own answers
/// are JSON in `payload` (one of the `…Data` structs in ToolData.swift).
@Model
final class TherapySession {
    var id: UUID = UUID()
    var toolRaw: String = TherapyTool.thoughtRecord.rawValue
    var methodRaw: String = TherapyMethod.cbt.rawValue
    var statusRaw: String = SessionStatus.draft.rawValue
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var completedAt: Date?
    /// When a pending session's real-world part is planned for.
    var scheduledAt: Date?
    /// The step to resume at.
    var stepKey: String = ""
    var stepPosition: Int = 1
    var stepTotal: Int = 1
    /// `JournalEntry.linkID` this came from, or "".
    var sourceEntryID: String = ""
    /// `QuickCapture.id` this came from, or "".
    var sourceCaptureID: String = ""
    var targetThought: String = ""
    var linkedBeliefIDs: [String] = []
    var triageData: Data?
    /// After crisis skills from triage: the tool the thought pointed to.
    var followUpToolRaw: String = ""
    /// The tool's headline before/after number, normalized to 0–100 so
    /// tools can be compared ("which skills help you most").
    var metricBefore: Double?
    var metricAfter: Double?
    /// Calm-time rehearsal (Practice), kept out of "in the moment" stats.
    var isPractice: Bool = false
    var payload: Data = Data()

    init(tool: TherapyTool) {
        self.toolRaw = tool.rawValue
        self.methodRaw = tool.method.rawValue
    }

    var tool: TherapyTool { TherapyTool(rawValue: toolRaw) ?? .thoughtRecord }
    var method: TherapyMethod { tool.method }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var triage: TriageAnswers? {
        get { triageData.flatMap { try? JSONDecoder().decode(TriageAnswers.self, from: $0) } }
        set { triageData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var followUpTool: TherapyTool? {
        get { TherapyTool(rawValue: followUpToolRaw) }
        set { followUpToolRaw = newValue?.rawValue ?? "" }
    }

    func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard !payload.isEmpty else { return nil }
        return try? JSONDecoder().decode(T.self, from: payload)
    }

    func store<T: Encodable>(_ value: T) {
        if let data = try? JSONEncoder().encode(value), data != payload {
            payload = data
            updatedAt = .now
        }
    }

    var idString: String { id.uuidString }
}

/// A recurring belief, kept as one object across every time it shows up.
@Model
final class LedgerBelief {
    var id: UUID = UUID()
    var canonicalText: String = ""
    /// From Defusion's "Name the story".
    var storyName: String = ""
    var createdAt: Date = Date.now
    var lastSeenAt: Date = Date.now
    var sessionIDs: [String] = []
    var captureIDs: [String] = []
    var ratingsData: Data = Data()

    init(canonicalText: String) {
        self.canonicalText = canonicalText
    }

    var ratings: [BeliefRatingPoint] {
        get { (try? JSONDecoder().decode([BeliefRatingPoint].self, from: ratingsData)) ?? [] }
        set { ratingsData = (try? JSONEncoder().encode(newValue)) ?? ratingsData }
    }

    var occurrences: Int { Set(sessionIDs).count + Set(captureIDs).count }
    var idString: String { id.uuidString }
}

/// A life domain and the values the user holds in it.
@Model
final class ValueDomain {
    var id: UUID = UUID()
    /// `LifeDomain` key for built-ins, "" for custom domains.
    var key: String = ""
    var name: String = ""
    var symbol: String = "circle"
    var order: Int = 0
    var isHidden: Bool = false
    var qualities: [String] = []
    var note: String = ""
    /// 0–10; nil until clarified.
    var importance: Int?
    var consistencyData: Data = Data()

    init(key: String, name: String, symbol: String, order: Int) {
        self.key = key
        self.name = name
        self.symbol = symbol
        self.order = order
    }

    var consistency: [ConsistencyPoint] {
        get { (try? JSONDecoder().decode([ConsistencyPoint].self, from: consistencyData)) ?? [] }
        set { consistencyData = (try? JSONEncoder().encode(newValue)) ?? consistencyData }
    }

    var latestConsistency: Int? { consistency.last?.value }
    var isClarified: Bool { importance != nil }
    var isCustom: Bool { key.isEmpty }
    var idString: String { id.uuidString }

    /// "Curious, honest, kind"
    var qualitiesLine: String {
        qualities.joined(separator: ", ").capitalizedFirst
    }
}

@Model
final class DiaryCard {
    var id: UUID = UUID()
    /// Start of the day this card is for.
    var day: Date = Date.now
    var updatedAt: Date = Date.now
    /// Intensity stored 0–100 (the card's 0–5 × 20).
    var emotionsData: Data = Data()
    var urgesData: Data = Data()
    var skillsUsed: [String] = []
    var note: String = ""

    init(day: Date) {
        self.day = Calendar.current.startOfDay(for: day)
    }

    var emotions: [EmotionRating] {
        get { (try? JSONDecoder().decode([EmotionRating].self, from: emotionsData)) ?? [] }
        set { emotionsData = (try? JSONEncoder().encode(newValue)) ?? emotionsData }
    }

    var urges: [UrgeRating] {
        get { (try? JSONDecoder().decode([UrgeRating].self, from: urgesData)) ?? [] }
        set { urgesData = (try? JSONEncoder().encode(newValue)) ?? urgesData }
    }
}

enum CaptureStatus: String, Codable, Sendable {
    case inbox, processed, archived
}

/// A hot thought caught in the moment, to work through later.
@Model
final class QuickCapture {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var text: String = ""
    var familyRaw: String = ""
    var word: String = ""
    /// 0–10.
    var intensity: Int = 5
    var tag: String = ""
    var statusRaw: String = CaptureStatus.inbox.rawValue
    var sessionID: String = ""

    init(text: String) {
        self.text = text
    }

    var status: CaptureStatus {
        get { CaptureStatus(rawValue: statusRaw) ?? .inbox }
        set { statusRaw = newValue.rawValue }
    }

    var family: EmotionFamily? { EmotionFamily(rawValue: familyRaw) }
    var emotionLabel: String { word.isEmpty ? (family?.name ?? "") : word }
    var idString: String { id.uuidString }
}

/// A reframe card: front is the automatic thought, back is the user's own
/// balanced thought plus a piece of their own evidence.
@Model
final class PracticeCard {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var sessionID: String = ""
    var beliefID: String = ""
    var front: String = ""
    var back: String = ""
    var evidence: String = ""
    /// Leitner box, 1…`SpacedRepetition.intervals.count`.
    var box: Int = 1
    var dueAt: Date = Date.now
    var lastReviewedAt: Date?
    var reviewsData: Data = Data()
    var isArchived: Bool = false

    init(front: String, back: String, evidence: String, sessionID: String) {
        self.front = front
        self.back = back
        self.evidence = evidence
        self.sessionID = sessionID
    }

    var reviews: [PracticeReview] {
        get { (try? JSONDecoder().decode([PracticeReview].self, from: reviewsData)) ?? [] }
        set { reviewsData = (try? JSONEncoder().encode(newValue)) ?? reviewsData }
    }
}

enum PlanSource: String, Codable, Sendable {
    case manual, chain, experiment

    var label: String {
        switch self {
        case .manual: "Your plan"
        case .chain: "From a chain analysis"
        case .experiment: "From an experiment"
        }
    }
}

/// "If [trigger], then I'll [response]."
@Model
final class IfThenPlan {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var trigger: String = ""
    var response: String = ""
    var isActive: Bool = true
    var sourceRaw: String = PlanSource.manual.rawValue
    var sourceSessionID: String = ""
    var remindersOn: Bool = false
    var firesData: Data = Data()

    init(trigger: String, response: String, source: PlanSource, sourceSessionID: String = "") {
        self.trigger = trigger
        self.response = response
        self.sourceRaw = source.rawValue
        self.sourceSessionID = sourceSessionID
    }

    var source: PlanSource { PlanSource(rawValue: sourceRaw) ?? .manual }

    var fires: [PlanFire] {
        get { (try? JSONDecoder().decode([PlanFire].self, from: firesData)) ?? [] }
        set { firesData = (try? JSONEncoder().encode(newValue)) ?? firesData }
    }

    /// Share of recorded occasions where the plan fired, nil if none yet.
    var hitRate: Double? {
        let all = fires
        guard !all.isEmpty else { return nil }
        return Double(all.filter(\.fired).count) / Double(all.count)
    }

    var idString: String { id.uuidString }
}

/// Stanley-Brown safety plan. One per device.
@Model
final class SafetyPlan {
    var warningSigns: String = ""
    var copingAlone: String = ""
    var distractions: String = ""
    var contactsData: Data = Data()
    var professionals: String = ""
    var environment: String = ""
    var reasonsForLiving: String = ""
    var updatedAt: Date = Date.now

    init() {}

    var contacts: [SafetyContact] {
        get { (try? JSONDecoder().decode([SafetyContact].self, from: contactsData)) ?? [] }
        set { contactsData = (try? JSONEncoder().encode(newValue)) ?? contactsData }
    }
}

/// Skills settings that are personal enough to keep in the protected store
/// rather than `UserDefaults`.
@Model
final class TherapySettings {
    /// Urges tracked on the diary card ("avoid", "doomscroll"…).
    var trackedUrges: [String] = []

    init() {}
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
