import SwiftUI
import SwiftData
import NaturalLanguage

/// After "Save": the entry's confirmation, plus an optional, non-pushy
/// "Work through this". Leaving is one tap (Done); free writing counts on
/// its own. Any sentence can be picked as the thought to examine (press and
/// hold), and with AI on, up to three likely automatic thoughts are offered.
struct PostEntryView: View {
    let entry: JournalEntry
    let onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var launch: TherapyLaunch?
    @State private var candidates: [String] = []

    var body: some View {
        if let launch {
            TherapyFlowHost(start: .fresh(launch), onClose: onFinish)
                .transition(.opacity)
        } else {
            NavigationStack {
                content
            }
            .task { await findCandidates() }
        }
    }

    private var sentences: [String] {
        SentenceSplitter.sentences(in: entry.text)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Saved to history", systemImage: "checkmark.circle.fill")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Ink.tertiary)
                    Text(entry.createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.flowTitle)
                }

                Button {
                    workThrough(thought: "")
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 20))
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Work through this")
                                .font(.flowSection)
                            Text("A short exercise to examine a thought, calm a feeling, or take a step. Optional.")
                                .font(.flowHelper)
                                .foregroundStyle(Ink.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Ink.tertiary)
                            .padding(.top, 4)
                    }
                    .foregroundStyle(Ink.primary)
                    .padding(18)
                    .contentShape(Rectangle())
                    .card()
                }
                .buttonStyle(.plain)

                if !candidates.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(candidates, id: \.self) { thought in
                            Button {
                                workThrough(thought: thought)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "text.quote")
                                        .foregroundStyle(Ink.tertiary)
                                        .accessibilityHidden(true)
                                    Text("You wrote “\(thought)”. Want to examine it?")
                                        .font(.flowHelper.weight(.medium))
                                        .foregroundStyle(Ink.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(14)
                                .card(filled: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .transition(.opacity)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        CapsLabel("What you wrote")
                        Spacer()
                    }
                    Text("Press and hold a sentence to examine it.")
                        .font(.flowCaption)
                        .foregroundStyle(Ink.tertiary)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(sentences.enumerated()), id: \.offset) { _, sentence in
                            Text(sentence)
                                .font(.flowBody)
                                .lineSpacing(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .padding(.horizontal, -8)
                                .contextMenu {
                                    Button {
                                        workThrough(thought: sentence)
                                    } label: {
                                        Label("Examine this thought", systemImage: "magnifyingglass")
                                    }
                                }
                                .accessibilityAction(named: "Examine this thought") {
                                    workThrough(thought: sentence)
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .animation(.gentle, value: candidates)
        }
        .background(Color.white)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Done", action: onFinish)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.white.ignoresSafeArea())
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func workThrough(thought: String) {
        let linkID = entry.ensureLinkID()
        try? modelContext.save()
        withAnimation(.gentle) {
            launch = TherapyLaunch(sourceEntryID: linkID, entryText: entry.text, targetThought: thought)
        }
    }

    private func findCandidates() async {
        guard TherapyAI.isEnabled else { return }
        let found = await TherapyAI.automaticThoughts(in: entry.text)
        withAnimation(.gentle) { candidates = found }
    }
}

enum SentenceSplitter {
    static func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var out: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { out.append(s) }
            return true
        }
        return out.isEmpty && !text.trimmed.isEmpty ? [text.trimmed] : out
    }
}
