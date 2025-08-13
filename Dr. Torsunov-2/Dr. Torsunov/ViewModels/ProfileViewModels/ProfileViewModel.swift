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

    init() {
        let physicalVM = PhysicalDataViewModel()
        self.personalVM = PersonalViewModel(physicalDataVM: physicalVM)
    }

    /// Подтянуть профиль и расшифровать base64-аватар
    func loadUserAndAvatar() {
        isLoadingAvatar = true
        Task {
            defer { isLoadingAvatar = false }
            do {
                let user = try await personalVM.userRepository.getUser() // ← уже есть в проекте
                if let b64 = user.avatarImageBase64, !b64.isEmpty {
                    self.avatar = Self.decodeBase64Avatar(b64)
                } else {
                    self.avatar = nil
                }
            } catch {
                print("❌ Не удалось загрузить профиль/аватар:", error.localizedDescription)
                self.avatar = nil
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

        // отправка на сервер по существующему API (PATCH avatar_image base64)
        Task {
            do {
                try await personalVM.userRepository.uploadAvatar(image) // уже реализовано
                print("✅ Аватар успешно загружен на сервер")
                // подтягиваем профиль, чтобы синхронизировать серверное состояние (дата изменения и т.п.)
                self.loadUserAndAvatar()
            } catch {
                print("❌ Ошибка при загрузке аватара:", error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    private static func decodeBase64Avatar(_ raw: String) -> UIImage? {
        // иногда приходит с префиксом data:image/jpeg;base64,
        let pure = raw.contains(",") ? String(raw.split(separator: ",").last!) : raw
        guard let data = Data(base64Encoded: pure, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }
}

enum PhotoSource: Identifiable {
    case camera, gallery
    var id: String { self == .camera ? "camera" : "gallery" }
}




