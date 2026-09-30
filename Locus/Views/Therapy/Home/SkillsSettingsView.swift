import SwiftUI
import SwiftData

struct SkillsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(TherapyAI.enabledKey) private var aiEnabled = false
    @AppStorage(ReminderScheduler.Daily.diary.defaultsKey) private var diaryReminder = false
    @AppStorage(ReminderScheduler.Daily.inbox.defaultsKey) private var inboxReminder = false
    @AppStorage(ReminderScheduler.Daily.practice.defaultsKey) private var practiceReminder = false
    @AppStorage(ReminderScheduler.valuesKey) private var valuesReminder = false

    @State private var urges: [String] = []
    @State private var newUrge = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use AI in the skills toolkit", isOn: $aiEnabled)
                    if aiEnabled, let reason = TherapyAI.unavailableReason {
                        Label(reason, systemImage: "exclamationmark.circle")
                            .font(.flowCaption)
                            .foregroundStyle(Ink.secondary)
                    }
                } header: {
                    Text("AI")
                } footer: {
                    Text("""
                    When on, Apple's on-device model reads only the text needed for one request \
                    (a thought, or the step you're on) to suggest thoughts to examine, offer a \
                    question, spot a similar belief in your ledger, or summarize your patterns \
                    from counts. It runs on this iPhone; nothing is sent anywhere. It only ever \
                    asks questions: it never writes your balanced thoughts or conclusions. \
                    Everything works with it off.
                    """)
                }

                Section {
                    Toggle("Diary card, evenings", isOn: $diaryReminder)
                        .onChange(of: diaryReminder) { _, on in ReminderScheduler.setDaily(.diary, on: on) }
                    Toggle("Thoughts waiting in the inbox", isOn: $inboxReminder)
                        .onChange(of: inboxReminder) { _, on in
                            ReminderScheduler.setDaily(.inbox, on: on)
                            if on { refreshInboxReminder(modelContext) }
                        }
                    Toggle("Daily practice", isOn: $practiceReminder)
                        .onChange(of: practiceReminder) { _, on in ReminderScheduler.setDaily(.practice, on: on) }
                    Toggle("Weekly values check-in", isOn: $valuesReminder)
                        .onChange(of: valuesReminder) { _, on in ReminderScheduler.setWeeklyValues(on: on) }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Reminders for experiments and planned steps are set when you plan them. Notification text never includes what you wrote.")
                }

                Section {
                    ForEach(urges, id: \.self) { Text($0.capitalizedFirst) }
                        .onDelete { offsets in
                            urges.remove(atOffsets: offsets)
                            saveUrges()
                        }
                    HStack {
                        TextField("Add an urge to track", text: $newUrge)
                        Button("Add") {
                            let u = newUrge.trimmed
                            guard !u.isEmpty, !urges.contains(u) else { return }
                            urges.append(u)
                            newUrge = ""
                            saveUrges()
                        }
                        .disabled(newUrge.trimmed.isEmpty)
                    }
                } header: {
                    Text("Diary card urges")
                } footer: {
                    Text("Rated 0–5 each day, with whether you acted on them.")
                }

                Section("Safety") {
                    NavigationLink("Safety plan") { SafetyPlanView() }
                }

                Section {
                    Link(destination: TherapyCatalog.findTherapistURL) {
                        Label("Find a therapist", systemImage: "arrow.up.right.square")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Locus is a self-help skills tool. It isn't therapy and can't diagnose or treat anything. Your skills data stays on this device, protected by its passcode encryption, and isn't synced to iCloud.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { urges = modelContext.singleton { TherapySettings() }.trackedUrges }
        }
    }

    private func saveUrges() {
        modelContext.singleton { TherapySettings() }.trackedUrges = urges
        try? modelContext.save()
    }
}
