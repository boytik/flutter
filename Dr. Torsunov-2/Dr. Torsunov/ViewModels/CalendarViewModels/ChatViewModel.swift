import SwiftUI
import Foundation

enum ChatRole: String, Codable {
    case user
    case bot
}

struct ChatMessage: Identifiable, Hashable, Codable {
    let id: UUID
    let role: ChatRole
    var text: String
    var date: Date
    var isPending: Bool
    var error: String?

    init(id: UUID = UUID(),
         role: ChatRole,
         text: String,
         date: Date = Date(),
         isPending: Bool = false,
         error: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.isPending = isPending
        self.error = error
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var input: String = ""
    @Published var isSending = false
    @Published var isRecording = false
    @Published var errorBanner: String?

    private let repo: ChatRepository
    private let recorder = AudioRecorder()

    init(initialMessages: [ChatMessage] = [],
         repo: ChatRepository = ChatRepositoryImpl()) {
        self.messages = initialMessages
        self.repo = repo
    }

    func sendText() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        input = ""

        let userMsg = ChatMessage(role: .user, text: text)
        messages.append(userMsg)

        var pendingBot = ChatMessage(role: .bot, text: "…", isPending: true)
        messages.append(pendingBot)
        isSending = true

        do {
            let answer = try await repo.ask(text: text)
            if let idx = messages.firstIndex(where: { $0.id == pendingBot.id }) {
                pendingBot.text = answer
                pendingBot.isPending = false
                messages[idx] = pendingBot
            }
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == pendingBot.id }) {
                pendingBot.text = "Ошибка отправки. Повторите позже."
                pendingBot.isPending = false
                pendingBot.error = error.localizedDescription
                messages[idx] = pendingBot
            }
            errorBanner = error.localizedDescription
        }
        isSending = false
    }

    func toggleRecording() async {
        if isRecording {
            recorder.stop()
            isRecording = false
            await sendAudioIfAvailable()
        } else {
            let allowed = await recorder.requestPermission()
            guard allowed else {
                errorBanner = "Нет доступа к микрофону."
                return
            }
            do {
                try recorder.start()
                isRecording = true
            } catch {
                errorBanner = "Не удалось начать запись: \(error.localizedDescription)"
            }
        }
    }

    private func sendAudioIfAvailable() async {
        guard let url = recorder.lastFileURL else { return }
        guard !isSending else { return }

        let userMsg = ChatMessage(role: .user, text: "🎤 Голосовое сообщение")
        messages.append(userMsg)

        var pendingBot = ChatMessage(role: .bot, text: "Отправляю аудио…", isPending: true)
        messages.append(pendingBot)
        isSending = true

        do {
            let serverText = try await repo.askAudio(fileURL: url)
            if let idx = messages.firstIndex(where: { $0.id == pendingBot.id }) {
                pendingBot.text = serverText.isEmpty ? "Аудио отправлено" : serverText
                pendingBot.isPending = false
                messages[idx] = pendingBot
            }
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == pendingBot.id }) {
                pendingBot.text = "Ошибка отправки аудио."
                pendingBot.isPending = false
                pendingBot.error = error.localizedDescription
                messages[idx] = pendingBot
            }
            errorBanner = error.localizedDescription
        }
        isSending = false
    }
}


