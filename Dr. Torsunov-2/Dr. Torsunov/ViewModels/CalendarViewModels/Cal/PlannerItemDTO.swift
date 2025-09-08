import Foundation

/// Модели, возвращаемые бэкендом для планировщика
struct PlannerItemDTO: Codable {
    let date: String?
    let startDate: String?
    let plannedDate: String?
    let workoutDate: String?
    let description: String?
    let durationHours: Int?
    let durationMinutes: Int?
    let activityType: String?
    let type: String?
    let name: String?
    let workoutUuid: String?
    let workoutKey: String?
    let id: String?

    // Доп. поля для протоколов/слоёв
    let layers: Int?
    let swimLayers: [Int]?

    private enum CodingKeys: String, CodingKey {
        case date, description, type, name, id
        case startDate        = "start_date"
        case plannedDate      = "planned_date"
        case workoutDate      = "workout_date"
        case durationHours    = "duration_hours"
        case durationMinutes  = "duration_minutes"
        case activityLower    = "activity"
        case activitySnake    = "activity_type"
        case workoutUuid      = "workout_uuid"
        case workoutKey       = "workout_key"
        case layers
        case swimLayers       = "swim_layers"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date            = try c.decodeIfPresent(String.self, forKey: .date)
        startDate       = try c.decodeIfPresent(String.self, forKey: .startDate)
        plannedDate     = try c.decodeIfPresent(String.self, forKey: .plannedDate)
        workoutDate     = try c.decodeIfPresent(String.self, forKey: .workoutDate)
        description     = try c.decodeIfPresent(String.self, forKey: .description)
        durationHours   = try c.decodeIfPresent(Int.self,    forKey: .durationHours)
        durationMinutes = try c.decodeIfPresent(Int.self,    forKey: .durationMinutes)

        let actLower = try c.decodeIfPresent(String.self, forKey: .activityLower)
        let actSnake = try c.decodeIfPresent(String.self, forKey: .activitySnake)
        activityType  = (actLower ?? actSnake)

        type          = try c.decodeIfPresent(String.self, forKey: .type)
        name          = try c.decodeIfPresent(String.self, forKey: .name)
        workoutUuid   = try c.decodeIfPresent(String.self, forKey: .workoutUuid)
        workoutKey    = try c.decodeIfPresent(String.self, forKey: .workoutKey)
        id            = try c.decodeIfPresent(String.self, forKey: .id)

        layers        = try c.decodeIfPresent(Int.self, forKey: .layers)
        swimLayers    = try c.decodeIfPresent([Int].self, forKey: .swimLayers)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(date,            forKey: .date)
        try c.encodeIfPresent(startDate,       forKey: .startDate)
        try c.encodeIfPresent(plannedDate,     forKey: .plannedDate)
        try c.encodeIfPresent(workoutDate,     forKey: .workoutDate)
        try c.encodeIfPresent(description,     forKey: .description)
        try c.encodeIfPresent(durationHours,   forKey: .durationHours)
        try c.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try c.encodeIfPresent(activityType,    forKey: .activityLower)
        try c.encodeIfPresent(type,            forKey: .type)
        try c.encodeIfPresent(name,            forKey: .name)
        try c.encodeIfPresent(workoutUuid,     forKey: .workoutUuid)
        try c.encodeIfPresent(workoutKey,      forKey: .workoutKey)
        try c.encodeIfPresent(layers,          forKey: .layers)
        try c.encodeIfPresent(swimLayers,      forKey: .swimLayers)
    }
}
