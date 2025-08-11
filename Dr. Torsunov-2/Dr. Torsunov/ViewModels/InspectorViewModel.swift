import SwiftUI

@MainActor
final class InspectorViewModel: ObservableObject {
    @Published var toCheck: [Workout] = []
    @Published var fullCheck: [Workout] = []
    @Published var isLoading = false
    @Published var error: String?

    private let repo: InspectorRepository

    init(repo: InspectorRepository = InspectorRepositoryImpl()) {
        self.repo = repo
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let a = repo.getActivitiesForCheck()
            async let b = repo.getActivitiesFullCheck()
            (toCheck, fullCheck) = try await (a, b)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func approve(id: String) async {
        do {
            try await repo.checkWorkout(id: id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
