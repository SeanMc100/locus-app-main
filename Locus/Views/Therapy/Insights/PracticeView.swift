import SwiftUI
import SwiftData

/// Practice when calm: skills fail under stress if they've only ever been
/// practiced under stress.
struct PracticeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<PracticeCard> { !$0.isArchived }, sort: \PracticeCard.dueAt) private var cards: [PracticeCard]
    @Query(sort: \IfThenPlan.createdAt, order: .reverse) private var plans: [IfThenPlan]
    @AppStorage(ReminderScheduler.Daily.practice.defaultsKey) private var practiceReminder = false

    @State private var showDeck = false
    @State private var showNewPlan = false
    @State private var showBreathing = false
    @State private var flow: FlowLaunch?

    private var due: [PracticeCard] { cards.filter { $0.dueAt <= .now } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // Reframe deck
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reframe deck").font(.flowSection)
                    if cards.isEmpty {
                        InsightsEmptyState(symbol: "rectangle.stack", title: "No cards yet",
                                           message: "When you finish a Thought Record, you can add your balanced thought here. Each card shows the old thought; flip it to see your own balanced thought and evidence. Practicing on calm days makes them easier to reach for later.")
                    } else {
                        Text(due.isEmpty ? "Nothing due. Next card \(cards.first?.dueAt.formatted(.relative(presentation: .named)) ?? "soon")."
                             : "\(due.count) card\(due.count == 1 ? "" : "s") due, of \(cards.count).")
                            .font(.flowHelper)
                            .foregroundStyle(Ink.secondary)
                        PrimaryButton(title: due.isEmpty ? "Practice anyway" : "Practice now") { showDeck = true }
                    }
                    Toggle("Daily practice reminder", isOn: $practiceReminder)
                        .font(.flowHelper.weight(.semibold))
                        .tint(TherapyMethod.cbt.accent)
                        .onChange(of: practiceReminder) { _, on in ReminderScheduler.setDaily(.practice, on: on) }
                }

                // If-then plans
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("If-then plans").font(.flowSection)
                        Spacer()
                        Button { showNewPlan = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("New if-then plan")
                    }
                    if plans.isEmpty {
                        InsightsEmptyState(symbol: "arrow.triangle.branch", title: "No plans yet",
                                           message: "“If [trigger], then I'll [response].” Plans come from chain analyses and experiments, or you can write one. Deciding in advance makes the new response easier to reach for.")
                    }
                    ForEach(plans) { plan in
                        PlanRow(plan: plan)
                    }
                }

                // Skill rehearsal
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rehearse a skill").font(.flowSection)
                    Text("A short run-through while things are calm.")
                        .font(.flowHelper)
                        .foregroundStyle(Ink.secondary)
                    ChoiceCard(title: "Paced breathing", detail: "One to three minutes, out-breath longer than in.",
                               symbol: "wind", accent: TherapyMethod.dbt.accent) { showBreathing = true }
                    ChoiceCard(title: "Defusion", detail: "Practice unhooking from a familiar thought.",
                               symbol: "cloud", accent: TherapyMethod.act.accent) {
                        flow = FlowLaunch(start: .tool(.defusion, TherapyLaunch(isPractice: true)))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color.white)
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showDeck) {
            PracticeDeckView(cards: due.isEmpty ? Array(cards.prefix(10)) : due)
        }
        .sheet(isPresented: $showNewPlan) { NewPlanSheet() }
        .sheet(isPresented: $showBreathing) { BreathingRehearsal() }
        .fullScreenCover(item: $flow) { launch in
            TherapyFlowHost(start: launch.start) { flow = nil }
        }
    }
}

/// Practice in its own navigation stack, for opening from a reminder.
struct PracticeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PracticeView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }.fontWeight(.semibold)
                    }
                }
        }
    }
}

private struct PlanRow: View {
    @Bindable var plan: IfThenPlan
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("If \(plan.trigger), then I'll \(plan.response).")
                .font(.system(.body, weight: .medium))
                .foregroundStyle(plan.isActive ? Ink.primary : Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(plan.source.label)
                if let rate = plan.hitRate {
                    Text("· fired \(Int((rate * 100).rounded()))% of \(plan.fires.count) time\(plan.fires.count == 1 ? "" : "s")")
                }
            }
            .font(.flowCaption)
            .foregroundStyle(Ink.tertiary)
            Toggle("Active", isOn: $plan.isActive)
                .font(.flowHelper)
                .tint(TherapyMethod.dbt.accent)
            Toggle("Daily reminder", isOn: $plan.remindersOn)
                .font(.flowHelper)
                .tint(TherapyMethod.dbt.accent)
                .disabled(!plan.isActive)
                .onChange(of: plan.remindersOn) { _, on in ReminderScheduler.setPlanReminder(planID: plan.idString, on: on && plan.isActive) }
                .onChange(of: plan.isActive) { _, active in
                    if !active { ReminderScheduler.setPlanReminder(planID: plan.idString, on: false) }
                }
            if plan.isActive {
                HStack(spacing: 8) {
                    Text("Came up today?").font(.flowCaption.weight(.semibold)).foregroundStyle(Ink.secondary)
                    Spacer()
                    Button("It fired") { record(true) }
                    Button("It didn't") { record(false) }
                }
                .font(.flowCaption.weight(.semibold))
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .card()
        .contextMenu {
            Button(role: .destructive) {
                ReminderScheduler.setPlanReminder(planID: plan.idString, on: false)
                modelContext.delete(plan)
            } label: { Label("Delete plan", systemImage: "trash") }
        }
    }

