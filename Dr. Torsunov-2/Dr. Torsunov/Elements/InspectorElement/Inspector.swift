import Foundation



protocol InspectorRepository {
    func getActivitiesForCheck() async throws -> [Workout]
    func getActivitiesFullCheck() async throws -> [Workout]
    func checkWorkout(id: String) async throws
}


final class InspectorRepositoryImpl: InspectorRepository {
    private let client = HTTPClient.shared

    func getActivitiesForCheck() async throws -> [Workout] {
        try await client.request([Workout].self,
                                 url: ApiRoutes.Inspector.toCheck)
    }

    func getActivitiesFullCheck() async throws -> [Workout] {
        try await client.request([Workout].self,
                                 url: ApiRoutes.Inspector.fullCheck)
    }

    func checkWorkout(id: String) async throws {
        struct Body: Encodable { let id: String }
        try await client.requestVoid(url: ApiRoutes.Inspector.checkWorkout,
                                     method: .POST,
                                     body: Body(id: id))
    }
}
