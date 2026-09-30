import SwiftUI

/// One before/after pair on a completion screen.
struct ChangeRow: Identifiable, Hashable {
    enum Scale: Hashable { case percent, outOf10 }

    var id: String { label }
    let label: String
    let before: Double
    let after: Double?
    var scale: Scale = .percent

    var maxValue: Double { scale == .percent ? 100 : 10 }

    func format(_ v: Double) -> String {
        scale == .percent ? "\(Int(v.rounded()))%" : "\(Int(v.rounded()))"
    }
}

/// Before -> after as two plain bars. No better/worse colouring (the app's
/// rule for ratings): a number that holds steady is fine too.
struct ChangeBars: View {
    let rows: [ChangeRow]
    var accent: Color = .black

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label)
                            .font(.system(.body, weight: .semibold))
                        Spacer()
                        Text(row.format(row.before))
                            .foregroundStyle(Ink.tertiary)
                        if let after = row.after {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Ink.tertiary)
                            Text(row.format(after))
                                .fontWeight(.bold)
                        }
                    }
                    .font(.system(.body))
                    .monospacedDigit()
                    bar(row.before, of: row.maxValue, fill: Color.black.opacity(0.18), label: "Before")
                    if let after = row.after {
                        bar(after, of: row.maxValue, fill: accent, label: "After")
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.label)
                .accessibilityValue("Before \(row.format(row.before))" + (row.after.map { ", after \(row.format($0))" } ?? ""))
            }
        }
    }

    private func bar(_ value: Double, of maxValue: Double, fill: Color, label: String) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.fill)
                Capsule().fill(fill)
                    .frame(width: max(6, geo.size.width * CGFloat(min(value, maxValue) / maxValue)))
            }
        }
        .frame(height: 8)
    }
}

/// An optional next step on a completion screen.
struct NextStepButton: View {
    let title: String
    var detail: String? = nil
    var symbol = "arrow.right"
    let action: () -> Void

    var body: some View {
        ChoiceCard(title: title, detail: detail, symbol: symbol, action: action)
    }
}

/// The last screen of every flow: what changed, and one optional next step.
struct CompletionContent<Extra: View>: View {
    let title: String
    var subtitle: String? = nil
    let rows: [ChangeRow]
    var accent: Color = .black
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Ink.tertiary)
                Text(title)
                    .font(.flowTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.flowHelper)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !rows.isEmpty {
                ChangeBars(rows: rows, accent: accent)
            }
            extra
        }
    }
}

/// A titled block of the user's own words on a summary.
struct OwnWordsBlock: View {
    let title: String
    let text: String

    var body: some View {
        if !text.trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                CapsLabel(title)
                Text(text.trimmed)
                    .font(.flowBody)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
