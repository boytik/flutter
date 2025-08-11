
import Foundation

final class PhysicalDataRepositoryImpl: PhysicalDataRepository {
    private let client = HTTPClient.shared

    func save(data: PhysicalData) async throws {
        try await client.requestVoid(url: ApiRoutes.Profile.physical,
                                     method: .PUT,
                                     body: data)
    }

    func load() async throws -> PhysicalData {
        try await client.request(PhysicalData.self,
                                 url: ApiRoutes.Profile.physical,
                                 method: .GET)
    }
}


