

import Foundation

struct UserApiModel: Codable {
    let email: String
    let name: String

    func toUser() -> User {
        return User(email: email, name: name)
    }
}
