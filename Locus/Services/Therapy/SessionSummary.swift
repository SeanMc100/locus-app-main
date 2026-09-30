import Foundation

/// A tool-independent, readable summary of a session: labelled blocks of
/// the user's own words plus before/after numbers. Used by the session
/// detail screen and by export.
struct SessionSummary {
    struct Block: Hashable {
        let title: String
        let text: String
    }

    struct Change: Hashable {
        let label: String
        let before: Double
        let after: Double?
        /// 10 or 100.
        let scale: Double
    }

    var blocks: [Block] = []
    var changes: [Change] = []
    var chain: ChainData?

    init(session: TherapySession) {
        func add(_ title: String, _ text: String?) {
            guard let text, !text.trimmed.isEmpty else { return }
            blocks.append(Block(title: title, text: text.trimmed))
        }
        func pct(_ label: String, _ before: Double?, _ after: Double?) {
            guard let before else { return }
            changes.append(Change(label: label, before: before, after: after, scale: 100))
        }
        func ten(_ label: String, _ before: Int?, _ after: Int?) {
            guard let before else { return }
            changes.append(Change(label: label, before: Double(before), after: after.map(Double.init), scale: 10))
        }
        func emotions(_ list: [EmotionRating]) -> String {
            list.map { "\($0.word.capitalizedFirst) \(Int($0.intensity))%" }.joined(separator: ", ")
        }

        switch session.tool {
        case .thoughtRecord:
            guard let d = session.decode(ThoughtRecordData.self) else { return }
            add("Situation", d.situation)
            add("Emotions", emotions(d.emotionsBefore))
            add("Automatic thoughts", d.enteredThoughts.joined(separator: "\n"))
            add("Hot thought", d.hotThought)
            add("Thinking traps", d.noDistortions ? "None of these" : d.distortions.compactMap { Distortions.named($0)?.name }.joined(separator: ", "))
            add("Evidence for", d.evidenceFor)
            add("Evidence against", d.evidenceAgainst)
            add("Balanced thought", d.balancedThought + (d.balancedBelief.map { " (believed \(Int($0))%)" } ?? ""))
            pct("Belief in the thought", d.beliefBefore, d.beliefAfter)
            for e in d.emotionsBefore {
                pct(e.word.capitalizedFirst, e.intensity, d.emotionsAfter.first { $0.word == e.word && $0.family == e.family }?.intensity)
            }
        case .behavioralExperiment:
            guard let d = session.decode(ExperimentData.self) else { return }
            add("Prediction", d.prediction + (d.confidence.map { " (\(Int($0))% sure)" } ?? ""))
            add("What would show it came true", d.observable)
            add("Alternative", d.alternative + (d.alternativeConfidence.map { " (\(Int($0))% sure)" } ?? ""))
            add("The experiment", d.action)
            add("When", d.when?.formatted(date: .abbreviated, time: .shortened))
            add("Watching for", d.observe)
            add("Safety behavior to drop", d.safetyBehavior)
            add("If-then plans", d.obstacles.filter(\.isFilled).map { "If \($0.trigger), then I'll \($0.response)." }.joined(separator: "\n"))
            add("What happened", d.outcome)
            add("Came true?", d.cameTrue?.label)
            add("What you learned", d.learning)
            pct("Belief in the prediction", d.confidence, d.beliefAfter)
            pct("How bad: expected → actual", d.severityExpected, d.severityActual)
        case .behavioralActivation:
            guard let d = session.decode(ActivationData.self) else { return }
            add("Activity", d.activity + (d.category.map { " (\($0.label.lowercased()))" } ?? ""))
            add("Did it?", d.did.map { $0 ? "Yes" : "Not this time" })
            add("Mastery / pleasure", d.mastery.map { m in "\(m)/10 · \(d.pleasure ?? 0)/10" })
            ten("Mood", d.moodBefore, d.moodAfter)
            ten("Energy (before)", d.energyBefore, nil)
        case .crisisSkills:
            guard let d = session.decode(CrisisData.self) else { return }
            add("Skill", d.skill == .stop ? "STOP" : (d.tippDone.isEmpty ? "TIPP" : "TIPP: " + d.tippDone.map(\.title).joined(separator: ", ")))
            add("Observed", d.observe)
            add("Proceeding with", d.proceed)
            ten("Intensity", d.intensityBefore, d.intensityAfter)
        case .checkTheFacts:
            guard let d = session.decode(CheckFactsData.self) else { return }
            add("Emotion", d.emotion.map { "\($0.word.capitalizedFirst) \(Int($0.intensity))%" })
            add("Prompting event", d.event)
            add("Interpretations", d.interpretations)
            add("Other interpretations", d.otherInterpretations)
            add("Threat", d.threat + (d.threatLikelihood.map { " (\(Int($0))% likely)" } ?? ""))
            add("Worst realistic outcome", d.catastrophe)
            add("How you'd cope", d.coping)
            add("Fits the facts?", d.fit?.label)
            add("Problem solving", d.problemSolving)
            add("Did the threat happen?", d.threatHappened?.label)
            pct(d.emotion?.word.capitalizedFirst ?? "Emotion", d.emotion?.intensity, d.intensityAfter)
        case .oppositeAction:
            guard let d = session.decode(OppositeActionData.self) else { return }
            add("Emotion", d.emotion.map { "\($0.word.capitalizedFirst) \(Int($0.intensity))%" })
            add("Urge", d.urge)
            add("Fits the facts?", d.fit?.label)
            add("Problem solving", d.problemSolving)
            add("Opposite action", d.action)
            add("Did it?", d.did.map { $0 ? "Yes" : "Not this time" })
            pct(d.emotion?.word.capitalizedFirst ?? "Emotion", d.emotion?.intensity, d.intensityAfter)
        case .chainAnalysis:
            guard let d = session.decode(ChainData.self) else { return }
            chain = d
            add("Repair", d.repair)
        case .defusion:
            guard let d = session.decode(DefusionData.self) else { return }
            add("Thought", d.thought)
            add("Techniques", d.techniquesUsed.map(\.title).joined(separator: ", "))
            add("Story name", d.storyName)
            add("Leaves", d.leaves.joined(separator: "\n"))
            add("What matters", d.whatMatters)
            pct("How hooked", d.hookedBefore, d.hookedAfter)
        case .valuesCheckIn:
            guard let d = session.decode(ValuesCheckInData.self) else { return }
            add("Check-in", d.ratings.isEmpty ? nil : "\(d.ratings.count) value area\(d.ratings.count == 1 ? "" : "s") rated")
        case .committedAction:
            guard let d = session.decode(CommittedActionData.self) else { return }
            add("Value", d.valueName)
            add("Small step", d.step)
            add("Barriers", d.barriers)
            add("Did it?", d.did.map { $0 ? "Yes" : "Not this time" })
            add("How it felt", d.howFelt)
        }
    }
}
