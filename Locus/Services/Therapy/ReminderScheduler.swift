import Foundation
import UserNotifications

/// Local notifications for the skills toolkit. Copy is deliberately
/// generic ("How did your experiment go?"), since it can show on the lock
/// screen. Each carries a `route` the app opens on tap (`AppRouter`).
@MainActor
enum ReminderScheduler {
    enum Daily: String, CaseIterable {
        case diary, inbox, practice

        var defaultsKey: String { "skills.reminder.\(rawValue)" }
        var hourKey: String { "skills.reminder.\(rawValue).hour" }
        var defaultHour: Int {
            switch self {
            case .diary: 20
            case .inbox: 18
            case .practice: 9
            }
        }
    }

    static let valuesKey = "skills.reminder.values"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// A one-off reminder for a pending session (experiment outcome,
    /// planned activity, committed action…).
    static func scheduleSession(id: String, at date: Date, title: String, body: String) {
        let fireDate = max(date, .now.addingTimeInterval(5))
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        add(id: "session.\(id)", title: title, body: body, route: "session:\(id)",
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }

    static func cancel(sessionID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["session.\(sessionID)"])
    }

    static func isOn(_ daily: Daily) -> Bool {
        UserDefaults.standard.bool(forKey: daily.defaultsKey)
    }

    static func hour(_ daily: Daily) -> Int {
        let stored = UserDefaults.standard.object(forKey: daily.hourKey) as? Int
        return stored ?? daily.defaultHour
    }

    /// Turns a daily reminder on or off. The inbox one also needs the
    /// current count (`refreshInbox`).
    static func setDaily(_ daily: Daily, on: Bool, hour: Int? = nil, inboxCount: Int = 0) {
        UserDefaults.standard.set(on, forKey: daily.defaultsKey)
        if let hour { UserDefaults.standard.set(hour, forKey: daily.hourKey) }
        let id = "daily.\(daily.rawValue)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        guard on else { return }
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: self.hour(daily), minute: 0), repeats: true)
        switch daily {
        case .diary:
            add(id: id, title: "Diary card", body: "A minute to check in on today.", route: "diary", trigger: trigger)
        case .practice:
            add(id: id, title: "Practice", body: "A few cards to practice while things are calm.", route: "practice", trigger: trigger)
        case .inbox:
            guard inboxCount > 0 else { return }
            let body = inboxCount == 1 ? "You have 1 thought to work through." : "You have \(inboxCount) thoughts to work through."
            add(id: id, title: "Inbox", body: body, route: "inbox", trigger: trigger)
        }
    }

    /// Keeps the inbox reminder's count current (or removes it at zero).
    static func refreshInbox(count: Int) {
        guard isOn(.inbox) else { return }
        setDaily(.inbox, on: true, inboxCount: count)
    }

    static func setWeeklyValues(on: Bool) {
        UserDefaults.standard.set(on, forKey: valuesKey)
        let id = "weekly.values"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        guard on else { return }
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 10, minute: 0, weekday: 1), repeats: true)
        add(id: id, title: "Values check-in", body: "How have you been living your values this week?", route: "values", trigger: trigger)
    }

    /// A daily nudge to keep an if-then plan in mind.
    static func setPlanReminder(planID: String, on: Bool) {
        let id = "plan.\(planID)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        guard on else { return }
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 9, minute: 0), repeats: true)
        add(id: id, title: "Your if-then plan", body: "A reminder of the plan you made.", route: "practice", trigger: trigger)
    }

    private static func add(id: String, title: String, body: String, route: String, trigger: UNNotificationTrigger) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["route": route]
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        Task {
            guard await requestAuthorization() else { return }
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}
