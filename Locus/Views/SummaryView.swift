import SwiftUI

struct SummaryView: View {
    let entry: JournalEntry
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Saved to history", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.5))
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                    Text(entry.createdAt.formatted(date: .complete, time: .shortened))
                        .font(.system(size: 14))
                        .foregroundStyle(.black.opacity(0.45))
                }

                if entry.isSortFlow {
                    ItemGroupView(kind: .inControl, items: entry.inControl)
                    ItemGroupView(kind: .notInControl, items: entry.notInControl, counterparts: entry.counterparts)
                } else {
                    JudgementFlowResultView(entry: entry)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What you wrote")
                            .font(.system(size: 19, weight: .bold))
                        Text(JudgementHighlighter.attributed(entry.text, highlighting: entry.judgements))
                            .font(.system(size: 16))
                            .lineSpacing(5)
                            .foregroundStyle(.black.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Done", action: onDone)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.white.ignoresSafeArea())
        }
        .navigationBarBackButtonHidden()
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        if entry.isSortFlow { return "Here's where you stand" }
        if !entry.question.isEmpty { return "Yours to keep" }
        if !entry.friendReply.isEmpty { return "Now read it as if it's for you" }
        if !entry.truerJudgement.isEmpty { return "Yours to keep" }
        return "Here's what happened"
    }
}

/// Question-flow and judgement-flow results: the question and the user's
/// answer, or their own words (friend reply or truer judgement), the
/// before/after ratings, and the stripped version.
/// Shared by the summary and history detail; the entry as written is
/// shown separately by each.
struct JudgementFlowResultView: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !entry.question.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    OwnWordsGroupView(title: entry.question, text: entry.questionAnswer)
                    if QuestionAsker.showsDiagnostics {
                        QuestionDiagnosticsView(moveID: entry.questionMove, notes: entry.questionNotes)
                    }
                }
            }
            if !entry.friendReply.isEmpty {
                OwnWordsGroupView(title: "What you'd tell a friend", text: entry.friendReply)
            }
            if !entry.truerJudgement.isEmpty {
                OwnWordsGroupView(title: "What's true", text: entry.truerJudgement)
            }
            if let before = entry.intensityBefore {
                IntensityChangeView(before: before, after: entry.intensityAfter)
            }
            if !entry.withoutJudgements.isEmpty && !entry.judgements.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What happened")
                        .font(.system(size: 19, weight: .bold))
                    Text(entry.withoutJudgements)
                        .font(.system(size: 17))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

/// "How strongly you felt it": before -> after, stated plainly. No
/// better/worse colouring; a rating that holds steady is fine.
struct IntensityChangeView: View {
    let before: Int
    let after: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How strongly you felt it")
                .font(.system(size: 19, weight: .bold))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                rating(before, label: "as written")
                if let after {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.35))
                    rating(after, label: "what happened")
                }
            }
        }
    }

    private func rating(_ value: Int, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(value)")
                .font(.system(size: 28, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.black.opacity(0.5))
        }
    }
}

/// A titled list of sorted items, shared by the summary and history detail.
struct ItemGroupView: View {
    enum Kind {
        case inControl, notInControl

        var title: String { self == .inControl ? "In my control" : "Not in my control" }
        var subtitle: String { self == .inControl ? "Where your energy can go." : "Worth letting go of." }
        var symbol: String { self == .inControl ? "circle.fill" : "circle" }
    }

    let kind: Kind
    let items: [String]
    /// User-authored "mine instead" phrases for `.notInControl`, same
    /// order as `items`. Ignored for `.inControl`.
    var counterparts: [String]? = nil

    private func counterpart(at i: Int) -> String? {
        guard let counterparts, i < counterparts.count, !counterparts[i].isEmpty else { return nil }
        return counterparts[i]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(kind.title)
                        .font(.system(size: 19, weight: .bold))
                    Spacer()
                    Text("\(items.count)")
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.black.opacity(0.4))
                }
                Text(kind.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.black.opacity(0.45))
            }

            if items.isEmpty {
                Text("Nothing here.")
                    .font(.system(size: 16))
                    .foregroundStyle(.black.opacity(0.35))
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Image(systemName: kind.symbol)
                                    .font(.system(size: 8))
                                Text(item)
                                    .font(.system(size: 16))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if let counterpart = counterpart(at: i) {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.black.opacity(0.35))
                                    Text(counterpart)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.black.opacity(0.65))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(.vertical, 12)
                        if i < items.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.black.opacity(0.1))
                )
            }
        }
    }
}

/// A user-authored line (friend reply or truer judgement), shared by the
/// summary and history detail.
struct OwnWordsGroupView: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
            Text(text)
                .font(.system(size: 17))
                .lineSpacing(6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.black.opacity(0.1))
                )
        }
    }
}
