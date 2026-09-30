import Foundation
import SwiftData

/// Where the skills data lives: a separate SwiftData store in the same
/// container as the journal, but local-only (no CloudKit), in its own
/// folder with iOS Data Protection set to `completeUnlessOpen`. That's
/// hardware-backed at-rest encryption: the files can't be opened while the
/// device is locked, except ones the app already had open (so a save that
/// finishes just after locking doesn't fail).
enum TherapyStore {
    static var modelTypes: [any PersistentModel.Type] {
        [TherapySession.self, LedgerBelief.self, ValueDomain.self, DiaryCard.self,
         QuickCapture.self, PracticeCard.self, IfThenPlan.self, SafetyPlan.self,
         TherapySettings.self]
    }

    private static let protection = FileProtectionType.completeUnlessOpen

    private static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Skills", directoryHint: .isDirectory)
    }

    static func configuration() -> ModelConfiguration {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                attributes: [.protectionKey: protection])
        // New files (the store, its -wal and -shm) inherit the folder's
        // protection class; set it explicitly too in case the folder existed.
        try? fm.setAttributes([.protectionKey: protection], ofItemAtPath: directory.path)
        return ModelConfiguration("Skills",
                                  schema: Schema(modelTypes),
                                  url: directory.appending(path: "skills.store"),
                                  cloudKitDatabase: .none)
    }

    /// Re-applies protection to every file in the store's folder. Called once
    /// the container is open, since SQLite creates its side files lazily.
    static func protectFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files {
            try? fm.setAttributes([.protectionKey: protection],
                                  ofItemAtPath: directory.appending(path: file).path)
        }
    }
}

extension ModelContext {
    /// The one instance of a model that should only exist once (safety
    /// plan, settings), created on first use.
    func singleton<T: PersistentModel>(_ make: () -> T) -> T {
        if let existing = try? fetch(FetchDescriptor<T>()).first { return existing }
        let created = make()
        insert(created)
        return created
    }

    func session(id: String) -> TherapySession? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<TherapySession>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    func belief(id: String) -> LedgerBelief? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<LedgerBelief>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    func capture(id: String) -> QuickCapture? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<QuickCapture>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    func valueDomain(id: String) -> ValueDomain? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<ValueDomain>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    func journalEntry(linkID: String) -> JournalEntry? {
        guard !linkID.isEmpty else { return nil }
        var descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.linkID == linkID })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }
}
