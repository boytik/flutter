
import Foundation

public protocol MonthWorkoutsNetworking {
    /// Fetch workouts for a month. If server supports ETag/If-None-Match, pass `ifNoneMatch` and return the new etag.
    /// Return empty array if server responds 304 or has no workouts; repository will decide whether to keep local cache.
    func fetchMonth(monthKey: String, ifNoneMatch: String?) async throws -> (etag: String?, workouts: [CachedWorkout])
}

public enum WorkoutSource {
    case networkThenCache
    case cacheOnly
}

public final class OfflineWorkoutRepository {
    private let cache: WorkoutCacheStoring
    private let api: MonthWorkoutsNetworking

    public init(cache: WorkoutCacheStoring, api: MonthWorkoutsNetworking) {
        self.cache = cache
        self.api = api
    }

    public func loadMonth(_ monthKey: String, source: WorkoutSource) async -> [CachedWorkout] {
        switch source {
        case .cacheOnly:
            return (try? cache.loadMonth(monthKey)?.workouts) ?? []
        case .networkThenCache:
            let local = try? cache.loadMonth(monthKey)
            do {
                let (etag, remote) = try await api.fetchMonth(monthKey: monthKey, ifNoneMatch: local?.etag)
                if remote.isEmpty, let existing = local?.workouts {
                    // Server empty/304 → keep our local “seen” workouts
                    return existing
                }
                let merged = Self.merge(local: local?.workouts ?? [], remote: remote)
                let env = CachedMonthEnvelope(monthKey: monthKey, fetchedAt: Date(), etag: etag, workouts: merged, softDeletedIDs: local?.softDeletedIDs ?? [])
                try? cache.saveMonth(env)
                return merged
            } catch {
                // Offline → fallback to cache if present
                if let existing = local?.workouts { return existing }
                return []
            }
        }
    }

    public func markServerDeletion(ids: [String], monthKey: String) {
        guard var env = try? cache.loadMonth(monthKey) else { return }
        env.softDeletedIDs.formUnion(ids)
        env.workouts.removeAll { ids.contains($0.id) }
        try? cache.saveMonth(env)
    }

    private static func merge(local: [CachedWorkout], remote: [CachedWorkout]) -> [CachedWorkout] {
        var map = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for r in remote {
            if let l = map[r.id] {
                map[r.id] = (r.updatedAt >= l.updatedAt) ? r : l
            } else {
                map[r.id] = r
            }
        }
        return Array(map.values).sorted { $0.date < $1.date }
    }
}
