import SwiftUI
import SwiftData

@MainActor
enum ValuesService {
    /// Creates the built-in life domains the first time values are used.
    static func ensureDomains(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ValueDomain>())) ?? []
        let keys = Set(existing.map(\.key))
        for (i, domain) in TherapyCatalog.lifeDomains.enumerated() where !keys.contains(domain.key) {
            context.insert(ValueDomain(key: domain.key, name: domain.name, symbol: domain.symbol, order: i))
        }
        try? context.save()
    }

    static func recordConsistency(_ value: Int, for domain: ValueDomain) {
        var history = domain.consistency
        // One point per day: a second check-in the same day replaces it.
        history.removeAll { Calendar.current.isDateInToday($0.date) }
        history.append(ConsistencyPoint(date: .now, value: value))
        domain.consistency = history
    }
}

/// ACT values: first-time clarification (domains, qualities, importance,
/// consistency), then ongoing check-ins that re-rate consistency.
struct ValuesCheckInFlow: View {
    let session: TherapySession
    let callbacks: FlowCallbacks

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ValueDomain.order) private var domains: [ValueDomain]

    enum Step: String { case domains, clarify, checkIn, complete }

    @State private var data = ValuesCheckInData()
    @State private var step: Step = .checkIn
    @State private var loaded = false
    @State private var editing: ValueDomain?
    @State private var newDomain = ""

    private let accent = TherapyMethod.act.accent
    private var visible: [ValueDomain] { domains.filter { !$0.isHidden } }
    private var clarified: [ValueDomain] { visible.filter(\.isClarified) }

    private var steps: [Step] {
        clarified.isEmpty || step == .domains || step == .clarify ? [.domains, .clarify, .complete] : [.checkIn, .complete]
    }
    private var index: Int { steps.firstIndex(of: step) ?? 0 }

    var body: some View {
        StepScaffold(toolTitle: session.tool.title, accent: accent, stepID: step.rawValue,
                     position: index + 1, total: steps.count - 1,
                     showsProgress: step != .complete,
                     primaryTitle: step == .complete ? "Done" : (step == .domains ? "Next" : "Save"),
                     canContinue: canContinue,
                     secondaryTitle: step == .checkIn ? "Edit your values" : nil,
                     onSecondary: { go(to: .domains) },
                     onPrimary: primary,
                     onBack: backAction,
                     closesWithoutAsking: step == .complete,
                     onSaveForLater: callbacks.onClose,
                     onDiscard: callbacks.onDiscard) {
            content
        }
        .onAppear(perform: load)
        .onChange(of: data) { _, new in session.store(new) }
        .sheet(item: $editing) { domain in
            DomainEditor(domain: domain)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .domains:
            StepHeader(question: "Which parts of life matter to you?",
                       helper: "Hide any that don't apply right now, and add your own.")
            VStack(spacing: 8) {
                ForEach(domains) { domain in
                    Button {
                        domain.isHidden.toggle()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: domain.symbol)
                                .foregroundStyle(accent)
                                .frame(width: 26)
                            Text(domain.name)
                                .font(.flowBody)
                                .foregroundStyle(domain.isHidden ? Ink.tertiary : Ink.primary)
                                .strikethrough(domain.isHidden)
                            Spacer()
                            Image(systemName: domain.isHidden ? "eye.slash" : "checkmark.circle.fill")
                                .foregroundStyle(domain.isHidden ? Ink.tertiary : Ink.primary)
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                        .card(selected: !domain.isHidden)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(domain.name)
                    .accessibilityValue(domain.isHidden ? "Hidden" : "Included")
                }
            }
            HStack(spacing: 8) {
                FlowLineField(placeholder: "Add your own…", text: $newDomain)
                SecondaryButton(title: "Add", symbol: "plus") {
                    let name = newDomain.trimmed
                    guard !name.isEmpty else { return }
                    modelContext.insert(ValueDomain(key: "", name: name, symbol: "star", order: domains.count))
                    newDomain = ""
                }
            }

        case .clarify:
            StepHeader(question: "What kind of person do you want to be in each?",
                       helper: "Values are directions, not goals: you never finish being kind. Tap each area to choose its qualities and rate it.")
            VStack(spacing: 10) {
                ForEach(visible) { domain in
                    Button {
                        editing = domain
                    } label: {
                        DomainRow(domain: domain, accent: accent)
                    }
                    .buttonStyle(.plain)
                }
            }

        case .checkIn:
            StepHeader(question: "How consistently have you acted on each lately?",
                       helper: "0 is not at all, 10 is fully. Weekly is a good rhythm.")
            VStack(spacing: 12) {
                ForEach(clarified) { domain in
                    ConsistencyRow(domain: domain, value: Binding(
                        get: { data.ratings[domain.idString] },
                        set: { data.ratings[domain.idString] = $0 }), accent: accent)
                }
            }

        case .complete:
            CompletionContent(title: "Values checked in", rows: completionRows, accent: accent) {
                Text("The Values Gap in Insights shows where importance and action are furthest apart.")
                    .font(.flowCaption)
                    .foregroundStyle(Ink.tertiary)
            }
        }
    }

    private var completionRows: [ChangeRow] {
        clarified.compactMap { d in
            guard let importance = d.importance, let consistency = d.latestConsistency else { return nil }
            return ChangeRow(label: "\(d.name): importance → consistency", before: Double(importance),
                             after: Double(consistency), scale: .outOf10)
        }
    }

    private var canContinue: Bool {
        switch step {
        case .domains: !visible.isEmpty
        case .clarify: !clarified.isEmpty
        case .checkIn: clarified.contains { data.ratings[$0.idString] != nil }
        case .complete: true
        }
    }

    private var backAction: (() -> Void)? {
        switch step {
        case .clarify: { go(to: .domains) }
        case .domains, .checkIn: callbacks.onBackFromStart
        case .complete: nil
        }
    }

    private func primary() {
        switch step {
        case .domains:
            try? modelContext.save()
            go(to: .clarify)
        case .clarify:
            for d in clarified { if let c = d.latestConsistency { data.ratings[d.idString] = c } }
            finish()
        case .checkIn:
            for d in clarified {
                if let value = data.ratings[d.idString] { ValuesService.recordConsistency(value, for: d) }
            }
            finish()
        case .complete:
            callbacks.onNext(.done)
        }
    }

    private func finish() {
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
        ValuesService.ensureDomains(in: modelContext)
        data = session.decode(ValuesCheckInData.self) ?? ValuesCheckInData()
        let clarifiedNow = ((try? modelContext.fetch(FetchDescriptor<ValueDomain>())) ?? []).contains { $0.isClarified && !$0.isHidden }
        step = Step(rawValue: session.stepKey) ?? (clarifiedNow ? .checkIn : .domains)
        if session.status == .complete { step = .complete }
    }
}

