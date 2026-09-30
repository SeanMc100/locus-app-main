import SwiftUI

// The skills screens use the same sizes as the rest of Locus (28/22/17/15/
// 13/12 pt), but as text styles, so they scale with Dynamic Type. At the
// default size they render identically to the existing `.system(size:)`.
extension Font {
    /// 28 bold: screen titles.
    static let flowTitle = Font.system(.title, weight: .bold)
    /// 22 bold: the one question on a step.
    static let flowQuestion = Font.system(.title2, weight: .bold)
    /// 20 bold: section titles.
    static let flowSection = Font.system(.title3, weight: .bold)
    /// 17: body and inputs.
    static let flowBody = Font.system(.body)
    /// 16 semibold: buttons.
    static let flowButton = Font.system(.callout, weight: .semibold)
    /// 15: helper text under a question.
    static let flowHelper = Font.system(.subheadline)
    /// 13: small print.
    static let flowCaption = Font.system(.footnote)
    /// 12 semibold, uppercased by the caller: small labels.
    static let flowLabel = Font.system(.caption, weight: .semibold)
}

/// Monochrome, like the rest of the app. Secondary text is a little darker
/// than the existing 0.45–0.5 so helper copy passes WCAG AA contrast.
enum Ink {
    static let primary = Color.black
    static let secondary = Color.black.opacity(0.62)
    static let tertiary = Color.black.opacity(0.5)
    static let hairline = Color.black.opacity(0.1)
    static let fill = Color.black.opacity(0.04)
    static let fillStrong = Color.black.opacity(0.07)
}

extension TherapyMethod {
    /// A muted accent per method, for orientation only (progress, dots).
    var accent: Color {
        switch self {
        case .cbt: Color(red: 0.30, green: 0.40, blue: 0.56)
        case .dbt: Color(red: 0.29, green: 0.47, blue: 0.40)
        case .act: Color(red: 0.62, green: 0.43, blue: 0.26)
        }
    }
}

extension AnyTransition {
    /// Steps fade and drift a few points; calm, never a hard slide.
    static func gentleStep(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10)),
            removal: .opacity)
    }
}

extension Animation {
    static let gentle = Animation.easeInOut(duration: 0.3)
}

/// Small uppercase label used above cards ("WHAT YOU WROTE").
struct CapsLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.flowLabel)
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(Ink.tertiary)
    }
}

/// Rounded outlined container, the app's card style.
struct CardBackground: ViewModifier {
    var filled = false
    var selected = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.black.opacity(0.06) : filled ? Ink.fill : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.black : Ink.hairline, lineWidth: selected ? 1.5 : 1)
            )
    }
}

extension View {
    func card(filled: Bool = false, selected: Bool = false) -> some View {
        modifier(CardBackground(filled: filled, selected: selected))
    }
}
