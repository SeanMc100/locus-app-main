import SwiftUI
import SwiftData

/// CBT behavioral experiment: a prediction, an alternative, a plan to test
/// it, obstacles as if-then plans, then it waits (pending, with a
/// reminder) for real life. The outcome and learning come later, and feed
/// prediction calibration.
struct ExperimentFlow: View {
    let session: TherapySession
    let callbacks: FlowCallbacks

    @Environment(\.modelContext) private var modelContext
    @Environment(\.safetyGate) private var safetyGate

    enum Step: String {
        case prediction, alternative, plan, obstacles, schedule, scheduled, outcome, learning, complete
    }

    @State private var data = ExperimentData()
    @State private var step: Step = .prediction
    @State private var loaded = false

    private let accent = TherapyMethod.cbt.accent
    /// Planning, then (later) the outcome; `scheduled` isn't a numbered step.
    private let planSteps: [Step] = [.prediction, .alternative, .plan, .obstacles, .schedule]
    private let outcomeSteps: [Step] = [.outcome, .learning]

    private var progress: (position: Int, total: Int) {
        if let i = planSteps.firstIndex(of: step) { return (i + 1, planSteps.count) }
        if let i = outcomeSteps.firstIndex(of: step) { return (i + 1, outcomeSteps.count) }
        return (1, 1)
    }

    var body: some View {
        StepScaffold(toolTitle: session.tool.title, accent: accent, stepID: step.rawValue,
                     position: progress.position, total: progress.total,
                     showsProgress: step != .complete && step != .scheduled,
                     primaryTitle: primaryTitle, canContinue: canContinue,
                     secondaryTitle: step == .scheduled ? "It already happened: record it now" : nil,
                     onSecondary: { go(to: .outcome) },
                     onPrimary: primary,
                     onBack: backAction,
                     closesWithoutAsking: step == .complete || step == .scheduled,
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
        case .prediction:
            StepHeader(question: "What do you predict will happen?",
                       helper: "Make it specific enough that you'd know whether it came true.")
            FlowTextField(placeholder: "I predict that…", text: $data.prediction)
            VStack(alignment: .leading, spacing: 10) {
                Text("What exactly would you see or hear if it came true?")
                    .font(.system(.body, weight: .semibold))
                FlowTextField(placeholder: "Something observable…", text: $data.observable, minLines: 2)
            }
            PercentSlider(label: "How sure are you it will happen?", value: $data.confidence,
                          lowLabel: "Not at all", highLabel: "Certain", accent: accent)
            LedgerLinkView(thought: data.prediction, linkedBeliefID: $data.linkedBeliefID)
            SocraticPromptCard(step: .prediction, context: context)

        case .alternative:
            TargetThoughtCard(thought: data.prediction, label: "Your prediction", accent: accent)
            StepHeader(question: "What's another possible outcome?",
                       helper: "Not the best case: just another way it could realistically go.")
            FlowTextField(placeholder: "It could also…", text: $data.alternative)
            PercentSlider(label: "How sure are you of this one?", value: $data.alternativeConfidence,
                          lowLabel: "Not at all", highLabel: "Certain", accent: accent)
            SocraticPromptCard(step: .alternativePrediction, context: context)

        case .plan:
            TargetThoughtCard(thought: data.prediction, label: "Your prediction", accent: accent)
            StepHeader(question: "How could you test this?",
                       helper: "A small, safe experiment in real life. What you'd do is what you'll learn from.")
            labeled("What you'll do") {
                FlowTextField(placeholder: "I'll…", text: $data.action, minLines: 2)
            }
            labeled("When") {
                WhenPicker(date: $data.when)
            }
            labeled("What you'll watch for") {
                FlowTextField(placeholder: "How you'll know how it went…", text: $data.observe, minLines: 2)
            }
            labeled("Optional: anything you usually do to feel safe that might stop you learning the truth?") {
                FlowTextField(placeholder: "e.g. over-preparing, avoiding eye contact…", text: $data.safetyBehavior, minLines: 2)
            }
            SocraticPromptCard(step: .experimentPlan, context: context)

        case .obstacles:
            StepHeader(question: "What might get in the way, and how will you handle it?",
                       helper: "Deciding in advance makes it easier to follow through.")
            VStack(spacing: 12) {
                ForEach($data.obstacles) { $pair in
                    VStack(spacing: 8) {
                        FlowLineField(placeholder: "If…", text: $pair.trigger)
                        FlowLineField(placeholder: "then I'll…", text: $pair.response)
                    }
                    .padding(12)
                    .card(filled: true)
                }
            }
            SecondaryButton(title: "Add another", symbol: "plus") { data.obstacles.append(IfThen()) }
            Toggle(isOn: $data.saveObstaclesAsPlans) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save these as if-then plans")
                        .font(.system(.body, weight: .semibold))
                    Text("They'll appear in Practice, where you can keep them in mind.")
                        .font(.flowCaption)
                        .foregroundStyle(Ink.secondary)
                }
            }
            .tint(accent)

