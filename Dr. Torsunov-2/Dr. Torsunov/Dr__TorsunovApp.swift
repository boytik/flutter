import SwiftUI
import Combine
import UserNotifications
import UIKit

@main
struct Dr__TorsunovApp: App {
    // Подключаем AppDelegate для APNs/UNUserNotificationCenter
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject var auth = AppAuthState()

    init() {
        segmentStyle()
        tapBarStyle()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoggedIn || auth.isDemo {
                    TapBarView()
                } else {
                    StartScreen()
                }
            }
            .environmentObject(auth)

            // Deep links из нотификаций/URL
            .onReceive(NotificationCenter.default.publisher(for: .didReceiveDeepLink)) { note in
                guard let link = note.object as? DeepLink else { return }
                switch link {
                case .workout(_):
                    break
                case .activities:
                    break
                case .profile:
                    break
                case .unknown:
                    break
                }
            }
            .onOpenURL { url in
                DeepLinkRouter.shared.handle(url: url)
            }

            // Запрос разрешений на уведомления при первом запуске UI
            .onAppear {
                PushNotificationManager.requestAuthorization { granted in
                    if !granted {
                        print("Notifications permission not granted")
                    }
                }
                // Регистрация на пуши (на случай если AppDelegate ещё не успел)
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - UI стили
    private func segmentStyle() {
        let appearance = UISegmentedControl.appearance()
        appearance.selectedSegmentTintColor = UIColor.green
        appearance.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        appearance.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        appearance.backgroundColor = UIColor.tapBar
    }

    private func tapBarStyle(){
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "TapBar")

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
