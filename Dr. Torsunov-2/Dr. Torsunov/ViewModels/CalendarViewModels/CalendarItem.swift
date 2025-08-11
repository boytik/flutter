
import Foundation

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
        case .activity(let a): return a.name
        }
    }

    var description: String? {
        switch self {
        case .workout(let w): return w.description
        case .activity(let a): return a.description
        }
    }

    var emoji: String {
        switch self {
        case .workout: return "💪"
        case .activity: return "✅"
        }
    }

    var asWorkout: Workout? {
        if case let .workout(w) = self {
            return w
        }
        return nil
    }

    var isWorkout: Bool {
        if case .workout = self { return true }
        return false
    }
    var asActivity: Activity? {
        if case let .activity(a) = self {
            return a
        }
        return nil
    }

}
