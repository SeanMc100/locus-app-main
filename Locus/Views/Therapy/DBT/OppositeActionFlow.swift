import SwiftUI
import SwiftData

/// DBT opposite action: the emotion and its urge; a check that the emotion
/// doesn't fit the facts (skipped when coming from Check the Facts); the
/// user's own opposite action, done all the way; then schedule it and
/// check back.
struct OppositeActionFlow: View {
    let session: TherapySession
    let callbacks: FlowCallbacks

    @Environment(\.modelContext) private var modelContext
    @Environment(\.safetyGate) private var safetyGate

    enum Step: String {
        case emotionUrge, justified, problemSolving, action, allTheWay, schedule, doing, scheduled, followUp, complete
    }

    @State private var data = OppositeActionData()
    @State private var step: Step = .emotionUrge
    @State private var loaded = false

    private let accent = TherapyMethod.dbt.accent

    /// Emotion fits: problem solving instead of opposite action.
    private var fits: Bool { data.fit == .fits || data.fit == .partly }

    private var planSteps: [Step] {
        var s: [Step] = [.emotionUrge]
        if !data.fromCheckFacts { s.append(.justified) }
        if fits { return s + [.problemSolving, .followUp] }
        return s + [.action, .allTheWay, .schedule]
    }

    private var progress: (position: Int, total: Int) {
        if let i = planSteps.firstIndex(of: step) { return (i + 1, planSteps.count) }
        return (1, 1)
    }

    private var emotionBinding: Binding<[EmotionRating]> {
        Binding(get: { data.emotion.map { [$0] } ?? [] }, set: { data.emotion = $0.first })
    }

    private var emotionName: String { data.emotion?.word ?? "the emotion" }

    private var suggestions: [String] {
        guard let emotion = data.emotion else { return [] }
        if EmotionFamily.guiltWords.contains(emotion.word) { return EmotionFamily.guiltOppositeActions }
        return emotion.family.oppositeActions
    }

