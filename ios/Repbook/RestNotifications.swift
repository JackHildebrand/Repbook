import UIKit
import UserNotifications

@MainActor
final class RepbookAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = RestNotifications.shared
        return true
    }
}

@MainActor
final class RestNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RestNotifications()
    private let identifier = "repbook-rest"
    private var updateTask: Task<Void, Never>?
    private var scheduledKey: String?

    func requestPermissionIfNeeded() async {
        guard !ProcessInfo.processInfo.arguments.contains("-repbook-ui-testing"),
              UIApplication.shared.applicationState == .active,
              UserDefaults.standard.object(forKey: "restNotifications") as? Bool ?? true else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            // No sound permission or sound payload: this alert is deliberately silent.
            do {
                _ = try await center.requestAuthorization(options: [.alert])
                scheduledKey = nil
            }
            catch { WorkoutStore.shared.error = "Could not request notification permission: \(error.localizedDescription)" }
        }
        scheduledKey = nil
        synchronize(session: WorkoutStore.shared.data.active)
    }

    func clearDelivered() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func synchronize(session: Session?) {
        guard !ProcessInfo.processInfo.arguments.contains("-repbook-ui-testing") else { return }
        let enabled = UserDefaults.standard.object(forKey: "restNotifications") as? Bool ?? true
        let deadline = enabled ? session?.restUntil : nil
        let key = deadline.map { (session?.id ?? "") + ":" + String($0.timeIntervalSince1970) }
        guard key != scheduledKey || key == nil else { return }
        scheduledKey = key
        // Serialize replacements so a slow add cannot restore an obsolete timer.
        let previous = updateTask
        updateTask = Task {
            await previous?.value
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
            guard let session, let deadline, deadline > Date() else { return }
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let delay = deadline.timeIntervalSinceNow
            guard delay > 0 else { return }
            let content = UNMutableNotificationContent()
            content.title = "Rest complete ✓"
            content.body = "Back to your next set."
            content.sound = nil
            content.userInfo = ["sessionID": session.id]
            content.threadIdentifier = "repbook-rest"
            let request = UNNotificationRequest(identifier: identifier, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false))
            do { try await center.add(request) }
            catch { WorkoutStore.shared.error = "Could not schedule the rest notification: \(error.localizedDescription)" }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // The in-app rest card and haptic already signal completion.
        completionHandler([])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])
        let sessionID = response.notification.request.content.userInfo["sessionID"] as? String
        Task { @MainActor in
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier, let sessionID {
                WorkoutStore.shared.notificationSessionID = sessionID
            }
            completionHandler()
        }
    }
}
