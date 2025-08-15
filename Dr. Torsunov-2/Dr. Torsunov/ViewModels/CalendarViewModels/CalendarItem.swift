import Foundation
import SwiftUI

enum CalendarItem: Identifiable, Codable, Equatable {
    case workout(Workout)
    case activity(Activity)

    var id: String {
        switch self {
        case .workout(let w): return "workout_\(w.id)"
        case .activity(let a): return "activity_\(a.id)"
        }
    }

    var date: Date {
        switch self {
        case .workout(let w): return w.date
        case .activity(let a): return a.createdAt ?? Date()
        }
    }

    var name: String {
        switch self {
        case .workout(let w): return w.name
        case .activity(let a): return a.name ?? "Activity"     // <-- фикс
        }
    }

    var description: String? {
        switch self {
        case .workout(let w): return w.description
        case .activity(let a): return a.description
        }
    }

    // MARK: - SF Symbols + цвет
    var symbolName: String {
        switch self {
        case .workout(let w):
            return CalendarItem.symbol(for: w.name).name
        case .activity:
            return "checkmark.seal.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .workout(let w):
            return CalendarItem.symbol(for: w.name).color
        case .activity:
            return .green
        }
    }

    var asWorkout: Workout? {
        if case let .workout(w) = self { return w }
        return nil
    }

    var asActivity: Activity? {
        if case let .activity(a) = self { return a }
        return nil
    }

    // MARK: - Mapping name -> symbol/color
    private static func symbol(for name: String) -> (name: String, color: Color) {
        let s = name.lowercased()

        // yoga
        if s.contains("yoga") || s.contains("йога") {
            return ("figure.mind.and.body", .purple) // iOS 15+
        }

        // walking / running
        if s.contains("walk") || s.contains("run") || s.contains("ходь") || s.contains("бег") {
            return ("figure.run", .orange) // iOS 14+
        }

        // swimming / water
        if s.contains("swim") || s.contains("water") || s.contains("pool") || s.contains("вода") || s.contains("плаван") {
            if #available(iOS 17.0, *) {
                return ("figure.pool.swim", .blue)
            } else {
                return ("water.waves", .blue) // fallback (iOS 15+)
            }
        }

        // sauna
        if s.contains("sauna") || s.contains("сауна") {
            if #available(iOS 15.0, *) {
                return ("thermometer.sun", .red)
            } else {
                return ("flame", .red)
            }
        }

        // fasting
        if s.contains("fast") || s.contains("пост") {
            return ("hourglass", .yellow) // iOS 13+
        }

        // default
        if #available(iOS 16.0, *) {
            return ("dumbbell.fill", .green)
        } else {
            return ("bolt.heart", .green)
        }
    }
}
