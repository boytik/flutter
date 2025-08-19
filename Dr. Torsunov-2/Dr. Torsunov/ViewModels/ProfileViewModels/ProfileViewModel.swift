import SwiftUI
import UIKit
import OSLog

@MainActor
final class ProfileViewModel: ObservableObject {
    // MARK: - Состояние
    @Published var personalVM: PersonalViewModel
    @Published var showPhotoPicker = false
    @Published var photoSource: PhotoSource? = nil
    @Published var appVersion: String = "1.0.0"

    @Published var avatar: UIImage? = nil
    @Published var isLoadingAvatar = false
    @Published var photoURL: URL? = nil

    // MARK: - KVStore (offline)
    private let ns = "user_profile"
    private let kvKeyAvatar = "avatar_image"
    private let kvTTLAvatar: TimeInterval = 60 * 60 * 24

    // MARK: - Логгер
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app",
                             category: "ProfileVM")

    // MARK: - Init
    init() {
        let physicalVM = PhysicalDataViewModel()
        self.personalVM = PersonalViewModel(physicalDataVM: physicalVM)
    }

    // MARK: - Профиль и аватар
    func loadUserAndAvatar() {
        self.isLoadingAvatar = true
        Task { [weak self] in
            await self?.loadUserAndAvatarAsync()
        }
    }

    private func loadUserAndAvatarAsync() async {
        defer { self.isLoadingAvatar = false }

        if let cached: Data = try? KVStore.shared.get(Data.self, namespace: self.ns, key: self.kvKeyAvatar),
           let img = UIImage(data: cached) {
            self.avatar = img
            log.debug("[KV] HIT \(self.ns)/\(self.kvKeyAvatar) bytes=\(cached.count)")
        }

        do {
            let user = try await self.personalVM.userRepository.getUser()
            if let b64 = user.avatarImageBase64, !b64.isEmpty,
               let (img, raw) = Self.decodeBase64AvatarAndData(b64) {
                self.avatar = img
                try? KVStore.shared.put(raw, namespace: self.ns, key: self.kvKeyAvatar, ttl: self.kvTTLAvatar)
                log.debug("[KV] SAVE \(self.ns)/\(self.kvKeyAvatar) bytes=\(raw.count)")
            } else {
                self.avatar = nil
                try? KVStore.shared.delete(namespace: self.ns, key: self.kvKeyAvatar)
                log.info("[KV] DELETE \(self.ns)/\(self.kvKeyAvatar)")
            }
        } catch {
            log.error("[Avatar] load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    func setPhoto(_ image: UIImage) {
        self.avatar = image
        if let data = image.jpegData(compressionQuality: 0.8),
           let url = FileManager.default.saveToDocuments(data: data, filename: "profile_photo.jpg") {
            self.photoURL = url
        } else {
            log.warning("[Photo] local save failed")
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.personalVM.userRepository.uploadAvatar(image)
                log.info("[Avatar] uploaded")

                if let data = image.jpegData(compressionQuality: 0.9) {
                    try? KVStore.shared.put(data, namespace: self.ns, key: self.kvKeyAvatar, ttl: self.kvTTLAvatar)
                    log.debug("[KV] SAVE \(self.ns)/\(self.kvKeyAvatar) bytes=\(data.count)")
                }
                await self.loadUserAndAvatarAsync()
            } catch {
                log.error("[Avatar] upload failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Helpers

    private static func decodeBase64AvatarAndData(_ raw: String) -> (UIImage, Data)? {
        let pure = raw.contains(",") ? String(raw.split(separator: ",").last!) : raw
        guard let data = Data(base64Encoded: pure, options: .ignoreUnknownCharacters),
              let img = UIImage(data: data) else { return nil }
        return (img, data)
    }

    func clearAvatarOffline() {
        try? KVStore.shared.delete(namespace: self.ns, key: self.kvKeyAvatar)
        log.info("[KV] DELETE \(self.ns)/\(self.kvKeyAvatar)")
    }
}

enum PhotoSource: Identifiable {
    case camera, gallery
    var id: String { self == .camera ? "camera" : "gallery" }
}
