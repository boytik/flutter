import SwiftUI

struct ProfileScreen: View {
    @Binding var openChat: Bool
    @State private var showChat = false

    var body: some View {
        NavigationStack {
            ProfileView(viewModel: ProfileViewModel())
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showChat = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                Text("Чат")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .navigationDestination(isPresented: $showChat) {
                    ChatView(messages: [])
                        .navigationTitle("Чат")
                        .navigationBarTitleDisplayMode(.inline)
                }
        }
        .modifier(OpenChatOnChange(openChat: $openChat, showChat: $showChat))
    }
}

// MARK: - Универсальный onChange для iOS 16/17
private struct OpenChatOnChange: ViewModifier {
    @Binding var openChat: Bool
    @Binding var showChat: Bool

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.onChange(of: openChat) { _, newValue in
                if newValue {
                    showChat = true
                    openChat = false
                }
            }
        } else {
            content.onChange(of: openChat) { newValue in
                if newValue {
                    showChat = true
                    openChat = false
                }
            }
        }
    }
}
