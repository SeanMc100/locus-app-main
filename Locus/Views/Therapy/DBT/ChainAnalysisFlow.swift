import SwiftUI
import SwiftData

/// DBT chain analysis: the problem behavior, what set it off, what made
/// you vulnerable, the links in between (typed, reorderable), the
/// consequences, then the weak links where a skill could change the
/// direction, an if-then plan, and repair.
struct ChainAnalysisFlow: View {
    let session: TherapySession
    let callbacks: FlowCallbacks

    @Environment(\.modelContext) private var modelContext
    @Environment(\.safetyGate) private var safetyGate

    enum Step: String {
        case behavior, event, vulnerabilities, links, consequences, weakLinks, precommit, repair, complete
    }

    @State private var data = ChainData()
    @State private var step: Step = .behavior
    @State private var loaded = false
    @State private var newKind: ChainLinkKind? = .thought
    @State private var newText = ""
    @State private var planTrigger = ""
    @State private var planResponse = ""
    @State private var savePlan = true

    private let accent = TherapyMethod.dbt.accent
    private let steps: [Step] = [.behavior, .event, .vulnerabilities, .links, .consequences, .weakLinks, .precommit, .repair, .complete]
    private var index: Int { steps.firstIndex(of: step) ?? 0 }

    var body: some View {
        StepScaffold(toolTitle: session.tool.title, accent: accent, stepID: step.rawValue,
                     position: index + 1, total: steps.count - 1,
                     showsProgress: step != .complete,
                     primaryTitle: primaryTitle, canContinue: canContinue,
                     secondaryTitle: step == .repair ? "Skip" : nil,
                     onSecondary: { finish() },
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
        case .behavior:
            StepHeader(question: "What did you do that you want to understand?",
                       helper: "Specific and concrete: what you did, and when. Understanding it isn't excusing it or judging it.")
            FlowTextField(placeholder: "I…", text: $data.problemBehavior)

        case .event:
            TargetThoughtCard(thought: data.problemBehavior, label: "The behavior", accent: accent)
            StepHeader(question: "What set it off?",
                       helper: "The event that started the chain, as a camera would have seen it.")
            FlowTextField(placeholder: "It started when…", text: $data.promptingEvent)

        case .vulnerabilities:
            StepHeader(question: "What made you more vulnerable beforehand?",
                       helper: "Things that lower the threshold. Over time, patterns here are easy to act on.")
            FlowLayout(spacing: 8) {
                ForEach(TherapyCatalog.vulnerabilities, id: \.self) { factor in
                    Chip(title: factor, selected: data.vulnerabilities.contains(factor)) {
                        if data.vulnerabilities.contains(factor) {
                            data.vulnerabilities.removeAll { $0 == factor }
                        } else {
                            data.vulnerabilities.append(factor)
                        }
                    }
                }
            }
            FlowLineField(placeholder: "Something else…", text: $data.vulnerabilityOther)

        case .links:
            StepHeader(question: "What happened next?",
                       helper: "Add each link between the event and what you did: thoughts, feelings, sensations, urges, actions. Drag to reorder.")
            ChainNode(kindLabel: "Prompting event", symbol: "bolt", text: data.promptingEvent, accent: accent, isEnd: true)
            ForEach(Array(data.links.enumerated()), id: \.element.id) { i, link in
                ChainConnector()
                EditableChainNode(link: link, accent: accent,
                                  canMoveUp: i > 0, canMoveDown: i < data.links.count - 1,
                                  onMoveUp: { move(from: i, to: i - 1) },
                                  onMoveDown: { move(from: i, to: i + 1) },
                                  onDelete: { data.links.removeAll { $0.id == link.id } },
                                  onDrop: { id in
                                      guard let from = data.links.firstIndex(where: { $0.id == id }) else { return false }
                                      move(from: from, to: i)
                                      return true
                                  })
            }
            ChainConnector()
            addLinkForm
            ChainConnector()
            ChainNode(kindLabel: "What you did", symbol: "flag", text: data.problemBehavior, accent: accent, isEnd: true)
            SocraticPromptCard(step: .chainLinks)

        case .consequences:
            StepHeader(question: "What were the consequences?",
                       helper: "Both matter: short-term relief is often why a behavior sticks.")
            labeled("Short-term (right after: relief, others' reactions)") {
                FlowTextField(placeholder: "Right after…", text: $data.shortTerm, minLines: 2)
            }
            labeled("Long-term") {
                FlowTextField(placeholder: "Later on…", text: $data.longTerm, minLines: 2)
            }

        case .weakLinks:
            StepHeader(question: "Where could you have done something differently?",
                       helper: "Tap the links where a different response could have changed the direction.")
            ForEach(data.links) { link in
                weakLinkRow(link)
            }

        case .precommit:
            StepHeader(question: "Make an if-then plan for next time?",
                       helper: "Deciding in advance makes the new response easier to reach for when the moment comes.")
            if data.weakLinks.count > 1 {
                VStack(spacing: 8) {
                    ForEach(data.weakLinks, id: \.linkID) { weak in
                        if let link = data.links.first(where: { $0.id == weak.linkID }) {
                            ChoiceCard(title: link.text, detail: weak.response.isEmpty ? nil : "→ \(weak.response)",
                                       selected: data.planLinkID == weak.linkID) {
                                choosePlanLink(weak.linkID)
                            }
                        }
                    }
                }
            }
            VStack(spacing: 8) {
                FlowLineField(placeholder: "If…", text: $planTrigger)
                FlowLineField(placeholder: "then I'll…", text: $planResponse)
            }
            .padding(12)
            .card(filled: true)
            Toggle("Save as an if-then plan", isOn: $savePlan)
                .font(.system(.body, weight: .semibold))
                .tint(accent)

        case .repair:
            StepHeader(question: "Is there anything you need to repair or make right?",
                       helper: "Optional. Sometimes there's nothing to repair, and that's fine.")
            FlowTextField(placeholder: "I could…", text: $data.repair)
            SocraticPromptCard(step: .repair)

        case .complete:
            CompletionContent(
                title: "You mapped the chain",
                subtitle: "\(data.links.count) link\(data.links.count == 1 ? "" : "s") · \(data.weakLinks.count) place\(data.weakLinks.count == 1 ? "" : "s") to respond differently",
                rows: [],
                accent: accent
            ) {
                ChainDiagram(data: data, accent: accent)
                if data.createdPlanID != nil {
                    Label("If-then plan saved to Practice", systemImage: "checkmark.circle.fill")
                        .font(.flowHelper.weight(.semibold))
                        .foregroundStyle(Ink.secondary)
                }
                OwnWordsBlock(title: "To repair", text: data.repair)
            }
        }
    }

