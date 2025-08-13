
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

        // удобства для сетевых патчей
        var isInspector: Bool { self == .inspector }
        var serverStrings: [String] { [rawValue, rawValue.lowercased(), rawValue.capitalized] }
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
    @MainActor
    func loadUser() async {
        do {
            let user = try await userRepository.getUser()
            email = user.email
            name  = user.name ?? ""

            // 1) Сначала берём роль из локального хранилища (Flutter-подход)
            if let saved = UserDefaults.standard.string(forKey: "user_role"),
               let savedRole = Role(rawValue: saved) {
                self.role = savedRole
            } else if let r = user.role?.lowercased(), r == "inspector" {
                // 2) Если сервер когда-нибудь начнёт присылать роль — подхватим
                self.role = .inspector
            } else {
                self.role = .user
            }

            // Синхронизируем для остальных экранов (CalendarView и т.п.)
            UserDefaults.standard.set(self.role.rawValue, forKey: "user_role")
        } catch {
            print("❌ loadUser error:", error.localizedDescription)
            if email.isEmpty, let local = TokenStorage.shared.currentEmail() {
                email = local
            }
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

    /// Локально переключаем роль (для UI) + «мягко» пытаемся отправить изменения на сервер.
    func updateRole(to newRole: Role) async {
        // 1) мгновенно меняем локально
        self.role = newRole
        UserDefaults.standard.set(newRole.rawValue, forKey: "user_role")
        print("🔁 Local role switched to \(newRole.rawValue)")

        // 2) НИКАКИХ сетевых вызовов ровно сейчас — сервер не поддерживает
        // Если сервер позже добавит поле — вернём PATCH здесь.
    }


    // MARK: - Session
    func logout() {
        TokenStorage.shared.clear()
        print("Выход выполнен")
    }

    func deleteAccount() {
        // Заглушка. Добавим API, когда появится.
        print("Аккаунт удалён (stub)")
    }

    // MARK: - Private: Best-effort PATCH
    private func tryUpdateRoleOnServer(_ role: Role) async {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else { return }
        let client = HTTPClient.shared

        // /users/<email>
        let url1 = ApiRoutes.Users.update(email: email)
        for body in PatchRolePayload.bodies(for: role) {
            do {
                try await client.requestVoid(url: url1, method: .PATCH, body: body)
                print("✅ Role updated via /users/<email> with \(body.debugName)")
                return
            } catch {
                print("↩️ role patch failed (\(body.debugName)): \(error.localizedDescription)")
            }
        }

        // fallback: /user?email=
        let url2 = ApiRoutes.Users.byQuery(email: email)
        for body in PatchRolePayload.bodies(for: role) {
            do {
                try await client.requestVoid(url: url2, method: .PATCH, body: body)
                print("✅ Role updated via /user?email with \(body.debugName)")
                return
            } catch {
                print("↩️ role patch (query) failed (\(body.debugName)): \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Пакеты тел для PATCH (варианты ключей)
private struct PatchRolePayload: Encodable {
    var role: String? = nil
    var user_type: String? = nil
    var is_inspector: Bool? = nil

    var debugName: String {
        if role != nil { return "role" }
        if user_type != nil { return "user_type" }
        if is_inspector != nil { return "is_inspector" }
        return "unknown"
    }

    static func bodies(for role: PersonalViewModel.Role) -> [PatchRolePayload] {
        var arr: [PatchRolePayload] = []
        for s in role.serverStrings { arr.append(.init(role: s)) }       // role
        for s in role.serverStrings { arr.append(.init(user_type: s)) }  // user_type
        arr.append(.init(is_inspector: role.isInspector))                 // is_inspector
        return arr
    }
}
