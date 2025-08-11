
import SwiftUI
import UIKit

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var personalVM: PersonalViewModel
    @Published var photoURL: URL? = nil
    @Published var showPhotoPicker = false
    @Published var photoSource: PhotoSource? = nil
    @Published var appVersion: String = "1.0.0"

    init() {
        let physicalVM = PhysicalDataViewModel()
        self.personalVM = PersonalViewModel(
            physicalDataVM: physicalVM
        )
    }

    func setPhoto(_ image: UIImage) {
        // локальное сохранение
        if let data = image.jpegData(compressionQuality: 0.8),
           let url = FileManager.default.saveToDocuments(data: data, filename: "profile_photo.jpg") {
            photoURL = url
        }

        // отправка на сервер — async/await
        Task {
            do {
                try await personalVM.userRepository.uploadAvatar(image)
                print("✅ Аватар успешно загружен на сервер")
            } catch {
                print("❌ Ошибка при загрузке аватара:", error.localizedDescription)
            }
        }
    }
}


enum PhotoSource: Identifiable {
    case camera, gallery

    var id: String {
        switch self {
        case .camera: return "camera"
        case .gallery: return "gallery"
        }
    }
}




