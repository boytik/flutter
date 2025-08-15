import Foundation
import SwiftUI

// MARK: - UI-модель тренировки
struct Workout: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var description: String?
    var duration: Int
    var date: Date
}

// MARK: - День календаря (маркеры-точки)
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
    let date: String?               // "yyyy-MM-dd" или "yyyy-MM-dd HH:mm:ss"
    let durationMinutes: Int?
    let durationHours: Int?
    let description: String?
    let dayOfWeek: String?
    let type: String?

    var id: String { workoutUuid ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case workoutUuid       = "workout_uuid"
        case userEmail
        case activityType      = "activity"
        case date
        case durationMinutes   = "duration_minutes"
        case durationHours     = "duration_hours"
        case description
        case dayOfWeek         = "day_of_week"
        case type
    }
}

// MARK: - Планировщик (контракт)
protocol WorkoutPlannerRepository {
    /// Получить план за месяц (yyyy-MM)
    func getPlannerCalendar(filterMonth: String) async throws -> [ScheduledWorkoutDTO]
}

enum WorkoutsPlannerError: LocalizedError {
    case noEmail
    var errorDescription: String? { "No email to load workouts" }
}

// MARK: - Планировщик (реализация)
final class WorkoutPlannerRepositoryImpl: WorkoutPlannerRepository {
    private let client = HTTPClient.shared

    func getPlannerCalendar(filterMonth: String) async throws -> [ScheduledWorkoutDTO] {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            throw WorkoutsPlannerError.noEmail
        }

        // yyyy-MM → границы месяца (UTC) и строки в формате yyyy-MM-dd
        let (start, end) = Self.monthBounds(from: filterMonth)
        let startStr = Self.fmtDayUTC.string(from: start)
        let endStr   = Self.fmtDayUTC.string(from: end)

        // Основной рабочий маршрут → запасной
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
                if !res.isEmpty { return res }               // нашли непустой ответ — возвращаем
                if firstSuccessfulEmpty == nil { firstSuccessfulEmpty = res } // запомним первый пустой, если потом тоже пусто
            } catch NetworkError.server(let code, _) where (400...599).contains(code) {
                // серверная ошибка — пробуем следующий маршрут
                print("↩️ \(label) HTTP \(code) \(url.absoluteString)")
                lastError = NetworkError.server(status: code, data: nil)
                continue
            } catch {
                // сетевая/другая ошибка — пробуем следующий
                print("↩️ \(label) error: \(error.localizedDescription)")
                lastError = error
                continue
            }
        }

        // Все маршруты сработали, но вернули пусто — возвращаем пустой массив
        if let empty = firstSuccessfulEmpty { return empty }
        // Все маршруты упали — пробрасываем последнюю ошибку
        throw lastError
    }

    // MARK: - Helpers

    /// Форматтер yyyy-MM-dd в UTC, чтобы границы месяца не "плавали"
    private static let fmtDayUTC: DateFormatter = {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .init(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "yyyy-MM" → (первый, последний день месяца) в UTC
    private static func monthBounds(from yyyyMM: String) -> (Date, Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .init(secondsFromGMT: 0)!

        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM"

        let base  = f.date(from: yyyyMM) ?? Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: base))!
        let range = cal.range(of: .day, in: .month, for: start)!
        let end   = cal.date(byAdding: .day, value: range.count - 1, to: start)!
        return (start, end)
    }
}
