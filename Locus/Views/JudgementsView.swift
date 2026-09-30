import SwiftUI


/// The stripped version first ("this is what actually happened"), with a
/// toggle back to the entry as written, judgements highlighted. Below it,
/// the user re-rates how strongly they feel it: that's the reflection.
/// Finding only; the user does any replacing on the next step. Quotes
/// that don't appear verbatim in the entry can't be highlighted, so
/// they're counted in a note, to gauge how reliable the matching is.
struct JudgementsView: View {
    let entryText: String
    let judgements: [String]
    let withoutJudgements: String
    /// The before rating, shown next to the scale for reference.
    let ratingBefore: Int?
    /// Pre-selects the after rating when coming back to this step.
    var initialRatingAfter: Int? = nil
    let onCancel: () -> Void
    /// Passes the after rating (nil when there were no judgements, so
    /// nothing to re-rate against).
    let onContinue: (_ ratingAfter: Int?) -> Void

    @State private var showOriginal = false
    @State private var ratingAfter: Int?

    private var located: (ranges: [Range<String.Index>], unmatched: [String]) {
        JudgementHighlighter.locate(judgements, in: entryText)
    }

    var body: some View {
        let unmatched = located.unmatched

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(judgements.isEmpty ? "No judgements found"
                         : showOriginal ? "Where you added meaning" : "What actually happened")
                        .font(.system(size: 28, weight: .bold))
                    Text(judgements.isEmpty ? "Everything here reads as what happened and how it felt."
                         : showOriginal ? "Highlighted: the parts that go beyond what actually happened."
                         : "Your entry, with the judgements you added taken out.")
                        .font(.system(size: 15))
                        .foregroundStyle(.black.opacity(0.5))
                }

                if !judgements.isEmpty {
                    Picker("Version", selection: $showOriginal) {
                        Text("What happened").tag(false)
                        Text("What you wrote").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                if !judgements.isEmpty && !showOriginal {
                    Text(withoutJudgements.isEmpty ? "Nothing's left once the judgements are removed." : withoutJudgements)
                        .font(.system(size: 17))
                        .lineSpacing(6)
                        .foregroundStyle(.black.opacity(withoutJudgements.isEmpty ? 0.4 : 1))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else {
                    Text(JudgementHighlighter.attributed(entryText, highlighting: judgements))
                        .font(.system(size: 17))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if showOriginal && !unmatched.isEmpty {
                    Label("\(unmatched.count) of \(judgements.count) couldn't be matched to your exact words, so they aren't highlighted.",
                          systemImage: "questionmark.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.black.opacity(0.45))
                }

                if !judgements.isEmpty {
                    reRating
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Continue", disabled: !judgements.isEmpty && ratingAfter == nil) {
                onContinue(judgements.isEmpty ? nil : ratingAfter)
            }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.white.ignoresSafeArea())
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", action: onCancel)
            }
        }
        .onAppear { ratingAfter = initialRatingAfter }
    }

    /// Worded so a same-or-higher number is just as valid: some things
    /// hurt as much once the judgements are gone, and that's proportionate.
    private var reRating: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Reading just what happened, how strongly do you feel it now?")
                    .font(.system(size: 19, weight: .bold))
                Text(ratingBefore.map { "You said \($0) before. There's no right answer." }
                     ?? "There's no right answer.")
                    .font(.system(size: 14))
                    .foregroundStyle(.black.opacity(0.5))
            }
            IntensityScale(value: $ratingAfter)
        }
    }
}
