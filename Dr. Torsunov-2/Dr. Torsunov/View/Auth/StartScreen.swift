import SwiftUI

struct StartScreen: View {
    @EnvironmentObject var auth: AppAuthState
    @State private var showAuth = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Image("auth_bg") // поставь свой фон
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Button {
                    showAuth = true
                } label: {
                    Text("Войти")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                        .padding(.horizontal, 24)
                }

                Text(appVersionString())
                    .font(.caption.italic())
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showAuth) {
            AuthLandingView()
                .environmentObject(auth)
        }
    }

    private func appVersionString() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v \(v)(\(b))"
    }
}
