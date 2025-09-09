
import Foundation

final class TokenStorage {
    static let shared = TokenStorage()
    private init() {}

    private let kAccess = "auth.access.token"
    private let kAppleUserID = "auth.apple.userId"
    private let kAppleEmail = "auth.apple.email"

    var accessToken: String? {
        get { UserDefaults.standard.string(forKey: kAccess) }
        set { newValue == nil ? UserDefaults.standard.removeObject(forKey: kAccess)
                              : UserDefaults.standard.set(newValue, forKey: kAccess) }
    }

    var appleUserId: String? {
        get { UserDefaults.standard.string(forKey: kAppleUserID) }
        set { newValue == nil ? UserDefaults.standard.removeObject(forKey: kAppleUserID)
                              : UserDefaults.standard.set(newValue, forKey: kAppleUserID) }
    }

    var appleEmail: String? {
        get { UserDefaults.standard.string(forKey: kAppleEmail) }
        set { newValue == nil ? UserDefaults.standard.removeObject(forKey: kAppleEmail)
                              : UserDefaults.standard.set(newValue, forKey: kAppleEmail) }
    }

    func clear() {
        [kAccess, kAppleUserID, kAppleEmail].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
    }

    /// Во Flutter email — ключ для профиля
    func currentEmail() -> String? {
        #if DEBUG
        // ⛔️ ВРЕМЕННО: форсим тестовый email для всех запросов
//        return "dmitriyt21@gmail.com"
        return "vasiariov@gmail.com"
        #else
        // на проде – как было
        return appleEmail?.removingPercentEncoding
        #endif
    }

}



