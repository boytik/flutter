import SwiftUI
import AuthenticationServices
import UIKit

struct SignInView: View {
    @State private var isLoading = false
    @State private var error: String?
    @State private var loggedIn = false

    let authRepo = AuthenticationRepositoryImpl()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Добро пожаловать в My Revive")
                .font(.title2.bold())
                .foregroundColor(.white)

            if let error {
                Text(error).foregroundColor(.red).multilineTextAlignment(.center)
            }

            if isLoading {
                ProgressView().tint(.white)
            } else {
                SignInWithAppleButton()
            }
            Spacer()
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
    }

    @ViewBuilder
    private func SignInWithAppleButton() -> some View {
        SignInWithAppleButtonRepresentable {
            Task {
                await handleAppleSignIn()
            }
        }
        .frame(height: 52)
        .cornerRadius(12)
    }

    private func handleAppleSignIn() async {
        error = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let idToken = try await AppleSignIn().start()
            let ok = await authRepo.loginWithApple(idToken: idToken)
            loggedIn = ok
            if !ok { error = "Не удалось войти через Apple" }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SignInWithAppleButtonRepresentable: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let btn = ASAuthorizationAppleIDButton(type: .signIn, style: .black) 
        btn.addTarget(context.coordinator,
                      action: #selector(Coordinator.tap),
                      for: UIControl.Event.touchUpInside)
        return btn
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}


