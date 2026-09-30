import SwiftUI

/// The frame every skills step sits in: progress ("Step 3 of 9"), one
/// scrollable question area, one primary button, Back, and Close with
/// "Save and finish later" / "Discard".
struct StepScaffold<Content: View>: View {
    let toolTitle: String
    let accent: Color
    /// Changes when the step changes; drives the transition and scroll reset.
    let stepID: String
    let position: Int
    let total: Int
    var showsProgress = true
    var primaryTitle = "Next"
    var canContinue = true
    var secondaryTitle: String? = nil
    var onSecondary: (() -> Void)? = nil
    let onPrimary: () -> Void
    var onBack: (() -> Void)? = nil
    /// Close without asking (completion screens, nothing entered yet).
    var closesWithoutAsking = false
    let onSaveForLater: () -> Void
    let onDiscard: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmClose = false

    var body: some View {
        VStack(spacing: 0) {
            if showsProgress {
                StepProgress(position: position, total: total, accent: accent)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        content
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                .id(stepID)
                .transition(.gentleStep(reduceMotion: reduceMotion))
            }
            .animation(.gentle, value: stepID)
        }
        .background(Color.white)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                PrimaryButton(title: primaryTitle, disabled: !canContinue, action: onPrimary)
                if let secondaryTitle, let onSecondary {
                    Button(secondaryTitle, action: onSecondary)
                        .font(.flowButton)
                        .foregroundStyle(Ink.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.white.ignoresSafeArea())
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let onBack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Back")
                        }
                    }
                    .accessibilityLabel("Back")
                }
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 7, height: 7)
                    Text(toolTitle)
                        .font(.system(.subheadline, weight: .semibold))
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                KeyboardHideButton()
                Button {
                    if closesWithoutAsking { onSaveForLater() } else { confirmClose = true }
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }
        }
        .confirmationDialog("Leave this for now?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Save and finish later", action: onSaveForLater)
            Button("Discard", role: .destructive, action: onDiscard)
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Saved work shows under In progress, so you can pick it up where you left off.")
        }
    }
}

struct StepProgress: View {
    let position: Int
    let total: Int
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Step \(min(position, total)) of \(total)")
                .font(.flowCaption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Ink.tertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.fillStrong)
                    Capsule().fill(accent)
                        .frame(width: geo.size.width * CGFloat(min(position, total)) / CGFloat(max(total, 1)))
                }
            }
            .frame(height: 4)
            .animation(.gentle, value: position)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(min(position, total)) of \(total)")
    }
}

@MainActor
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// The one question on a step, with a line on why the step matters.
struct StepHeader: View {
    let question: String
    var helper: String? = nil
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question)
                .font(large ? .flowTitle : .flowQuestion)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let helper {
                Text(helper)
                    .font(.flowHelper)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Same as the journal's: shown while the keyboard is up, to put it away
/// and reach what's under it.
struct KeyboardHideButton: View {
    @State private var keyboardUp = false

    var body: some View {
        Group {
            if keyboardUp {
                Button(action: hideKeyboard) {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Hide keyboard")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
    }
}
