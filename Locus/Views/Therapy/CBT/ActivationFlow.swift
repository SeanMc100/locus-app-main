import SwiftUI
import SwiftData

/// CBT behavioral activation: check in, pick one small activity (mastery
/// or pleasure), schedule it, and check back afterwards. Over time Insights
/// shows which activities reliably lift this person's mood.
struct ActivationFlow: View {
    let session: TherapySession
    let callbacks: FlowCallbacks

    @Environment(\.modelContext) private var modelContext
    @Environment(\.safetyGate) private var safetyGate
    @Query(filter: #Predicate<ValueDomain> { !$0.isHidden }, sort: \ValueDomain.order) private var domains: [ValueDomain]

    enum Step: String {
        case checkIn, activity, schedule, doing, scheduled, after, complete
    }

    @State private var data = ActivationData()
    @State private var step: Step = .checkIn
    @State private var loaded = false
    @State private var category: ActivityCategory = .pleasure

    private let accent = TherapyMethod.cbt.accent
    private let planSteps: [Step] = [.checkIn, .activity, .schedule]

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
                     onSecondary: { go(to: .after) },
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
        case .checkIn:
            StepHeader(question: "How are you right now?",
                       helper: "A quick baseline, so you can see what the activity does.")
            VStack(alignment: .leading, spacing: 10) {
                Text("Mood").font(.system(.body, weight: .semibold))
                TenPointScale(label: "Mood", value: $data.moodBefore, anchors: [0: "Very low", 5: "Okay", 10: "Great"])
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Energy").font(.system(.body, weight: .semibold))
                TenPointScale(label: "Energy", value: $data.energyBefore, anchors: [0: "Empty", 5: "Some", 10: "Full"])
            }

        case .activity:
            StepHeader(question: "Pick something small that might help.",
                       helper: "Small, specific, and doable beats ambitious. Ten minutes counts.")
            Picker("Kind of activity", selection: $category) {
                ForEach(ActivityCategory.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(category.detail)
                .font(.flowHelper)
                .foregroundStyle(Ink.secondary)
            if category == .custom {
                FlowLineField(placeholder: "e.g. Water the plants", text: $data.activity)
            } else {
                VStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { idea in
                        ChoiceCard(title: idea, selected: data.activity == idea && data.category == category) {
                            data.activity = idea
                            data.category = category
                        }
                    }
                }
            }
            if !clarifiedDomains.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Optional: which value does it serve?")
                        .font(.system(.body, weight: .semibold))
                    FlowLayout(spacing: 8) {
                        ForEach(clarifiedDomains) { domain in
                            Chip(title: domain.name, selected: data.valueDomainID == domain.idString) {
                                data.valueDomainID = data.valueDomainID == domain.idString ? nil : domain.idString
                            }
                        }
                    }
                }
            }
            SocraticPromptCard(step: .activity)

        case .schedule:
            TargetThoughtCard(thought: data.activity, label: "Your activity", accent: accent)
            StepHeader(question: "When will you do it?",
                       helper: "Putting a time on it makes it much more likely to happen.")
            OptionRow(options: [true, false], selection: $data.doNow) { $0 ? "Now" : "Later" }
            if data.doNow == false {
                WhenPicker(date: $data.when)
                    .transition(.opacity)
            }

        case .doing:
            waitingView(title: "Go for it",
                        line: "Do “\(data.activity)” now. Come back when you're done to see how it went.")

        case .scheduled:
            waitingView(title: "Activity planned",
                        line: "We'll remind you at \((session.scheduledAt ?? .now).formatted(date: .abbreviated, time: .shortened)). It'll wait under In progress.")

