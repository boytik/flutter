import SwiftUI
import UIKit

struct TapBarView: View {
    @State private var selectedTab = 1
    @StateObject private var bt = BluetoothManager.shared
    private let uploadPump = BLEUploadPump()
    @Environment(\.scenePhase) private var scenePhase

    // диплинк «app://chat» будет открывать чат во вкладке Профиля
    @State private var openChatDeepLink = false

    var body: some View {
        let content = TabView(selection: $selectedTab) {
            // 0 — Тренировки
            NavigationStack {
                TrainingView()
                    .onAppear { openOtherAppOrStore() }
            }
            .tabItem { Label("tab_workouts", systemImage: "figure.run") }
            .tag(0)

            // 1 — Календарь
            NavigationStack { CalendarView() }
                .tabItem { Label("tab_calendar", systemImage: "calendar") }
                .tag(1)

            // 2 — Профиль (с кнопкой «Чат» внутри)
            ProfileScreen(openChat: $openChatDeepLink)
                .tabItem { Label("tab_profile", systemImage: "person.circle") }
                .tag(2)
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
        // диплинки вида app://chat, torsunov://chat и т.п.
        .onOpenURL { url in
            if url.host?.lowercased() == "chat" || url.absoluteString.lowercased().contains("/chat") {
                selectedTab = 2
                openChatDeepLink = true
            }
        }

        if #available(iOS 17.0, *) {
            content
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active: bt.activateIfNeeded()
                    case .inactive, .background: bt.stopScanning()
                    @unknown default: break
                    }
                }
        } else {
            content
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active: bt.activateIfNeeded()
                    case .inactive, .background: bt.stopScanning()
                    @unknown default: break
                    }
                }
        }
    }

    private func openOtherAppOrStore() {
        let appScheme = "otherappscheme://"
        let appStoreURL = "https://apps.apple.com/kz/app/my-revive/id/6743324076"
        if let schemeURL = URL(string: appScheme) {
            UIApplication.shared.open(schemeURL, options: [:]) { success in
                if !success, let storeURL = URL(string: appStoreURL) {
                    UIApplication.shared.open(storeURL)
                }
            }
        }
    }
}
