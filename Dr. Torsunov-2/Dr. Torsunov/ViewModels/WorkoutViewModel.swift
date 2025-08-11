
import SwiftUI

@MainActor
final class WorkoutViewModel: ObservableObject {
    @Published var workouts: [Workout] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repository: WorkoutRepository

    init(repository: WorkoutRepository = WorkoutRepositoryImpl()) {
        self.repository = repository
        Task { await load() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            workouts = try await repository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func upload(workout: Workout) async {
        do {
            try await repository.upload(workout: workout)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
