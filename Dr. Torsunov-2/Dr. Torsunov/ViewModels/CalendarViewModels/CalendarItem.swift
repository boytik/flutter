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

    // Универсально достаём дату:
    var date: Date {
        switch self {
        case .workout(let w):
            return CalendarItem.extractDate(from: w) ?? Date()
        case .activity(let a):
            return a.createdAt ?? Date()
        }
    }

    var name: String {
        switch self {
        case .workout(let w): return w.name
        case .activity(let a): return a.name ?? "Activity"
        }
    }

    var description: String? {
        switch self {
        case .workout(let w): return w.description
        case .activity(let a): return a.description
        }
    }

    // MARK: - SF Symbols + цвет (по типу)
    var symbolName: String {
        switch self {
        case .workout(let w):
            return CalendarItem.symbol(for: w.name).name
        case .activity(let a):
            return CalendarItem.symbol(for: a.name ?? "Activity").name
        }
    }

    var tintColor: Color {
        switch self {
        case .workout(let w):
            return CalendarItem.symbol(for: w.name).color
        case .activity(let a):
            return CalendarItem.symbol(for: a.name ?? "Activity").color
        }
    }

    // Удобства для ячеек
    var asWorkout: Workout?  { if case let .workout(w) = self { return w } else { return nil } }
    var asActivity: Activity? { if case let .activity(a) = self { return a } else { return nil } }
    var email: String? { if case let .activity(a) = self { return a.userEmail } else { return nil } }

    // MARK: - Mapping name -> symbol/color
    private static func symbol(for name: String) -> (name: String, color: Color) {
        let s = name.lowercased()
        if s.contains("yoga") || s.contains("йога")         { return ("figure.mind.and.body", .purple) }
        if s.contains("walk") || s.contains("run")
            || s.contains("ходь") || s.contains("бег")      { return ("figure.run", .orange) }
        if s.contains("water") || s.contains("вода") || s.contains("swim") { return ("drop.fill", .blue) }
        if s.contains("sauna") || s.contains("баня")         { return ("flame.fill", .red) }
        if s.contains("fast")  || s.contains("пост")         { return ("hourglass", .yellow) }
        if #available(iOS 16.0, *) { return ("dumbbell.fill", .green) }
        return ("bolt.heart", .green)
    }

    // MARK: - Универсальный извлекатель даты из Workout
    private static func extractDate(from workout: Workout) -> Date? {
        // 1) попробуем прямые поля типа Date через отражение
        let mirror = Mirror(reflecting: workout)
        for child in mirror.children {
            guard let label = child.label?.lowercased() else { continue }
            if (label.contains("date") || label.contains("time")),
               let d = child.value as? Date {
                return d
            }
        }
        // 2) попробуем строки, которые выглядят как дата
        for child in mirror.children {
            guard let label = child.label?.lowercased() else { continue }
            if (label.contains("date") || label.contains("time")),
               let s = child.value as? String {
                if let d = CalendarItem.iso8601Full.date(from: s)
                    ?? CalendarItem.iso8601Short.date(from: s) {
                    return d
                }
            }
        }
        return nil
    }

    // Форматтеры для возможных строковых дат
    private static let iso8601Full: DateFormatter = {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return f
    }()

    private static let iso8601Short: DateFormatter = {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
