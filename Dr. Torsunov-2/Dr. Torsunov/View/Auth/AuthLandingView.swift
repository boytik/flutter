import SwiftUI
import AuthenticationServices

struct AuthLandingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AppAuthState
    private let authRepo = AuthenticationRepositoryImpl()

    @State private var isLoading = false
    @State private var error: String?
    @State private var showDemo = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
//            Image("auth_bg")
//                .resizable()
//                .scaledToFill()
//                .ignoresSafeArea()

            // Поддержка
            Button {
                UIApplication.shared.open(ApiRoutes.StaticLinks.support)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "headphones")
                    Text("Поддержка")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14).stroke(Color.green))
            }
            .padding(.top, 10).padding(.trailing, 12)

            VStack(spacing: 16) {
                Spacer()

                if isLoading { ProgressView().tint(.white) }

                // DEMO
                Button("Войти в demo режим") { showDemo = true }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding(.horizontal, 24)

                // Apple
                SignInWithAppleButtonRepresentable {
                    Task { await handleApple() }
                }
                .frame(height: 52)
                .cornerRadius(12)
                .padding(.horizontal, 24)

                if let error { Text(error).foregroundColor(.red).padding(.horizontal, 24) }

                // Terms / Privacy
                consentText
            }
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showDemo) {
            DemoPasswordView { success in
                if success {
                    auth.enterDemo()
                    dismiss()
                }
            }
            .applyDetentsCompat() // см. расширение ниже
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
            }
        }
    }

    @ViewBuilder
    private var consentText: some View {
        VStack(spacing: 8) {
            Text("Продолжая, Вы соглашаетесь с")
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
            HStack(spacing: 6) {
                Link("Правилами и условиями", destination: ApiRoutes.StaticLinks.terms)
                Text("и")
                    .foregroundColor(.white.opacity(0.9))
                    .font(.caption)
                Link("Политикой конфиденциальности", destination: ApiRoutes.StaticLinks.privacy)
            }
            .font(.caption.weight(.semibold))
        }
    }

    private func handleApple() async {
        error = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let idToken = try await AppleSignIn().start()
            let ok = await authRepo.loginWithApple(idToken: idToken)
            if ok {
                auth.markLoggedIn()
                dismiss()
            } else {
                error = "Не удалось войти через Apple"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// iOS 16.0–16.3 нет .fraction — делаем совместимый модификатор
private extension View {
    @ViewBuilder
    func applyDetentsCompat() -> some View {
        if #available(iOS 16.4, *) {
            self.presentationDetents([.fraction(0.55)])
        } else {
            self.presentationDetents([.medium])
        }
    }
}
