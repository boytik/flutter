
import SwiftUI
import Combine

@main
struct Dr__TorsunovApp: App {
    @StateObject var auth = AppAuthState()
    
    init() {
        segmentStyle()
        tapBarStyle()
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
              if auth.isLoggedIn || auth.isDemo {
                TapBarView()
              } else {
                  StartScreen()
              }
            }
            .environmentObject(auth)
            .onReceive(NotificationCenter.default.publisher(for: .didReceiveDeepLink)) { note in
                guard let link = note.object as? DeepLink else { return }
                switch link {
                case .workout(_):
                    break
                case .activities:
                    break
                case .profile:
                    break
                case .unknown:
                    break
                }
            }

            .onOpenURL { url in
                DeepLinkRouter.shared.handle(url: url)
            }

        }
    }
    
    private func segmentStyle() {
        let appearance = UISegmentedControl.appearance()
        appearance.selectedSegmentTintColor = UIColor.green
        appearance.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        appearance.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        appearance.backgroundColor = UIColor.tapBar
    }
    
    private func tapBarStyle(){
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "TapBar")
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
