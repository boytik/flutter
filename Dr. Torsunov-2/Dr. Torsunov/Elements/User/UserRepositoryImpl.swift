
import Foundation
import UIKit

final class UserRepositoryImpl: UserRepository {
    private let client = HTTPClient.shared

    // GET /users/me
    func getUser() async throws -> User {
        try await client.request(User.self, url: ApiRoutes.Profile.me)
    }

    // PUT /users/me { name, email }
    func updateNameAndEmail(name: String, email: String) async throws {
        struct Body: Encodable { let name: String; let email: String }
        try await client.requestVoid(url: ApiRoutes.Profile.me, method: .PUT,
                                     body: Body(name: name, email: email))
    }

    // PUT /users/me { role }
    func updateRole(to newRole: String) async throws {
        struct Body: Encodable { let role: String }
        try await client.requestVoid(url: ApiRoutes.Profile.me, method: .PUT,
                                     body: Body(role: newRole))
    }


    func uploadAvatar(_ image: UIImage) async throws {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NetworkError.encoding(NSError(domain: "ImageEncoding", code: -1))
            // или так: throw NetworkError.other(NSError(domain: "ImageEncoding", code: -1))
        }

        try await client.uploadMultipart(
            url: ApiRoutes.Profile.avatar,
            fields: [:],
            parts: [
                HTTPClient.UploadPart(
                    name: "file",
                    filename: "avatar.jpg",
                    mime: "image/jpeg",
                    data: data
                )
            ]
        )
    }

}

