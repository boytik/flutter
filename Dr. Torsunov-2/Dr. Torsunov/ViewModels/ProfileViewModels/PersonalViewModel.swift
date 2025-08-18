import SwiftUI
import Foundation
import Combine
import UIKit

// Лёгкая модель пользователя под наш UI и оффлайн-снапшот
struct User: Codable, Equatable {
    var email: String
    var name: String?
    var role: String?                 // "User" / "Inspector" / др.
    var avatarImageBase64: String?
}

@MainActor
final class PersonalViewModel: ObservableObject {
    enum Role: String, CaseIterable, Identifiable {
        case user = "User"
        case inspector = "Inspector"
        var id: String { rawValue }

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

    // KVStore
    private let ns = "user_profile"
    private let kvKeyUser = "user_self"
    private let kvTTLUser: TimeInterval = 60 * 60 // 1 час

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
        // 0) оффлайн — подхватываем мгновенно
        if let cached: User = try? KVStore.shared.get(User.self, namespace: ns, key: kvKeyUser) {
            email = cached.email
            name  = cached.name ?? ""
            applyRoleFallback(fromServerString: cached.role)
            print("📦 KV HIT \(ns)/\(kvKeyUser)")
        } else if email.isEmpty, let local = TokenStorage.shared.currentEmail() {
            // хотя бы email, если вообще пусто
            email = local
        }

        // 1) сеть
        do {
            // репозиторий может возвращать любую модель — маппим в наш User-снапшот
            let remote = try await userRepository.getUser()
            let snapshot = mapToUser(remote)
            email = snapshot.email
            name  = snapshot.name ?? ""
            applyRoleFallback(fromServerString: snapshot.role)

            // синхронизируем роль в UserDefaults (используется в других экранах)
            UserDefaults.standard.set(self.role.rawValue, forKey: "user_role")

            // оффлайн-снапшот
            try? KVStore.shared.put(snapshot, namespace: ns, key: kvKeyUser, ttl: kvTTLUser)
            print("💾 KV SAVE \(ns)/\(kvKeyUser)")
        } catch {
            print("❌ loadUser error:", error.localizedDescription)
        }
    }

    /// Маппер «что бы ни вернул репозиторий» → наш лёгкий `User`
    /// Попытка прочитать поля через KVC/Reflect — на случай, если тип не совпадает.
    private func mapToUser(_ anyUser: Any) -> User {
        // если это уже наш User
        if let u = anyUser as? User { return u }

        // пробуем через Mirror вытащить известные поля
        let m = Mirror(reflecting: anyUser)
        var email: String = self.email
        var name: String? = self.name
        var role: String? = nil
        var avatar: String? = nil

        for child in m.children {
            switch child.label ?? "" {
            case "email":                email  = child.value as? String ?? email
            case "name", "fullName":     name   = child.value as? String ?? name
            case "role", "user_type":    role   = child.value as? String ?? role
            case "avatarImageBase64",
                 "avatarBase64",
                 "avatar":               avatar = child.value as? String ?? avatar
            default: break
            }
        }
        return User(email: email, name: name, role: role, avatarImageBase64: avatar)
    }

    private func applyRoleFallback(fromServerString serverRole: String?) {
        // 1) локально сохранённая роль — приоритет
        if let saved = UserDefaults.standard.string(forKey: "user_role"),
           let savedRole = Role(rawValue: saved) {
            self.role = savedRole
            return
        }
        // 2) если сервер присылает роль — подхватим
        if let r = serverRole?.lowercased(), r == "inspector" {
            self.role = .inspector
        } else {
            self.role = .user
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

            // обновим оффлайн-снапшот пользователя
            var cached = (try? KVStore.shared.get(User.self, namespace: ns, key: kvKeyUser))
                         ?? User(email: newEmail, name: newName, role: role.rawValue, avatarImageBase64: nil)
            cached.email = newEmail
            cached.name  = newName
            try? KVStore.shared.put(cached, namespace: ns, key: kvKeyUser, ttl: kvTTLUser)
            print("💾 KV UPDATE \(ns)/\(kvKeyUser)")
        } catch {
            print("❌ updateNameAndEmail error:", error.localizedDescription)
        }
    }

    /// Локально переключаем роль (для UI).
    func updateRole(to newRole: Role) async {
        self.role = newRole
        UserDefaults.standard.set(newRole.rawValue, forKey: "user_role")
        print("🔁 Local role switched to \(newRole.rawValue)")
        // сервер не поддерживает — не шлём PATCH
    }

    // MARK: - Session
    func logout() {
        TokenStorage.shared.clear()
        print("Выход выполнен")
        // можно почистить и оффлайн
        try? KVStore.shared.delete(namespace: ns, key: kvKeyUser)
    }

    func deleteAccount() {
        // Заглушка. Добавим API, когда появится.
        print("Аккаунт удалён (stub)")
    }

    // MARK: - Private: Best-effort PATCH (пока не используется)
    private func tryUpdateRoleOnServer(_ role: Role) async {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else { return }
        let client = HTTPClient.shared

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
