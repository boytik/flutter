import Foundation

public final class CalendarAPIAdapter: MonthWorkoutsNetworking {
    public struct Fetcher {
        public var fetch: (_ monthKey: String, _ ifNoneMatch: String?) async throws -> (etag: String?, workouts: [CachedWorkout])
        public init(fetch: @escaping (_ monthKey: String, _ ifNoneMatch: String?) async throws -> (etag: String?, workouts: [CachedWorkout])) {
            self.fetch = fetch
        }
    }
    private let fetcher: Fetcher
    public init(fetcher: Fetcher) { self.fetcher = fetcher }

    public func fetchMonth(monthKey: String, ifNoneMatch: String?) async throws -> (etag: String?, workouts: [CachedWorkout]) {
        try await fetcher.fetch(monthKey, ifNoneMatch)
    }
}
