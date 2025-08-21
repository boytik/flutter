import SwiftUI

struct ChatView: View {
    @StateObject private var vm: ChatViewModel
    @FocusState private var focusInput: Bool

    // совместимость с существующим вызовом ChatView(messages: [])
    init(messages: [ChatMessage] = []) {
        _vm = StateObject(wrappedValue: ChatViewModel(initialMessages: messages))
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // Сообщения
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.messages) { msg in
                            ChatBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .background(Color.black)
                // iOS 17+: два параметра; iOS 16: один параметр
                .modifier(ScrollToBottomOnMessagesChange(vm: vm, proxy: proxy))

                Divider().overlay(Color.white.opacity(0.1))

                // Инпут
                inputBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.black)
            }
            .toolbarTitleDisplayMode(.inline)
            .navigationTitle("Чат")
            .background(Color.black.ignoresSafeArea())
            .overlay(alignment: .top) {
                if let err = vm.errorBanner {
                    Text(err)
                        .font(.footnote)
                        .padding(8)
                        .background(Color.red.opacity(0.9), in: Capsule())
                        .foregroundColor(.white)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Mic
            Button {
                Task { await vm.toggleRecording() }
            } label: {
                Image(systemName: vm.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(vm.isRecording ? .red : .green)
            }
            .buttonStyle(.plain)

            // TextField
            ZStack(alignment: .leading) {
                if vm.input.isEmpty {
                    Text("Напишите сообщение…")
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                TextField("", text: $vm.input, axis: .vertical)
                    .focused($focusInput)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(false)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )

            // Send
            Button {
                Task { await vm.sendText() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isSending ? .gray : .green)
            }
            .disabled(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isSending)
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Модификатор для кросс-версии onChange
private struct ScrollToBottomOnMessagesChange: ViewModifier {
    @ObservedObject var vm: ChatViewModel
    let proxy: ScrollViewProxy

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.onChange(of: vm.messages.count) { _, newCount in
                guard newCount > 0, let last = vm.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        } else {
            content.onChange(of: vm.messages.count) { _ in
                if let last = vm.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Сообщение (пузырь)
private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .bot {
                bubble
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubble
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.text)
                .foregroundColor(message.role == .user ? .black : .white)
                .font(.body)

            HStack(spacing: 6) {
                if let err = message.error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text(err).lineLimit(1)
                } else if message.isPending {
                    ProgressView().scaleEffect(0.7)
                    Text("...")
                } else {
                    Text(message.date, style: .time)
                }
            }
            .font(.caption2)
            .foregroundColor(message.role == .user ? .black.opacity(0.7) : .white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            message.role == .user
            ? AnyView(RoundedRectangle(cornerRadius: 14).fill(Color.green))
            : AnyView(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(message.role == .user ? Color.green.opacity(0.4) : Color.white.opacity(0.12), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}
