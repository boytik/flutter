import Foundation
import CryptoKit

// MARK: - Кэшируемая запись
private struct CachedEntry: Codable {
    let data: Data
    let createdAt: Date
    let ttl: TimeInterval
    var isExpired: Bool { Date().timeIntervalSince(createdAt) > ttl }
}

// MARK: - Хранилище кэша (память + диск)
final class HTTPCacheStore {
    static let shared = HTTPCacheStore()
    private init() {}

    private let memory = NSCache<NSString, NSData>()
    private lazy var diskDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("HttpCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private let ioQueue = DispatchQueue(label: "http.cache.disk.queue", qos: .utility)

    func load(for key: String) -> Data? {
        let nsKey = key as NSString

        // ✅ ВАЖНО: не используем Data(referencing:)!
        // Берём копию данных, чтобы не зависеть от возможной эвикции NSCache.
        if let mem = memory.object(forKey: nsKey) {
            return mem as Data  // копия/bridging, удерживает NSData
        }

        let url = path(for: key)
        guard let raw = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(CachedEntry.self, from: raw),
              !entry.isExpired else {
            // если просрочено/битое — удалим с диска
            ioQueue.async { [url] in try? FileManager.default.removeItem(at: url) }
            return nil
        }

        // Положим в память (как NSData). При чтении мы всё равно делаем копию.
        memory.setObject(entry.data as NSData, forKey: nsKey)
        return entry.data
    }


    func save(_ data: Data, for key: String, ttl: TimeInterval) {
        let entry = CachedEntry(data: data, createdAt: Date(), ttl: ttl)
        guard let packed = try? JSONEncoder().encode(entry) else { return }

        let nsKey = key as NSString
        memory.setObject(data as NSData, forKey: nsKey)
        let url = path(for: key)
        ioQueue.async { try? packed.write(to: url, options: .atomic) }
    }

    func invalidate(key: String) {
        let nsKey = key as NSString
        memory.removeObject(forKey: nsKey)
        let url = path(for: key)
        ioQueue.async { try? FileManager.default.removeItem(at: url) }
    }

    func invalidateAll() {
        memory.removeAllObjects()
        ioQueue.async {
            let dir = self.diskDir
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func path(for key: String) -> URL {
        diskDir.appendingPathComponent(key).appendingPathExtension("cache")
    }
}

// MARK: - Ключ кэша
struct HTTPCacheKey {
    static func make(url: URL, method: String, headers: [String: String]?) -> String {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        if let q = comps.queryItems {
            comps.queryItems = q.sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        }
        let normalizedURL = comps.url?.absoluteString ?? url.absoluteString

        var keyString = method + " " + normalizedURL

        let varyHeaders = ["Accept-Language"]
        if let headers = headers {
            let filtered = headers
                .filter { varyHeaders.contains($0.key) }
                .sorted { $0.key < $1.key }
            if !filtered.isEmpty {
                keyString += " HEADERS:" + filtered.map { "\($0.key)=\($0.value)" }.joined(separator: ";")
            }
        }

        let digest = SHA256.hash(data: Data(keyString.utf8))
        let base = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return base
    }
}

// MARK: - Политика кэша
struct HTTPCachePolicy {
    static var shared = HTTPCachePolicy()
    var defaultTTL: TimeInterval = 60           // 1 минута
    var maxInMemoryBytes: Int = 2 * 1024 * 1024 // 2 МБ
    var enableForGET: Bool = true
    var respectNoStore: Bool = true
}

// MARK: - Клиент с кэшированием
final class CachedHTTPClient {
    static let shared = CachedHTTPClient()
    private init() {}

    // Проксируем зависимости при необходимости
    var tokenProvider: TokenProvider? {
        get { HTTPClient.shared.tokenProvider }
        set { HTTPClient.shared.tokenProvider = newValue }
    }
    var authRefresher: AuthRefresher? {
        get { HTTPClient.shared.authRefresher }
        set { HTTPClient.shared.authRefresher = newValue }
    }
    var urlSession: URLSession {
        get { HTTPClient.shared.urlSession }
        set { HTTPClient.shared.urlSession = newValue }
    }

    /// Основной метод (кэш только для GET без тела).
    @discardableResult
    func request<T: Codable>(
        _ url: URL,
        method: HTTPClient.Method = .GET,
        headers: [String: String] = [:],
        body: (any Encodable)? = nil,
        ttl: TimeInterval? = nil
    ) async throws -> T {
        // Для не-GET или наличия тела — кэш не используем
        guard method == .GET, HTTPCachePolicy.shared.enableForGET, body == nil else {
            // Важно: сигнатура вашего HTTPClient должна быть без параметра `decode:`
            let value: T = try await HTTPClient.shared.request(url, method: method, headers: headers, body: body)
            return value
        }

        let key = HTTPCacheKey.make(url: url, method: method.rawValue, headers: headers)

        if let cached = HTTPCacheStore.shared.load(for: key) {
            if let decoded = try? JSONDecoder().decode(T.self, from: cached) {
                if HTTPClient.isLoggingEnabled {
                    print("📦 cache HIT \(url.absoluteString)")
                }
                return decoded
            } else {
                HTTPCacheStore.shared.invalidate(key: key)
            }
        } else if HTTPClient.isLoggingEnabled {
            print("📦 cache MISS \(url.absoluteString)")
        }

        // Сеть
        let value: T = try await HTTPClient.shared.request(url, method: method, headers: headers, body: body)

        // Сохраняем (повторно кодируем как JSON)
        if let reencoded = try? JSONEncoder().encode(value) {
            if reencoded.count <= HTTPCachePolicy.shared.maxInMemoryBytes {
                let ttlToUse = ttl ?? HTTPCachePolicy.shared.defaultTTL
                HTTPCacheStore.shared.save(reencoded, for: key, ttl: ttlToUse)
                if HTTPClient.isLoggingEnabled {
                    print("📦 cache STORE \(url.absoluteString) (\(reencoded.count) bytes, ttl \(Int(ttlToUse))s)")
                }
            } else if HTTPClient.isLoggingEnabled {
                print("📦 cache SKIP (too large: \(reencoded.count) bytes) \(url.absoluteString)")
            }
        }
        return value
    }

    // Инвалидация
    func invalidateAll() { HTTPCacheStore.shared.invalidateAll() }

    func invalidate(url: URL, method: HTTPClient.Method = .GET, headers: [String: String] = [:]) {
        let key = HTTPCacheKey.make(url: url, method: method.rawValue, headers: headers)
        HTTPCacheStore.shared.invalidate(key: key)
    }
}