    private var addLinkForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel("Add a link")
            FlowLayout(spacing: 6) {
                ForEach(ChainLinkKind.allCases, id: \.self) { kind in
                    Chip(title: kind.label, selected: newKind == kind) { newKind = kind }
                }
            }
            FlowLineField(placeholder: "What happened next?", text: $newText)
            SecondaryButton(title: "Add link", symbol: "plus") {
                guard let kind = newKind, !newText.trimmed.isEmpty else { return }
                data.links.append(ChainLink(kind: kind, text: newText.trimmed))
                newText = ""
            }
            .disabled(newText.trimmed.isEmpty)
            .opacity(newText.trimmed.isEmpty ? 0.4 : 1)
        }
        .padding(14)
        .card(filled: true)
    }

    private func weakLinkRow(_ link: ChainLink) -> some View {
        let weakIndex = data.weakLinks.firstIndex { $0.linkID == link.id }
        let isWeak = weakIndex != nil
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                if let weakIndex { data.weakLinks.remove(at: weakIndex) } else { data.weakLinks.append(WeakLink(linkID: link.id)) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isWeak ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isWeak ? accent : Ink.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.kind.label)
                            .font(.flowCaption.weight(.semibold))
                            .foregroundStyle(Ink.tertiary)
                        Text(link.text)
                            .font(.flowBody)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isWeak ? [.isButton, .isSelected] : .isButton)

            if let weakIndex {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What skill or different response could you use here next time?")
                        .font(.flowHelper.weight(.semibold))
                    Menu {
                        Button("None") { data.weakLinks[weakIndex].skill = "" }
                        ForEach(TherapyCatalog.skills, id: \.self) { skill in
                            Button(skill) { data.weakLinks[weakIndex].skill = skill }
                        }
                    } label: {
                        HStack {
                            Text(data.weakLinks[weakIndex].skill.isEmpty ? "Choose a skill" : data.weakLinks[weakIndex].skill)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12))
                        }
                        .font(.flowBody)
                        .foregroundStyle(Ink.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .card()
                    }
                    FlowLineField(placeholder: "Or in your own words…",
                                  text: Binding(get: { data.weakLinks[weakIndex].custom },
                                                set: { data.weakLinks[weakIndex].custom = $0 }))
                }
                .padding(.leading, 32)
                .transition(.opacity)
            }
        }
        .padding(14)
        .card(selected: isWeak)
        .animation(.gentle, value: isWeak)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(.body, weight: .semibold))
            content()
        }
    }

    private func move(from: Int, to: Int) {
        guard data.links.indices.contains(from), data.links.indices.contains(to), from != to else { return }
        withAnimation(.gentle) {
            let link = data.links.remove(at: from)
            data.links.insert(link, at: to)
        }
    }

    private func choosePlanLink(_ id: UUID) {
        data.planLinkID = id
        if let link = data.links.first(where: { $0.id == id }),
           let weak = data.weakLinks.first(where: { $0.linkID == id }) {
            planTrigger = link.text
            planResponse = weak.response
        }
    }

    // MARK: Navigation

    private var primaryTitle: String {
        switch step {
        case .repair: "Finish"
        case .complete: "Done"
        default: "Next"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .behavior: !data.problemBehavior.trimmed.isEmpty
        case .event: !data.promptingEvent.trimmed.isEmpty
        case .links: !data.links.isEmpty
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
        case .links:
            // A half-typed link still counts.
            if let kind = newKind, !newText.trimmed.isEmpty {
                data.links.append(ChainLink(kind: kind, text: newText.trimmed))
                newText = ""
            }
            safetyGate.check(data) { go(to: .consequences) }
        case .weakLinks:
            safetyGate.check(data) {
                if data.weakLinks.isEmpty {
                    go(to: .repair)
                } else {
                    if data.planLinkID == nil || !data.weakLinks.contains(where: { $0.linkID == data.planLinkID }) {
                        choosePlanLink(data.weakLinks[0].linkID)
                    }
                    go(to: .precommit)
                }
            }
        case .precommit:
            if savePlan, data.createdPlanID == nil, !planTrigger.trimmed.isEmpty, !planResponse.trimmed.isEmpty {
                let plan = IfThenPlan(trigger: planTrigger.trimmed, response: planResponse.trimmed,
                                      source: .chain, sourceSessionID: session.idString)
                modelContext.insert(plan)
                data.createdPlanID = plan.idString
            }
            go(to: .repair)
        case .repair:
            safetyGate.check(data) { finish() }
        default:
            safetyGate.check(data) { go(to: steps[index + 1]) }
        }
    }

    private func finish() {
        session.targetThought = data.problemBehavior.trimmed
        SessionService.complete(session, metricBefore: nil, metricAfter: nil, in: modelContext)
        go(to: .complete)
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
        data = session.decode(ChainData.self) ?? ChainData()
        step = Step(rawValue: session.stepKey) ?? .behavior
        if session.status == .complete { step = .complete }
        if let id = data.planLinkID { choosePlanLink(id) }
    }
}

