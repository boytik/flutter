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

    // то, что нужно для карточки будущей тренировки
    let durationMinutes: Int?
    let durationHours: Int?
    let description: String?
    let dayOfWeek: String?
    let type: String?
    let breakDuration: Int?
    let breaks: Int?
    let layers: Int?
    let swimLayers: [Int]?
    let protocolName: String?       // backend key: "protocol"

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
        case breakDuration     = "break_duration"
        case breaks
        case layers
        case swimLayers        = "swim_layers"
        case protocolName      = "protocol"
    }
}

// MARK: - Планировщик (контракт)
protocol WorkoutPlannerRepository {
    /// Получить план за месяц (yyyy-MM)
    func getPlannerCalendar(filterMonth: String) async throws -> [ScheduledWorkoutDTO]

    /// Получить план на конкретный день
    func getPlannerDay(_ date: Date) async throws -> [ScheduledWorkoutDTO]
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

        // 1) диапазон дат → 2) фильтр по месяцу
        let candidates: [(label: String, url: URL)] = [
            ("range_path", ApiRoutes.Workouts.calendarRange(email: email, startDate: startStr, endDate: endStr)),
            ("month_path", ApiRoutes.Workouts.calendarMonth(email: email, month: filterMonth))
        ]
        return try await requestFirstNonEmpty(candidates)
    }

    func getPlannerDay(_ date: Date) async throws -> [ScheduledWorkoutDTO] {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            throw WorkoutsPlannerError.noEmail
        }
        let ymd = Self.fmtDayUTC.string(from: date)

        // 1) filter_date=yyyy-MM-dd → 2) range(yyyy-MM-dd .. yyyy-MM-dd)
        let candidates: [(label: String, url: URL)] = [
            ("day_filter", ApiRoutes.Workouts.calendarDay(email: email, date: ymd)),
            ("day_range",  ApiRoutes.Workouts.calendarRange(email: email, startDate: ymd, endDate: ymd))
        ]
        return try await requestFirstNonEmpty(candidates)
    }

    // MARK: - Common request helper
    private func requestFirstNonEmpty(_ candidates: [(label: String, url: URL)]) async throws -> [ScheduledWorkoutDTO] {
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
