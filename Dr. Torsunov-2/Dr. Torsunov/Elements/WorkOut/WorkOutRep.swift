import Foundation

// MARK: - Contract
protocol WorkoutRepository {
    func fetchAll() async throws -> [Workout]
    func fetch(by id: String) async throws -> Workout
    func upload(workout: Workout) async throws
}

// MARK: - Implementation
final class WorkoutRepositoryImpl: WorkoutRepository {
    private let client = HTTPClient.shared
    private let planner: WorkoutPlannerRepository

    init(planner: WorkoutPlannerRepository = WorkoutPlannerRepositoryImpl()) {
        self.planner = planner
    }

    // Основной список тренировок.
    // 1) Пытаемся GET /workouts
    // 2) Если 404 — берём текущий месяц из /workout_calendar и маппим в [Workout]
    func fetchAll() async throws -> [Workout] {
        // 1) попытка основного эндпоинта
        do {
            let list: [Workout] = try await client.request([Workout].self, url: ApiRoutes.Workouts.list)
            return list
        } catch let NetworkError.server(status: code, _) where code == 404 {
            // 2) фолбэк на планировщик за текущий месяц
            let filter = Self.formatYearMonth(Date()) // "yyyy-MM"
            let dtos = try await planner.getPlannerCalendar(filterMonth: filter)
            return dtos.compactMap(Self.dtoToWorkout)
        }
    }

    // Деталь по id: пробуем точечный эндпоинт; если упал — ищем в fetchAll()
    func fetch(by id: String) async throws -> Workout {
        do {
            let item: Workout = try await client.request(Workout.self, url: ApiRoutes.Workouts.by(id: id))
            return item
        } catch {
            let all = try await fetchAll()
            if let found = all.first(where: { $0.id == id }) { return found }
            throw error
        }
    }

    // Загрузка тренировки (если на dev-е нет роутов — сервер вернёт 404, это ок)
    func upload(workout: Workout) async throws {
        try await client.requestVoid(
            url: ApiRoutes.Workouts.upload,
            method: .POST,
            body: workout
        )
    }

    // MARK: - Helpers (DTO -> Workout)
    private static func dtoToWorkout(_ dto: ScheduledWorkoutDTO) -> Workout? {
        guard let date = parseDate(dto.date) else { return nil }
        let name = dto.activityType?.capitalized ?? "Workout"
        let minutes = dto.durationMinutes ?? (dto.durationHours.map { $0 * 60 }) ?? 60
        return Workout(
            id: dto.workoutUuid ?? UUID().uuidString,
            name: name,
            description: dto.description,
            duration: minutes,
            date: date
        )
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        // 1) yyyy-MM-dd
        if let d = dateFormatter("yyyy-MM-dd").date(from: s) { return d }
        // 2) yyyy-MM-dd HH:mm:ss
        if let d = dateFormatter("yyyy-MM-dd HH:mm:ss").date(from: s) { return d }
        // 3) ISO8601 fallback
        return ISO8601DateFormatter().date(from: s)
    }

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .init(secondsFromGMT: 0)
        f.dateFormat = format
        return f
    }

    private static func formatYearMonth(_ date: Date) -> String {
        let f = dateFormatter("yyyy-MM")
        return f.string(from: date)
    }
}
