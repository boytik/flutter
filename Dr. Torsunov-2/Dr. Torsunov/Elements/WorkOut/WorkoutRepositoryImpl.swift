

import Foundation
import SwiftUI

/// Базовая модель тренировки, которую ждут `CalendarItem`, `WorkoutDetailView` и прочие экраны.
struct Workout: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var description: String?
    var duration: Int
    var date: Date
}

/// День календаря с точками (как в `CalendarGridView`)
struct WorkoutDay: Identifiable {
    let id = UUID()
    let date: Date
    let dots: [Color]
}


// DTO из календарного API
import Foundation

// DTO под ответ календаря
struct ScheduledWorkoutDTO: Decodable, Identifiable {
    let workoutUuid: String?
    let userEmail: String?
    let activityType: String?
    let date: String?              // "yyyy-MM-dd" или "yyyy-MM-dd HH:mm:ss"
    let durationMinutes: Int?
    let durationHours: Int?
    let description: String?
    let dayOfWeek: String?
    let type: String?

    var id: String { workoutUuid ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case workoutUuid = "workout_uuid"
        case userEmail
        case activityType = "activity"
        case date
        case durationMinutes = "duration_minutes"
        case durationHours  = "duration_hours"
        case description
        case dayOfWeek = "day_of_week"
        case type
    }
}

protocol WorkoutPlannerRepository {
    func getPlannerCalendar(filterMonth: String) async throws -> [ScheduledWorkoutDTO] // "yyyy-MM"
}

enum WorkoutsPlannerError: LocalizedError {
    case noEmail
    var errorDescription: String? { "No email to load workouts" }
}

final class WorkoutPlannerRepositoryImpl: WorkoutPlannerRepository {
    private let client = HTTPClient.shared

    func getPlannerCalendar(filterMonth: String) async throws -> [ScheduledWorkoutDTO] {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            throw WorkoutsPlannerError.noEmail
        }

        // превратим "yyyy-MM" → start_date / end_date
        let (start, end) = Self.monthBounds(from: filterMonth)
        let startStr = Self.fmtDayUTC.string(from: start)
        let endStr   = Self.fmtDayUTC.string(from: end)

        // пробуем оба варианта роутинга: /workout_calendar/<email>?... и ?email=...
        let candidates: [URL] = [
            ApiRoutes.Workouts.calendarRange(email: email, startDate: startStr, endDate: endStr),
            ApiRoutes.Workouts.calendarRangeByQuery(email: email, startDate: startStr, endDate: endStr)
        ]

        var lastError: Error = WorkoutsPlannerError.noEmail
        for u in candidates {
            do {
                let res: [ScheduledWorkoutDTO] = try await client.request([ScheduledWorkoutDTO].self, url: u)
                print("✅ Planner loaded from:", u.absoluteString)
                return res
            } catch NetworkError.server(let code, let data) where code == 404 || code == 500 || code == 400 {
                // 400 могли получить из-за неверного формата — но мы уже строго ISO (yyyy-MM-dd),
                // всё равно фоллбечимся на альтернативный роут.
                print("↩️ \(code) on \(u.absoluteString), trying next…")
                lastError = NetworkError.server(status: code, data: data)
                continue
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    // MARK: - Helpers
    private static let fmtDayUTC: DateFormatter = {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .init(secondsFromGMT: 0) // UTC
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // yyyy-MM -> (first,last) в UTC, чтобы не съезжало на -1 день
    private static func monthBounds(from yyyyMM: String) -> (Date, Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)! // считаем границы месяца в UTC

        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM"

        let base = f.date(from: yyyyMM) ?? Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: base))!
        let range = cal.range(of: .day, in: .month, for: start)!
        let end = cal.date(byAdding: .day, value: range.count - 1, to: start)!
        return (start, end)
    }

}
