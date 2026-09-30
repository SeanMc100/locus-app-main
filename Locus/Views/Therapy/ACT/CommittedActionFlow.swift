import SwiftUI
import SwiftData

/// ACT committed action: choose a value, one small step in the next day or
/// two, the barriers (and willingness to have them), schedule, follow up.
/// Completed actions count toward that value in Insights.
struct CommittedActionFlow: View {
    let session: TherapySession
    let callbacks: FlowCallbacks

    @Environment(\.modelContext) private var modelContext
    @Environment(\.safetyGate) private var safetyGate
    @Query(sort: \ValueDomain.order) private var domains: [ValueDomain]

    enum Step: String {
        case value, step, barriers, schedule, doing, scheduled, followUp, complete
    }

    @State private var data = CommittedActionData()
    @State private var step: Step = .value
    @State private var loaded = false
    // Mini clarification when no values exist yet.
    @State private var miniDomainKey: String?
    @State private var miniQualities: [String] = []
    @State private var miniImportance: Int?

    private let accent = TherapyMethod.act.accent
    private let planSteps: [Step] = [.value, .step, .barriers, .schedule]

    private var clarified: [ValueDomain] { domains.filter { $0.isClarified && !$0.isHidden } }

    private var progress: (position: Int, total: Int) {
        if let i = planSteps.firstIndex(of: step) { return (i + 1, planSteps.count) }
        return (1, 1)
    }

    var body: some View {
        StepScaffold(toolTitle: session.tool.title, accent: accent, stepID: step.rawValue,
                     position: progress.position, total: progress.total,
                     showsProgress: planSteps.contains(step),
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
        case .value:
            TargetThoughtCard(thought: session.targetThought, label: "What matters here", accent: accent)
            if clarified.isEmpty {
                miniClarification
            } else {
                StepHeader(question: "Which value do you want to move toward?",
                           helper: "Values are directions: there's always a next step, however small.")
                VStack(spacing: 10) {
                    ForEach(clarified) { domain in
                        ChoiceCard(title: domain.name, detail: domain.qualitiesLine.isEmpty ? nil : domain.qualitiesLine,
                                   symbol: domain.symbol, accent: accent,
                                   selected: data.valueDomainID == domain.idString) {
                            data.valueDomainID = domain.idString
                            data.valueName = domain.name
                        }
                    }
                }
            }

        case .step:
            TargetThoughtCard(thought: data.valueName, label: "Your value", accent: accent)
            StepHeader(question: "What's one small action in the next 24–48 hours that moves you toward it?",
                       helper: "Small and specific: something you'd actually do. “Text Sam to ask about Saturday,” not “be a better friend.”")
            FlowTextField(placeholder: "I'll…", text: $data.step)
            SocraticPromptCard(step: .committedStep, context: SocraticContext(targetThought: data.valueName))

        case .barriers:
            TargetThoughtCard(thought: data.step, label: "Your step", accent: accent)
            StepHeader(question: "What thoughts or feelings might show up and try to stop you?",
                       helper: "Naming them in advance makes them easier to carry along.")
            FlowTextField(placeholder: "My mind might say…", text: $data.barriers)
            VStack(alignment: .leading, spacing: 10) {
                Text("Are you willing to have those and do it anyway?")
                    .font(.system(.body, weight: .semibold))
                OptionRow(options: [true, false], selection: $data.willing) { $0 ? "Yes" : "Let me pick a smaller step" }
            }
            SocraticPromptCard(step: .barriers)

        case .schedule:
            TargetThoughtCard(thought: data.step, label: "Your step", accent: accent)
            StepHeader(question: "When will you do it?")
            OptionRow(options: [true, false], selection: $data.doNow) { $0 ? "Now" : "Later" }
            if data.doNow == false {
                WhenPicker(date: $data.when)
            }

        case .doing:
            waiting("Go for it", "Do it now. Come back when you're done.")

        case .scheduled:
            waiting("Planned", "We'll remind you at \((session.scheduledAt ?? .now).formatted(date: .abbreviated, time: .shortened)). It'll wait under In progress.")

        case .followUp:
            TargetThoughtCard(thought: data.step, label: "Your step", accent: accent)
            StepHeader(question: "Did you do it?")
            OptionRow(options: [true, false], selection: $data.did) { $0 ? "Yes" : "Not this time" }
            if data.did != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text(data.did == true ? "How did it feel?" : "What got in the way?")
                        .font(.system(.body, weight: .semibold))
                    FlowTextField(placeholder: "It felt…", text: $data.howFelt, minLines: 2)
                }
            }

