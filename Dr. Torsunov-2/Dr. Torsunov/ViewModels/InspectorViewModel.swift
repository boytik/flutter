import SwiftUI

@MainActor
final class InspectorViewModel: ObservableObject {
    @Published var toCheck: [Activity] = []
    @Published var fullCheck: [Activity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repo: InspectorRepository
    private let fallbackActivities: ActivityRepository

    init(
        repo: InspectorRepository = InspectorRepositoryImpl(),
        fallbackActivities: ActivityRepository = ActivityRepositoryImpl()
    ) {
        self.repo = repo
        self.fallbackActivities = fallbackActivities
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let a: [Activity] = repo.getActivitiesForCheck()
            async let b: [Activity] = repo.getActivitiesFullCheck()
            let (listA, listB) = try await (a, b)

            // Разводим дубли по id: всё, что есть в toCheck, из fullCheck убираем
            toCheck = listA
            fullCheck = listB.filter { bItem in !listA.contains(where: { $0.id == bItem.id }) }

        } catch {
            // Фолбэк: если инспекторские списки недоступны — подгружаем историю активностей
            do {
                let acts = try await fallbackActivities.fetchAll() // /list_workouts
                toCheck = acts
                fullCheck = []
                errorMessage = "Инспекторские списки недоступны, показана история через /list_workouts."
            } catch {
                errorMessage = (error as NSError).localizedDescription
                toCheck = []
                fullCheck = []
            }
        }
    }

    func approve(id: String) async {
        errorMessage = nil
        do {
            try await repo.checkWorkout(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Удобный объединённый список (без дублей), по дате убыв.
    var allSortedByDateDesc: [Activity] {
        let merged = toCheck + fullCheck
        let unique = Dictionary(grouping: merged, by: { $0.id }).compactMap { $0.value.first }
        return unique.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
}

