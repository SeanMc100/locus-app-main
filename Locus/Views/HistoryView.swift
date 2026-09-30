import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalEntry.createdAt, order: .reverse) private var entries: [JournalEntry]

    private var sections: [(title: String, entries: [JournalEntry])] {
        var result: [(String, [JournalEntry])] = []
        for entry in entries {
            let title = entry.createdAt.formatted(.dateTime.month(.wide).year())
            if result.last?.0 == title {
                result[result.count - 1].1.append(entry)
            } else {
                result.append((title, [entry]))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No entries yet",
                        systemImage: "clock",
                        description: Text("Entries show up here once you've finished them.")
                    )
                } else {
                    List {
                        ForEach(sections, id: \.title) { section in
                            Section {
                                ForEach(section.entries) { entry in
                                    NavigationLink(value: entry) {
                                        HistoryRow(entry: entry)
                                    }
                                }
                                .onDelete { offsets in
                                    for i in offsets { modelContext.delete(section.entries[i]) }
                                    try? modelContext.save()
                                }
                            } header: {
                                Text(section.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .textCase(.uppercase)
                                    .foregroundStyle(.black.opacity(0.45))
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.white)
            .navigationTitle("History")
            .navigationDestination(for: JournalEntry.self) { EntryDetailView(entry: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.createdAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                .font(.system(size: 15, weight: .semibold))
            Text(entry.text)
                .font(.system(size: 15))
                .foregroundStyle(.black.opacity(0.55))
                .lineLimit(2)
            if entry.isSortFlow {
                HStack(spacing: 14) {
                    Label("\(entry.inControl.count) in control", systemImage: "circle.fill")
                    Label("\(entry.notInControl.count) not", systemImage: "circle")
                }
                .font(.system(size: 12, weight: .medium))
                .labelStyle(CompactLabelStyle())
                .foregroundStyle(.black.opacity(0.6))
                .padding(.top, 2)
            } else if let ownWords = [entry.questionAnswer, entry.truerJudgement, entry.friendReply].first(where: { !$0.isEmpty }) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10))
                    Text(ownWords)
                        .lineLimit(1)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.black.opacity(0.6))
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}

struct EntryDetailView: View {
    let entry: JournalEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var confirmDelete = false
    @State private var pendingDelete = false
    @State private var workThrough: FlowLaunch?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.createdAt.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 13, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(.black.opacity(0.45))
                    Text(entry.createdAt.formatted(.dateTime.month(.wide).day().year()))
                        .font(.system(size: 28, weight: .bold))
                    Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 14))
                        .foregroundStyle(.black.opacity(0.45))
                }

                if entry.isSortFlow {
                    ItemGroupView(kind: .inControl, items: entry.inControl)
                    ItemGroupView(kind: .notInControl, items: entry.notInControl, counterparts: entry.counterparts)
                } else {
                    JudgementFlowResultView(entry: entry)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Journal entry")
                        .font(.system(size: 19, weight: .bold))
                    Text(JudgementHighlighter.attributed(entry.text, highlighting: entry.judgements))
                        .font(.system(size: 17))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                }

                if FeatureFlags.showsSkillsToolkit {
                    WorkedThroughSection(entry: entry)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if FeatureFlags.showsSkillsToolkit {
                        Button {
                            let linkID = entry.ensureLinkID()
                            try? modelContext.save()
                            workThrough = FlowLaunch(start: .fresh(TherapyLaunch(sourceEntryID: linkID, entryText: entry.text)))
                        } label: {
                            Label("Work through this", systemImage: "arrow.triangle.branch")
                        }
                    }
                    ShareLink(item: shareText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete entry", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                pendingDelete = true
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
        .fullScreenCover(item: $workThrough) { launch in
            TherapyFlowHost(start: launch.start) { workThrough = nil }
        }
        // Delete only after the pop finishes, so this view never re-renders
        // against a deleted model (SwiftData can trap on that).
        .onDisappear {
            guard pendingDelete else { return }
            modelContext.delete(entry)
            try? modelContext.save()
        }
    }

    private var shareText: String {
        var s = entry.createdAt.formatted(date: .complete, time: .shortened) + "\n\n"
        if !entry.isSortFlow {
            s += entry.text
            if !entry.question.isEmpty { s += "\n\n" + entry.question + "\n" + entry.questionAnswer }
            if !entry.friendReply.isEmpty { s += "\n\nWhat I'd tell a friend:\n" + entry.friendReply }
            if !entry.truerJudgement.isEmpty { s += "\n\nWhat's true:\n" + entry.truerJudgement }
            return s
        }
        s += "In my control:\n" + entry.inControl.map { "• \($0)" }.joined(separator: "\n")
        s += "\n\nNot in my control:\n" + entry.notInControl.enumerated().map { i, item in
            let counterpart = i < entry.counterparts.count ? entry.counterparts[i] : ""
            return counterpart.isEmpty ? "• \(item)" : "• \(item)\n  → \(counterpart)"
        }.joined(separator: "\n")
        s += "\n\n" + entry.text
        return s
    }
}
