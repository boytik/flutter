import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let date: Date
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var input: String = ""
    @Published var messages: [ChatMessage] = []
    @Published var isSending = false
    @Published var error: String?

    let repo: ChatRepository

    init(repo: ChatRepository = ChatRepositoryImpl()) {
        self.repo = repo
    }

    func sendText() async {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        input = ""
        messages.append(.init(text: question, isUser: true, date: Date()))
        isSending = true
        error = nil
        defer { isSending = false }

        do {
            let answer = try await repo.ask(text: question)
            messages.append(.init(text: answer, isUser: false, date: Date()))
        } catch {
            self.error = error.localizedDescription
        }
    }

    func sendAudio(fileURL: URL) async {
        isSending = true
        error = nil
        defer { isSending = false }
        do {
            let answer = try await repo.askAudio(fileURL: fileURL)
            messages.append(.init(text: answer, isUser: false, date: Date()))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

