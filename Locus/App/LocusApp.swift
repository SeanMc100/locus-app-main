import SwiftUI
import SwiftData

@main
struct LocusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var draft = DraftStore()

    var body: some Scene {
        WindowGroup {
            JournalView()
                .modifier(SkillsRouting())
                #if DEBUG
                .onAppear {
                    // Test containers only, never the real stores.
                    let arguments = ProcessInfo.processInfo.arguments
                    if arguments.contains("-uiTesting"), arguments.contains("-seedSkillsDemo"),
                       (try? sharedModelContainer.mainContext.fetchCount(FetchDescriptor<LedgerBelief>())) == 0 {
                        SkillsDemoData.seed(in: sharedModelContainer.mainContext)
                    }
                }
                #endif
                .environment(draft)
                .preferredColorScheme(.light)
                .tint(.black)
        }
        .modelContainer(sharedModelContainer)
    }
}

/// Syncs `JournalEntry` through the user's private iCloud database (CloudKit),
/// so entries survive an uninstall/reinstall or show up on another device
/// signed into the same Apple ID.
///
/// The skills toolkit's models live in a second, local-only store
/// (`TherapyStore`): never synced, and file-protected at rest. The journal
/// configuration is unchanged, so it keeps using the same store file.
private let sharedModelContainer: ModelContainer = {
    #if DEBUG
    // UI tests (LocusUITests): in-memory only, so tests never touch real
    // entries or iCloud.
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("-uiTesting") {
        let schema = Schema([JournalEntry.self] + TherapyStore.modelTypes)
        // `-uiTestingStore <name>` keeps data across relaunches (resume tests).
        if let i = arguments.firstIndex(of: "-uiTestingStore"), i + 1 < arguments.count {
            let url = URL.temporaryDirectory.appending(path: "\(arguments[i + 1]).store")
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        }
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    #endif
    let journalSchema = Schema([JournalEntry.self])
    let configuration = ModelConfiguration(
        schema: journalSchema,
        cloudKitDatabase: .private("iCloud.com.seanmcdonnell.Locus")
    )
    let schema = Schema([JournalEntry.self] + TherapyStore.modelTypes)
    do {
        let container = try ModelContainer(for: schema, configurations: [configuration, TherapyStore.configuration()])
        TherapyStore.protectFiles()
        return container
    } catch {
        fatalError("Failed to create ModelContainer: \(error)")
    }
}()
