import SwiftUI
import SwiftData

struct JournalView: View {
    @Environment(DraftStore.self) private var draft
    @Environment(\.modelContext) private var modelContext
    @FocusState private var editorFocused: Bool

    @State private var showHistory = false
    @State private var showFlow = false
    @State private var flowText = ""
    @State private var unavailableMessage: String?
    /// Skills post-entry flow: the entry just saved.
    @State private var savedEntry: JournalEntry?
    @State private var showToolkit = false

    var body: some View {
        @Bindable var draft = draft

        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                ZStack(alignment: .topLeading) {
                    if draft.text.isEmpty {
                        Text("What's on your mind?")
                            .font(.system(size: 18))
                            .foregroundStyle(.black.opacity(0.3))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $draft.text)
                        .font(.system(size: 18))
                        .lineSpacing(6)
                        .foregroundStyle(.black)
                        .scrollContentBackground(.hidden)
                        .scrollDismissesKeyboard(.interactively)
                        .focused($editorFocused)
                        .autocorrectionDisabled(false)
                        .textInputAutocapitalization(.sentences)
                }
                .padding(.horizontal, 17)
                .fullScreenCover(item: $savedEntry) { entry in
                    PostEntryView(entry: entry) { savedEntry = nil }
                }
            }
            .background(Color.white)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .toolbar { toolbarContent }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showHistory) { HistoryView() }
            .fullScreenCover(isPresented: $showFlow) {
                // Pass the snapshot, not draft.text: the draft is cleared
                // mid-flow once the entry is saved.
                SessionFlowView(text: flowText,
                                onSaved: { draft.clear() },
                                onFinish: { showFlow = false })
            }
            .alert("Apple Intelligence required", isPresented: .init(
                get: { unavailableMessage != nil },
                set: { if !$0 { unavailableMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(unavailableMessage ?? "")
            }
            .onAppear { editorFocused = true }
            // A quick action or notification is about to open something:
            // close whatever this screen has up first.
            .onChange(of: AppRouter.shared.dismissToken) {
                showHistory = false
                showToolkit = false
                savedEntry = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text((draft.startedAt ?? .now).formatted(.dateTime.weekday(.wide)))
                .font(.system(size: 13, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(.black.opacity(0.45))
            Text((draft.startedAt ?? .now).formatted(.dateTime.month(.wide).day()))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.black)
        }
        .sheet(isPresented: $showToolkit) { ToolkitHomeView() }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("\(draft.wordCount) \(draft.wordCount == 1 ? "word" : "words")")
                statusLabel
            }
            .font(.system(size: 13))
            .foregroundStyle(.black.opacity(0.45))
            .monospacedDigit()

            Spacer()

            Button {
                breakItDown()
            } label: {
                HStack(spacing: 6) {
                    if FeatureFlags.useLegacyPostEntryFlow && SessionFlowView.flow == .sort {
                        Image(systemName: "sparkles")
                    }
                    Text(!FeatureFlags.useLegacyPostEntryFlow ? "Save"
                         : SessionFlowView.flow == .sort ? "Break it down" : "Continue")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Capsule().fill(.black))
            }
            .disabled(draft.isEmpty)
            .opacity(draft.isEmpty ? 0.25 : 1)
            .animation(.easeOut(duration: 0.15), value: draft.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Color.white
                .overlay(alignment: .top) { Divider().opacity(0.6) }
                .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch draft.status {
        case .idle: EmptyView()
        case .saving: Text("· Saving…")
        case .saved:
            HStack(spacing: 3) {
                Text("·")
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                Text("Saved")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                editorFocused = false
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .accessibilityLabel("History")
        }
        ToolbarItem(placement: .principal) {
            Text("Locus")
                .font(.system(size: 17, weight: .semibold))
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if FeatureFlags.showsSkillsToolkit {
                Button {
                    showToolkit = true
                } label: {
                    ToolkitIcon()
                }
                .accessibilityLabel("Toolkit")
            }
            if editorFocused {
                Button {
                    editorFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Hide keyboard")
            }
        }
    }

    private func breakItDown() {
        if !FeatureFlags.useLegacyPostEntryFlow {
            saveEntry()
            return
        }
        if SessionFlowView.flow == .sort, let reason = ItemExtractor.unavailableReason {
            unavailableMessage = reason
            return
        }
        editorFocused = false
        flowText = draft.text
        showFlow = true
    }

    /// Skills post-entry flow: saving is one tap; "Work through this" is
    /// offered on the next screen.
    private func saveEntry() {
        editorFocused = false
        let entry = JournalEntry(text: draft.text, linkID: UUID().uuidString, postEntryFlow: "saved")
        modelContext.insert(entry)
        try? modelContext.save()
        draft.clear()
        savedEntry = entry
    }
}
