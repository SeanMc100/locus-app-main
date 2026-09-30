import SwiftUI
import UserNotifications

/// Where a home-screen quick action or a tapped notification wants to go.
enum AppDestination: Hashable {
    case quickCapture
    case calmDown
    case session(String)
    case toolkit
    case diary
    case practice
    case values

    init?(route: String) {
        switch route {
        case "quickCapture": self = .quickCapture
        case "calmDown": self = .calmDown
        case "inbox", "toolkit": self = .toolkit
        case "diary": self = .diary
        case "practice": self = .practice
        case "values": self = .values
        default:
            guard route.hasPrefix("session:") else { return nil }
            self = .session(String(route.dropFirst("session:".count)))
        }
    }
}

/// Carries deep links from the app/scene delegates into SwiftUI.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    /// Set by a quick action or notification; `SkillsRouting` presents it.
    var pending: AppDestination?
    /// Bumped to ask open sheets to close before a deep link is shown.
    var dismissToken = 0

    func open(_ destination: AppDestination) {
        guard FeatureFlags.showsSkillsToolkit else { return }
        dismissToken += 1
        pending = destination
    }

    static let quickCaptureType = "com.seanmcdonnell.Locus.quickCapture"
    static let calmDownType = "com.seanmcdonnell.Locus.calmDown"

    func handle(shortcutType: String) {
        switch shortcutType {
        case Self.quickCaptureType: open(.quickCapture)
        case Self.calmDownType: open(.calmDown)
        default: break
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        if let item = options.shortcutItem {
            let type = item.type
            Task { @MainActor in AppRouter.shared.handle(shortcutType: type) }
        }
        return configuration
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let route = response.notification.request.content.userInfo["route"] as? String
        Task { @MainActor in
            if let route, let destination = AppDestination(route: route) {
                AppRouter.shared.open(destination)
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        AppRouter.shared.handle(shortcutType: shortcutItem.type)
        completionHandler(true)
    }
}
