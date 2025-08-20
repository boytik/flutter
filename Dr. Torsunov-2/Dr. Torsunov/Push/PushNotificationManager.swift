import Foundation
import UserNotifications

/// Высокоуровневый фасад для работы с уведомлениями из SwiftUI/ViewModel.
enum PushNotificationManager {

    /// Запросить разрешения пользователя (баннер/звук/бейдж)
    static func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                completion?(granted)
            }
        }
    }

    /// Получить текущий статус прав
    static func getAuthorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(settings.authorizationStatus)
        }
    }

    /// Запланировать локальное уведомление на конкретную дату/время
    ///
    /// - Parameters:
    ///   - id: стабильный идентификатор (чтобы можно было отменить/перезаписать)
    ///   - title/body: текст уведомления
    ///   - date: локальное время срабатывания
    ///   - repeats: нужен ли повтор по тем же компонентам даты
    ///   - categoryId: категория для экшенов (кнопок)
    ///   - userInfo: дополнительный payload (например ["deeplink": "myrevive://..."])
    static func scheduleLocal(
        id: String,
        title: String,
        body: String,
        date: Date,
        repeats: Bool = false,
        categoryId: String? = NotificationCategoryFactory.defaultCategoryId,
        userInfo: [AnyHashable: Any] = [:]
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: 1)
        if let categoryId { content.categoryIdentifier = categoryId }
        content.userInfo = userInfo

        // Точные компоненты для локального календарного триггера
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("scheduleLocal error:", error) }
        }
    }

    /// Отменить по идентификаторам
    static func cancel(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Отменить все запланированные уведомления
    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
