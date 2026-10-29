import UserNotifications
import UIKit

/// Local notifications (the brief allows local notifications instead of remote push):
/// treatment re-check reminders, geofence zone-entry reminders, weather warnings and outbreak alerts.
enum NotificationService {
    static var center: UNUserNotificationCenter { .current() }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { await MainActor.run { PushRegistration.register() } }     // remote push (needs the Push capability)
        return granted
    }

    static func status() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }

    static func schedule(id: String, title: String, body: String, after seconds: TimeInterval, userInfo: [String: String] = [:]) {
        guard AppSettings.shared.notificationsEnabled else { return }
        let content = makeContent(title, body, userInfo)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func schedule(id: String, title: String, body: String, at date: Date, userInfo: [String: String] = [:]) {
        guard AppSettings.shared.notificationsEnabled, date > Date() else { return }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: makeContent(title, body, userInfo), trigger: trigger))
    }

    static func fireNow(id: String = UUID().uuidString, title: String, body: String, userInfo: [String: String] = [:]) {
        schedule(id: id, title: title, body: body, after: 1, userInfo: userInfo)
    }

    static func cancel(ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    static func cancelAll() { center.removeAllPendingNotificationRequests(); center.removeAllDeliveredNotifications() }

    private static func makeContent(_ title: String, _ body: String, _ info: [String: String]) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default; c.userInfo = info
        return c
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Must exist at launch: iOS relaunches the app in the background for geofence events and delivers them to this delegate.
        LocationService.shared.syncGeofences(from: PersistenceController.shared.viewContext)
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistration.didReceive(deviceToken: deviceToken)
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Remote push unavailable: \(error.localizedDescription)")   // expected without the Push capability / on simulator
    }
    /// Show banners even while the app is open (important for demos).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        await MainActor.run {
            switch info["route"] as? String {
            case "treatments": AppRouter.shared.go(.treatments)
            case "radar": AppRouter.shared.go(.radar)
            case "farm": AppRouter.shared.go(.farm)
            default: AppRouter.shared.go(.dashboard)
            }
        }
    }
}
