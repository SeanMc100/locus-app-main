import SwiftUI

/// The question flow's one step after writing: a single question chosen
/// for this entry, answered in writing. Nothing else on screen competes
/// with it. The keyboard isn't raised automatically, so the question gets
/// a moment to land before the user starts typing.
struct QuestionView: View {
    let entryText: String
    let asked: QuestionAsker.Asked
    let onCancel: () -> Void
    let onFinish: (_ answer: String) -> Void

    @State private var answer = ""
    @FocusState private var focused: Bool

    private var trimmedAnswer: String {
        answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EntryPreviewCard(label: "What you wrote", entryText: entryText)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            Text(asked.question)
                .font(.system(size: 24, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 22)
                .padding(.top, 28)

            if asked.moveID == "reachOut" {
                Text("If you might act on thoughts of hurting yourself, please contact a local crisis line now (for example 988 in the US and Canada, or Samaritans on 116 123 in the UK and Ireland).")
                    .font(.system(size: 14))
                    .foregroundStyle(.black.opacity(0.6))
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
            }

            if QuestionAsker.showsDiagnostics {
                QuestionDiagnosticsView(moveID: asked.moveID, notes: asked.notes)
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
            }

            ZStack(alignment: .topLeading) {
                if answer.isEmpty {
                    Text("Take your time…")
                        .font(.system(size: 18))
                        .foregroundStyle(.black.opacity(0.3))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $answer)
                    .font(.system(size: 18))
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .focused($focused)
                    .textInputAutocapitalization(.sentences)
            }
            .padding(.horizontal, 17)
            .padding(.top, 12)
        }
        .background(Color.white)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Finish", disabled: trimmedAnswer.isEmpty) {
                onFinish(trimmedAnswer)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.white.ignoresSafeArea())
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if focused {
                    Button {
                        focused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Hide keyboard")
                }
            }
        }
    }
}

/// Testing only (`QuestionAsker.showsDiagnostics`): which move was used
/// and why, with "no fit" called out so gaps in the library are obvious.
struct QuestionDiagnosticsView: View {
    let moveID: String
    let notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if moveID == "none" {
                Label("No move fit this entry", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            Text(notes)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.black.opacity(0.4))
                .textSelection(.enabled)
        }
    }
}
