import SwiftUI

/// Multi-line text input in the app's card style. Dictation comes with the
/// system keyboard's mic button.
struct FlowTextField: View {
    let placeholder: String
    @Binding var text: String
    var minLines = 3
    var accessibilityLabel: String? = nil

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(.flowBody)
            .lineLimit(minLines...14)
            .textInputAutocapitalization(.sentences)
            .padding(14)
            .card()
            .accessibilityLabel(accessibilityLabel ?? placeholder)
    }
}

/// One-line text input in the app's card style.
struct FlowLineField: View {
    let placeholder: String
    @Binding var text: String
    var accessibilityLabel: String? = nil

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.flowBody)
            .textInputAutocapitalization(.sentences)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .card()
            .accessibilityLabel(accessibilityLabel ?? placeholder)
    }
}

/// A large, tappable option card: title, optional detail, optional icon.
struct ChoiceCard: View {
    let title: String
    var detail: String? = nil
    var symbol: String? = nil
    var accent: Color = .black
    var selected = false
    var large = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: large ? 22 : 18, weight: .regular))
                        .foregroundStyle(accent)
                        .frame(width: 28)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(large ? .flowSection : .system(.body, weight: .semibold))
                        .foregroundStyle(Ink.primary)
                        .multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail)
                            .font(.flowHelper)
                            .foregroundStyle(Ink.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .accessibilityHidden(true)
                }
            }
            .padding(large ? 18 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .card(selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A capsule chip for multi-select lists.
struct Chip: View {
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.white : Ink.primary.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(selected ? Color.black : Ink.fillStrong))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wraps chips onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > maxWidth && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

/// 0–100% rating: "how much do you believe this", "how strong is it".
/// Starts unrated (shows "–") until the user moves it, so a before-rating
/// is always a real answer.
struct PercentSlider: View {
    let label: String
    @Binding var value: Double?
    var lowLabel = "Not at all"
    var highLabel = "Completely"
    var accent: Color = .black
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 10) {
            HStack(alignment: .firstTextBaseline) {
                if compact {
                    Text(label)
                        .font(.system(.body, weight: .semibold))
                    Spacer()
                }
                Text(value.map { "\(Int($0.rounded()))%" } ?? "–")
                    .font(compact ? .system(.body, weight: .semibold) : .system(.largeTitle, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(value == nil ? Ink.tertiary : Ink.primary)
                    .contentTransition(.numericText())
                if !compact && value == nil {
                    Text("Drag to rate")
                        .font(.flowCaption)
                        .foregroundStyle(Ink.tertiary)
                }
            }
            Slider(value: Binding(get: { value ?? 50 }, set: { value = $0.rounded() }), in: 0...100)
                .tint(accent)
                .opacity(value == nil ? 0.55 : 1)
                .accessibilityLabel(label)
                .accessibilityValue(value.map { "\(Int($0.rounded())) percent" } ?? "Not rated yet")
                .accessibilityAdjustableAction { direction in
                    let current = value ?? 50
                    switch direction {
                    case .increment: value = min(100, current + 10)
                    case .decrement: value = max(0, current - 10)
                    @unknown default: break
                    }
                }
            HStack {
                Text(lowLabel)
                Spacer()
                Text(highLabel)
            }
            .font(.flowLabel)
            .foregroundStyle(Ink.tertiary)
            .accessibilityHidden(true)
        }
        .sensoryFeedback(.selection, trigger: value.map { Int($0 / 10) })
    }
}

/// A 0–10 row of tappable numbers (the app's `IntensityScale` look), with
/// anchor words; the chosen number's anchor is spelled out underneath.
struct TenPointScale: View {
    let label: String
    @Binding var value: Int?
    /// e.g. [0: "Calm", 5: "Uncomfortable", 8: "Hard to think straight", 10: "Overwhelmed"]
    var anchors: [Int: String] = [0: "Barely", 10: "Overwhelming"]
    var range: ClosedRange<Int> = 0...10

    private var description: String? {
        guard let value else { return nil }
        let key = anchors.keys.filter { $0 <= value }.max()
        return key.flatMap { anchors[$0] }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(range), id: \.self) { n in
                    let selected = value == n
                    Button {
                        value = n
                    } label: {
                        Text("\(n)")
                            .font(.system(.subheadline, weight: selected ? .bold : .medium))
                            .monospacedDigit()
                            .foregroundStyle(selected ? .white : .black.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selected ? Color.black : Color.black.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(label): \(n) out of \(range.upperBound)" + (anchors[n].map { ", \($0)" } ?? ""))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            HStack {
                Text(anchors[range.lowerBound] ?? "")
                Spacer()
                Text(anchors[range.upperBound] ?? "")
            }
            .font(.flowLabel)
            .foregroundStyle(Ink.tertiary)
            .accessibilityHidden(true)
            if let description, value != range.lowerBound, value != range.upperBound {
                Text("\(value ?? 0): \(description)")
                    .font(.flowHelper.weight(.medium))
                    .foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .sensoryFeedback(.selection, trigger: value)
        .animation(.gentle, value: value)
    }
}

/// A small "Yes / No" (or any two-to-four option) segmented choice with
/// large targets.
struct OptionRow<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option?
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let selected = selection == option
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.system(.body, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? .white : Ink.primary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? Color.black : Ink.fillStrong)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Small bordered secondary button ("Add another thought").
struct SecondaryButton: View {
    let title: String
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(Ink.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().strokeBorder(Ink.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A gentle inline notice (fake-reframe check, fit notes…).
struct NoticeCard<Actions: View>: View {
    let text: String
    var symbol = "lightbulb"
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(Ink.secondary)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.flowHelper)
                    .foregroundStyle(Ink.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(filled: true)
    }
}

extension NoticeCard where Actions == EmptyView {
    init(text: String, symbol: String = "lightbulb") {
        self.text = text
        self.symbol = symbol
        self.actions = EmptyView()
    }
}

/// Date and time for a plan, with a few quick picks.
struct WhenPicker: View {
    @Binding var date: Date?
    var label = "When"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Chip(title: "In an hour", selected: false) { date = .now.addingTimeInterval(3600) }
                Chip(title: "This evening", selected: false) { date = Self.today(at: 19) }
                Chip(title: "Tomorrow", selected: false) { date = Self.tomorrow(at: 10) }
            }
            DatePicker(label,
                       selection: Binding(get: { date ?? .now.addingTimeInterval(3600) }, set: { date = $0 }),
                       in: Date.now.addingTimeInterval(-60)...,
                       displayedComponents: [.date, .hourAndMinute])
                .font(.flowBody)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .card()
        }
    }

    private static func today(at hour: Int) -> Date {
        let d = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return d < .now ? .now.addingTimeInterval(3600) : d
    }

    private static func tomorrow(at hour: Int) -> Date {
        let t = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: t) ?? t
    }
}