        case .complete:
            CompletionContent(
                title: data.did == true ? "You acted on \(data.valueName.lowercased())" : "Checked in",
                subtitle: "“\(data.step.trimmed)”",
                rows: [],
                accent: accent
            ) {
                OwnWordsBlock(title: "How it felt", text: data.howFelt)
                Text(data.did == true ? "This counts toward \(data.valueName) in your Values Gap." : "Smaller steps are easier to start. Any step counts.")
                    .font(.flowCaption)
                    .foregroundStyle(Ink.tertiary)
            }
        }
    }

    private var miniClarification: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHeader(question: "Pick one area of life that matters to you.",
                       helper: "A quick start. You can clarify the rest in Values Check-in.")
            FlowLayout(spacing: 8) {
                ForEach(TherapyCatalog.lifeDomains) { d in
                    Chip(title: d.name, selected: miniDomainKey == d.key) { miniDomainKey = d.key }
                }
            }
            if miniDomainKey != nil {
                Text("What qualities do you want to act with there?")
                    .font(.system(.body, weight: .semibold))
                FlowLayout(spacing: 8) {
                    ForEach(TherapyCatalog.valueWords, id: \.self) { w in
                        Chip(title: w, selected: miniQualities.contains(w)) {
                            if miniQualities.contains(w) { miniQualities.removeAll { $0 == w } } else { miniQualities.append(w) }
                        }
                    }
                }
                Text("How important is it to you?")
                    .font(.system(.body, weight: .semibold))
                TenPointScale(label: "Importance", value: $miniImportance, anchors: [0: "Not at all", 10: "Extremely"])
            }
        }
    }

    private func waiting(_ title: String, _ line: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: TherapyTool.committedAction.symbol)
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
        case .barriers: data.willing == false ? "Pick a smaller step" : "Next"
        case .schedule: data.doNow == true ? "Start now" : "Plan it"
        case .doing: "I'm back"
        case .scheduled, .complete: "Done"
        case .followUp: "Finish"
        default: "Next"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .value:
            clarified.isEmpty ? (miniDomainKey != nil && miniImportance != nil) : data.valueDomainID != nil
        case .step: !data.step.trimmed.isEmpty
        case .barriers: data.willing != nil
        case .schedule: data.doNow == true || (data.doNow == false && data.when != nil)
        case .followUp: data.did != nil
        default: true
        }
    }

    private var backAction: (() -> Void)? {
        guard let i = planSteps.firstIndex(of: step) else { return nil }
        if i == 0 { return callbacks.onBackFromStart }
        return { go(to: planSteps[i - 1]) }
    }

    private func primary() {
        switch step {
        case .value:
            if clarified.isEmpty { saveMiniClarification() }
            go(to: .step)
        case .barriers:
            if data.willing == false {
                data.willing = nil
                go(to: .step)
            } else {
                safetyGate.check(data) { go(to: .schedule) }
            }
        case .schedule:
            session.targetThought = data.step.trimmed
            if data.doNow == true {
                session.status = .pending
                session.scheduledAt = .now
                try? modelContext.save()
                go(to: .doing)
            } else {
                SessionService.schedule(session, at: data.when ?? .now.addingTimeInterval(3600),
                                        title: "Time for your small step",
                                        body: "Tap to check in afterwards.", in: modelContext)
                go(to: .scheduled)
            }
        case .doing:
            go(to: .followUp)
        case .scheduled, .complete:
            callbacks.onNext(.done)
        case .followUp:
            safetyGate.check(data) {
                SessionService.complete(session, metricBefore: nil, metricAfter: nil, in: modelContext)
                go(to: .complete)
            }
        default:
            safetyGate.check(data) {
                if let i = planSteps.firstIndex(of: step), i + 1 < planSteps.count { go(to: planSteps[i + 1]) }
            }
        }
    }

    private func saveMiniClarification() {
        ValuesService.ensureDomains(in: modelContext)
        guard let key = miniDomainKey,
              let domain = ((try? modelContext.fetch(FetchDescriptor<ValueDomain>())) ?? []).first(where: { $0.key == key })
        else { return }
        domain.qualities = miniQualities
        domain.importance = miniImportance
        domain.isHidden = false
        data.valueDomainID = domain.idString
        data.valueName = domain.name
        try? modelContext.save()
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
        data = session.decode(CommittedActionData.self) ?? CommittedActionData()
        step = Step(rawValue: session.stepKey) ?? .value
        switch session.status {
        case .pending: step = .followUp
        case .complete: step = .complete
        case .draft: break
        }
    }
}