    private func record(_ fired: Bool) {
        var fires = plan.fires.filter { !Calendar.current.isDateInToday($0.date) }
        fires.append(PlanFire(date: .now, fired: fired))
        plan.fires = fires
        try? modelContext.save()
    }
}

private struct NewPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var trigger = ""
    @State private var response = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                StepHeader(question: "New if-then plan",
                           helper: "Name the moment, then the response you'll reach for.")
                FlowLineField(placeholder: "If…", text: $trigger)
                FlowLineField(placeholder: "then I'll…", text: $response)
                Spacer()
            }
            .padding(24)
            .background(Color.white)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Save plan", disabled: trigger.trimmed.isEmpty || response.trimmed.isEmpty) {
                    modelContext.insert(IfThenPlan(trigger: trigger.trimmed, response: response.trimmed, source: .manual))
                    try? modelContext.save()
                    dismiss()
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { KeyboardHideButton() }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Paced breathing on its own, logged as calm-time practice.
private struct BreathingRehearsal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TippExerciseView(skill: .breathing, onDone: {
            let session = TherapySession(tool: .crisisSkills)
            session.isPractice = true
            var data = CrisisData()
            data.skill = .tipp
            data.tippDone = [.breathing]
            session.store(data)
            session.status = .complete
            session.completedAt = .now
            modelContext.insert(session)
            try? modelContext.save()
            dismiss()
        }, onClose: { dismiss() })
    }
}

/// Spaced-repetition review: front is the old thought; flip for your own
/// balanced thought and evidence; rate how it lands.
struct PracticeDeckView: View {
    let cards: [PracticeCard]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var flipped = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if index < cards.count {
                    let card = cards[index]
                    Text("\(index + 1) of \(cards.count)")
                        .font(.flowCaption.weight(.medium))
                        .foregroundStyle(Ink.tertiary)
                    Button {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.45)) { flipped.toggle() }
                    } label: {
                        ZStack {
                            face(label: "The old thought", text: card.front, detail: "Tap to see what you worked out")
                                .opacity(flipped ? 0 : 1)
                            face(label: "Your balanced thought", text: card.back,
                                 detail: card.evidence.isEmpty ? nil : "Your evidence: \(card.evidence)")
                                .opacity(flipped ? 1 : 0)
                                .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (0, 1, 0))
                        }
                        .rotation3DEffect(.degrees(flipped && !reduceMotion ? 180 : 0), axis: (0, 1, 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(flipped ? "Your balanced thought: \(card.back)" : "The old thought: \(card.front)")
                    .accessibilityHint(flipped ? "" : "Flips the card")

                    if flipped {
                        VStack(spacing: 10) {
                            Text("How does it land today?")
                                .font(.system(.body, weight: .semibold))
                            HStack(spacing: 8) {
                                ForEach(PracticeRating.allCases, id: \.self) { rating in
                                    Button(rating.label) { rate(card, rating) }
                                        .font(.flowHelper.weight(.semibold))
                                        .foregroundStyle(Ink.primary)
                                        .frame(maxWidth: .infinity, minHeight: 50)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(Ink.fillStrong))
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        .transition(.opacity)
                    }
                    Spacer()
                } else {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 34, weight: .light))
                    Text("Practice done").font(.flowTitle)
                    Text("Cards come back sooner when they're still hard, and less often as they get stronger.")
                        .font(.flowHelper)
                        .foregroundStyle(Ink.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                    PrimaryButton(title: "Done") { dismiss() }
                }
            }
            .padding(24)
            .background(Color.white)
            .navigationTitle("Reframe deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
            }
        }
    }

    private func face(label: String, text: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CapsLabel(label)
            Text(text)
                .font(.system(.title3, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.flowHelper)
                    .foregroundStyle(Ink.secondary)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .card(filled: true)
    }

    private func rate(_ card: PracticeCard, _ rating: PracticeRating) {
        let next = SpacedRepetition.schedule(box: card.box, rating: rating)
        card.box = next.box
        card.dueAt = next.due
        card.lastReviewedAt = .now
        card.reviews = card.reviews + [PracticeReview(date: .now, rating: rating)]
        try? modelContext.save()
        withAnimation(.gentle) {
            flipped = false
            index += 1
        }
    }
}