        case .after:
            TargetThoughtCard(thought: data.activity, label: "Your activity", accent: accent)
            StepHeader(question: "Did you do it?")
            OptionRow(options: [true, false], selection: $data.did) { $0 ? "Yes" : "Not this time" }
            if data.did == true {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sense of accomplishment").font(.system(.body, weight: .semibold))
                    TenPointScale(label: "Mastery", value: $data.mastery, anchors: [0: "None", 10: "A lot"])
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Enjoyment").font(.system(.body, weight: .semibold))
                    TenPointScale(label: "Pleasure", value: $data.pleasure, anchors: [0: "None", 10: "A lot"])
                }
            } else if data.did == false {
                Text("That's useful to know too. Smaller steps are easier to start.")
                    .font(.flowHelper)
                    .foregroundStyle(Ink.secondary)
            }
            if data.did != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Mood now").font(.system(.body, weight: .semibold))
                    TenPointScale(label: "Mood now", value: $data.moodAfter, anchors: [0: "Very low", 5: "Okay", 10: "Great"])
                }
            }

        case .complete:
            CompletionContent(
                title: data.did == true ? "You did it" : "Checked in",
                subtitle: "“\(data.activity)”",
                rows: completionRows,
                accent: accent
            ) {
                Text("Insights will show which activities tend to lift your mood.")
                    .font(.flowCaption)
                    .foregroundStyle(Ink.tertiary)
            }
        }
    }

    private func waitingView(title: String, line: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: TherapyTool.behavioralActivation.symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(title).font(.flowTitle)
            Text(line)
                .font(.flowBody)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var completionRows: [ChangeRow] {
        var rows: [ChangeRow] = []
        if let before = data.moodBefore {
            rows.append(ChangeRow(label: "Mood", before: Double(before), after: data.moodAfter.map(Double.init), scale: .outOf10))
        }
        return rows
    }

    private var suggestions: [String] {
        category == .mastery ? TherapyCatalog.masteryActivities : TherapyCatalog.pleasureActivities
    }

    private var clarifiedDomains: [ValueDomain] { domains.filter(\.isClarified) }

    // MARK: Navigation

    private var primaryTitle: String {
        switch step {
        case .schedule: data.doNow == true ? "Start now" : "Plan it"
        case .doing: "I'm back"
        case .scheduled, .complete: "Done"
        case .after: "Finish"
        default: "Next"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .checkIn: data.moodBefore != nil && data.energyBefore != nil
        case .activity: !data.activity.trimmed.isEmpty
        case .schedule: data.doNow == true || (data.doNow == false && data.when != nil)
        case .doing, .scheduled, .complete: true
        case .after: data.did != nil && data.moodAfter != nil
            && (data.did == false || (data.mastery != nil && data.pleasure != nil))
        }
    }

    private var backAction: (() -> Void)? {
        switch step {
        case .checkIn: callbacks.onBackFromStart
        case .activity: { go(to: .checkIn) }
        case .schedule: { go(to: .activity) }
        default: nil
        }
    }

    private func primary() {
        switch step {
        case .checkIn:
            go(to: .activity)
        case .activity:
            if data.category == nil || category == .custom { data.category = category }
            safetyGate.check(data) { go(to: .schedule) }
        case .schedule:
            session.targetThought = data.activity.trimmed
            if data.doNow == true {
                session.status = .pending
                session.scheduledAt = .now
                try? modelContext.save()
                go(to: .doing)
            } else {
                SessionService.schedule(session, at: data.when ?? .now.addingTimeInterval(3600),
                                        title: "Time for your planned activity",
                                        body: "Tap to check in afterwards.", in: modelContext)
                go(to: .scheduled)
            }
        case .doing:
            go(to: .after)
        case .scheduled, .complete:
            callbacks.onNext(.done)
        case .after:
            SessionService.complete(session,
                                    metricBefore: data.moodBefore.map { Double($0) * 10 },
                                    metricAfter: data.moodAfter.map { Double($0) * 10 },
                                    in: modelContext)
            go(to: .complete)
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
        data = session.decode(ActivationData.self) ?? ActivationData()
        if let c = data.category { category = c }
        step = Step(rawValue: session.stepKey) ?? .checkIn
        switch session.status {
        case .pending: step = .after
        case .complete: step = .complete
        case .draft: break
        }
    }
}
