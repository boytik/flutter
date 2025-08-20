import Foundation
import UserNotifications

/// Регистрирует категории/экшены для уведомлений.
enum NotificationCategoryFactory {
    static let defaultCategoryId = "APP_DEFAULT_CATEGORY"

    static func registerAll() {
        // Кнопка "Выполнено"
        let markDone = UNNotificationAction(
            identifier: "ACTION_MARK_DONE",
            title: NSLocalizedString("Mark done", comment: "Mark item as done"),
            options: [.authenticationRequired]
        )

        // Стандартное открытие приложения
        let open = UNNotificationAction(
            identifier: UNNotificationDefaultActionIdentifier,
            title: NSLocalizedString("Open", comment: "Open app"),
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: defaultCategoryId,
            actions: [markDone, open],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
