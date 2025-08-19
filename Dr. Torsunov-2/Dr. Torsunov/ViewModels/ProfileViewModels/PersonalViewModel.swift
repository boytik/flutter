import SwiftUI
import Foundation
import Combine
import UIKit
import OSLog

struct User: Codable, Equatable {
    var email: String
    var name: String?
    var role: String?            
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

    // MARK: - UI state
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

    private let ns = "user_profile"
    private let kvKeyUser = "user_self"
    private let kvTTLUser: TimeInterval = 60 * 60

    enum EditingField: Identifiable {
        case name
        case email
        var id: Int { hashValue }
    }

    // MARK: - Logger
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app",
                             category: "PersonalVM")

    init(userRepository: UserRepository = UserRepositoryImpl(),
         physicalDataVM: PhysicalDataViewModel) {
        self.userRepository = userRepository
        self.physicalDataVM = physicalDataVM

        Task { [weak self] in
            await self?.loadUser()
        }
    }

    // MARK: - Data
    func loadUser() async {
        if let cached: User = try? KVStore.shared.get(User.self, namespace: self.ns, key: self.kvKeyUser) {
            self.email = cached.email
            self.name  = cached.name ?? ""
            self.applyRoleFallback(fromServerString: cached.role)
            self.log.debug("[KV] HIT \(self.ns)/\(self.kvKeyUser)")
        } else if self.email.isEmpty, let local = TokenStorage.shared.currentEmail() {
            self.email = local
        }

        do {
            let remote = try await self.userRepository.getUser()
            let snapshot = self.mapToUser(remote)
            self.email = snapshot.email
            self.name  = snapshot.name ?? ""
            self.applyRoleFallback(fromServerString: snapshot.role)

            UserDefaults.standard.set(self.role.rawValue, forKey: "user_role")

            try? KVStore.shared.put(snapshot, namespace: self.ns, key: self.kvKeyUser, ttl: self.kvTTLUser)
            self.log.debug("[KV] SAVE \(self.ns)/\(self.kvKeyUser)")
        } catch {
            self.log.error("[LoadUser] failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Маппер «что бы ни вернул репозиторий» → наш лёгкий `User`
    private func mapToUser(_ anyUser: Any) -> User {
        if let u = anyUser as? User { return u }

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
        if let saved = UserDefaults.standard.string(forKey: "user_role"),
           let savedRole = Role(rawValue: saved) {
            self.role = savedRole
            return
        }
        if let r = serverRole?.lowercased(), r == "inspector" {
            self.role = .inspector
        } else {
            self.role = .user
        }
    }

    func saveChanges(for field: EditingField, with newValue: String) async {
        let newEmail = (field == .email) ? newValue : self.email
        let newName  = (field == .name)  ? newValue : self.name
        do {
            try await self.userRepository.updateNameAndEmail(name: newName, email: newEmail)
            self.email = newEmail
            self.name  = newName
            self.editingField = nil

            var cached = (try? KVStore.shared.get(User.self, namespace: self.ns, key: self.kvKeyUser))
                         ?? User(email: newEmail, name: newName, role: self.role.rawValue, avatarImageBase64: nil)
            cached.email = newEmail
            cached.name  = newName
            try? KVStore.shared.put(cached, namespace: self.ns, key: self.kvKeyUser, ttl: self.kvTTLUser)
            self.log.debug("[KV] UPDATE \(self.ns)/\(self.kvKeyUser)")
        } catch {
            self.log.error("[UpdateNameEmail] failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func updateRole(to newRole: Role) async {
        self.role = newRole
        UserDefaults.standard.set(newRole.rawValue, forKey: "user_role")
        self.log.info("[Role] switched locally to \(newRole.rawValue, privacy: .public)")
    }

    // MARK: - Session
    func logout() {
        TokenStorage.shared.clear()
        self.log.info("[Session] logout")
        try? KVStore.shared.delete(namespace: self.ns, key: self.kvKeyUser)
        self.log.info("[KV] DELETE \(self.ns)/\(self.kvKeyUser)")
    }

    func deleteAccount() {
        self.log.info("[Account] delete (stub)")
    }

    // MARK: - Private: Best-effort PATCH (пока не используется)
    private func tryUpdateRoleOnServer(_ role: Role) async {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else { return }
        let client = HTTPClient.shared

        let url1 = ApiRoutes.Users.update(email: email)
        for body in PatchRolePayload.bodies(for: role) {
            do {
                try await client.requestVoid(url: url1, method: .PATCH, body: body)
                self.log.info("[Role] updated via /users/<email> with \(body.debugName, privacy: .public)")
                return
            } catch {
                self.log.error("[Role] patch failed (\(body.debugName, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            }
        }

        let url2 = ApiRoutes.Users.byQuery(email: email)
        for body in PatchRolePayload.bodies(for: role) {
            do {
                try await client.requestVoid(url: url2, method: .PATCH, body: body)
                self.log.info("[Role] updated via /user?email with \(body.debugName, privacy: .public)")
                return
            } catch {
                self.log.error("[Role] patch (query) failed (\(body.debugName, privacy: .public)): \(error.localizedDescription, privacy: .public)")
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
        for s in role.serverStrings { arr.append(.init(role: s)) }
        for s in role.serverStrings { arr.append(.init(user_type: s)) }
        arr.append(.init(is_inspector: role.isInspector))            
        return arr
    }
}
