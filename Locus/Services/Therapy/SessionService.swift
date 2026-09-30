import Foundation
import SwiftData
import SwiftUI

/// What a flow starts from: where it came from and what carries over.
struct TherapyLaunch: Hashable {
    var sourceEntryID = ""
    var sourceCaptureID = ""
    var entryText = ""
    var targetThought = ""
    var emotion: EmotionRating?
    var triage: TriageAnswers?
    /// After crisis skills: the tool the triage matched.
    var followUpTool: TherapyTool?
    var valueDomainID: String?
    var linkedBeliefID: String?
    var fromCheckFacts = false
    var isPractice = false
}

/// What a flow asks the host to do when it ends.
enum FlowNext {
    case done
    case start(TherapyTool, TherapyLaunch)
}

/// How a tool flow talks to the host.
struct FlowCallbacks {
    /// Back from the first step (to the tool picker); nil when resumed.
    var onBackFromStart: (() -> Void)?
    /// Close, keeping the draft ("Save and finish later").
    let onClose: () -> Void
    /// Close and delete this session.
    let onDiscard: () -> Void
    let onNext: (FlowNext) -> Void
}

/// Runs the risk check on text a step collected before moving on. The host
/// shows the safety screen when something new is found, then calls
/// `proceed` if the user chooses to carry on.
struct SafetyGate {
    var check: @MainActor (_ text: String, _ proceed: @escaping () -> Void) -> Void

    @MainActor
    func check<T: Encodable>(_ draft: T, then proceed: @escaping () -> Void) {
        check(SafetyText.strings(in: draft), proceed)
    }
}

extension EnvironmentValues {
    @Entry var safetyGate = SafetyGate { _, proceed in proceed() }
}

@MainActor
enum SessionService {

    static func start(_ tool: TherapyTool, launch: TherapyLaunch, in context: ModelContext) -> TherapySession {
        let session = TherapySession(tool: tool)
        session.sourceEntryID = launch.sourceEntryID
        session.sourceCaptureID = launch.sourceCaptureID
        session.targetThought = launch.targetThought.trimmed
        session.triage = launch.triage
        session.followUpTool = launch.followUpTool
        session.isPractice = launch.isPractice
        if let belief = launch.linkedBeliefID { session.linkedBeliefIDs = [belief] }

        let thought = launch.targetThought.trimmed
        switch tool {
        case .thoughtRecord:
            var data = ThoughtRecordData()
            if !thought.isEmpty { data.thoughts = [thought] }
            if let emotion = launch.emotion { data.emotionsBefore = [emotion] }
            data.linkedBeliefID = launch.linkedBeliefID
            session.store(data)
        case .behavioralExperiment:
            var data = ExperimentData()
            data.prediction = thought
            data.linkedBeliefID = launch.linkedBeliefID
            session.store(data)
        case .behavioralActivation:
            var data = ActivationData()
            data.valueDomainID = launch.valueDomainID
            session.store(data)
        case .crisisSkills:
            session.store(CrisisData())
        case .checkTheFacts:
            var data = CheckFactsData()
            data.emotion = launch.emotion
            session.store(data)
        case .oppositeAction:
            var data = OppositeActionData()
            data.emotion = launch.emotion
            data.fromCheckFacts = launch.fromCheckFacts
            if launch.fromCheckFacts { data.fit = .doesnt }
            session.store(data)
        case .chainAnalysis:
            session.store(ChainData())
        case .defusion:
            var data = DefusionData()
            data.thought = thought
            data.linkedBeliefID = launch.linkedBeliefID
            session.store(data)
        case .valuesCheckIn:
            session.store(ValuesCheckInData())
        case .committedAction:
            var data = CommittedActionData()
            data.valueDomainID = launch.valueDomainID
            if let id = launch.valueDomainID, let domain = context.valueDomain(id: id) {
                data.valueName = domain.name
            }
            session.store(data)
        }

        context.insert(session)
        if !launch.sourceCaptureID.isEmpty, let capture = context.capture(id: launch.sourceCaptureID) {
            capture.status = .processed
            capture.sessionID = session.idString
        }
        try? context.save()
        return session
    }

    /// Ratings to add to a Belief Ledger entry when a session completes.
    struct BeliefUpdate {
        var beliefID: String?
        var kind: BeliefRatingKind
        var before: Double?
        var after: Double?
        var storyName: String = ""
    }

