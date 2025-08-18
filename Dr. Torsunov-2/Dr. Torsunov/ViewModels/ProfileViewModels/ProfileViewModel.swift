import SwiftUI
import UIKit

@MainActor
final class ProfileViewModel: ObservableObject {
    // то, что у тебя уже было
    @Published var personalVM: PersonalViewModel
    @Published var showPhotoPicker = false
    @Published var photoSource: PhotoSource? = nil
    @Published var appVersion: String = "1.0.0"

    // новое для отображения
    @Published var avatar: UIImage? = nil
    @Published var isLoadingAvatar = false

    // можно оставить, если где-то ещё нужен локальный файл (в UI больше не используется)
    @Published var photoURL: URL? = nil

    // оффлайн
    private let ns = "user_profile"
    private let kvKeyAvatar = "avatar_image"           // храним Data (jpeg/png)
    private let kvTTLAvatar: TimeInterval = 60 * 60 * 24 // 24 часа

    init() {
        let physicalVM = PhysicalDataViewModel()
        self.personalVM = PersonalViewModel(physicalDataVM: physicalVM)
    }

    /// Подтянуть профиль и аватар:
    /// 1) оффлайн изображение из KV (если есть)
    /// 2) свежий профиль с сервера и аватар base64 → сохранить в KV
    func loadUserAndAvatar() {
        isLoadingAvatar = true
        Task {
            defer { isLoadingAvatar = false }

            // 1) оффлайн
            if let cached: Data = try? KVStore.shared.get(Data.self, namespace: ns, key: kvKeyAvatar),
               let img = UIImage(data: cached) {
                self.avatar = img
                print("📦 KV HIT \(ns)/\(kvKeyAvatar) (\(cached.count) bytes)")
            }

            // 2) сеть
            do {
                let user = try await personalVM.userRepository.getUser()
                if let b64 = user.avatarImageBase64, !b64.isEmpty,
                   let (img, raw) = Self.decodeBase64AvatarAndData(b64) {
                    self.avatar = img
                    try? KVStore.shared.put(raw, namespace: ns, key: kvKeyAvatar, ttl: kvTTLAvatar)
                    print("💾 KV SAVE \(ns)/\(kvKeyAvatar) (\(raw.count) bytes)")
                } else {
                    self.avatar = nil
                    try? KVStore.shared.delete(namespace: ns, key: kvKeyAvatar)
                }
            } catch {
                print("❌ Не удалось загрузить профиль/аватар:", error.localizedDescription)
            }
        }
    }

    /// Пользователь выбрал фото: сразу показать, сохранить (опц.), залить на сервер
    func setPhoto(_ image: UIImage) {
        // мгновенно обновляем UI
        self.avatar = image

        // (опционально) сохраняем локально — вдруг нужно ещё где-то
        if let data = image.jpegData(compressionQuality: 0.8),
           let url = FileManager.default.saveToDocuments(data: data, filename: "profile_photo.jpg") {
            self.photoURL = url
        } else {
            print("⚠️ Не удалось сохранить фото локально")
        }

        // отправка на сервер и обновление оффлайна
        Task {
            do {
                try await personalVM.userRepository.uploadAvatar(image)
                print("✅ Аватар успешно загружен на сервер")

                if let data = image.jpegData(compressionQuality: 0.9) {
                    try? KVStore.shared.put(data, namespace: ns, key: kvKeyAvatar, ttl: kvTTLAvatar)
                    print("💾 KV SAVE \(ns)/\(kvKeyAvatar) (\(data.count) bytes)")
                }
                // подтянем профиль для консистентности
                self.loadUserAndAvatar()
            } catch {
                print("❌ Ошибка при загрузке аватара:", error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    private static func decodeBase64AvatarAndData(_ raw: String) -> (UIImage, Data)? {
        // иногда приходит с префиксом data:image/jpeg;base64,
        let pure = raw.contains(",") ? String(raw.split(separator: ",").last!) : raw
        guard let data = Data(base64Encoded: pure, options: .ignoreUnknownCharacters),
              let img = UIImage(data: data) else { return nil }
        return (img, data)
    }

    func clearAvatarOffline() {
        try? KVStore.shared.delete(namespace: ns, key: kvKeyAvatar)
        print("🧹 KV DELETE \(ns)/\(kvKeyAvatar)")
    }
}

enum PhotoSource: Identifiable {
    case camera, gallery
    var id: String { self == .camera ? "camera" : "gallery" }
}
