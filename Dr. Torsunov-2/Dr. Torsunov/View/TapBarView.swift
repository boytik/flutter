import SwiftUI
import UIKit

struct TapBarView: View {
    @State private var selectedTab = 1

    var body: some View {
        TabView(selection: $selectedTab) {
            // Workouts
            NavigationStack {
                TrainingView()
                    .onAppear { openOtherAppOrStore() }
            }
            .tabItem { Label("tab_workouts", systemImage: "figure.run") }
            .tag(0)

            // Calendar
            NavigationStack {
                CalendarView()
            }
            .tabItem { Label("tab_calendar", systemImage: "calendar") }
            .tag(1)

            // Chat
            NavigationStack {
                ChatView(messages: [])
            }
            .tabItem { Label("tab_chat", systemImage: "bubble.left.and.bubble.right") }
            .tag(2)

            // Profile
            NavigationStack {
                ProfileView(viewModel: ProfileViewModel())
            }
            .tabItem { Label("tab_profile", systemImage: "person.circle") }
            .tag(3)

            // NEW: Bluetooth tab
            NavigationStack {
                BLEScanView()
                    .navigationTitle("Bluetooth")
            }
            .tabItem { Label("tab_bluetooth", systemImage: "dot.radiowaves.left.and.right") }
            .tag(4)
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




