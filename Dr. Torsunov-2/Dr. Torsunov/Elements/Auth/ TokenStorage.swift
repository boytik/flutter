
import Foundation
import Security

final class TokenStorage: TokenProvider {
    static let shared = TokenStorage()

    private let service = "com.revive.ReviveMobile.tokens"
    private let kAccess = "accessToken"
    private let kRefresh = "refreshToken"

    var accessToken: String? { read(account: kAccess) }
    var refreshToken: String? { read(account: kRefresh) }

    // Новый основной метод
    func save(accessToken: String, refreshToken: String?) {
        write(value: accessToken, account: kAccess)
        if let rt = refreshToken {
            write(value: rt, account: kRefresh)
        }
    }

    // Совместимость с твоим старым кодом
    func saveAccessToken(_ token: String) {
        write(value: token, account: kAccess)
    }

    func clear() {
        delete(account: kAccess)
        delete(account: kRefresh)
    }

    // MARK: Keychain helpers
    private func write(value: String, account: String) {
        let data = Data(value.utf8)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(q as CFDictionary)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private func read(account: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private func delete(account: String) -> Bool {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemDelete(q as CFDictionary) == errSecSuccess
    }
}

