#if DEBUG
import Foundation
import SwiftData

/// UI tests only (`-uiTesting -seedSkillsDemo`): a few weeks of plausible
/// skills records so Insights has something to compute. Never runs on real
/// stores; the test container is in-memory or throwaway.
@MainActor
enum SkillsDemoData {
    static func seed(in context: ModelContext) {
        let cal = Calendar.current
        func daysAgo(_ d: Int, hour: Int = 20) -> Date {
            let day = cal.date(byAdding: .day, value: -d, to: .now) ?? .now
            return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        func complete(_ tool: TherapyTool, _ date: Date, before: Double?, after: Double?, _ store: (TherapySession) -> Void) {
            let s = TherapySession(tool: tool)
            s.createdAt = date
            s.updatedAt = date
            s.completedAt = date.addingTimeInterval(900)
            s.status = .complete
            s.metricBefore = before
            s.metricAfter = after
            store(s)
            context.insert(s)
        }

        let belief = LedgerBelief(canonicalText: "I'm falling behind")
        belief.createdAt = daysAgo(20)
        context.insert(belief)

        // Five experiments: feared predictions that mostly didn't come true.
        let experiments: [(Double, PredictionOutcome, Double, Double)] = [
            (90, .no, 80, 10), (80, .partly, 80, 30), (70, .no, 70, 5), (85, .yes, 90, 40), (60, .no, 60, 10),
        ]
        for (i, e) in experiments.enumerated() {
            complete(.behavioralExperiment, daysAgo(18 - i * 3), before: e.0, after: e.0 - 40) { s in
                var d = ExperimentData()
                d.prediction = "The meeting will go badly"
                d.confidence = e.0
                d.cameTrue = e.1
                d.severityExpected = e.2
                d.severityActual = e.3
                d.outcome = "It was mostly fine."
                d.beliefAfter = e.0 - 40
                s.targetThought = d.prediction
                s.store(d)
            }
        }

        // Thought records linked to the belief, with emotions and traps.
        var ratings: [BeliefRatingPoint] = []
        for (i, pair) in [(90.0, 60.0), (80.0, 45.0), (70.0, 35.0)].enumerated() {
            let date = daysAgo(15 - i * 5, hour: 8)
            complete(.thoughtRecord, date, before: 85, after: 40) { s in
                var d = ThoughtRecordData()
                d.situation = "At work"
                d.thoughts = ["I'm falling behind"]
                d.emotionsBefore = [EmotionRating(family: .fear, word: "anxious", intensity: 85)]
                d.emotionsAfter = [EmotionRating(family: .fear, word: "anxious", intensity: 40, phase: .after)]
                d.beliefBefore = pair.0
                d.beliefAfter = pair.1
                d.distortions = ["overgeneralization", "mindReading"]
                d.evidenceAgainst = "Shipped the project on time."
                d.balancedThought = "I'm behind on one thing, not everything."
                d.linkedBeliefID = belief.idString
                s.linkedBeliefIDs = [belief.idString]
                s.targetThought = "I'm falling behind"
                s.store(d)
                belief.sessionIDs.append(s.idString)
                ratings += [BeliefRatingPoint(date: date, value: pair.0, kind: .belief, phase: .before, sessionID: s.idString),
                            BeliefRatingPoint(date: date.addingTimeInterval(900), value: pair.1, kind: .belief, phase: .after, sessionID: s.idString)]
            }
        }
        belief.ratings = ratings
        belief.lastSeenAt = daysAgo(5)

        // Crisis skills and activation for "what helps".
        for i in 0..<3 {
            complete(.crisisSkills, daysAgo(10 - i * 3, hour: 22), before: 80, after: 40) { s in
                var d = CrisisData(); d.intensityBefore = 8; d.intensityAfter = 4; d.skill = .tipp; d.tippDone = [.breathing]
                s.store(d)
            }
            complete(.behavioralActivation, daysAgo(9 - i * 3, hour: 11), before: 30, after: 60) { s in
                var d = ActivationData(); d.activity = "Walk for 10 minutes"; d.moodBefore = 3; d.moodAfter = 6; d.did = true
                s.store(d)
            }
        }

        // Two chains with a shared vulnerability.
        for i in 0..<2 {
            complete(.chainAnalysis, daysAgo(12 - i * 6), before: nil, after: nil) { s in
                var d = ChainData()
                d.problemBehavior = "Snapped at my partner"
                d.promptingEvent = "Asked about the bill"
                d.vulnerabilities = ["Poor sleep"] + (i == 0 ? ["Stress"] : [])
                d.links = [ChainLink(kind: .thought, text: "I'm useless"), ChainLink(kind: .urge, text: "Shut it down")]
                s.store(d)
            }
        }

        let capture = QuickCapture(text: "They're all judging me")
        capture.familyRaw = EmotionFamily.shame.rawValue
        capture.word = "embarrassed"
        capture.intensity = 7
        capture.tag = "Work"
        capture.createdAt = daysAgo(2, hour: 9)
        context.insert(capture)

        try? context.save()
    }
}
#endif
