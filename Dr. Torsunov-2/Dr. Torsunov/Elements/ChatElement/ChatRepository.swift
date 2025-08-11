import Foundation

protocol ChatRepository {
    func ask(text: String) async throws -> String
    func askAudio(fileURL: URL) async throws -> String
}