    var body: some View {
        StepScaffold(toolTitle: session.tool.title, accent: accent, stepID: step.rawValue,
                     position: progress.position, total: progress.total,
                     showsProgress: planSteps.contains(step) && step != .followUp,
                     primaryTitle: primaryTitle, canContinue: canContinue,
                     secondaryTitle: step == .scheduled ? "I've done it: check in now" : nil,
                     onSecondary: { go(to: .followUp) },
                     onPrimary: primary,
                     onBack: backAction,
                     closesWithoutAsking: [.complete, .scheduled, .doing].contains(step),
                     onSaveForLater: callbacks.onClose,
                     onDiscard: callbacks.onDiscard) {
            content
        }
        .onAppear(perform: load)
        .onChange(of: data) { _, new in session.store(new) }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .emotionUrge:
            if data.fromCheckFacts, let emotion = data.emotion {
                TargetThoughtCard(thought: "\(emotion.word.capitalizedFirst), \(Int(emotion.intensity))%", label: "The emotion", accent: accent)
                StepHeader(question: "What does \(emotion.word) urge you to do?",
                           helper: "Every emotion comes with an urge: to hide, to attack, to avoid, to withdraw.")
            } else {
                StepHeader(question: "What emotion is it, and what does it urge you to do?",
                           helper: "Every emotion comes with an urge: to hide, to attack, to avoid, to withdraw.")
                EmotionPicker(ratings: emotionBinding, allowsMultiple: false, accent: accent)
            }
            FlowTextField(placeholder: "It makes me want to…", text: $data.urge, minLines: 2)

        case .justified:
            emotionCard
            StepHeader(question: "Does the emotion fit the facts?",
                       helper: "Opposite action is for emotions that don't fit the situation, or are much bigger than it.")
            if let family = data.emotion?.family {
                NoticeCard(text: family.fitsWhen, symbol: "info.circle")
            }
            OptionRow(options: FactsFit.allCases, selection: $data.fit) { $0.label }
            if fits {
                NoticeCard(text: "If it fits, acting against it isn't the goal. Solving the problem it's pointing at usually helps more; that's next.",
                           symbol: "arrow.turn.down.right")
                    .transition(.opacity)
            }

        case .problemSolving:
            emotionCard
            StepHeader(question: "What could you do about the situation?",
                       helper: "When the emotion fits, it's pointing at a real problem worth working on.")
            FlowTextField(placeholder: "One thing I could do…", text: $data.problemSolving)
            SocraticPromptCard(step: .problemSolving)

        case .action:
            emotionCard
            StepHeader(question: "What's the opposite of that urge, for you, here?",
                       helper: "Be specific: what you'll do, where, and with whom. These are starting points; write your own.")
            if !suggestions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { idea in
                        ChoiceCard(title: idea, symbol: "lightbulb", accent: accent) {
                            data.action = data.action.trimmed.isEmpty ? idea : data.action
                        }
                    }
                }
            }
            FlowTextField(placeholder: "Specifically, I'll…", text: $data.action)
            SocraticPromptCard(step: .oppositeAction)

        case .allTheWay:
            TargetThoughtCard(thought: data.action, label: "Your opposite action", accent: accent)
            StepHeader(question: "Do it all the way.",
                       helper: "Opposite action works best when it's done fully, not just the behavior.")
            VStack(alignment: .leading, spacing: 12) {
                allTheWayRow("figure.stand", "Posture", "Stand or sit the way you would if you felt differently.")
                allTheWayRow("face.smiling", "Face", "Relax your face; a half-smile if it fits.")
                allTheWayRow("waveform", "Voice", "Speak at the tone and pace of someone calm.")
                allTheWayRow("brain", "Thoughts", "Let go of thoughts that feed the emotion, as best you can.")
            }

        case .schedule:
            TargetThoughtCard(thought: data.action, label: "Your opposite action", accent: accent)
            StepHeader(question: "When will you do it?")
            OptionRow(options: [true, false], selection: $data.doNow) { $0 ? "Now" : "Later" }
            if data.doNow == false {
                WhenPicker(date: $data.when)
            }

        case .doing:
            waiting("Go for it", "Do it now, all the way. Come back when you're done.")

        case .scheduled:
            waiting("Planned", "We'll remind you at \((session.scheduledAt ?? .now).formatted(date: .abbreviated, time: .shortened)). It'll wait under In progress.")

        case .followUp:
            emotionCard
            if !fits {
                StepHeader(question: "Did you do it?")
                OptionRow(options: [true, false], selection: $data.did) { $0 ? "Yes" : "Not this time" }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("How strong is \(emotionName) now?")
                    .font(.system(.body, weight: .semibold))
                PercentSlider(label: "\(emotionName.capitalizedFirst) now", value: $data.intensityAfter,
                              lowLabel: "None", highLabel: "Strongest", accent: accent)
            }

        case .complete:
            CompletionContent(
                title: fits ? "You made a plan" : (data.did == true ? "You acted against the urge" : "Checked in"),
                rows: data.emotion.map { [ChangeRow(label: $0.word.capitalizedFirst, before: $0.intensity, after: data.intensityAfter)] } ?? [],
                accent: accent
            ) {
                OwnWordsBlock(title: fits ? "What you could do" : "Your opposite action", text: fits ? data.problemSolving : data.action)
            }
        }
    }

    @ViewBuilder
    private var emotionCard: some View {
        if let emotion = data.emotion {
            TargetThoughtCard(thought: "\(emotion.word.capitalizedFirst), \(Int(emotion.intensity))%" + (data.urge.trimmed.isEmpty ? "" : ": urge to \(data.urge.trimmed)"),
                              label: "The emotion", accent: accent)
        }
    }

    private func allTheWayRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.body, weight: .semibold))
                Text(detail).font(.flowHelper).foregroundStyle(Ink.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func waiting(_ title: String, _ line: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: TherapyTool.oppositeAction.symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(title).font(.flowTitle)
            Text(line).font(.flowBody).foregroundStyle(Ink.secondary)
        }
    }

    // MARK: Navigation

    private var primaryTitle: String {
        switch step {
        case .schedule: data.doNow == true ? "Start now" : "Plan it"
        case .doing: "I'm back"
        case .scheduled, .complete: "Done"
        case .followUp: "Finish"
        default: "Next"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .emotionUrge: data.emotion != nil && !data.urge.trimmed.isEmpty
        case .justified: data.fit != nil
        case .problemSolving: !data.problemSolving.trimmed.isEmpty
        case .action: !data.action.trimmed.isEmpty
        case .schedule: data.doNow == true || (data.doNow == false && data.when != nil)
        case .followUp: data.intensityAfter != nil && (fits || data.did != nil)
        default: true
        }
    }

    private var backAction: (() -> Void)? {
        guard let i = planSteps.firstIndex(of: step), !(step == .followUp && !fits) else { return nil }
        if i == 0 { return callbacks.onBackFromStart }
        return { go(to: planSteps[i - 1]) }
    }

    private func primary() {
        switch step {
        case .schedule:
            session.targetThought = data.action.trimmed
            if data.doNow == true {
                session.status = .pending
                session.scheduledAt = .now
                try? modelContext.save()
                go(to: .doing)
            } else {
                SessionService.schedule(session, at: data.when ?? .now.addingTimeInterval(3600),
                                        title: "Time for your opposite action",
                                        body: "Tap to check in afterwards.", in: modelContext)
                go(to: .scheduled)
            }
        case .doing:
            go(to: .followUp)
        case .scheduled, .complete:
            callbacks.onNext(.done)
        case .followUp:
            SessionService.complete(session, metricBefore: data.emotion?.intensity, metricAfter: data.intensityAfter,
                                    in: modelContext)
            go(to: .complete)
        default:
            safetyGate.check(data) {
                if let i = planSteps.firstIndex(of: step), i + 1 < planSteps.count {
                    go(to: planSteps[i + 1])
                }
            }
        }
    }

    private func go(to newStep: Step) {
        hideKeyboard()
        withAnimation(.gentle) { step = newStep }
        let p = progress
        session.record(step: newStep.rawValue, position: p.position, total: p.total)
        try? modelContext.save()
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        data = session.decode(OppositeActionData.self) ?? OppositeActionData()
        step = Step(rawValue: session.stepKey) ?? .emotionUrge
        switch session.status {
        case .pending: step = .followUp
        case .complete: step = .complete
        case .draft: break
        }
    }
}
