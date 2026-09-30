import SwiftUI
import SwiftData

/// Hot capture: the thought, one emotion, how strong, an optional tag, and
/// one tap to save. Processing happens later, from the inbox.
struct QuickCaptureView: View {
    /// Asks the presenter to open crisis skills (strong feelings, risk).
    var onCalmDown: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var focused: Bool

    @State private var text = ""
    @State private var family: EmotionFamily?
    @State private var word = ""
    @State private var intensity: Int?
    @State private var tag = ""
    @State private var saved: QuickCapture?
    @State private var risk = false

    private let accent = TherapyMethod.dbt.accent

    var body: some View {
        NavigationStack {
            Group {
                if risk {
                    SafetyResourcesView(onCalmDown: calmDown, onContinue: { dismiss() })
                } else if let saved {
                    savedView(saved)
                } else {
                    form
                }
            }
            .animation(.gentle, value: saved != nil)
            .animation(.gentle, value: risk)
        }
        .presentationDetents(saved == nil && !risk ? [.large] : [.medium, .large])
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What's the thought?")
                        .font(.flowQuestion)
                    TextField("Just as it sounds in your head", text: $text, axis: .vertical)
                        .font(.flowBody)
                        .lineLimit(2...6)
                        .focused($focused)
                        .padding(14)
                        .card()
                        .accessibilityLabel("What's the thought?")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Feeling").font(.system(.body, weight: .semibold))
                    FlowLayout(spacing: 6) {
                        ForEach(EmotionFamily.allCases) { f in
                            Chip(title: f.name, selected: family == f) {
                                family = family == f ? nil : f
                                word = ""
                            }
                        }
                    }
                    if let family {
                        FlowLayout(spacing: 6) {
                            ForEach(family.words, id: \.self) { w in
                                Chip(title: w, selected: word == w) { word = word == w ? "" : w }
                            }
                        }
                        .transition(.opacity)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("How strong?").font(.system(.body, weight: .semibold))
                    TenPointScale(label: "How strong", value: $intensity,
                                  anchors: [0: "Barely", 5: "Uncomfortable", 8: "Hard to think straight", 10: "Overwhelming"])
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Where? (optional)").font(.system(.body, weight: .semibold))
                    FlowLayout(spacing: 6) {
                        ForEach(TherapyCatalog.captureTags, id: \.self) { t in
                            Chip(title: t, selected: tag == t) { tag = tag == t ? "" : t }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .animation(.gentle, value: family)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.white)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Save to inbox", disabled: text.trimmed.isEmpty, action: save)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white.ignoresSafeArea())
        }
        .navigationTitle("Quick capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) { KeyboardHideButton() }
        }
        .onAppear { focused = true }
    }

    private func savedView(_ capture: QuickCapture) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Saved to your inbox", systemImage: "tray.and.arrow.down.fill")
                .font(.flowSection)
            Text("It'll wait there until you're ready to work through it.")
                .font(.flowHelper)
                .foregroundStyle(Ink.secondary)
            if capture.intensity >= 8 {
                NoticeCard(text: "That's a strong feeling. Want to bring it down first?", symbol: "wind") {
                    PrimaryButton(title: "Try a calming skill", action: calmDown)
                }
            }
            Spacer()
            Button("Done") { dismiss() }
                .font(.flowButton)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    private func save() {
        let capture = QuickCapture(text: text.trimmed)
        capture.familyRaw = family?.rawValue ?? ""
        capture.word = word
        capture.intensity = intensity ?? 5
        capture.tag = tag
        modelContext.insert(capture)
        try? modelContext.save()
        focused = false
        refreshInboxReminder(modelContext)
        if RiskDetector.assess(capture.text).isRisk {
            risk = true
        } else {
            saved = capture
        }
    }

    private func calmDown() {
        dismiss()
        onCalmDown?()
    }
}

@MainActor
func refreshInboxReminder(_ context: ModelContext) {
    let inbox = CaptureStatus.inbox.rawValue
    let count = (try? context.fetchCount(FetchDescriptor<QuickCapture>(predicate: #Predicate { $0.statusRaw == inbox }))) ?? 0
    ReminderScheduler.refreshInbox(count: count)
}

/// "Thoughts to work through": captures waiting in the inbox.
struct InboxSection: View {
    let onWorkThrough: (QuickCapture) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<QuickCapture> { $0.statusRaw == "inbox" }, sort: \QuickCapture.createdAt, order: .reverse)
    private var captures: [QuickCapture]

    var body: some View {
        if !captures.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CapsLabel("Thoughts to work through")
                    Spacer()
                    Text("\(captures.count)")
                        .font(.flowCaption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Ink.tertiary)
                }
                VStack(spacing: 10) {
                    ForEach(captures) { capture in
                        InboxRow(capture: capture,
                                 onWorkThrough: { onWorkThrough(capture) },
                                 onArchive: {
                                     withAnimation(.gentle) { capture.status = .archived }
                                     try? modelContext.save()
                                     refreshInboxReminder(modelContext)
                                 })
                    }
                }
            }
        }
    }
}

private struct InboxRow: View {
    let capture: QuickCapture
    let onWorkThrough: () -> Void
    let onArchive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("“\(capture.text)”")
                .font(.system(.body, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if !capture.emotionLabel.isEmpty {
                    Text("\(capture.emotionLabel.capitalizedFirst) \(capture.intensity)/10")
                } else {
                    Text("\(capture.intensity)/10")
                }
                if !capture.tag.isEmpty { Text("· \(capture.tag)") }
                Text("· \(capture.createdAt.formatted(.relative(presentation: .named)))")
            }
            .font(.flowCaption)
            .foregroundStyle(Ink.tertiary)
            HStack(spacing: 10) {
                SecondaryButton(title: "Work through this", symbol: "arrow.triangle.branch", action: onWorkThrough)
                Button("Archive", action: onArchive)
                    .font(.flowHelper.weight(.semibold))
                    .foregroundStyle(Ink.secondary)
                    .frame(minHeight: 44)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

extension QuickCapture {
    /// What the capture carries into a skills flow.
    var launch: TherapyLaunch {
        var emotion: EmotionRating?
        if let family {
            emotion = EmotionRating(family: family, word: word.isEmpty ? family.words[0] : word,
                                    intensity: Double(intensity * 10))
        }
        return TherapyLaunch(sourceCaptureID: idString, entryText: text, targetThought: text, emotion: emotion)
    }
}
