import SwiftUI

@MainActor
final class ActivityViewModel: ObservableObject {
    @Published var activities: [Activity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repository: ActivityRepository

    init(repository: ActivityRepository = ActivityRepositoryImpl()) {
        self.repository = repository
        Task { await load() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            activities = try await repository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func upload(activity: Activity) async {
        do {
            try await repository.upload(activity: activity)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submit(activityId: String,
                comment: String?,
                beforeImage: UIImage?,
                afterImage: UIImage?) async {
        do {
            try await repository.submit(activityId: activityId,
                                        comment: comment,
                                        beforeImage: beforeImage,
                                        afterImage: afterImage)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
