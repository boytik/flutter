
// Elements/Profile/UserRepository.swift
import Foundation
import UIKit

struct UserProfile: Decodable {
    let email: String
    let name: String?
    let role: String?

    // ↓ новое
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
                .init(codingPath: decoder.codingPath, debugDescription: "email/userEmail not found")
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




enum UserRepoError: LocalizedError {
    case noEmail
    var errorDescription: String? { "No email to load/update profile" }
}

protocol UserRepository {
    func getUser() async throws -> UserProfile
    func updateNameAndEmail(name: String, email: String) async throws
    func updateRole(to role: String) async throws
    func uploadAvatar(_ image: UIImage) async throws
    func getUser(email: String, short: Bool) async throws -> UserProfile
}

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
        print("🔎 currentEmail(raw):", email)
        print("🔎 path get:", ApiRoutes.Users.get(email: email).absoluteString)
        print("🔎 path get(short):", ApiRoutes.Users.get(email: email, short: true).absoluteString)
        print("🔎 query get:", ApiRoutes.Users.byQuery(email: email).absoluteString)

        for u in candidates {
            do {
                let res: UserProfile = try await client.request(UserProfile.self, url: u)
                print("✅ User loaded from:", u.absoluteString)
                return res
            } catch NetworkError.server(let code, let data) where code == 404 || code == 500 {
                print("↩️ \(code) on \(u.absoluteString), trying next…")
                lastError = NetworkError.server(status: code, data: data)
                continue
            } catch {
                lastError = error
                continue
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
                print("✅ User updated via:", u.absoluteString)
                return
            } catch NetworkError.server(let code, let data) where code == 404 || code == 500 {
                print("↩️ \(code) on \(u.absoluteString), trying next…")
                lastError = NetworkError.server(status: code, data: data)
                continue
            } catch {
                lastError = error
                continue
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
                print("✅ Role updated via:", u.absoluteString)
                return
            } catch NetworkError.server(let code, let data) where code == 404 || code == 500 {
                print("↩️ \(code) on \(u.absoluteString), trying next…")
                lastError = NetworkError.server(status: code, data: data)
                continue
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }


    struct AvatarBody: Encodable { let avatar_image: String }

    func uploadAvatar(_ image: UIImage) async throws {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            throw UserRepoError.noEmail
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NetworkError.other(NSError(domain: "ImageEncoding", code: -1))
        }
        let base64 = data.base64EncodedString()

        // сначала PATCH /users/<email>, затем fallback PATCH /user?email=...
        let candidates: [URL] = [
            ApiRoutes.Users.update(email: email),
            ApiRoutes.Users.byQuery(email: email)
        ]

        var lastError: Error = UserRepoError.noEmail
        for u in candidates {
            do {
                try await client.requestVoid(
                    url: u,
                    method: .PATCH,
                    body: AvatarBody(avatar_image: base64)
                )
                print("✅ Avatar uploaded via:", u.absoluteString)
                return
            }
            // ВАРИАНТ 1: если enum объявлен как case server(status: Int, data: Data?)
            catch let NetworkError.server(status: code, data: data) where code == 404 || code == 500 {
                print("↩️ \(code) on \(u.absoluteString), trying next…")
                lastError = NetworkError.server(status: code, data: data)
                continue
            }

            catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }



    func getUser(email: String, short: Bool) async throws -> UserProfile {
        try await client.request(UserProfile.self, url: ApiRoutes.Users.get(email: email, short: short))
    }
}
