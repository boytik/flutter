
import Foundation

// MARK: - Core cached entities (agnostic to your app models)

public struct CachedWorkout: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var date: Date          // start time
    public var durationSec: Int?
    public var type: String?
    public var updatedAt: Date     // server-side updatedAt or local fetch date

    public init(id: String, name: String, date: Date, durationSec: Int?, type: String?, updatedAt: Date) {
        self.id = id
        self.name = name
        self.date = date
        self.durationSec = durationSec
        self.type = type
        self.updatedAt = updatedAt
    }
}

public struct CachedMonthEnvelope: Codable, Equatable {
    public var monthKey: String        // "yyyy-MM"
    public var fetchedAt: Date
    public var etag: String?
    public var workouts: [CachedWorkout]
    public var softDeletedIDs: Set<String>

    public init(monthKey: String, fetchedAt: Date, etag: String? = nil, workouts: [CachedWorkout], softDeletedIDs: Set<String> = []) {
        self.monthKey = monthKey
        self.fetchedAt = fetchedAt
        self.etag = etag
        self.workouts = workouts
        self.softDeletedIDs = softDeletedIDs
    }
}

// Utilities
public enum MonthKey {
    public static func from(date: Date) -> String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM"
        return df.string(from: date)
    }
}
