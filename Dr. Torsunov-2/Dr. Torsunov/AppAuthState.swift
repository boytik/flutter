import Foundation


@MainActor
final class AppAuthState: ObservableObject {
    @Published var isLoggedIn: Bool
    @Published var isDemo: Bool

    init() {
        self.isLoggedIn = TokenStorage.shared.accessToken != nil
        self.isDemo = UserDefaults.standard.bool(forKey: "demo_mode")
    }

    func markLoggedIn() {
        isLoggedIn = true
        isDemo = false
        UserDefaults.standard.set(false, forKey: "demo_mode")
    }

    func enterDemo() {
        isDemo = true
        isLoggedIn = false
        UserDefaults.standard.set(true, forKey: "demo_mode")
        TokenStorage.shared.clear()
    }

    func logout() {
        isLoggedIn = false
        isDemo = false
        UserDefaults.standard.set(false, forKey: "demo_mode")
        TokenStorage.shared.clear()
    }
}