// MARK: - Chain pieces

struct ChainConnector: View {
    var body: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(width: 2, height: 18)
            .padding(.leading, 27)
            .accessibilityHidden(true)
    }
}

struct ChainNode: View {
    let kindLabel: String
    let symbol: String
    let text: String
    var accent: Color = .black
    var isEnd = false
    var isWeak = false
    var response: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isEnd ? .white : accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(isEnd ? accent : accent.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(kindLabel)
                    .font(.flowCaption.weight(.semibold))
                    .foregroundStyle(Ink.tertiary)
                Text(text.isEmpty ? "–" : text)
                    .font(.flowBody)
                    .fixedSize(horizontal: false, vertical: true)
                if isWeak {
                    Label(response.isEmpty ? "Could respond differently here" : "Next time: \(response)",
                          systemImage: "arrow.turn.down.right")
                        .font(.flowHelper.weight(.semibold))
                        .foregroundStyle(accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .card(selected: isWeak)
        .accessibilityElement(children: .combine)
    }
}

private struct EditableChainNode: View {
    let link: ChainLink
    let accent: Color
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    let onDrop: (UUID) -> Bool

    var body: some View {
        HStack(spacing: 4) {
            // Drag the node itself to reorder; the buttons stay separate
            // so VoiceOver can reach them.
            ChainNode(kindLabel: link.kind.label, symbol: link.kind.symbol, text: link.text, accent: accent)
                .draggable(link.id.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                    return onDrop(id)
                }
            VStack(spacing: 0) {
                Button(action: onMoveUp) { Image(systemName: "chevron.up").frame(width: 36, height: 30) }
                    .disabled(!canMoveUp)
                    .accessibilityLabel("Move up")
                Button(action: onDelete) { Image(systemName: "trash").frame(width: 36, height: 30) }
                    .accessibilityLabel("Delete link")
                Button(action: onMoveDown) { Image(systemName: "chevron.down").frame(width: 36, height: 30) }
                    .disabled(!canMoveDown)
                    .accessibilityLabel("Move down")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Ink.secondary)
            .buttonStyle(.plain)
        }
    }
}

/// The whole chain, read-only: vulnerabilities, event, links (weak ones
/// marked with the new response), behavior, consequences.
struct ChainDiagram: View {
    let data: ChainData
    var accent: Color = .black

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let factors = data.vulnerabilities + (data.vulnerabilityOther.trimmed.isEmpty ? [] : [data.vulnerabilityOther.trimmed])
            if !factors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    CapsLabel("Vulnerable because of")
                    Text(factors.joined(separator: " · "))
                        .font(.flowHelper)
                        .foregroundStyle(Ink.secondary)
                }
                .padding(.bottom, 12)
            }
            ChainNode(kindLabel: "Prompting event", symbol: "bolt", text: data.promptingEvent, accent: accent, isEnd: true)
            ForEach(data.links) { link in
                ChainConnector()
                let weak = data.weakLinks.first { $0.linkID == link.id }
                ChainNode(kindLabel: link.kind.label, symbol: link.kind.symbol, text: link.text, accent: accent,
                          isWeak: weak != nil, response: weak?.response ?? "")
            }
            ChainConnector()
            ChainNode(kindLabel: "What you did", symbol: "flag", text: data.problemBehavior, accent: accent, isEnd: true)
            if !data.shortTerm.trimmed.isEmpty || !data.longTerm.trimmed.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    OwnWordsBlock(title: "Short-term", text: data.shortTerm)
                    OwnWordsBlock(title: "Long-term", text: data.longTerm)
                }
                .padding(.top, 16)
            }
        }
    }
}
