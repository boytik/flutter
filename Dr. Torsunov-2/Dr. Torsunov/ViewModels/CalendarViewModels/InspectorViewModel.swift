import SwiftUI
import OSLog

@MainActor
final class InspectorViewModel: ObservableObject {
    @Published var toCheck: [Activity] = []
    @Published var fullCheck: [Activity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repo: InspectorRepository
    private let fallbackActivities: ActivityRepository

    private let ns = "inspector"
    private let kvKeyA = "toCheck"
    private let kvKeyB = "fullCheck"
    private let kvTTL: TimeInterval = 60 * 2

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app",
                             category: "InspectorVM")

    init(
        repo: InspectorRepository = InspectorRepositoryImpl(),
        fallbackActivities: ActivityRepository = ActivityRepositoryImpl()
    ) {
        self.repo = repo
        self.fallbackActivities = fallbackActivities
    }

    func load() async {
        self.isLoading = true
        self.errorMessage = nil

        if let a: [Activity] = try? KVStore.shared.get([Activity].self, namespace: self.ns, key: self.kvKeyA) {
            self.toCheck = a
            log.debug("[KV] HIT \(self.ns)/\(self.kvKeyA) count=\(a.count)")
        }
        if let b: [Activity] = try? KVStore.shared.get([Activity].self, namespace: self.ns, key: self.kvKeyB) {
            self.fullCheck = b
            log.debug("[KV] HIT \(self.ns)/\(self.kvKeyB) count=\(b.count)")
        }

        defer { self.isLoading = false }

        // 2) сеть
        do {
            async let aAsync: [Activity] = self.repo.getActivitiesForCheck()
            async let bAsync: [Activity] = self.repo.getActivitiesFullCheck()
            let (listA, listB) = try await (aAsync, bAsync)

            self.toCheck = listA
            self.fullCheck = listB.filter { bItem in
                !listA.contains(where: { $0.id == bItem.id })
            }

            try? KVStore.shared.put(self.toCheck,  namespace: self.ns, key: self.kvKeyA, ttl: self.kvTTL)
            try? KVStore.shared.put(self.fullCheck, namespace: self.ns, key: self.kvKeyB, ttl: self.kvTTL)
            log.debug("[KV] SAVE \(self.ns)/\(self.kvKeyA)=\(self.toCheck.count); \(self.ns)/\(self.kvKeyB)=\(self.fullCheck.count)")
        } catch {
            do {
                let acts = try await self.fallbackActivities.fetchAll()
                self.toCheck = acts
                self.fullCheck = []
                self.errorMessage = "Инспекторские списки недоступны, показана история через /list_workouts."
                log.error("[Inspector] fallback to /list_workouts, count=\(acts.count)")
            } catch {
                self.errorMessage = (error as NSError).localizedDescription
                self.toCheck = []
                self.fullCheck = []
                log.error("[Inspector] load failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func approve(id: String) async {
        self.errorMessage = nil
        do {
            try await self.repo.checkWorkout(id: id)
            log.info("[Inspector] approved id=\(id, privacy: .public)")
            await self.load()
        } catch {
            self.errorMessage = error.localizedDescription
            log.error("[Inspector] approve failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var allSortedByDateDesc: [Activity] {
        let merged = self.toCheck + self.fullCheck
        let unique = Dictionary(grouping: merged, by: { $0.id }).compactMap { $0.value.first }
        return unique.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
}
