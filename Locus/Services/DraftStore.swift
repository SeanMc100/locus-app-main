import Foundation
import Observation

/// Holds the in-progress journal text and persists it on every change,
/// so nothing is lost if the app is closed or killed.
@MainActor
@Observable
final class DraftStore {
    enum SaveStatus { case idle, saving, saved }

    private static let textKey = "draft.text"
    private static let startedKey = "draft.startedAt"

    var text: String {
        didSet {
            guard text != oldValue else { return }
            persist()
        }
    }

    private(set) var startedAt: Date?
    private(set) var status: SaveStatus = .idle
    private var statusTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        text = defaults.string(forKey: Self.textKey) ?? ""
        startedAt = defaults.object(forKey: Self.startedKey) as? Date
        if !text.isEmpty { status = .saved }
    }

    var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func clear() {
        text = ""  // persist() also resets startedAt
        statusTask?.cancel()
        status = .idle
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(text, forKey: Self.textKey)
        if text.isEmpty {
            // Emptied draft = fresh start; don't carry an old date forward.
            startedAt = nil
            defaults.removeObject(forKey: Self.startedKey)
        } else if startedAt == nil {
            startedAt = .now
            defaults.set(startedAt, forKey: Self.startedKey)
        }

        status = .saving
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            self.status = self.text.isEmpty ? .idle : .saved
        }
    }
}
