import SwiftUI
import SwiftData

/// DBT check the facts: name the emotion, separate the prompting event from
/// the interpretations, look at the threat and the catastrophe, then ask
/// whether the emotion fits. If it doesn't, Opposite Action is next.
struct CheckFactsFlow: View {
    let session: TherapySession
    let callbacks: FlowCallbacks

    @Environment(\.modelContext) private var modelContext
    @Environment(\.safetyGate) private var safetyGate

    enum Step: String {
        case emotion, event, interpretations, threat, catastrophe, fit, route, rerate, complete
    }

    @State private var data = CheckFactsData()
    @State private var step: Step = .emotion
    @State private var loaded = false

    private let accent = TherapyMethod.dbt.accent
    private let steps: [Step] = [.emotion, .event, .interpretations, .threat, .catastrophe, .fit, .route, .rerate, .complete]
    private var index: Int { steps.firstIndex(of: step) ?? 0 }

    private var emotionBinding: Binding<[EmotionRating]> {
        Binding(get: { data.emotion.map { [$0] } ?? [] }, set: { data.emotion = $0.first })
    }

    private var emotionName: String { data.emotion?.word ?? "the emotion" }

    var body: some View {
        StepScaffold(toolTitle: session.tool.title, accent: accent, stepID: step.rawValue,
                     position: index + 1, total: steps.count - 1,
                     showsProgress: step != .complete,
                     primaryTitle: primaryTitle, canContinue: canContinue,
                     onPrimary: primary,
                     onBack: backAction,
                     closesWithoutAsking: step == .complete,
                     onSaveForLater: callbacks.onClose,
                     onDiscard: callbacks.onDiscard) {
            content
        }
        .onAppear(perform: load)
        .onChange(of: data) { _, new in session.store(new) }
    }

    @ViewBuilder
    private var content: some View {
        if step != .emotion && step != .complete, let emotion = data.emotion {
            TargetThoughtCard(thought: "\(emotion.word.capitalizedFirst), \(Int(emotion.intensity))%", label: "The emotion", accent: accent)
        }
        switch step {
        case .emotion:
            TargetThoughtCard(thought: session.targetThought, accent: accent)
            StepHeader(question: "What emotion are you feeling?",
                       helper: "Pick the main one, and how strong it is.")
            EmotionPicker(ratings: emotionBinding, allowsMultiple: false, accent: accent)

        case .event:
            StepHeader(question: "What happened that set this off?",
                       helper: "Describe only the facts, the way a camera would have seen it.")
            FlowTextField(placeholder: "What happened was…", text: $data.event)
            SocraticPromptCard(step: .situation, context: context)

        case .interpretations:
            StepHeader(question: "What are you assuming or interpreting about it?",
                       helper: "The meaning you're giving the event, which can feel like part of it.")
            FlowTextField(placeholder: "I'm assuming…", text: $data.interpretations)
            VStack(alignment: .leading, spacing: 8) {
                Text("Are there other possible interpretations?")
                    .font(.system(.body, weight: .semibold))
                FlowTextField(placeholder: "It could also mean…", text: $data.otherInterpretations, minLines: 2)
            }
            SocraticPromptCard(step: .interpretations, context: context)

        case .threat:
            StepHeader(question: "Are you assuming a threat? What is it?",
                       helper: "Fear and anger often come from a threat we expect. Naming it lets you check it.")
            FlowTextField(placeholder: "The threat I'm expecting is… (or “none”)", text: $data.threat)
            if !data.threat.trimmed.isEmpty {
                PercentSlider(label: "How likely is it, really?", value: $data.threatLikelihood,
                              lowLabel: "Very unlikely", highLabel: "Certain", accent: accent)
                    .transition(.opacity)
            }
            SocraticPromptCard(step: .threat, context: context)

        case .catastrophe:
            StepHeader(question: "What's the worst that could realistically happen?",
                       helper: "Realistically, not the movie version.")
            FlowTextField(placeholder: "The worst realistic outcome…", text: $data.catastrophe)
            VStack(alignment: .leading, spacing: 8) {
                Text("How would you cope if it did?")
                    .font(.system(.body, weight: .semibold))
                FlowTextField(placeholder: "I'd cope by…", text: $data.coping, minLines: 2)
            }
            SocraticPromptCard(step: .catastrophe, context: context)

        case .fit:
            StepHeader(question: "Does your emotion, and its intensity, fit the facts?",
                       helper: "Emotions are useful when they fit. The question is only whether this one does, and how much.")
            if let family = data.emotion?.family {
                NoticeCard(text: family.fitsWhen, symbol: "info.circle")
            }
            OptionRow(options: FactsFit.allCases, selection: $data.fit) { $0.label }

        case .route:
            if data.fit == .doesnt {
                StepHeader(question: "It doesn't quite fit the facts.",
                           helper: "When an emotion doesn't fit, acting opposite to its urge is one of the most reliable ways to bring it down.")
                NoticeCard(text: "After rating how you feel now, you can go straight into Opposite Action, carrying over \(emotionName).",
                           symbol: TherapyTool.oppositeAction.symbol)
            } else {
                StepHeader(question: "What could you do about the situation?",
                           helper: "When the emotion fits, the most helpful move is often to solve the problem it's pointing at.")
                FlowTextField(placeholder: "One thing I could do…", text: $data.problemSolving)
                SocraticPromptCard(step: .problemSolving, context: context)
            }

        case .rerate:
            StepHeader(question: "How strong is \(emotionName) now?")
            if let before = data.emotion?.intensity {
                Text("Before: \(Int(before))%")
                    .font(.flowCaption)
                    .foregroundStyle(Ink.tertiary)
            }
            PercentSlider(label: "\(emotionName.capitalizedFirst) now", value: $data.intensityAfter,
                          lowLabel: "None", highLabel: "Strongest", accent: accent)

        case .complete:
            CompletionContent(
                title: "You checked the facts",
                subtitle: data.fit.map { "Your emotion: \($0.label.lowercased())." },
                rows: data.emotion.map { [ChangeRow(label: $0.word.capitalizedFirst, before: $0.intensity, after: data.intensityAfter)] } ?? [],
                accent: accent
            ) {
                OwnWordsBlock(title: "What you could do", text: data.problemSolving)
                if !data.threat.trimmed.isEmpty {
                    Text("Later, you can mark whether the threat happened. It counts toward your prediction calibration in Insights.")
                        .font(.flowCaption)
                        .foregroundStyle(Ink.tertiary)
                }
                if data.fit == .doesnt, let emotion = data.emotion {
                    VStack(alignment: .leading, spacing: 12) {
                        CapsLabel("One optional next step")
                        NextStepButton(title: "Try Opposite Action",
                                       detail: "Act against the urge of \(emotion.word), fully.",
                                       symbol: TherapyTool.oppositeAction.symbol) {
                            var carried = emotion
                            carried.intensity = data.intensityAfter ?? emotion.intensity
                            callbacks.onNext(.start(.oppositeAction, TherapyLaunch(
                                sourceEntryID: session.sourceEntryID, sourceCaptureID: session.sourceCaptureID,
                                targetThought: session.targetThought, emotion: carried, fromCheckFacts: true)))
                        }
                    }
                }
            }
        }
    }

