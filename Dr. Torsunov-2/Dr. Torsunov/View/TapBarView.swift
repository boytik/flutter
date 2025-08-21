import SwiftUI
import UIKit

struct TapBarView: View {
    @State private var selectedTab = 1
    @StateObject private var bt = BluetoothManager.shared
    private let uploadPump = BLEUploadPump()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let content = TabView(selection: $selectedTab) {
            NavigationStack {
                TrainingView()
                    .onAppear { openOtherAppOrStore() }
            }
            .tabItem { Label("tab_workouts", systemImage: "figure.run") }
            .tag(0)

            NavigationStack { CalendarView() }
            .tabItem { Label("tab_calendar", systemImage: "calendar") }
            .tag(1)

            NavigationStack { ChatView(messages: []) }
            .tabItem { Label("tab_chat", systemImage: "bubble.left.and.bubble.right") }
            .tag(2)

            NavigationStack { ProfileView(viewModel: ProfileViewModel()) }
            .tabItem { Label("tab_profile", systemImage: "person.circle") }
            .tag(3)
        }
        .onAppear {
            bt.activateIfNeeded()
            let provider = BluetoothManagerJSONAdapter(manager: bt)
            uploadPump.start(with: provider)
        }
        .onDisappear {
            uploadPump.stop()
            bt.stopScanning()
        }

        // Корректная обработка жизненного цикла со свежим onChange
        if #available(iOS 17.0, *) {
            content
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        bt.activateIfNeeded()
                    case .inactive, .background:
                        bt.stopScanning()
                    @unknown default:
                        break
                    }
                }
        } else {
            content
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active:
                        bt.activateIfNeeded()
                    case .inactive, .background:
                        bt.stopScanning()
                    @unknown default:
                        break
                    }
                }
        }
    }

    private func openOtherAppOrStore() {
        let appScheme = "otherappscheme://"
        let appStoreURL = "https://apps.apple.com/kz/app/my-revive/id6743324076"
        if let schemeURL = URL(string: appScheme) {
            UIApplication.shared.open(schemeURL, options: [:]) { success in
                if !success, let storeURL = URL(string: appStoreURL) {
                    UIApplication.shared.open(storeURL)
                }
            }
        }
    }
}
