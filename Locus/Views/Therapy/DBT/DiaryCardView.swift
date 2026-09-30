import SwiftUI
import SwiftData

/// DBT diary card: a daily check-in meant to take under a minute. Top
/// emotions (0–5), tracked urges (0–5 and whether you acted), skills used
/// (pre-ticked from today's sessions), whether if-then plans fired, a note.
struct DiaryCardView: View {
    var day: Date = .now

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<IfThenPlan> { $0.isActive }, sort: \IfThenPlan.createdAt) private var plans: [IfThenPlan]

    @State private var emotions: [EmotionRating] = []
    @State private var urges: [UrgeRating] = []
    @State private var skills: [String] = []
    @State private var note = ""
    @State private var fired: [String: Bool] = [:]
    @State private var trackedUrges: [String] = []
    @State private var newUrge = ""
    @State private var loaded = false

    private let accent = TherapyMethod.dbt.accent
    private var startOfDay: Date { Calendar.current.startOfDay(for: day) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 6) {
                        CapsLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        Text("Diary card")
                            .font(.flowTitle)
                        Text("A quick check-in on today. Skip anything that doesn't apply.")
                            .font(.flowHelper)
                            .foregroundStyle(Ink.secondary)
                    }

                    section("Top emotions today") {
                        EmotionPicker(ratings: $emotions, fivePoint: true, showsHint: false, accent: accent)
                    }

                    section("Urges") {
                        if trackedUrges.isEmpty {
                            Text("Add an urge you want to keep an eye on, like “avoid” or “doomscroll”.")
                                .font(.flowHelper)
                                .foregroundStyle(Ink.secondary)
                        }
                        ForEach(trackedUrges, id: \.self) { name in
                            urgeRow(name)
                        }
                        HStack(spacing: 8) {
                            FlowLineField(placeholder: "Track another urge…", text: $newUrge)
                            SecondaryButton(title: "Add", symbol: "plus") { addUrge(newUrge) }
                                .disabled(newUrge.trimmed.isEmpty)
                        }
                        if trackedUrges.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(TherapyCatalog.suggestedUrges, id: \.self) { s in
                                    Chip(title: s) { addUrge(s) }
                                }
                            }
                        }
                    }

                    section("Skills used today") {
                        FlowLayout(spacing: 8) {
                            ForEach(TherapyCatalog.skills, id: \.self) { skill in
                                Chip(title: skill, selected: skills.contains(skill)) {
                                    if skills.contains(skill) { skills.removeAll { $0 == skill } } else { skills.append(skill) }
                                }
                            }
                        }
                    }

                    if !plans.isEmpty {
                        section("Did your if-then plans fire?") {
                            ForEach(plans) { plan in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("If \(plan.trigger), then I'll \(plan.response).")
                                        .font(.flowHelper)
                                    OptionRow(options: [true, false], selection: Binding(
                                        get: { fired[plan.idString] },
                                        set: { fired[plan.idString] = $0 })) { $0 ? "It fired" : "It didn't" }
                                }
                                .padding(14)
                                .card()
                            }
                            Text("Leave it if the situation didn't come up.")
                                .font(.flowCaption)
                                .foregroundStyle(Ink.tertiary)
                        }
                    }

                    section("Note") {
                        FlowLineField(placeholder: "One line about today (optional)", text: $note)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.white)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Save", action: save)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.white.ignoresSafeArea())
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) { KeyboardHideButton() }
            }
            .onAppear(perform: load)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.flowSection)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func urgeRow(_ name: String) -> some View {
        let i = urges.firstIndex { $0.name == name }
        let intensity = Binding<Int?>(
            get: { i.map { urges[$0].intensity } },
            set: { value in
                if let i { urges[i].intensity = value ?? 0 } else { urges.append(UrgeRating(name: name, intensity: value ?? 0, acted: false)) }
            })
        let acted = Binding<Bool>(
            get: { i.map { urges[$0].acted } ?? false },
            set: { value in
                if let i { urges[i].acted = value } else { urges.append(UrgeRating(name: name, intensity: 0, acted: value)) }
            })
        return VStack(alignment: .leading, spacing: 10) {
            Text(name.capitalizedFirst)
                .font(.system(.body, weight: .semibold))
            OptionRow(options: Array(0...5), selection: intensity) { "\($0)" }
                .accessibilityLabel("\(name) urge, 0 to 5")
            Toggle("Acted on it", isOn: acted)
                .font(.flowHelper)
                .tint(accent)
        }
        .padding(14)
        .card()
    }

    private func addUrge(_ raw: String) {
        let name = raw.trimmed
        guard !name.isEmpty, !trackedUrges.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        trackedUrges.append(name)
        let settings = modelContext.singleton { TherapySettings() }
        settings.trackedUrges = trackedUrges
        newUrge = ""
    }

    private func existingCard() -> DiaryCard? {
        let start = startOfDay
        var descriptor = FetchDescriptor<DiaryCard>(predicate: #Predicate { $0.day == start })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        trackedUrges = modelContext.singleton { TherapySettings() }.trackedUrges
        if let card = existingCard() {
            emotions = card.emotions
            urges = card.urges
            skills = card.skillsUsed
            note = card.note
        }
        // Pre-tick skills from sessions completed today.
        let start = startOfDay
        let complete = SessionStatus.complete.rawValue
        let descriptor = FetchDescriptor<TherapySession>(predicate: #Predicate { $0.statusRaw == complete && $0.updatedAt >= start })
        for session in (try? modelContext.fetch(descriptor)) ?? [] {
            guard let done = session.completedAt, done >= start else { continue }
            let name = TherapyCatalog.skillName(for: session.tool)
            if !skills.contains(name) { skills.append(name) }
        }
        for plan in plans {
            if let today = plan.fires.last(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
                fired[plan.idString] = today.fired
            }
        }
    }

    private func save() {
        let card = existingCard() ?? {
            let c = DiaryCard(day: day)
            modelContext.insert(c)
            return c
        }()
        card.emotions = emotions
        card.urges = urges.filter { trackedUrges.contains($0.name) }
        card.skillsUsed = skills
        card.note = note.trimmed
        card.updatedAt = .now
        for plan in plans {
            guard let value = fired[plan.idString] else { continue }
            var fires = plan.fires.filter { !Calendar.current.isDate($0.date, inSameDayAs: day) }
            fires.append(PlanFire(date: day, fired: value))
            plan.fires = fires
        }
        try? modelContext.save()
        dismiss()
    }
}
