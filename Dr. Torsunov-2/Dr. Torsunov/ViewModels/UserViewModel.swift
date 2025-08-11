
import SwiftUI

@MainActor
final class UserViewModel: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repository: UserRepository

    init(repository: UserRepository = UserRepositoryImpl()) {
        self.repository = repository
        Task { await loadUser() }
    }

    func loadUser() async {
        isLoading = true
        defer { isLoading = false }
        do {
            user = try await repository.getUser()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateNameAndEmail(name: String, email: String) async {
        do {
            try await repository.updateNameAndEmail(name: name, email: email)
            await loadUser()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateRole(to newRole: String) async {
        do {
            try await repository.updateRole(to: newRole)
            await loadUser()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
