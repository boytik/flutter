import SwiftUI
import UserNotifications
import UIKit

// Если планируешь FCM — раскомментируй и добавь пакеты через SPM:
// import FirebaseCore
// import FirebaseMessaging

extension Notification.Name {
    static let didUpdateFCMToken = Notification.Name("app.didUpdateFCMToken")
}

/// AppDelegate отвечает за регистрацию APNs/права и обработку кликов по уведомлениям.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate /*, MessagingDelegate*/ {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // Если используешь Firebase:
        // FirebaseApp.configure()

        // Делегат нотификаций + категории действий
        UNUserNotificationCenter.current().delegate = self
        NotificationCategoryFactory.registerAll()

        // Регистрация на пуши
        application.registerForRemoteNotifications()
        return true
    }

    // MARK: - APNs token
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Если используешь Firebase:
        // Messaging.messaging().apnsToken = deviceToken
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("APNs token:", tokenString)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed:", error.localizedDescription)
    }

    // MARK: - FCM token (если Firebase)
//    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
//        NotificationCenter.default.post(name: .didUpdateFCMToken, object: fcmToken)
//        print("FCM token:", fcmToken ?? "nil")
//    }

    // MARK: - Показ уведомлений в foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    // MARK: - Обработка кликов по уведомлению/экшенам
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {

        let userInfo = response.notification.request.content.userInfo

        // Ожидаем строковый диплинк в payload по ключу "deeplink"
        if let deeplink = userInfo["deeplink"] as? String,
           let url = Self.makeURL(from: deeplink) {
            DeepLinkRouter.shared.handle(url: url)
        }

        switch response.actionIdentifier {
        case "ACTION_MARK_DONE":
            print("Notification action: MARK DONE")
        default:
            break
        }

        completionHandler()
    }

    // MARK: - Helpers
    /// Безопасно собирает URL из строки (добавляет percent-encoding при необходимости).
    private static func makeURL(from string: String) -> URL? {
        if let url = URL(string: string) { return url }
        // Попытка добавить percent-encoding для нестандартных символов
        if let encoded = string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) {
            return URL(string: encoded)
        }
        return nil
    }
}