struct DomainRow: View {
    let domain: ValueDomain
    var accent: Color = .black

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: domain.symbol)
                .foregroundStyle(accent)
                .frame(width: 26)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(domain.name)
                    .font(.system(.body, weight: .semibold))
                Text(domain.qualities.isEmpty ? "Tap to choose qualities" : domain.qualitiesLine)
                    .font(.flowHelper)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.leading)
                if let importance = domain.importance {
                    Text("Importance \(importance)/10" + (domain.latestConsistency.map { " · acting on it \($0)/10" } ?? ""))
                        .font(.flowCaption)
                        .foregroundStyle(Ink.tertiary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: domain.isClarified ? "checkmark.circle.fill" : "chevron.right")
                .foregroundStyle(domain.isClarified ? accent : Ink.tertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
        .card()
        .accessibilityElement(children: .combine)
    }
}

private struct ConsistencyRow: View {
    let domain: ValueDomain
    @Binding var value: Int?
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: domain.symbol).foregroundStyle(accent)
                Text(domain.name).font(.system(.body, weight: .semibold))
                Spacer()
                Text(value.map { "\($0)" } ?? "–")
                    .font(.system(.body, weight: .bold))
                    .monospacedDigit()
            }
            if !domain.qualities.isEmpty {
                Text(domain.qualitiesLine)
                    .font(.flowCaption)
                    .foregroundStyle(Ink.tertiary)
            }
            Slider(value: Binding(get: { Double(value ?? domain.latestConsistency ?? 5) }, set: { value = Int($0.rounded()) }),
                   in: 0...10, step: 1)
                .tint(accent)
                .accessibilityLabel("\(domain.name): how consistently")
                .accessibilityValue(value.map { "\($0) out of 10" } ?? "Not rated")
        }
        .padding(14)
        .card()
    }
}

/// Qualities, importance, and current consistency for one domain.
struct DomainEditor: View {
    @Bindable var domain: ValueDomain

    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""
    @State private var importance: Int?
    @State private var consistency: Int?

    private let accent = TherapyMethod.act.accent

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    StepHeader(question: "What kind of person do you want to be in \(domain.name.lowercased())?",
                               helper: "Pick the qualities you want to act with. A few is plenty.")
                    FlowLayout(spacing: 8) {
                        ForEach(TherapyCatalog.valueWords + domain.qualities.filter { !TherapyCatalog.valueWords.contains($0) }, id: \.self) { word in
                            Chip(title: word, selected: domain.qualities.contains(word)) {
                                if domain.qualities.contains(word) { domain.qualities.removeAll { $0 == word } } else { domain.qualities.append(word) }
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        FlowLineField(placeholder: "In your own words…", text: $custom)
                        SecondaryButton(title: "Add", symbol: "plus") {
                            let w = custom.trimmed.lowercased()
                            guard !w.isEmpty, !domain.qualities.contains(w) else { return }
                            domain.qualities.append(w)
                            custom = ""
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("How important is this to you?").font(.system(.body, weight: .semibold))
                        TenPointScale(label: "Importance", value: $importance, anchors: [0: "Not at all", 10: "Extremely"])
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("How consistently have you acted on it lately?").font(.system(.body, weight: .semibold))
                        TenPointScale(label: "Consistency", value: $consistency, anchors: [0: "Not at all", 10: "Fully"])
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(Color.white)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Save", disabled: importance == nil || consistency == nil) {
                    domain.importance = importance
                    if let consistency { ValuesService.recordConsistency(consistency, for: domain) }
                    dismiss()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white.ignoresSafeArea())
            }
            .navigationTitle(domain.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { KeyboardHideButton() }
            }
            .onAppear {
                importance = domain.importance
                consistency = domain.latestConsistency
            }
        }
    }
}
