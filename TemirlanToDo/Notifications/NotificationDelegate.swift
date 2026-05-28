import Foundation
import UserNotifications

/// `UNUserNotificationCenterDelegate`, чтобы уведомления показывались
/// и когда приложение открыто (foreground). Без делегата iOS подавляет
/// баннер и звук для активного приложения, и пользователю кажется, что
/// уведомлений нет.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    private override init() {
        super.init()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .list])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}
