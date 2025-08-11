
import Foundation
protocol WorkoutRepository {
    func fetchAll() async throws -> [Workout]
    func fetch(by id: String) async throws -> Workout
    func upload(workout: Workout) async throws
}

