
import Foundation

/// Локальная «авторизация как во Flutter»: без запроса на сервер
final class AuthenticationRepositoryImpl {
    private let tokens = TokenStorage.shared

    @discardableResult
    func loginWithApple(idToken: String, appleUserId: String? = nil) async -> Bool {
        tokens.accessToken = idToken
        tokens.appleUserId = appleUserId
        return true
    }


    /// Гостевой вход (если нужен)
    @discardableResult
    func loginDemo() async -> Bool {
        tokens.accessToken = "demo-token"
        tokens.appleUserId = nil
        return true
    }

    func logout() async {
        tokens.clear()
    }
}

