import Foundation

// MARK: - Planner mutation DTOs (avoid name clash with ScheduledWorkoutDTO used for reading)
public struct PlannerScheduledWorkoutMutationDTO: Codable, Equatable {
    public var workoutUUID: String?
    public var isDeleted: Bool?
    public var date: String?
    public var startTime: String?
    public var endTime: String?
    public var workoutType: String?
    public var comment: String?

    enum CodingKeys: String, CodingKey {
        case workoutUUID = "workout_uuid"
        case isDeleted   = "is_deleted"
        case date
        case startTime   = "start_time"
        case endTime     = "end_time"
        case workoutType = "workout_type"
        case comment
    }

    public init(workoutUUID: String? = nil,
                isDeleted: Bool? = nil,
                date: String? = nil,
                startTime: String? = nil,
                endTime: String? = nil,
                workoutType: String? = nil,
                comment: String? = nil) {
        self.workoutUUID = workoutUUID
        self.isDeleted   = isDeleted
        self.date        = date
        self.startTime   = startTime
        self.endTime     = endTime
        self.workoutType = workoutType
        self.comment     = comment
    }
}

// Ответ createPlan возвращает список запланированных тренировок.
// В проекте уже есть ScheduledWorkoutDTO (для чтения). Чтобы не дублировать, используем совместимую оболочку.
public struct PlanResultDTO: Decodable {
    public let workouts: [ScheduledWorkoutDTO]
}
