import SwiftUI
import SwiftData

/// Presents deep links (home-screen quick actions, tapped reminders) over
/// the journal, keeps the quick actions registered, and saves skills data
/// when the app goes to the background.
struct SkillsRouting: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var flow: FlowLaunch?
    @State private var showCapture = false
    @State private var showDiary = false
    @State private var showPractice = false
    @State private var showToolkit = false

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .fullScreenCover(item: $flow) { launch in
                        TherapyFlowHost(start: launch.start) { flow = nil }
                    }
                Color.clear
                    .sheet(isPresented: $showCapture) {
                        QuickCaptureView(onCalmDown: calmDownSoon)
                    }
                Color.clear
                    .sheet(isPresented: $showDiary) { DiaryCardView() }
                Color.clear
                    .sheet(isPresented: $showPractice) { PracticeSheet() }
                Color.clear
                    .sheet(isPresented: $showToolkit) { ToolkitHomeView() }
            }
            .onAppear {
                registerQuickActions()
                if let pending = AppRouter.shared.pending { present(pending) }
            }
            .onChange(of: AppRouter.shared.pending) { _, destination in
                guard let destination else { return }
                // Give sheets that were just asked to close time to go.
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    present(destination)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .background, FeatureFlags.showsSkillsToolkit else { return }
                try? modelContext.save()
                refreshInboxReminder(modelContext)
            }
    }

    private func present(_ destination: AppDestination) {
        AppRouter.shared.pending = nil
        flow = nil
        showCapture = false
        showDiary = false
        showPractice = false
        showToolkit = false
        switch destination {
        case .quickCapture: showCapture = true
        case .calmDown: flow = FlowLaunch(start: .tool(.crisisSkills, TherapyLaunch()))
        case .session(let id):
            if let session = modelContext.session(id: id) {
                flow = FlowLaunch(start: .resume(session))
            } else {
                showToolkit = true
            }
        case .toolkit: showToolkit = true
        case .diary: showDiary = true
        case .practice: showPractice = true
        case .values: flow = FlowLaunch(start: .tool(.valuesCheckIn, TherapyLaunch()))
        }
    }

    private func calmDownSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            flow = FlowLaunch(start: .tool(.crisisSkills, TherapyLaunch()))
        }
    }

    private func registerQuickActions() {
        guard FeatureFlags.showsSkillsToolkit else {
            UIApplication.shared.shortcutItems = []
            return
        }
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(type: AppRouter.quickCaptureType, localizedTitle: "Quick capture",
                                      localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "bolt"),
                                      userInfo: nil),
            UIApplicationShortcutItem(type: AppRouter.calmDownType, localizedTitle: "I need to calm down",
                                      localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "wind"),
                                      userInfo: nil),
        ]
    }
}

/// The journal's toolkit button, with a dot when something's waiting
/// (inbox captures, or a planned step that's due).
struct ToolkitIcon: View {
    @Query(filter: #Predicate<QuickCapture> { $0.statusRaw == "inbox" }) private var inbox: [QuickCapture]
    @Query(filter: #Predicate<TherapySession> { $0.statusRaw == "pending" }) private var pending: [TherapySession]

    private var waiting: Int {
        inbox.count + pending.filter { ($0.scheduledAt ?? .distantFuture) <= .now }.count
    }

    var body: some View {
        Image(systemName: "square.grid.2x2")
            .overlay(alignment: .topTrailing) {
                if waiting > 0 {
                    Circle()
                        .fill(TherapyMethod.dbt.accent)
                        .frame(width: 8, height: 8)
                        .offset(x: 4, y: -3)
                }
            }
            .accessibilityValue(waiting > 0 ? "\(waiting) waiting" : "")
    }
}
