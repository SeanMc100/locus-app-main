import SwiftUI
import SwiftData

/// ACT defusion: the thought, how hooked you feel (not how true it is),
/// one or more techniques, re-rate, then a bridge to what matters.
/// Nothing here disputes the thought's content.
struct DefusionFlow: View {
    let session: TherapySession
    let callbacks: FlowCallbacks

    @Environment(\.modelContext) private var modelContext
    @Environment(\.safetyGate) private var safetyGate

    enum Step: String {
        case thought, hooked, technique, practice, rerate, bridge, complete
    }

    @State private var data = DefusionData()
    @State private var step: Step = .thought
    @State private var loaded = false

    private let accent = TherapyMethod.act.accent
    private let steps: [Step] = [.thought, .hooked, .technique, .practice, .rerate, .bridge, .complete]
    private var index: Int { steps.firstIndex(of: step) ?? 0 }

    var body: some View {
        StepScaffold(toolTitle: session.tool.title, accent: accent, stepID: step.rawValue + (data.technique?.rawValue ?? ""),
                     position: index + 1, total: steps.count - 1,
                     showsProgress: step != .complete,
                     primaryTitle: primaryTitle, canContinue: canContinue,
                     secondaryTitle: step == .practice ? "Try another technique" : nil,
                     onSecondary: { go(to: .technique) },
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
        switch step {
        case .thought:
            StepHeader(question: "What's the thought?",
                       helper: "Write it the way your mind says it. You won't be arguing with it.")
            FlowTextField(placeholder: "The thought…", text: $data.thought, minLines: 2)
            LedgerLinkView(thought: data.thought, linkedBeliefID: $data.linkedBeliefID)

        case .hooked:
            TargetThoughtCard(thought: data.thought, accent: accent)
            StepHeader(question: "How hooked by it do you feel right now?",
                       helper: "Not how true it is: how much it grips you and pulls you around.")
            PercentSlider(label: "How hooked", value: $data.hookedBefore, lowLabel: "Not at all", highLabel: "Completely", accent: accent)

        case .technique:
            TargetThoughtCard(thought: data.thought, accent: accent)
            StepHeader(question: "Pick a way to unhook.",
                       helper: "Each one changes your relationship with the thought, not the thought itself.")
            VStack(spacing: 10) {
                ForEach(DefusionTechnique.allCases) { technique in
                    ChoiceCard(title: technique.title,
                               detail: technique.summary + (data.techniquesUsed.contains(technique) ? " (tried)" : ""),
                               symbol: technique.symbol, accent: accent,
                               selected: data.technique == technique) {
                        data.technique = technique
                    }
                }
            }

        case .practice:
            if let technique = data.technique {
                DefusionTechniqueView(technique: technique, thought: data.thought, data: $data, accent: accent)
            }

        case .rerate:
            TargetThoughtCard(thought: data.thought, accent: accent)
            StepHeader(question: "How hooked do you feel now?",
                       helper: "The thought may still be there. That's fine; the question is its grip.")
            if let before = data.hookedBefore {
                Text("Before: \(Int(before))%")
                    .font(.flowCaption)
                    .foregroundStyle(Ink.tertiary)
            }
            PercentSlider(label: "How hooked now", value: $data.hookedAfter, lowLabel: "Not at all", highLabel: "Completely", accent: accent)

        case .bridge:
            StepHeader(question: "Now that the thought has a little less grip, what matters to you here?",
                       helper: "A direction, not a goal. Who do you want to be in this?")
            FlowTextField(placeholder: "What matters to me is…", text: $data.whatMatters)
            SocraticPromptCard(step: .defusionBridge, context: SocraticContext(targetThought: data.thought))

        case .complete:
            CompletionContent(
                title: "You unhooked a little",
                subtitle: "“\(data.thought.trimmed)”",
                rows: [ChangeRow(label: "How hooked", before: data.hookedBefore ?? 0, after: data.hookedAfter)],
                accent: accent
            ) {
                if !data.storyName.trimmed.isEmpty {
                    OwnWordsBlock(title: "The story", text: "The \(data.storyName.trimmed.replacingOccurrences(of: "the ", with: "", options: [.anchored, .caseInsensitive])) story")
                }
                OwnWordsBlock(title: "What matters to you here", text: data.whatMatters)
                VStack(alignment: .leading, spacing: 12) {
                    CapsLabel("One optional next step")
                    NextStepButton(title: "Take a small step: Committed Action",
                                   detail: "Turn what matters into one small action in the next day or two.",
                                   symbol: TherapyTool.committedAction.symbol) {
                        callbacks.onNext(.start(.committedAction, TherapyLaunch(
                            sourceEntryID: session.sourceEntryID, sourceCaptureID: session.sourceCaptureID,
                            targetThought: data.whatMatters)))
                    }
                }
            }
        }
    }

    // MARK: Navigation

    private var primaryTitle: String {
        switch step {
        case .technique: "Start"
        case .practice: "Done with this"
        case .bridge: "Finish"
        case .complete: "Done"
        default: "Next"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .thought: !data.thought.trimmed.isEmpty
        case .hooked: data.hookedBefore != nil
        case .technique: data.technique != nil
        case .rerate: data.hookedAfter != nil
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
        case .practice:
            if let t = data.technique, !data.techniquesUsed.contains(t) { data.techniquesUsed.append(t) }
            safetyGate.check(data) { go(to: .rerate) }
        case .bridge:
            safetyGate.check(data) {
                session.targetThought = data.thought.trimmed
                SessionService.complete(
                    session, metricBefore: data.hookedBefore, metricAfter: data.hookedAfter,
                    belief: .init(beliefID: data.linkedBeliefID, kind: .hooked, before: data.hookedBefore,
                                  after: data.hookedAfter, storyName: data.storyName),
                    in: modelContext)
                go(to: .complete)
            }
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
        data = session.decode(DefusionData.self) ?? DefusionData()
        step = Step(rawValue: session.stepKey) ?? .thought
        if session.status == .complete { step = .complete }
    }
}
