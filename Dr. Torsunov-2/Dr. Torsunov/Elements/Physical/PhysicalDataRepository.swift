

import Foundation

protocol PhysicalDataRepository {
    func save(data: PhysicalData) async throws
    func load() async throws -> PhysicalData
}

