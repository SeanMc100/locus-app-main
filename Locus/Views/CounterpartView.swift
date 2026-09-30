import SwiftUI

/// After sorting, walk through each "not in my control" item one at a time
/// and let the user name what's theirs to put attention on instead. The
/// phrase is entirely user-authored (never AI-generated) and skippable —
/// this is the user's own move, not something the app tells them.
struct CounterpartView: View {
    let items: [String]
    /// One phrase per item, same order as `items` (empty string = skipped).
    let onComplete: (_ counterparts: [String]) -> Void

    @State private var index = 0
    @State private var text = ""
    @State private var counterparts: [Int: String] = [:]
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.horizontal, 24)
                .padding(.top, 8)

            VStack(spacing: 10) {
                Text("Not in your control")
                    .font(.system(size: 13, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(.black.opacity(0.4))
                Text(items[index])
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28)
            .padding(.horizontal, 28)
            .id(index)

            VStack(alignment: .leading, spacing: 10) {
                Text("What's yours to focus on instead?")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.black.opacity(0.6))
                TextField("e.g. Whether I show up honestly", text: $text, axis: .vertical)
                    .font(.system(size: 17))
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.black.opacity(0.15))
                    )
                    .focused($focused)
            }
            .padding(.horizontal, 28)
            .padding(.top, 32)

            Spacer()

            VStack(spacing: 12) {
                PrimaryButton(
                    title: index + 1 < items.count ? "Next" : "Finish",
                    disabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: next
                )
                Button("Skip", action: skip)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.black.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Color.white)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .onAppear { focused = true }
    }

    private var progress: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.08))
                    Capsule().fill(.black)
                        .frame(width: geo.size.width * CGFloat(index) / CGFloat(max(items.count, 1)))
                }
            }
            .frame(height: 4)
            .animation(.easeOut(duration: 0.25), value: index)

            Text("\(min(index + 1, items.count)) of \(items.count)")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.black.opacity(0.45))
        }
    }

    private func next() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { counterparts[index] = trimmed }
        advance()
    }

    private func skip() {
        advance()
    }

    private func advance() {
        text = ""
        if index + 1 < items.count {
            index += 1
        } else {
            onComplete(items.indices.map { counterparts[$0] ?? "" })
        }
    }
}
