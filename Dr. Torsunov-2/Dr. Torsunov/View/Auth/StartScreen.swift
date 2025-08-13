
import SwiftUI
import AuthenticationServices

struct StartScreen: View {
    @EnvironmentObject var auth: AppAuthState
    private let authRepo = AuthenticationRepositoryImpl()

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("My Revive")
                .font(.largeTitle.bold())
                .foregroundColor(.white)

            Spacer()

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    handle(authorization: authorization)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 48)
            .cornerRadius(10)
            .padding(.horizontal, 24)

            Button {
                Task {
                    let ok = await authRepo.loginDemo()
                    if ok { auth.enterDemo() }
                }
            } label: {
                Text("Продолжить как гость")
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(10)
                    .padding(.horizontal, 24)
            }

            if let msg = errorMessage {
                Text(msg)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func handle(authorization: ASAuthorization) {
        guard
            let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = cred.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else {
            errorMessage = "Не удалось получить idToken Apple"
            return
        }

        let email = cred.email ?? extractEmail(from: idToken)
        if let email { TokenStorage.shared.appleEmail = email }
        TokenStorage.shared.appleUserId = cred.user

        Task {
            let ok = await authRepo.loginWithApple(idToken: idToken, appleUserId: cred.user)
            await MainActor.run {
                if ok { auth.markLoggedIn() } else { errorMessage = "Авторизация через Apple не удалась" }
            }
        }
    }


    private func extractEmail(from idToken: String) -> String? {
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        func base64urlToData(_ s: Substring) -> Data? {
            var str = String(s)
            str = str.replacingOccurrences(of: "-", with: "+")
                     .replacingOccurrences(of: "_", with: "/")
            let pad = 4 - (str.count % 4)
            if pad < 4 { str += String(repeating: "=", count: pad) }
            return Data(base64Encoded: str)
        }
        guard let payloadData = base64urlToData(parts[1]),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else { return nil }
        return json["email"] as? String
    }

}

