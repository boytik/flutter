import Foundation
import OSLog

protocol CacheRequesting {
    func request<T: Codable>(_ url: URL, ttl: TimeInterval) async throws -> T
}

struct CacheJSONClient: CacheRequesting {
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "Cache")
    func request<T: Codable>(_ url: URL, ttl: TimeInterval) async throws -> T {
        let key = HTTPCacheKey.make(url: url, method: "GET", headers: [:])

        if let cached = HTTPCacheStore.shared.load(for: key),
           let decoded = try? JSONDecoder().decode(T.self, from: cached) {
            log.debug("[cache] HIT \(url.absoluteString, privacy: .public)")
            return decoded
        } else {
            log.debug("[cache] MISS \(url.absoluteString, privacy: .public)")
        }

        let value: T = try await HTTPClient.shared.request(url, method: .GET, headers: [:], body: nil)

        if let data = try? JSONEncoder().encode(value) {
            HTTPCacheStore.shared.save(data, for: key, ttl: ttl)
            log.debug("[cache] STORE \(url.absoluteString, privacy: .public) — \(data.count) bytes, ttl=\(Int(ttl))s")
        }
        return value
    }
}
