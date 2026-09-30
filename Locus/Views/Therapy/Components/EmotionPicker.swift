import SwiftUI

/// Two-level emotion picker: a family, then the specific word, each chosen
/// emotion with its own intensity. Naming it precisely (emotional
/// granularity) is linked to better regulation, hence more than mood faces.
struct EmotionPicker: View {
    @Binding var ratings: [EmotionRating]
    var phase: EmotionPhase = .before
    var allowsMultiple = true
    /// Diary card: rate 0–5 (stored as 0–100).
    var fivePoint = false
    var showsHint = true
    var accent: Color = .black

    @State private var openFamily: EmotionFamily?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsHint {
                Text("The more precisely you can name it, the easier it is to work with.")
                    .font(.flowHelper)
                    .foregroundStyle(Ink.secondary)
            }

            FlowLayout(spacing: 8) {
                ForEach(EmotionFamily.allCases) { family in
                    Chip(title: family.name,
                         selected: openFamily == family) {
                        withAnimation(.gentle) { openFamily = openFamily == family ? nil : family }
                    }
                    .overlay(alignment: .topTrailing) {
                        if ratings.contains(where: { $0.family == family }) && openFamily != family {
                            Circle().fill(accent).frame(width: 8, height: 8).offset(x: 1, y: -1)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }

            if let family = openFamily {
                VStack(alignment: .leading, spacing: 10) {
                    CapsLabel("\(family.name): which word fits?")
                    FlowLayout(spacing: 8) {
                        ForEach(family.words, id: \.self) { word in
                            Chip(title: word, selected: isSelected(family, word)) {
                                toggle(family, word)
                            }
                        }
                    }
                }
                .padding(14)
                .card(filled: true)
                .transition(.opacity)
            }

            if !ratings.isEmpty {
                VStack(spacing: 10) {
                    ForEach($ratings) { $rating in
                        EmotionIntensityRow(rating: $rating, fivePoint: fivePoint, accent: accent) {
                            withAnimation(.gentle) { ratings.removeAll { $0.id == rating.id } }
                        }
                    }
                }
            }
        }
    }

    private func isSelected(_ family: EmotionFamily, _ word: String) -> Bool {
        ratings.contains { $0.family == family && $0.word == word }
    }

    private func toggle(_ family: EmotionFamily, _ word: String) {
        withAnimation(.gentle) {
            if let i = ratings.firstIndex(where: { $0.family == family && $0.word == word }) {
                ratings.remove(at: i)
            } else {
                let rating = EmotionRating(family: family, word: word, intensity: fivePoint ? 60 : 50, phase: phase)
                if allowsMultiple { ratings.append(rating) } else { ratings = [rating] }
                openFamily = nil
            }
        }
    }
}

/// One chosen emotion with its intensity.
struct EmotionIntensityRow: View {
    @Binding var rating: EmotionRating
    var fivePoint = false
    var accent: Color = .black
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rating.word.capitalizedFirst)
                    .font(.system(.body, weight: .semibold))
                Spacer()
                Text(fivePoint ? "\(Int(rating.intensity / 20))/5" : "\(Int(rating.intensity))%")
                    .font(.system(.body, weight: .semibold))
                    .monospacedDigit()
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Ink.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(rating.word)")
            }
            if fivePoint {
                OptionRow(options: Array(0...5), selection: Binding(
                    get: { Int(rating.intensity / 20) },
                    set: { rating.intensity = Double(($0 ?? 0) * 20) }
                )) { "\($0)" }
                .accessibilityLabel("\(rating.word) intensity")
            } else {
                Slider(value: $rating.intensity, in: 0...100, step: 5)
                    .tint(accent)
                    .accessibilityLabel("How strong is \(rating.word)")
                    .accessibilityValue("\(Int(rating.intensity)) percent")
            }
        }
        .padding(14)
        .card()
    }
}

/// After-ratings for emotions rated earlier: each before-rating gets a
/// matching after-rating so the change can be shown.
struct EmotionRerateList: View {
    let before: [EmotionRating]
    @Binding var after: [EmotionRating]
    var accent: Color = .black

    var body: some View {
        VStack(spacing: 12) {
            ForEach(before) { emotion in
                let binding = Binding<Double?>(
                    get: { after.first { $0.family == emotion.family && $0.word == emotion.word }?.intensity },
                    set: { newValue in
                        after.removeAll { $0.family == emotion.family && $0.word == emotion.word }
                        if let newValue {
                            after.append(EmotionRating(family: emotion.family, word: emotion.word, intensity: newValue, phase: .after))
                        }
                    })
                VStack(alignment: .leading, spacing: 6) {
                    Text("Before: \(Int(emotion.intensity))%")
                        .font(.flowCaption)
                        .foregroundStyle(Ink.tertiary)
                    PercentSlider(label: emotion.word.capitalizedFirst, value: binding,
                                  lowLabel: "None", highLabel: "Strongest", accent: accent, compact: true)
                }
                .padding(14)
                .card()
            }
        }
    }

    static func isComplete(before: [EmotionRating], after: [EmotionRating]) -> Bool {
        before.allSatisfy { b in after.contains { $0.family == b.family && $0.word == b.word } }
    }
}
