import SwiftUI
import SwiftData

/// The thought being worked on, pinned at the top of every step so the
/// user never loses the thread.
struct TargetThoughtCard: View {
    let thought: String
    var label = "The thought"
    var accent: Color = .black

    var body: some View {
        if !thought.trimmed.isEmpty {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    CapsLabel(label)
                    Text("“\(thought.trimmed)”")
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(Ink.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 12)
                Spacer(minLength: 0)
            }
            .padding(14)
            .card(filled: true)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Optional thinking-trap chips inside the thought record. Each row shows
/// a plain definition; tap the info button for an example.
struct DistortionSelector: View {
    @Binding var selected: [String]
    @Binding var none: Bool

    @State private var expanded: String?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Distortions.all) { distortion in
                row(distortion)
            }
            ChoiceCard(title: "None of these", selected: none) {
                none.toggle()
                if none { selected = [] }
            }
        }
    }

    private func row(_ d: Distortion) -> some View {
        let isOn = selected.contains(d.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    if isOn { selected.removeAll { $0 == d.id } } else { selected.append(d.id); none = false }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isOn ? Ink.primary : Ink.tertiary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(d.name)
                                .font(.system(.body, weight: .semibold))
                            Text(d.definition)
                                .font(.flowHelper)
                                .foregroundStyle(Ink.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)

                Button {
                    withAnimation(.gentle) { expanded = expanded == d.id ? nil : d.id }
                } label: {
                    Image(systemName: expanded == d.id ? "chevron.up" : "info.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Ink.tertiary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded == d.id ? "Hide example" : "Show an example of \(d.name)")
            }
            if expanded == d.id {
                Text("For example: \(d.example)")
                    .font(.flowHelper)
                    .italic()
                    .foregroundStyle(Ink.secondary)
                    .padding(.leading, 32)
                    .transition(.opacity)
            }
        }
        .padding(14)
        .card(selected: isOn)
    }
}

/// "Is this a thought you've had before?": link a thought to a Belief
/// Ledger entry, or start a new one.
struct LedgerLinkView: View {
    let thought: String
    @Binding var linkedBeliefID: String?

    @Environment(\.modelContext) private var modelContext
    @State private var showPicker = false

    private var linked: LedgerBelief? {
        linkedBeliefID.flatMap { modelContext.belief(id: $0) }
    }

    var body: some View {
        Group {
            if let linked {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "books.vertical")
                        .foregroundStyle(Ink.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("In your Belief Ledger")
                            .font(.flowCaption.weight(.semibold))
                            .foregroundStyle(Ink.tertiary)
                        Text(linked.storyName.isEmpty ? linked.canonicalText : "\(linked.canonicalText) (the “\(linked.storyName)” story)")
                            .font(.flowHelper.weight(.medium))
                    }
                    Spacer()
                    Button("Change") { showPicker = true }
                        .font(.flowHelper.weight(.semibold))
                }
                .padding(14)
                .card(filled: true)
            } else {
                Button {
                    showPicker = true
                } label: {
                    HStack {
                        Image(systemName: "books.vertical")
                        Text("Is this a thought you've had before?")
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    }
                    .font(.flowHelper.weight(.semibold))
                    .foregroundStyle(Ink.primary)
                    .padding(14)
                    .card()
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showPicker) {
            LedgerPickerSheet(thought: thought, linkedBeliefID: $linkedBeliefID)
        }
    }
}

private struct LedgerPickerSheet: View {
    let thought: String
    @Binding var linkedBeliefID: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LedgerBelief.lastSeenAt, order: .reverse) private var beliefs: [LedgerBelief]
    @State private var search = ""
    @State private var suggestion: LedgerBelief?

    private var filtered: [LedgerBelief] {
        let q = search.trimmed.lowercased()
        guard !q.isEmpty else { return beliefs }
        return beliefs.filter { $0.canonicalText.lowercased().contains(q) || $0.storyName.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let suggestion {
                    Section {
                        Button {
                            link(suggestion)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("This looks similar to “\(suggestion.canonicalText)”. Link it?")
                                    .font(.flowHelper.weight(.semibold))
                                Text("Suggested by AI. Nothing is linked unless you tap.")
                                    .font(.flowCaption)
                                    .foregroundStyle(Ink.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !thought.trimmed.isEmpty {
                    Section {
                        Button {
                            let belief = LedgerBelief(canonicalText: thought.trimmed)
                            modelContext.insert(belief)
                            link(belief)
                        } label: {
                            Label("Track “\(thought.trimmed)” as a new belief", systemImage: "plus.circle")
                                .font(.flowHelper.weight(.semibold))
                        }
                    } footer: {
                        Text("The ledger keeps every time a belief shows up, how strongly you held it, and the evidence you found.")
                    }
                }
                Section(beliefs.isEmpty ? "" : "Beliefs you've tracked") {
                    ForEach(filtered) { belief in
                        Button {
                            link(belief)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(belief.canonicalText)
                                        .font(.flowBody)
                                    Text("\(belief.occurrences) time\(belief.occurrences == 1 ? "" : "s")" + (belief.storyName.isEmpty ? "" : " · the “\(belief.storyName)” story"))
                                        .font(.flowCaption)
                                        .foregroundStyle(Ink.tertiary)
                                }
                                Spacer()
                                if linkedBeliefID == belief.idString {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if linkedBeliefID != nil {
                    Section {
                        Button("Unlink", role: .destructive) {
                            linkedBeliefID = nil
                            dismiss()
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search your beliefs")
            .navigationTitle("Had this thought before?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                suggestion = await TherapyAI.suggestLedgerMatch(thought: thought, beliefs: beliefs)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func link(_ belief: LedgerBelief) {
        linkedBeliefID = belief.idString
        try? modelContext.save()
        dismiss()
    }
}
