import Foundation
import SwiftUI

// MARK: - Базовая модель для UI
struct Workout: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var description: String?
    var duration: Int
    var date: Date
}

// MARK: - День в календаре (точки для сетки)
struct WorkoutDay: Identifiable {
    let id = UUID()
    let date: Date
    let dots: [Color]
}

// MARK: - DTO ответа планировщика (/workout_calendar)
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

// MARK: - Планировщик (только то, что нужно календарю)
protocol WorkoutPlannerRepository {
    /// Получить план за месяц (yyyy-MM)
    func getPlannerCalendar(filterMonth: String) async throws -> [ScheduledWorkoutDTO]
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

        // yyyy-MM -> границы месяца (UTC)
        let (start, end) = Self.monthBounds(from: filterMonth)
        let startStr = Self.fmtDayUTC.string(from: start)
        let endStr   = Self.fmtDayUTC.string(from: end)

        // Рабочие маршруты: сначала диапазон, затем месячный
        let candidates: [(label: String, url: URL)] = [
            ("range_path", ApiRoutes.Workouts.calendarRange(email: email, startDate: startStr, endDate: endStr)),
            ("month_path", ApiRoutes.Workouts.calendarMonth(email: email, month: filterMonth))
        ]

        var firstSuccessfulEmpty: [ScheduledWorkoutDTO]? = nil
        var lastError: Error = WorkoutsPlannerError.noEmail

        for (label, url) in candidates {
            do {
                let res: [ScheduledWorkoutDTO] = try await client.request([ScheduledWorkoutDTO].self, url: url)
                print("🛰️ planner \(label) -> \(url.absoluteString) items=\(res.count)")
                if !res.isEmpty { return res }
                if firstSuccessfulEmpty == nil { firstSuccessfulEmpty = res }
            } catch NetworkError.server(let code, _) where (400...599).contains(code) {
                print("↩️ \(label) HTTP \(code) \(url.absoluteString)")
                lastError = NetworkError.server(status: code, data: nil)
                continue
            } catch {
                print("↩️ \(label) error: \(error.localizedDescription)")
                lastError = error
                continue
            }
        }

        if let empty = firstSuccessfulEmpty { return empty }
        throw lastError
    }

    // MARK: - Helpers
    private static let fmtDayUTC: DateFormatter = {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .init(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// yyyy-MM -> (первый и последний день месяца) в UTC
    private static func monthBounds(from yyyyMM: String) -> (Date, Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)! // UTC
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