    static func complete(_ session: TherapySession, metricBefore: Double?, metricAfter: Double?,
                         belief: BeliefUpdate? = nil, in context: ModelContext) {
        let firstCompletion = session.status != .complete
        session.status = .complete
        if session.completedAt == nil { session.completedAt = .now }
        session.metricBefore = metricBefore
        session.metricAfter = metricAfter
        session.updatedAt = .now

        if let belief, let id = belief.beliefID, let ledger = context.belief(id: id) {
            if !session.linkedBeliefIDs.contains(id) { session.linkedBeliefIDs.append(id) }
            if firstCompletion || !ledger.sessionIDs.contains(session.idString) {
                var ratings = ledger.ratings.filter { $0.sessionID != session.idString }
                if let before = belief.before {
                    ratings.append(BeliefRatingPoint(date: session.createdAt, value: before, kind: belief.kind,
                                                     phase: .before, sessionID: session.idString))
                }
                if let after = belief.after {
                    ratings.append(BeliefRatingPoint(date: session.completedAt ?? .now, value: after, kind: belief.kind,
                                                     phase: .after, sessionID: session.idString))
                }
                ledger.ratings = ratings
                if !ledger.sessionIDs.contains(session.idString) { ledger.sessionIDs.append(session.idString) }
                ledger.lastSeenAt = .now
            }
            if !belief.storyName.trimmed.isEmpty { ledger.storyName = belief.storyName.trimmed }
        }

        if !session.sourceCaptureID.isEmpty, let capture = context.capture(id: session.sourceCaptureID) {
            capture.status = .processed
            capture.sessionID = session.idString
        }
        ReminderScheduler.cancel(sessionID: session.idString)
        try? context.save()
    }

    /// Mark as waiting on real life, with a reminder to come back.
    static func schedule(_ session: TherapySession, at date: Date, reminderDelay: TimeInterval = 0,
                         title: String, body: String, in context: ModelContext) {
        session.status = .pending
        session.scheduledAt = date
        session.updatedAt = .now
        try? context.save()
        ReminderScheduler.scheduleSession(id: session.idString, at: date.addingTimeInterval(reminderDelay),
                                          title: title, body: body)
    }

    static func discard(_ session: TherapySession, in context: ModelContext) {
        if !session.sourceCaptureID.isEmpty, let capture = context.capture(id: session.sourceCaptureID),
           capture.sessionID == session.idString {
            capture.status = .inbox
            capture.sessionID = ""
        }
        ReminderScheduler.cancel(sessionID: session.idString)
        context.delete(session)
        try? context.save()
    }

    /// Text of the journal entry or capture a session came from.
    static func sourceText(for session: TherapySession, in context: ModelContext) -> String {
        if let entry = context.journalEntry(linkID: session.sourceEntryID) { return entry.text }
        if let capture = context.capture(id: session.sourceCaptureID) { return capture.text }
        return ""
    }
}

extension TherapySession {
    /// Where the flow is, so it resumes there and "In progress" can say
    /// "Step 3 of 9".
    func record(step: String, position: Int, total: Int) {
        guard stepKey != step || stepPosition != position || stepTotal != total else { return }
        stepKey = step
        stepPosition = position
        stepTotal = total
        updatedAt = .now
    }

    /// What the before/after metric measures, for insights labels.
    var metricName: String {
        switch tool {
        case .thoughtRecord: "Emotion intensity"
        case .behavioralExperiment: "Belief in the prediction"
        case .behavioralActivation: "Mood"
        case .crisisSkills, .checkTheFacts, .oppositeAction: "Intensity"
        case .defusion: "How hooked"
        case .chainAnalysis, .valuesCheckIn, .committedAction: ""
        }
    }
}

enum EmotionMath {
    static func average(_ ratings: [EmotionRating]) -> Double? {
        guard !ratings.isEmpty else { return nil }
        return ratings.map(\.intensity).reduce(0, +) / Double(ratings.count)
    }

    /// Before/after rows for each emotion rated both times.
    static func changeRows(before: [EmotionRating], after: [EmotionRating]) -> [ChangeRow] {
        before.map { b in
            let a = after.first { $0.family == b.family && $0.word == b.word }
            return ChangeRow(label: b.word.capitalizedFirst, before: b.intensity, after: a?.intensity)
        }
    }
}

@MainActor
enum PracticeService {
    /// A reframe card from a finished thought record (opt-in).
    static func addCard(front: String, back: String, evidence: String, sessionID: String, beliefID: String?,
                        in context: ModelContext) {
        let card = PracticeCard(front: front, back: back, evidence: firstSentence(of: evidence), sessionID: sessionID)
        card.beliefID = beliefID ?? ""
        card.dueAt = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        context.insert(card)
        try? context.save()
    }

    static func addPlans(_ pairs: [IfThen], source: PlanSource, sessionID: String, in context: ModelContext) {
        for pair in pairs where pair.isFilled {
            context.insert(IfThenPlan(trigger: pair.trigger.trimmed, response: pair.response.trimmed,
                                      source: source, sourceSessionID: sessionID))
        }
        try? context.save()
    }

    private static func firstSentence(of text: String) -> String {
        let sentences = SentenceSplitter.sentences(in: text)
        guard let first = sentences.first else { return text.trimmed }
        return first.count > 220 ? String(first.prefix(220)) + "…" : first
    }
}
