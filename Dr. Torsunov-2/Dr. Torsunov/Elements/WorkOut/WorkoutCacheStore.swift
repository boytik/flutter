
import Foundation

public protocol WorkoutCacheStoring {
    func loadMonth(_ monthKey: String) throws -> CachedMonthEnvelope?
    func saveMonth(_ envelope: CachedMonthEnvelope) throws
    func clearAll() throws
}

public final class WorkoutCacheStore: WorkoutCacheStoring {
    private let fm = FileManager.default
    private let folderURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(folderName: String = "WorkoutsCache") {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.folderURL = base.appendingPathComponent(folderName, isDirectory: true)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
        try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    private func fileURL(_ monthKey: String) -> URL {
        folderURL.appendingPathComponent("\(monthKey).json", conformingTo: .json)
    }

    public func loadMonth(_ monthKey: String) throws -> CachedMonthEnvelope? {
        let url = fileURL(monthKey)
        guard fm.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(CachedMonthEnvelope.self, from: data)
    }

    public func saveMonth(_ envelope: CachedMonthEnvelope) throws {
        let url = fileURL(envelope.monthKey)
        let data = try encoder.encode(envelope)
        try data.write(to: url, options: [.atomic])
    }

    public func clearAll() throws {
        guard fm.fileExists(atPath: folderURL.path) else { return }
        let urls = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        for u in urls { try? fm.removeItem(at: u) }
    }
}