        case .schedule:
            StepHeader(question: "Ready to try it?",
                       helper: "Locus will remind you afterwards to record what actually happened.")
            VStack(alignment: .leading, spacing: 14) {
                OwnWordsBlock(title: "Prediction", text: data.prediction)
                OwnWordsBlock(title: "You'll", text: data.action)
                if let when = data.when {
                    OwnWordsBlock(title: "When", text: when.formatted(date: .abbreviated, time: .shortened))
                }
                OwnWordsBlock(title: "Watching for", text: data.observe)
            }
            .padding(16)
            .card()

        case .scheduled:
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "bell")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text("Experiment planned")
                    .font(.flowTitle)
                Text(scheduledLine)
                    .font(.flowBody)
                    .foregroundStyle(Ink.secondary)
                Text("It'll wait under In progress until then.")
                    .font(.flowHelper)
                    .foregroundStyle(Ink.tertiary)
            }

        case .outcome:
            TargetThoughtCard(thought: data.prediction, label: "Your prediction", accent: accent)
            StepHeader(question: "What actually happened?",
                       helper: "Describe it as a camera would have seen it.")
            FlowTextField(placeholder: "What happened was…", text: $data.outcome)
            VStack(alignment: .leading, spacing: 10) {
                Text("Did your prediction come true?")
                    .font(.system(.body, weight: .semibold))
                OptionRow(options: PredictionOutcome.allCases, selection: $data.cameTrue) { $0.label }
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("How bad was it, compared to what you expected?")
                    .font(.system(.body, weight: .semibold))
                PercentSlider(label: "How bad you expected it to be", value: $data.severityExpected,
                              lowLabel: "Not bad", highLabel: "Terrible", accent: accent, compact: true)
                PercentSlider(label: "How bad it actually was", value: $data.severityActual,
                              lowLabel: "Not bad", highLabel: "Terrible", accent: accent, compact: true)
            }

        case .learning:
            TargetThoughtCard(thought: data.prediction, label: "Your prediction", accent: accent)
            StepHeader(question: "What did you learn?",
                       helper: "Whatever happened, it's information you didn't have before.")
            FlowTextField(placeholder: "I learned…", text: $data.learning)
            VStack(alignment: .leading, spacing: 8) {
                Text("How much do you now believe the original prediction?")
                    .font(.system(.body, weight: .semibold))
                if let confidence = data.confidence {
                    Text("Before: \(Int(confidence))%")
                        .font(.flowCaption)
                        .foregroundStyle(Ink.tertiary)
                }
                PercentSlider(label: "Belief in the prediction now", value: $data.beliefAfter, accent: accent)
            }
            SocraticPromptCard(step: .experimentLearning, context: context)

        case .complete:
            CompletionContent(
                title: "You tested it",
                subtitle: "“\(data.prediction.trimmed)”",
                rows: completionRows,
                accent: accent
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        CapsLabel("Came true?")
                        Spacer()
                        Text(data.cameTrue?.label ?? "–")
                            .font(.system(.body, weight: .bold))
                    }
                    OwnWordsBlock(title: "What happened", text: data.outcome)
                    OwnWordsBlock(title: "What you learned", text: data.learning)
                }
                .padding(16)
                .card()
                Text("This experiment now counts toward your prediction calibration in Insights.")
                    .font(.flowCaption)
                    .foregroundStyle(Ink.tertiary)
            }
        }
    }

    private var completionRows: [ChangeRow] {
        var rows = [ChangeRow(label: "Belief in the prediction", before: data.confidence ?? 0, after: data.beliefAfter)]
        if let expected = data.severityExpected {
            rows.append(ChangeRow(label: "How bad: expected → actual", before: expected, after: data.severityActual))
        }
        return rows
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.body, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
    }

    private var scheduledLine: String {
        let when = (session.scheduledAt ?? data.when ?? .now)
        return "We'll check in with you after \(when.formatted(date: .abbreviated, time: .shortened))."
    }

    private var context: SocraticContext {
        SocraticContext(targetThought: data.prediction, priorAnswers: [
            "Alternative": data.alternative, "Plan": data.action, "Outcome": data.outcome,
        ].filter { !$0.value.trimmed.isEmpty })
    }

    // MARK: Navigation

    private var primaryTitle: String {
        switch step {
        case .schedule: "Schedule it"
        case .scheduled, .complete: "Done"
        case .learning: "Finish"
        default: "Next"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .prediction: !data.prediction.trimmed.isEmpty && data.confidence != nil
        case .alternative: !data.alternative.trimmed.isEmpty && data.alternativeConfidence != nil
        case .plan: !data.action.trimmed.isEmpty && data.when != nil
        case .obstacles, .schedule, .scheduled, .complete: true
        case .outcome: !data.outcome.trimmed.isEmpty && data.cameTrue != nil
            && data.severityExpected != nil && data.severityActual != nil
        case .learning: data.beliefAfter != nil
        }
    }

    private var backAction: (() -> Void)? {
        switch step {
        case .prediction: return callbacks.onBackFromStart
        case .scheduled, .complete: return nil
        case .outcome: return session.status == .pending ? nil : { go(to: .scheduled) }
        default:
            if let i = planSteps.firstIndex(of: step), i > 0 { return { go(to: planSteps[i - 1]) } }
            if let i = outcomeSteps.firstIndex(of: step), i > 0 { return { go(to: outcomeSteps[i - 1]) } }
            return nil
        }
    }

    private func primary() {
        switch step {
        case .scheduled, .complete:
            callbacks.onNext(.done)
        case .schedule:
            let when = data.when ?? .now.addingTimeInterval(3600)
            if data.saveObstaclesAsPlans {
                PracticeService.addPlans(data.obstacles, source: .experiment, sessionID: session.idString, in: modelContext)
                data.saveObstaclesAsPlans = false
            }
            session.targetThought = data.prediction.trimmed
            // Check in an hour after the planned time.
            SessionService.schedule(session, at: when, reminderDelay: 3600,
                                    title: "How did your experiment go?",
                                    body: "Tap to record what actually happened.", in: modelContext)
            go(to: .scheduled)
        default:
            safetyGate.check(data) {
                switch step {
                case .prediction: go(to: .alternative)
                case .alternative: go(to: .plan)
                case .plan: go(to: .obstacles)
                case .obstacles: go(to: .schedule)
                case .outcome: go(to: .learning)
                case .learning:
                    finish()
                    go(to: .complete)
                default: break
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

    private func finish() {
        SessionService.complete(
            session, metricBefore: data.confidence, metricAfter: data.beliefAfter,
            belief: .init(beliefID: data.linkedBeliefID, kind: .belief, before: data.confidence, after: data.beliefAfter),
            in: modelContext)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        data = session.decode(ExperimentData.self) ?? ExperimentData()
        step = Step(rawValue: session.stepKey) ?? .prediction
        switch session.status {
        case .pending:
            // Back from the reminder or In progress: straight to the outcome.
            if step == .scheduled || step == .schedule { step = .outcome }
        case .complete:
            step = .complete
        case .draft:
            break
        }
    }
}
