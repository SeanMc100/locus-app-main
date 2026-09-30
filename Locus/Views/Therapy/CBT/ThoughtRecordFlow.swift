import SwiftUI
import SwiftData

/// CBT thought record, one step per screen: situation, emotions, automatic
/// thoughts (and the hot one), belief, thinking traps, evidence for and
/// against, the user's own balanced thought, re-rating, completion.
/// Nothing here writes the balanced thought for them.
struct ThoughtRecordFlow: View {
    let session: TherapySession
    let callbacks: FlowCallbacks

    @Environment(\.modelContext) private var modelContext
    @Environment(\.safetyGate) private var safetyGate

    enum Step: String {
        case situation, emotions, thoughts, hotThought, belief, distortions
        case evidenceFor, evidenceAgainst, balanced, rerate, complete
    }

    @State private var data = ThoughtRecordData()
    @State private var step: Step = .situation
    @State private var loaded = false
    @State private var sourceText = ""
    /// The balanced thought the "should feel believable" prompt was shown for.
    @State private var lowBeliefPromptFor: String?
    @State private var aiQuestion: String?
    @State private var aiCheckedFor: String?
    @State private var checking = false

    private let accent = TherapyMethod.cbt.accent

    private var steps: [Step] {
        var s: [Step] = [.situation, .emotions, .thoughts]
        if data.enteredThoughts.count > 1 { s.append(.hotThought) }
        s += [.belief, .distortions, .evidenceFor, .evidenceAgainst, .balanced, .rerate, .complete]
        return s
    }

    private var index: Int { steps.firstIndex(of: step) ?? 0 }

