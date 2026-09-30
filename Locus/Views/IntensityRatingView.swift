import SwiftUI

/// A 0–10 row of tappable numbers. Used before and after reading the
/// stripped version; the pair is a non-judgemental reflection (no "you
/// overreacted"), and the difference is a metric we can track later.
struct IntensityScale: View {
    @Binding var value: Int?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0...10, id: \.self) { n in
                    let selected = value == n
                    Button {
                        value = n
                    } label: {
                        Text("\(n)")
                            .font(.system(size: 15, weight: selected ? .bold : .medium))
                            .monospacedDigit()
                            .foregroundStyle(selected ? .white : .black.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selected ? Color.black : Color.black.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(n) out of 10")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            HStack {
                Text("Barely")
                Spacer()
                Text("Overwhelming")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.black.opacity(0.4))
        }
        .sensoryFeedback(.selection, trigger: value)
    }
}

/// First step after writing: rate how strongly you feel it, before seeing
/// anything the app found. Judgement finding runs in the background while
/// this is on screen.
struct RateBeforeView: View {
    let onCancel: () -> Void
    let onContinue: (Int) -> Void

    @State private var rating: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("How strongly do you feel this right now?")
                    .font(.system(size: 28, weight: .bold))
                Text("Just a gut number. You'll get to rate it again in a moment.")
                    .font(.system(size: 15))
                    .foregroundStyle(.black.opacity(0.5))
            }
            IntensityScale(value: $rating)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Continue", disabled: rating == nil) {
                if let rating { onContinue(rating) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white.ignoresSafeArea())
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", action: onCancel)
            }
        }
    }
}
