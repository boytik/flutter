import Foundation

protocol ChatRepository {
    func ask(text: String) async throws -> String
    func askAudio(fileURL: URL) async throws -> String
}


final class ChatRepositoryImpl: ChatRepository {
    private let client = HTTPClient.shared
    
    struct AskRequest: Encodable { let question: String }
    struct AskResponse: Decodable { let answer: String }
    
    func ask(text: String) async throws -> String {
        let resp = try await client.request(AskResponse.self,
                                            url: ApiRoutes.Chat.question,
                                            method: .POST,
                                            body: AskRequest(question: text))
        return resp.answer
    }
    
    func askAudio(fileURL: URL) async throws -> String {
        let data = try Data(contentsOf: fileURL)
        
        try await client.uploadMultipart(
            url: ApiRoutes.Chat.questionAudio,
            fields: [:],
            parts: [
                .init(
                    name: "file",
                    filename: fileURL.lastPathComponent.isEmpty ? "question.m4a" : fileURL.lastPathComponent,
                    mime: "audio/m4a",
                    data: data
                )
            ]
        )
        return NSLocalizedString("audio_question_sent", comment: "Audio question sent")
    }
    
}
