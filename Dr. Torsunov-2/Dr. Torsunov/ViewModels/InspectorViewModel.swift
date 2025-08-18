import SwiftUI

@MainActor
final class InspectorViewModel: ObservableObject {
    @Published var toCheck: [Activity] = []
    @Published var fullCheck: [Activity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repo: InspectorRepository
    private let fallbackActivities: ActivityRepository

    // оффлайн
    private let ns = "inspector"
    private let kvKeyA = "toCheck"
    private let kvKeyB = "fullCheck"
    private let kvTTL: TimeInterval = 60 * 2 // 2 минуты

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

        // оффлайн мгновенно
        if let a: [Activity] = try? KVStore.shared.get([Activity].self, namespace: ns, key: kvKeyA) {
            toCheck = a; print("📦 KV HIT \(ns)/\(kvKeyA) (\(a.count))")
        }
        if let b: [Activity] = try? KVStore.shared.get([Activity].self, namespace: ns, key: kvKeyB) {
            fullCheck = b; print("📦 KV HIT \(ns)/\(kvKeyB) (\(b.count))")
        }

        defer { isLoading = false }

        do {
            async let aAsync: [Activity] = repo.getActivitiesForCheck()
            async let bAsync: [Activity] = repo.getActivitiesFullCheck()
            let (listA, listB) = try await (aAsync, bAsync)

            toCheck = listA
            fullCheck = listB.filter { bItem in !listA.contains(where: { $0.id == bItem.id }) }

            try? KVStore.shared.put(toCheck, namespace: ns, key: kvKeyA, ttl: kvTTL)
            try? KVStore.shared.put(fullCheck, namespace: ns, key: kvKeyB, ttl: kvTTL)
            print("💾 KV SAVE \(ns)/\(kvKeyA) \(toCheck.count); \(ns)/\(kvKeyB) \(fullCheck.count)")

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
