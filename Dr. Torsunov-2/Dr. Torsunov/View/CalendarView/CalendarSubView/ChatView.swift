import SwiftUI

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

struct ChatView: View {
    let messages: [ChatMessage]
    @State private var inputText = ""

    /// Передай сюда свою логику, как определить «моё» сообщение.
    var isMine: (ChatMessage) -> Bool = { _ in false }

    var body: some View {
        VStack(spacing: 0) {
            MessagesList(messages: messages, isMine: isMine)
            ComposerBar(text: $inputText) { send() }
        }
    }

    private func send() {
        // TODO: отправка сообщения и очистка inputText
    }
}

private struct MessagesList: View {
    let messages: [ChatMessage]
    var isMine: (ChatMessage) -> Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(messages, id: \.id) { m in
                    MessageRow(message: m, mine: isMine(m))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let mine: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if mine {
                Spacer()
                Bubble(text: message.text, isMine: true)
            } else {
                Bubble(text: message.text, isMine: false)
                Spacer()
            }
        }
    }
}

private struct Bubble: View {
    let text: String
    let isMine: Bool

    var body: some View {
        Text(text)
            .padding(12)
            .background(isMine ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(maxWidth: 280, alignment: .leading)
    }
}

private struct ComposerBar: View {
    @Binding var text: String
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField(L("chat_input_placeholder"), text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            Button(action: { onSend() }) {
                Text(L("send"))
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }
}


