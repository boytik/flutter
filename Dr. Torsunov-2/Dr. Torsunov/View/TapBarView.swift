
import SwiftUI
import UIKit

struct TapBarView: View {
    @State private var selectedTab = 1

    var body: some View {
        TabView(selection: $selectedTab) {
            TrainingView()
                .tabItem {
                    Label("tab_workouts", systemImage: "figure.run") // <- ключ
                }
                .tag(0)
                .onAppear { openOtherAppOrStore() }

            CalendarView()
                .tabItem {
                    Label("tab_calendar", systemImage: "calendar")   // <- ключ
                }
                .tag(1)

            ChatView(messages: [])
                .tabItem {
                    Label("tab_chat", systemImage: "bubble.left.and.bubble.right") // <- ключ
                }
                .tag(2)
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





