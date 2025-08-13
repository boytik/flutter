import SwiftUI

struct DemoPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password: String = ""
    @State private var isValidating = false
    @State private var error: String?

    let onSuccess: (Bool) -> Void

    private var demoPassword: String {
        (Bundle.main.object(forInfoDictionaryKey: "DEMO_PASSWORD") as? String) ?? "demo1234"
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Введите пароль").font(.title3.weight(.semibold))

            SecureField("пароль*", text: $password)
                .textContentType(.password)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

            if let error { Text(error).foregroundColor(.red) }

            Button {
                Task { await validate() }
            } label: {
                if isValidating { ProgressView().frame(maxWidth: .infinity).padding() }
                else { Text("Войти в demo режим").frame(maxWidth: .infinity).padding() }
            }
            .disabled(isValidating || password.isEmpty)
            .background(password.isEmpty ? Color.gray : Color.black)
            .foregroundColor(.white)
            .cornerRadius(12)

            Spacer()
        }
        .padding()
    }

    private func validate() async {
        error = nil
        isValidating = true
        defer { isValidating = false }

        if password == demoPassword {
            onSuccess(true)
            dismiss()
        } else {
            error = "Неверный пароль"
            onSuccess(false)
        }
    }
}
