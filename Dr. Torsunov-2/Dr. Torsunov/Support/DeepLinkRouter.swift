import Foundation
import Combine

enum DeepLink {
    case workout(id: String)
    case activities
    case profile
    case unknown
}

final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    @Published var last: DeepLink = .unknown

    func handle(url: URL) {
        guard url.scheme == "myrevive" else { return }
        let path = url.path 

        if path.hasPrefix("/workouts/") {
            let id = String(path.split(separator: "/").last ?? "")
            last = .workout(id: id)
        } else if path == "/activities" {
            last = .activities
        } else if path == "/profile" {
            last = .profile
        } else {
            last = .unknown
        }

        NotificationCenter.default.post(name: .didReceiveDeepLink, object: last)
    }
}

extension Notification.Name {
    static let didReceiveDeepLink = Notification.Name("didReceiveDeepLink")
}