    private var context: SocraticContext {
        SocraticContext(targetThought: data.interpretations.trimmed.isEmpty ? session.targetThought : data.interpretations,
                        priorAnswers: ["Event": data.event, "Threat": data.threat].filter { !$0.value.trimmed.isEmpty })
    }

    // MARK: Navigation

    private var primaryTitle: String {
        switch step {
        case .rerate: "Finish"
        case .complete: "Done"
        default: "Next"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .emotion: data.emotion != nil
        case .event: !data.event.trimmed.isEmpty
        case .interpretations: !data.interpretations.trimmed.isEmpty
        case .threat: data.threat.trimmed.isEmpty || data.threatLikelihood != nil
        case .fit: data.fit != nil
        case .rerate: data.intensityAfter != nil
        default: true
        }
    }

    private var backAction: (() -> Void)? {
        if step == .complete { return nil }
        if index == 0 { return callbacks.onBackFromStart }
        return { go(to: steps[index - 1]) }
    }

    private func primary() {
        switch step {
        case .complete:
            callbacks.onNext(.done)
        case .rerate:
            SessionService.complete(session, metricBefore: data.emotion?.intensity, metricAfter: data.intensityAfter,
                                    in: modelContext)
            go(to: .complete)
        default:
            safetyGate.check(data) { go(to: steps[index + 1]) }
        }
    }

    private func go(to newStep: Step) {
        hideKeyboard()
        withAnimation(.gentle) { step = newStep }
        session.record(step: newStep.rawValue, position: (steps.firstIndex(of: newStep) ?? 0) + 1, total: steps.count - 1)
        try? modelContext.save()
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        data = session.decode(CheckFactsData.self) ?? CheckFactsData()
        step = Step(rawValue: session.stepKey) ?? .emotion
        if session.status == .complete { step = .complete }
    }
}
