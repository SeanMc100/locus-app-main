import SwiftUI
import SwiftData

/// A finished (or waiting) session, read-only, with a link back to the
/// journal entry it came from.
struct SessionDetailView: View {
    let session: TherapySession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var resume: FlowLaunch?
    @State private var confirmDelete = false
    @State private var threatHappened: PredictionOutcome?

    private var summary: SessionSummary { SessionSummary(session: session) }
    private var entry: JournalEntry? { modelContext.journalEntry(linkID: session.sourceEntryID) }

    var body: some View {
        let summary = summary
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(session.method.accent).frame(width: 8, height: 8)
                        Text("\(session.method.name) · \(session.tool.title)")
                            .font(.flowLabel)
                            .foregroundStyle(session.method.accent)
                    }
                    Text(session.targetThought.isEmpty ? session.tool.title : "“\(session.targetThought)”")
                        .font(.flowTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    Text((session.completedAt ?? session.createdAt).formatted(date: .complete, time: .shortened))
                        .font(.flowCaption)
                        .foregroundStyle(Ink.tertiary)
                    if session.status != .complete {
                        Text(session.status == .pending ? "Waiting to check in" : "Not finished")
                            .font(.flowCaption.weight(.semibold))
                            .foregroundStyle(session.method.accent)
                    }
                }

                if !summary.changes.isEmpty {
                    ChangeBars(rows: summary.changes.map {
                        ChangeRow(label: $0.label, before: $0.before, after: $0.after, scale: $0.scale == 10 ? .outOf10 : .percent)
                    }, accent: session.method.accent)
                }

                if let chain = summary.chain {
                    ChainDiagram(data: chain, accent: session.method.accent)
                }

                ForEach(summary.blocks, id: \.self) { block in
                    OwnWordsBlock(title: block.title, text: block.text)
                }

                if session.tool == .checkTheFacts, session.status == .complete,
                   let data = session.decode(CheckFactsData.self), !data.threat.trimmed.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Did the feared thing happen?")
                            .font(.system(.body, weight: .semibold))
                        Text("Your answer counts toward prediction calibration in Insights.")
                            .font(.flowCaption)
                            .foregroundStyle(Ink.tertiary)
                        OptionRow(options: PredictionOutcome.allCases, selection: $threatHappened) { $0.label }
                    }
                    .padding(16)
                    .card()
                    .onAppear { threatHappened = data.threatHappened }
                    .onChange(of: threatHappened) { _, value in
                        var d = data
                        d.threatHappened = value
                        session.store(d)
                        try? modelContext.save()
                    }
                }

                if let entry {
                    NavigationLink {
                        EntryDetailView(entry: entry)
                    } label: {
                        HStack {
                            Image(systemName: "book.closed")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("From your journal entry")
                                    .font(.system(.body, weight: .semibold))
                                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.flowCaption)
                                    .foregroundStyle(Ink.tertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Ink.primary)
                        .padding(16)
                        .card()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white)
        .safeAreaInset(edge: .bottom) {
            if session.status != .complete {
                PrimaryButton(title: session.status == .pending ? "Check in" : "Continue") {
                    resume = FlowLaunch(start: .resume(session))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white.ignoresSafeArea())
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                SessionService.discard(session, in: modelContext)
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
        .fullScreenCover(item: $resume) { launch in
            TherapyFlowHost(start: launch.start) { resume = nil }
        }
    }
}

/// On a journal entry: the skills sessions it led to.
struct WorkedThroughSection: View {
    let entry: JournalEntry
    @Query private var sessions: [TherapySession]

    init(entry: JournalEntry) {
        self.entry = entry
        // An entry that was never linked matches nothing.
        let id = entry.linkID.isEmpty ? "-" : entry.linkID
        _sessions = Query(filter: #Predicate<TherapySession> { $0.sourceEntryID == id },
                          sort: \TherapySession.createdAt)
    }

    var body: some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Worked through with")
                    .font(.system(size: 19, weight: .bold))
                ForEach(sessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: session.tool.symbol)
                                .foregroundStyle(session.method.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.tool.title)
                                    .font(.system(.body, weight: .semibold))
                                if session.status != .complete {
                                    Text(session.status == .pending ? "Waiting to check in" : "In progress")
                                        .font(.flowCaption)
                                        .foregroundStyle(Ink.tertiary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Ink.tertiary)
                        }
                        .foregroundStyle(Ink.primary)
                        .padding(14)
                        .card()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
