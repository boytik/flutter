
import Foundation

// Совместимые модели с твоим кодом
struct AuthTokens: Decodable {
    let accessToken: String
    let refreshToken: String?
}
typealias AuthResponse = AuthTokens
typealias AppleAuthResponse = AuthTokens

protocol AuthenticationRepository: AuthRefresher {
    @discardableResult
    func login(email: String, password: String) async -> Bool

    @discardableResult
    func loginWithApple(idToken: String) async -> Bool

    func logout() async
}
