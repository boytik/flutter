
import UIKit

final class AuthenticationRepositoryImpl: AuthenticationRepository {
    private let client = HTTPClient.shared
    private let tokens = TokenStorage.shared

    init() {
        // Интеграция с HTTPClient
        client.tokenProvider = tokens
        client.authRefresher = self
    }

    // MARK: Email+Password
    @discardableResult
    func login(email: String, password: String) async -> Bool {
        do {
            let payload = ["email": email, "password": password]
            let resp = try await client.request(AuthResponse.self,
                                                url: ApiRoutes.Auth.login,
                                                method: .POST,
                                                body: payload)
            tokens.save(accessToken: resp.accessToken, refreshToken: resp.refreshToken)
            return true
        } catch {
            print("❌ Login failed:", error)
            return false
        }
    }

    // MARK: Sign in with Apple
    @discardableResult
    func loginWithApple(idToken: String) async -> Bool {
        do {
            // Если сервер ждёт "id_token" — оставь как есть.
            let payload = ["id_token": idToken]
            let resp = try await client.request(AppleAuthResponse.self,
                                                url: ApiRoutes.Auth.apple,
                                                method: .POST,
                                                body: payload)
            tokens.save(accessToken: resp.accessToken, refreshToken: resp.refreshToken)
            return true
        } catch {
            print("❌ Apple login failed:", error)
            return false
        }
    }

    // MARK: Logout
    func logout() async {
        do {
            // Не падаем, даже если сервер недоступен
            try await client.requestVoid(url: ApiRoutes.Auth.logout, method: .POST)
        } catch {
            print("⚠️ server logout:", error)
        }
        tokens.clear()
    }

    // MARK: Refresh (AuthRefresher)
    func refreshToken() async throws {
        guard let rt = tokens.refreshToken else {
            throw NetworkError.unauthorized
        }
        struct Body: Encodable { let refreshToken: String }
        let resp: AuthTokens = try await client.request(ApiRoutes.Auth.refresh,
                                                        method: .POST,
                                                        body: Body(refreshToken: rt))
        tokens.save(accessToken: resp.accessToken, refreshToken: resp.refreshToken)
    }
}
