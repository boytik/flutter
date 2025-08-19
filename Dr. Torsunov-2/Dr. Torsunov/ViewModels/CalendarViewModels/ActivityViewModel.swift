import SwiftUI
import OSLog

// MARK: - Logger
private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app",
                         category: "ActivityViewModel")

@MainActor
final class ActivityViewModel: ObservableObject {
    @Published var activities: [Activity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repository: ActivityRepository

    private let ns = "activities"
    private let kvKeyAll = "all"
    private let kvTTL: TimeInterval = 60 * 10   // 10 минут

    init(repository: ActivityRepository = ActivityRepositoryImpl()) {
        self.repository = repository
        Task { [weak self] in
            await self?.load()
        }
    }
    func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }

        if let cached: [Activity] = try? KVStore.shared.get([Activity].self,
                                                            namespace: self.ns,
                                                            key: self.kvKeyAll) {
            self.activities = cached
            log.debug("[KV] HIT \(self.ns)/\(self.kvKeyAll) count=\(cached.count)")
        }

        do {
            log.info("[Activities] Fetch…")
            let fresh = try await self.repository.fetchAll()
            self.activities = fresh

            try? KVStore.shared.put(fresh, namespace: self.ns, key: self.kvKeyAll, ttl: self.kvTTL)
            log.debug("[KV] SAVE \(self.ns)/\(self.kvKeyAll) count=\(fresh.count), ttl=\(Int(self.kvTTL))s")
        } catch {
            if self.activities.isEmpty {
                self.errorMessage = self.shortError(error)
                log.error("[Activities] Fetch failed: \(error.localizedDescription, privacy: .public)")
            } else {
                log.error("[Activities] Fetch failed (offline shown): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func upload(activity: Activity) async {
        self.errorMessage = nil
        do {
            try await self.repository.upload(activity: activity)
            log.info("[Activities] Upload ok")
            await self.load()
        } catch {
            self.errorMessage = self.shortError(error)
            log.error("[Activities] Upload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func submit(activityId: String,
                comment: String?,
                beforeImage: UIImage?,
                afterImage: UIImage?) async {
        self.errorMessage = nil
        do {
            try await self.repository.submit(activityId: activityId,
                                             comment: comment,
                                             beforeImage: beforeImage,
                                             afterImage: afterImage)
            log.info("[Activities] Submit ok")
            await self.load()
        } catch {
            self.errorMessage = self.shortError(error)
            log.error("[Activities] Submit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Debug helpers
    func clearOffline() {
        try? KVStore.shared.delete(namespace: self.ns, key: self.kvKeyAll)
        log.info("[KV] DELETE \(self.ns)/\(self.kvKeyAll)")
    }

    // MARK: - Helpers
    private func shortError(_ error: Error) -> String {
        if case let NetworkError.server(status, _) = error {
            return "Server error (\(status))"
        }
        return error.localizedDescription
    }
}
