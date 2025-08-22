import Foundation

protocol ChatRepository {
    func ask(text: String) async throws -> String
    func askAudio(fileURL: URL) async throws -> String
}

final class ChatRepositoryImpl: ChatRepository {
    private let client = HTTPClient.shared

    private struct AskRequest: Encodable { let question: String }
    private struct AskResponse: Decodable { let answer: String }

    // MARK: - Text
    func ask(text: String) async throws -> String {
        try await retrying {
            do {
                let resp = try await self.client.request(
                    AskResponse.self,
                    url: ApiRoutes.Chat.question,   // /ask на RAG
                    method: .POST,
                    body: AskRequest(question: text)
                )
                return resp.answer
            } catch let NetworkError.server(status, dataOpt) {
                if Self.shouldRetry(status: status) { throw RetryableError.transient(status: status) }
                let body = dataOpt.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let msg  = body.isEmpty
                    ? "Ошибка чата (\(status))."
                    : "Ошибка чата (\(status)). Ответ сервера: \(body)"
                throw NSError(domain: "Chat", code: status,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
        }
    }

    // MARK: - Audio
    func askAudio(fileURL: URL) async throws -> String {
        let data = try Data(contentsOf: fileURL)
        let ext  = fileURL.pathExtension
        let mime = Self.mimeType(for: ext)

        return try await retrying {
            do {
                try await self.client.uploadMultipart(
                    url: ApiRoutes.Chat.questionAudio,
                    fields: [:],
                    parts: [
                        .init(
                            name: "audio_file",
                            filename: fileURL.lastPathComponent.isEmpty
                                ? "question.\(ext.isEmpty ? "m4a" : ext)"
                                : fileURL.lastPathComponent,
                            mime: mime,
                            data: data
                        )
                    ]
                )
                return NSLocalizedString("audio_question_sent", comment: "Audio question sent")
            } catch let NetworkError.server(status, dataOpt) {
                if Self.shouldRetry(status: status) { throw RetryableError.transient(status: status) }
                let body = dataOpt.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let msg  = body.isEmpty
                    ? "Ошибка загрузки аудио (\(status))."
                    : "Ошибка загрузки аудио (\(status)). Ответ сервера: \(body)"
                throw NSError(domain: "Chat", code: status,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
        }
    }

    // MARK: - Retry helpers
    private enum RetryableError: Error { case transient(status: Int) }

    private static func shouldRetry(status: Int) -> Bool {
        status == 502 || status == 503 || status == 504
    }

    /// 3 попытки: 0s → 1s → 2s
    private func retrying<T>(_ block: @escaping () async throws -> T) async throws -> T {
        var attempt = 0
        var lastError: Error?
        let delays: [UInt64] = [0, 1_000_000_000, 2_000_000_000] // наносекунды

        while attempt < delays.count {
            do {
                if delays[attempt] > 0 { try await Task.sleep(nanoseconds: delays[attempt]) }
                return try await block()
            } catch RetryableError.transient {
                lastError = NSError(domain: "Chat", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Сервис временно недоступен. Повторяем…"])
                attempt += 1
                continue
            } catch {
                lastError = error
                break
            }
        }
        throw lastError ?? NSError(domain: "Chat", code: -1,
                                   userInfo: [NSLocalizedDescriptionKey: "Не удалось отправить запрос."])
    }

    // MARK: - MIME
    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "m4a": return "audio/m4a"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "aac": return "audio/aac"
        case "caf": return "audio/x-caf"
        case "mp4": return "audio/mp4"
        default:    return "application/octet-stream"
        }
    }
}