    var body: some View {
        StepScaffold(toolTitle: session.tool.title, accent: accent, stepID: step.rawValue,
                     position: index + 1, total: steps.count - 1,
                     showsProgress: step != .complete,
                     primaryTitle: primaryTitle, canContinue: canContinue && !checking,
                     secondaryTitle: step == .distortions ? "Skip this step" : nil,
                     onSecondary: {
                         data.distortions = []
                         data.noDistortions = false
                         go(to: next(after: .distortions))
                     },
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

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .situation:
            TargetThoughtCard(thought: session.targetThought, accent: accent)
            StepHeader(question: "What was happening?",
                       helper: "Just the facts: where, when, who, what. Keeping facts apart from the story makes the rest clearer.")
            if !sourceText.isEmpty {
                EntryPreviewCard(label: "From your journal", entryText: sourceText)
            }
            FlowTextField(placeholder: "Where were you, and what happened?", text: $data.situation)
            SocraticPromptCard(step: .situation, context: context)

        case .emotions:
            TargetThoughtCard(thought: session.targetThought, accent: accent)
            StepHeader(question: "What did you feel?",
                       helper: "Name each feeling and how strong it was. You'll rate them again at the end.")
            EmotionPicker(ratings: $data.emotionsBefore, accent: accent)

        case .thoughts:
            StepHeader(question: "What went through your mind?",
                       helper: "Write the thoughts the way they sounded in your head, even if they seem extreme.")
            VStack(spacing: 10) {
                ForEach(data.thoughts.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 8) {
                        FlowTextField(placeholder: i == 0 ? "The thought…" : "Another thought…",
                                      text: $data.thoughts[i], minLines: 2,
                                      accessibilityLabel: "Thought \(i + 1)")
                        if data.thoughts.count > 1 {
                            Button {
                                data.thoughts.remove(at: i)
                                data.hotIndex = 0
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Ink.tertiary)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove thought \(i + 1)")
                        }
                    }
                }
            }
            SecondaryButton(title: "Add another thought", symbol: "plus") { data.thoughts.append("") }
            SocraticPromptCard(step: .automaticThought, context: context)

        case .hotThought:
            StepHeader(question: "Which thought feels most important?",
                       helper: "The one that carries the most feeling. That's the one to work on.")
            VStack(spacing: 10) {
                ForEach(Array(data.enteredThoughts.enumerated()), id: \.offset) { i, thought in
                    ChoiceCard(title: thought, selected: data.hotIndex == i) { data.hotIndex = i }
                }
            }

        case .belief:
            TargetThoughtCard(thought: data.hotThought, accent: accent)
            StepHeader(question: "How much do you believe it right now?",
                       helper: "How true it feels, not how true you think it should be.")
            PercentSlider(label: "Belief in the thought", value: $data.beliefBefore, accent: accent)
            LedgerLinkView(thought: data.hotThought, linkedBeliefID: $data.linkedBeliefID)

        case .distortions:
            TargetThoughtCard(thought: data.hotThought, accent: accent)
            StepHeader(question: "Do any of these thinking traps fit?",
                       helper: "Optional. Spotting a familiar pattern can loosen its grip. “None of these” is a fine answer.")
            DistortionSelector(selected: $data.distortions, none: $data.noDistortions)

        case .evidenceFor:
            TargetThoughtCard(thought: data.hotThought, accent: accent)
            StepHeader(question: "What facts support this thought?",
                       helper: "Facts, not feelings or interpretations. Being fair to the thought makes the next step honest.")
            FlowTextField(placeholder: "The facts that point this way…", text: $data.evidenceFor)
            SocraticPromptCard(step: .evidenceFor, context: context)

        case .evidenceAgainst:
            TargetThoughtCard(thought: data.hotThought, accent: accent)
            StepHeader(question: "What facts don't fit the thought?",
                       helper: "Anything the thought leaves out. This is usually where the picture changes.")
            FlowTextField(placeholder: "The facts that don't fit…", text: $data.evidenceAgainst)
            SocraticPromptCard(step: .evidenceAgainst, context: context)

        case .balanced:
            balancedStep

        case .rerate:
            TargetThoughtCard(thought: data.hotThought, accent: accent)
            StepHeader(question: "Now, how much do you believe the original thought?",
                       helper: "Whatever it is now is fine. A small shift counts.")
            if let before = data.beliefBefore {
                Text("Before: \(Int(before))%")
                    .font(.flowCaption)
                    .foregroundStyle(Ink.tertiary)
            }
            PercentSlider(label: "Belief in the original thought", value: $data.beliefAfter, accent: accent)
            if !data.emotionsBefore.isEmpty {
                StepHeader(question: "And how strong are these feelings now?")
                    .padding(.top, 8)
                EmotionRerateList(before: data.emotionsBefore, after: $data.emotionsAfter, accent: accent)
            }

        case .complete:
            completion
        }
    }

    private var balancedStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            TargetThoughtCard(thought: data.hotThought, accent: accent)
            StepHeader(question: "Considering all the evidence, what's a more balanced way to see this?",
                       helper: "In your own words. It should feel believable, not just positive.")
            EvidenceRecap(forText: data.evidenceFor, againstText: data.evidenceAgainst)
            FlowTextField(placeholder: "A more balanced way to see it…", text: $data.balancedThought)
            PercentSlider(label: "How much do you believe the balanced thought?", value: $data.balancedBelief, accent: accent)
            if lowBeliefPromptFor == data.balancedThought.trimmed {
                NoticeCard(text: "A balanced thought should feel believable, not just positive. Want to adjust it so it's something you actually believe?") {
                    reviseOrKeep
                }
                .transition(.opacity)
            } else if let aiQuestion {
                NoticeCard(text: aiQuestion, symbol: "questionmark.bubble") {
                    reviseOrKeep
                }
                .transition(.opacity)
            }
            SocraticPromptCard(step: .balancedThought, context: context)
        }
        .animation(.gentle, value: lowBeliefPromptFor)
        .animation(.gentle, value: aiQuestion)
    }

    private var reviseOrKeep: some View {
        HStack(spacing: 10) {
            SecondaryButton(title: "Revise", symbol: "pencil") {
                lowBeliefPromptFor = nil
                aiQuestion = nil
            }
            SecondaryButton(title: "Keep it") {
                data.keptLowBelief = true
                lowBeliefPromptFor = nil
                aiQuestion = nil
                go(to: .rerate)
            }
        }
    }

    private var completion: some View {
        CompletionContent(
            title: "You examined the thought",
            subtitle: "“\(data.hotThought)”",
            rows: [ChangeRow(label: "Belief in the thought", before: data.beliefBefore ?? 0, after: data.beliefAfter)]
                + EmotionMath.changeRows(before: data.emotionsBefore, after: data.emotionsAfter),
            accent: accent
        ) {
            OwnWordsBlock(title: "Your balanced thought", text: data.balancedThought)
            VStack(alignment: .leading, spacing: 12) {
                CapsLabel("One optional next step")
                NextStepButton(title: "Test this with a Behavioral Experiment",
                               detail: "Turn a prediction in the thought into something you can try.",
                               symbol: TherapyTool.behavioralExperiment.symbol) {
                    callbacks.onNext(.start(.behavioralExperiment, TherapyLaunch(
                        sourceEntryID: session.sourceEntryID, targetThought: data.hotThought,
                        linkedBeliefID: data.linkedBeliefID)))
                }
                if data.addedToPractice {
                    Label("Added to your Practice deck", systemImage: "checkmark.circle.fill")
                        .font(.flowHelper.weight(.semibold))
                        .foregroundStyle(Ink.secondary)
                        .padding(.vertical, 8)
                } else {
                    NextStepButton(title: "Add the balanced thought to your Practice deck",
                                   detail: "Rehearse it on calm days, so it's there when you need it.",
                                   symbol: "rectangle.stack") {
                        PracticeService.addCard(front: data.hotThought, back: data.balancedThought,
                                                evidence: data.evidenceAgainst, sessionID: session.idString,
                                                beliefID: data.linkedBeliefID, in: modelContext)
                        data.addedToPractice = true
                    }
                }
            }
        }
    }

    // MARK: Navigation

    private var context: SocraticContext {
        var answers: [String: String] = [:]
        if !data.situation.trimmed.isEmpty { answers["Situation"] = data.situation }
        if !data.evidenceFor.trimmed.isEmpty { answers["Evidence for"] = data.evidenceFor }
        if !data.evidenceAgainst.trimmed.isEmpty { answers["Evidence against"] = data.evidenceAgainst }
        return SocraticContext(targetThought: data.hotThought.isEmpty ? session.targetThought : data.hotThought,
                               priorAnswers: answers)
    }

    private var primaryTitle: String {
        switch step {
        case .rerate: "Finish"
        case .complete: "Done"
        default: "Next"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .situation: !data.situation.trimmed.isEmpty
        case .emotions: !data.emotionsBefore.isEmpty
        case .thoughts: !data.enteredThoughts.isEmpty
        case .hotThought: true
        case .belief: data.beliefBefore != nil
        case .distortions: true
        case .evidenceFor, .evidenceAgainst: true
        case .balanced: !data.balancedThought.trimmed.isEmpty && data.balancedBelief != nil
        case .rerate: data.beliefAfter != nil && EmotionRerateList.isComplete(before: data.emotionsBefore, after: data.emotionsAfter)
        case .complete: true
        }
    }

    private var backAction: (() -> Void)? {
        if step == .complete { return nil }
        if index == 0 { return callbacks.onBackFromStart }
        return { go(to: steps[index - 1]) }
    }

    private func next(after s: Step) -> Step {
        guard let i = steps.firstIndex(of: s), i + 1 < steps.count else { return .complete }
        return steps[i + 1]
    }

    private func primary() {
        switch step {
        case .complete:
            callbacks.onNext(.done)
        case .balanced:
            safetyGate.check(data) { Task { await checkBalanced() } }
        default:
            safetyGate.check(data) { advance() }
        }
    }

    private func advance() {
        if step == .thoughts, data.hotIndex >= data.enteredThoughts.count { data.hotIndex = 0 }
        let upcoming = next(after: step)
        if upcoming == .complete { finish() }
        go(to: upcoming)
    }

    /// The fake-reframe check: a balanced thought they barely believe gets
    /// a gentle prompt (once per wording); with AI on, a pure opposite or
    /// toxic positivity gets a question. Never a rewrite.
    private func checkBalanced() async {
        let balanced = data.balancedThought.trimmed
        if let belief = data.balancedBelief, belief < 50, !data.keptLowBelief, lowBeliefPromptFor != balanced {
            lowBeliefPromptFor = balanced
            return
        }
        if TherapyAI.isEnabled, aiCheckedFor != balanced, !data.keptLowBelief {
            aiCheckedFor = balanced
            checking = true
            let question = await TherapyAI.balancedThoughtQuestion(original: data.hotThought, balanced: balanced,
                                                                    belief: data.balancedBelief ?? 0)
            checking = false
            if let question {
                aiQuestion = question
                return
            }
        }
        advance()
    }

    private func go(to newStep: Step) {
        hideKeyboard()
        withAnimation(.gentle) { step = newStep }
        let position = (steps.firstIndex(of: newStep) ?? 0) + 1
        session.record(step: newStep.rawValue, position: position, total: steps.count - 1)
        try? modelContext.save()
    }

    private func finish() {
        let after = data.emotionsAfter
        session.targetThought = data.hotThought
        SessionService.complete(
            session,
            metricBefore: EmotionMath.average(data.emotionsBefore),
            metricAfter: EmotionMath.average(after),
            belief: .init(beliefID: data.linkedBeliefID, kind: .belief, before: data.beliefBefore, after: data.beliefAfter),
            in: modelContext)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        data = session.decode(ThoughtRecordData.self) ?? ThoughtRecordData()
        step = Step(rawValue: session.stepKey) ?? .situation
        if session.status == .complete { step = .complete }
        sourceText = SessionService.sourceText(for: session, in: modelContext)
    }
}

/// Evidence for and against, side by side, while writing the balanced
/// thought, so it doesn't have to be held in mind.
struct EvidenceRecap: View {
    let forText: String
    let againstText: String

    @State private var expanded = true

    var body: some View {
        if !forText.trimmed.isEmpty || !againstText.trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.gentle) { expanded.toggle() }
                } label: {
                    HStack {
                        CapsLabel("Your evidence")
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .foregroundStyle(Ink.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Hide your evidence" : "Show your evidence")
                if expanded {
                    if !forText.trimmed.isEmpty {
                        recapRow("For", forText)
                    }
                    if !againstText.trimmed.isEmpty {
                        recapRow("Against", againstText)
                    }
                }
            }
            .padding(14)
            .card(filled: true)
        }
    }

    private func recapRow(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.flowCaption.weight(.semibold))
                .foregroundStyle(Ink.tertiary)
            Text(text.trimmed)
                .font(.flowHelper)
                .foregroundStyle(Ink.primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
