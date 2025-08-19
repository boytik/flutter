
import Foundation
import UIKit
import OSLog

// MARK: - UserProfile
struct UserProfile: Decodable {
    let email: String
    let name: String?
    let role: String?
    let avatarImageBase64: String?
    let avatarImageChangeDate: Date?

    private enum CodingKeys: String, CodingKey {
        case userEmail
        case emailLegacy = "email"
        case name
        case role
        case avatarImageBase64 = "avatar_image"
        case avatarImageChangeDate = "avatar_image_change_date"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        if let e = try c.decodeIfPresent(String.self, forKey: .userEmail) {
            email = e
        } else if let e2 = try c.decodeIfPresent(String.self, forKey: .emailLegacy) {
            email = e2
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.userEmail,
                .init(codingPath: decoder.codingPath,
                      debugDescription: "email/userEmail not found")
            )
        }

        name = try c.decodeIfPresent(String.self, forKey: .name)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        avatarImageBase64 = try c.decodeIfPresent(String.self, forKey: .avatarImageBase64)

        if let s = try c.decodeIfPresent(String.self, forKey: .avatarImageChangeDate) {
            let df = DateFormatter()
            df.locale = .init(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            avatarImageChangeDate = df.date(from: s)
        } else {
            avatarImageChangeDate = nil
        }
    }
}

// MARK: - Ошибки
enum UserRepoError: LocalizedError {
    case noEmail
    var errorDescription: String? { "No email to load/update profile" }
}

// MARK: - Контракт
protocol UserRepository {
    func getUser() async throws -> UserProfile
    func updateNameAndEmail(name: String, email: String) async throws
    func updateRole(to role: String) async throws
    func uploadAvatar(_ image: UIImage) async throws
    func getUser(email: String, short: Bool) async throws -> UserProfile
}

// MARK: - Логгер
private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app",
                         category: "UserRepo")

// MARK: - Реализация
final class UserRepositoryImpl: UserRepository {
    private let client = HTTPClient.shared

    func getUser() async throws -> UserProfile {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty
        else { throw UserRepoError.noEmail }

        let candidates: [URL] = [
            ApiRoutes.Users.get(email: email, short: false),
            ApiRoutes.Users.get(email: email, short: true),
            ApiRoutes.Users.byQuery(email: email)
        ]

        var lastError: Error = UserRepoError.noEmail
        log.debug("[UserRepo] loading user email=\(email, privacy: .public)")

        for u in candidates {
            do {
                let res: UserProfile = try await client.request(UserProfile.self, url: u)
                log.info("[UserRepo] loaded via \(u.absoluteString, privacy: .public)")
                return res
            } catch NetworkError.server(let code, let data) where code == 404 || code == 500 {
                log.error("[UserRepo] HTTP \(code) on \(u.absoluteString, privacy: .public) → try next")
                lastError = NetworkError.server(status: code, data: data)
            } catch {
                log.error("[UserRepo] failed: \(error.localizedDescription, privacy: .public)")
                lastError = error
            }
        }
        throw lastError
    }

    func updateNameAndEmail(name: String, email: String) async throws {
        struct Body: Encodable { let name: String; let email: String }
        let current = TokenStorage.shared.currentEmail() ?? email

        let candidates: [URL] = [
            ApiRoutes.Users.update(email: current),
            ApiRoutes.Users.byQuery(email: current)
        ]

        var lastError: Error = UserRepoError.noEmail
        for u in candidates {
            do {
                try await client.requestVoid(url: u, method: .PATCH, body: Body(name: name, email: email))
                if current != email { TokenStorage.shared.appleEmail = email }
                log.info("[UserRepo] name/email updated via \(u.absoluteString, privacy: .public)")
                return
            } catch NetworkError.server(let code, let data) where code == 404 || code == 500 {
                log.error("[UserRepo] HTTP \(code) on \(u.absoluteString, privacy: .public) → try next")
                lastError = NetworkError.server(status: code, data: data)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func updateRole(to role: String) async throws {
        struct Body: Encodable { let role: String }
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty
        else { throw UserRepoError.noEmail }

        let candidates: [URL] = [
            ApiRoutes.Users.update(email: email),
            ApiRoutes.Users.byQuery(email: email)
        ]

        var lastError: Error = UserRepoError.noEmail
        for u in candidates {
            do {
                try await client.requestVoid(url: u, method: .PATCH, body: Body(role: role))
                log.info("[UserRepo] role updated via \(u.absoluteString, privacy: .public)")
                return
            } catch NetworkError.server(let code, let data) where code == 404 || code == 500 {
                log.error("[UserRepo] HTTP \(code) on \(u.absoluteString, privacy: .public) → try next")
                lastError = NetworkError.server(status: code, data: data)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func uploadAvatar(_ image: UIImage) async throws {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty
        else { throw UserRepoError.noEmail }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NetworkError.other(NSError(domain: "ImageEncoding", code: -1))
        }

        let base64 = data.base64EncodedString()
        struct AvatarBody: Encodable { let avatar_image: String }

        let candidates: [URL] = [
            ApiRoutes.Users.update(email: email),
            ApiRoutes.Users.byQuery(email: email)
        ]

        var lastError: Error = UserRepoError.noEmail
        for u in candidates {
            do {
                try await client.requestVoid(url: u,
                                             method: .PATCH,
                                             body: AvatarBody(avatar_image: base64))
                log.info("[UserRepo] avatar uploaded via \(u.absoluteString, privacy: .public)")
                return
            } catch NetworkError.server(let code, let data) where code == 404 || code == 500 {
                log.error("[UserRepo] HTTP \(code) on \(u.absoluteString, privacy: .public) → try next")
                lastError = NetworkError.server(status: code, data: data)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func getUser(email: String, short: Bool) async throws -> UserProfile {
        try await client.request(UserProfile.self, url: ApiRoutes.Users.get(email: email, short: short))
    }
}
