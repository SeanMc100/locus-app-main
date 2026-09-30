import SwiftUI

/// Optional last step: replace, don't just remove. The user picks one of
/// two ways to put it in their own words: answer it as if a friend had
/// said it (the first-to-second-person shift), or write the truer
/// judgement to themselves. No AI; the user always authors this. The
/// entry stays visible above so they don't have to hold it in their head.
struct OwnWordsView: View {
    enum Mode: Hashable {
        case friend, truer

        var prompt: String {
            switch self {
            case .friend: "What would you say to a friend who told you this?"
            case .truer: "What's actually true here? Say it to yourself."
            }
        }

        var placeholder: String {
            switch self {
            case .friend: "Write it to them directly…"
            case .truer: "You…"
            }
        }

        var previewLabel: String {
            switch self {
            case .friend: "Your friend said"
            case .truer: "What you wrote"
            }
        }
    }

    let entryText: String
    /// Judgement quotes to highlight in the entry preview.
    var highlights: [String] = []
    let onBack: () -> Void
    /// Empty text means the user skipped.
    let onComplete: (_ mode: Mode, _ text: String) -> Void

    @State private var mode: Mode = .friend
    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Write", selection: $mode) {
                Text("To a friend").tag(Mode.friend)
                Text("To yourself").tag(Mode.truer)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            EntryPreviewCard(label: mode.previewLabel, entryText: entryText, highlights: highlights)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Text(mode.prompt)
                .font(.system(size: 22, weight: .bold))
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 8)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(mode.placeholder)
                        .font(.system(size: 18))
                        .foregroundStyle(.black.opacity(0.3))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 18))
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .focused($focused)
                    .textInputAutocapitalization(.sentences)
            }
            .padding(.horizontal, 17)
        }
        .background(Color.white)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Finish", disabled: trimmedText.isEmpty) {
                onComplete(mode, trimmedText)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.white.ignoresSafeArea())
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", action: onBack)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if focused {
                    Button {
                        focused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Hide keyboard")
                } else {
                    Button("Skip") { onComplete(mode, "") }
                }
            }
        }
    }
}

/// The entry, collapsed to a few lines, kept above a writing step so the
/// user doesn't have to hold it in their head. Expanded: the whole entry in
/// a capped, scrollable box so the editor keeps room on screen.
struct EntryPreviewCard: View {
    let label: String
    let entryText: String
    var highlights: [String] = []

    @State private var expanded = false

    private var attributed: AttributedString {
        JudgementHighlighter.attributed(entryText, highlighting: highlights)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(1)
                    Spacer()
                    Text(expanded ? "Show less" : "Show all")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundStyle(.black.opacity(0.45))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ScrollView {
                    Text(attributed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            } else {
                Text(attributed)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 15))
        .lineSpacing(3)
        .foregroundStyle(.black.opacity(0.7))
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.04))
        )
    }
}
