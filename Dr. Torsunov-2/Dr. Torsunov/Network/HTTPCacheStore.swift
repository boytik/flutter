import Foundation
import CryptoKit
import OSLog

// MARK: - локальный логгер
private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app",
                         category: "HTTPCache")

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
        let nskey = key as NSString
        
        if let ns = memory.object(forKey: nskey) {
            return Data(ns)
        }
        var result: Data?
        ioQueue.sync {
            let url = path(for: key)
            guard let raw = try? Data(contentsOf: url) else { return }

            do {
                let entry = try JSONDecoder().decode(CachedEntry.self, from: raw)
                if entry.isExpired {
                    try? FileManager.default.removeItem(at: url)
                    return
                }

                let copy = Data(entry.data) 
                memory.setObject(copy as NSData, forKey: nskey)
                result = copy
            } catch {
                try? FileManager.default.removeItem(at: url)
                let keyStr = "\(key)"
                log.error("[Cache] Corrupted entry deleted for key \(keyStr, privacy: .public)")
            }
        }

        return result
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
