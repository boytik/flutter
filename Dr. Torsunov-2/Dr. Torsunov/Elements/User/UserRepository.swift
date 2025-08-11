
import UIKit

protocol UserRepository {
    func getUser() async throws -> User
    func updateNameAndEmail(name: String, email: String) async throws
    func updateRole(to newRole: String) async throws
    func uploadAvatar(_ image: UIImage) async throws
}


