import Foundation

protocol PlannerRepository {
    func createPlan(email: String, startDate: String?) async throws -> PlanResultDTO
    func deletePlan(email: String) async throws
    func updateWorkouts(email: String, items: [PlannerScheduledWorkoutMutationDTO]) async throws
}

final class PlannerRepositoryImpl: PlannerRepository {
    private let http: HTTPClient
    init(http: HTTPClient = .shared) { self.http = http }

    func createPlan(email: String, startDate: String?) async throws -> PlanResultDTO {
        struct Body: Encodable { let start_date: String? }
        let url = ApiRoutes.Planner.createPlan(email: email)

        // Вариант A (если HTTPClient сам выводит тип по левой части):
        let workouts: [ScheduledWorkoutDTO] =
            try await http.request(url, method: .POST, body: Body(start_date: startDate))

        // // Вариант B (если нужен явный decode-параметр):
        // let workouts: [ScheduledWorkoutDTO] =
        //     try await http.request(url, method: .POST,
        //                            body: Body(start_date: startDate),
        //                            decode: [ScheduledWorkoutDTO].self)

        return PlanResultDTO(workouts: workouts)
    }

    func deletePlan(email: String) async throws {
        let url = ApiRoutes.Planner.deletePlan(email: email)
        struct Empty: Decodable {}
        _ = try await http.request(url, method: .GET, decode: Empty.self)
    }

    func updateWorkouts(email: String, items: [PlannerScheduledWorkoutMutationDTO]) async throws {
        let url = ApiRoutes.Planner.updateWorkouts(email: email)
        struct ArrayBody: Encodable {
            let array: [PlannerScheduledWorkoutMutationDTO]
            init(_ arr: [PlannerScheduledWorkoutMutationDTO]) { self.array = arr }
            func encode(to encoder: Encoder) throws {
                var c = encoder.unkeyedContainer()
                try c.encode(contentsOf: array)
            }
        }
        struct Empty: Decodable {}
        _ = try await http.request(url, method: .POST, body: ArrayBody(items), decode: Empty.self)
    }
}
