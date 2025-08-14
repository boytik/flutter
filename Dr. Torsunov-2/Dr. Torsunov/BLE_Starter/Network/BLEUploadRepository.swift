
import Foundation

protocol BLEUploadRepository {
    func sendInsertData(rawJSONString: String) async throws
}

struct BLEUploadRepositoryImpl: BLEUploadRepository {
    private let http: HTTPClient = .shared

    func sendInsertData(rawJSONString: String) async throws {
        let url = ApiRoutes.Workouts.insertData
        try await http.postRawJSON(url, rawJSONString: rawJSONString)
    }
}
