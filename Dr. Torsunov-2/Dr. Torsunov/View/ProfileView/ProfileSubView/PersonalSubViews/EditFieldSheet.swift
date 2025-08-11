

import SwiftUI
import SwiftUI

struct EditFieldSheet: View {
    var title: String
    @Binding var text: String
    var placeholder: String
    var onSave: ((String) -> Void)? = nil

    @Environment(\.dismiss) var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            HStack(alignment: .center) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .tint(.red)
                }
                .padding(.trailing, 16)
                Spacer()
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.top, 40)

            VStack(spacing: 8) {
                TextField("", text: $text)
                    .placeholder(when: text.isEmpty) {
                        Text(placeholder)
                            .foregroundColor(.gray)
                    }
                    .foregroundColor(.white)
                    .font(.system(size: 17))
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .focused($isFocused)

                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.gray.opacity(0.5))
                    .padding(.horizontal, 16)
            }

            Button(action: {
                onSave?(text)
                dismiss()
            }) {
                Text("Сохранить")
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(text.isEmpty ? Color.gray.opacity(0.3) : Color.white.opacity(0.1))
                    .cornerRadius(8)
            }
            .disabled(text.isEmpty)
            .padding(.horizontal, 16)
            
            Spacer()
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isFocused = true
            }
        }
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

