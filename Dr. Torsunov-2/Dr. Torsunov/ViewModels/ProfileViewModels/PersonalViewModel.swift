
import SwiftUI
import Foundation
import Combine
import UIKit

@MainActor
final class PersonalViewModel: ObservableObject {
    enum Role: String, CaseIterable, Identifiable {
        case user = "User"
        case inspector = "Inspector"
        var id: String { rawValue }
    }

    @Published var email: String = ""
    @Published var name: String = ""
    @Published var role: Role = .user

    @Published var selectedImage: UIImage? = nil
    @Published var showImagePicker = false

    @Published var editingField: EditingField? = nil
    @Published var showRolePicker = false
    @Published var showPhysicalDataSheet = false
    @Published var showLogoutAlert = false
    @Published var showOtherActions = false
    @Published var showDeleteConfirmAlert = false

    let physicalDataVM: PhysicalDataViewModel
    let userRepository: UserRepository

    enum EditingField: Identifiable {
        case name
        case email
        var id: Int { hashValue }
    }

    init(userRepository: UserRepository = UserRepositoryImpl(),
         physicalDataVM: PhysicalDataViewModel) {
        self.userRepository = userRepository
        self.physicalDataVM = physicalDataVM

        Task { await loadUser() }
    }

    // MARK: - Data
    func loadUser() async {
        do {
            let user = try await userRepository.getUser()
            email = user.email
            name  = user.name
            // если сервер вернёт роль — распарси её здесь
            // role = Role(rawValue: user.role) ?? .user
        } catch {
            print("❌ loadUser error:", error.localizedDescription)
        }
    }

    func saveChanges(for field: EditingField, with newValue: String) async {
        let newEmail = (field == .email) ? newValue : email
        let newName  = (field == .name)  ? newValue : name
        do {
            try await userRepository.updateNameAndEmail(name: newName, email: newEmail)
            email = newEmail
            name  = newName
            editingField = nil
        } catch {
            print("❌ updateNameAndEmail error:", error.localizedDescription)
        }
    }

    func updateRole(to newRole: Role) async {
        do {
            try await userRepository.updateRole(to: newRole.rawValue)
            role = newRole
            UserDefaults.standard.set(newRole.rawValue, forKey: "user_role") 
        } catch {
            print("❌ updateRole error:", error.localizedDescription)
        }
    }

    // MARK: - Session
    func logout() {
        TokenStorage.shared.clear()
        print("Выход выполнен")
        // Тут же дерни навигацию/сброс состояния
    }


    func deleteAccount() {
        // Заглушка. Добавим API, когда появится.
        print("Аккаунт удалён (stub)")
    }
}




