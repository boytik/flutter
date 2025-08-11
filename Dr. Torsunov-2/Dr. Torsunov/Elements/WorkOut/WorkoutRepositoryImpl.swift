

import Foundation

final class WorkoutRepositoryImpl: WorkoutRepository {
    private let client = HTTPClient.shared

    func fetchAll() async throws -> [Workout] {
        try await client.request([Workout].self, url: ApiRoutes.Workouts.list)
    }

    func fetch(by id: String) async throws -> Workout {
        try await client.request(Workout.self, url: ApiRoutes.Workouts.by(id: id))
    }

    func upload(workout: Workout) async throws {
        try await client.requestVoid(url: ApiRoutes.Workouts.upload,
                                     method: .POST,
                                     body: workout)
    }
}



