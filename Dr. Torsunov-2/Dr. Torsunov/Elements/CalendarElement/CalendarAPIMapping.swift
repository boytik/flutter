import Foundation

enum CalendarAPIMapping {

    private struct InlinePlannerItemDTO: Decodable {
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
        let layers: Int?
        let swimLayers: [Int]?

        enum CodingKeys: String, CodingKey {
            case date, description, type, name, id, layers
            case startDate       = "start_date"
            case plannedDate     = "planned_date"
            case workoutDate     = "workout_date"
            case durationHours   = "duration_hours"
            case durationMinutes = "duration_minutes"
            case activityLower   = "activity"
            case activitySnake   = "activity_type"
            case workoutUuid     = "workout_uuid"
            case workoutKey      = "workout_key"
            case swimLayers      = "swim_layers"
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
            activityType    = (actLower ?? actSnake)
            type            = try c.decodeIfPresent(String.self, forKey: .type)
            name            = try c.decodeIfPresent(String.self, forKey: .name)
            workoutUuid     = try c.decodeIfPresent(String.self, forKey: .workoutUuid)
            workoutKey      = try c.decodeIfPresent(String.self, forKey: .workoutKey)
            id              = try c.decodeIfPresent(String.self, forKey: .id)
            layers          = try c.decodeIfPresent(Int.self,    forKey: .layers)
            swimLayers      = try c.decodeIfPresent([Int].self,  forKey: .swimLayers)
        }
    }

    static func fetchMonthMapped(monthKey: String, ifNoneMatch: String?) async throws -> (etag: String?, workouts: [CachedWorkout]) {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM"
        guard let startMonth = df.date(from: monthKey) else { return (etag: nil, workouts: []) }
        var cal = Calendar(identifier: .iso8601); cal.firstWeekday = 2
        let endMonth = cal.date(byAdding: .month, value: 1, to: startMonth)!
        let start = DateUtils.ymd.string(from: startMonth)
        let end   = DateUtils.ymd.string(from: cal.date(byAdding: .day, value: -1, to: endMonth)!)

        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else { return (etag: nil, workouts: []) }

        var comps = URLComponents(url: APIEnv.baseURL.appendingPathComponent("/workout_calendar/\(email)"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [ .init(name: "start_date", value: start), .init(name: "end_date", value: end) ]
        var req = URLRequest(url: comps.url!); req.httpMethod = "GET"
        if let tag = ifNoneMatch { req.addValue(tag, forHTTPHeaderField: "If-None-Match") }
        if let token = UserDefaults.standard.string(forKey: "auth_token") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 304 {
            return (etag: http.value(forHTTPHeaderField: "ETag"), workouts: [])
        }

        let dtos = try JSONDecoder().decode([InlinePlannerItemDTO].self, from: data)
        let workouts = mapToCachedWorkouts(dtos)
        let etag = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag")
        return (etag: etag, workouts: workouts)
    }

    private static func inferTypeKey(_ strings: [String?]) -> String? {
        let hay = strings.compactMap { $0?.lowercased() }.joined(separator: " | ")
        if hay.contains("swim") || hay.contains("плав") || hay.contains("water") { return "swim" }
        if hay.contains("run") || hay.contains("бег") || hay.contains("walk") || hay.contains("ход") { return "run" }
        if hay.contains("bike") || hay.contains("velo") || hay.contains("вел") || hay.contains("cycl") { return "bike" }
        if hay.contains("yoga") || hay.contains("йога") || hay.contains("strength") || hay.contains("сил") { return "yoga" }
        if hay.contains("sauna") || hay.contains("баня") || hay.contains("хаммам") { return "sauna" }
        return nil
    }

    private static func mapToCachedWorkouts(_ dtos: [InlinePlannerItemDTO]) -> [CachedWorkout] {
        var out: [CachedWorkout] = []
        for dto in dtos {
            let rawDate = dto.date ?? dto.startDate ?? dto.plannedDate ?? dto.workoutDate
            guard let d = DateUtils.parse(rawDate) else { continue }
            let minutes = (dto.durationHours ?? 0) * 60 + (dto.durationMinutes ?? 0)
            let baseID = dto.workoutUuid ?? dto.workoutKey ?? dto.id ?? UUID().uuidString
            let visibleName = dto.name ?? dto.type ?? dto.description ?? "Тренировка"
            let fromBackend = dto.activityType?.lowercased()
            let inferred = inferTypeKey([dto.activityType, dto.type, dto.name, dto.description])
            let finalType = (fromBackend?.isEmpty == false ? fromBackend : inferred) ?? "other"

            let waterArr = dto.swimLayers ?? []
            let saunaL = dto.layers ?? 0
            let isSaunaProtocol = finalType.contains("sauna") || finalType.contains("баня")

            if isSaunaProtocol && (saunaL > 0 || !waterArr.isEmpty) {
                if let w1 = waterArr.first, w1 > 0 {
                    out.append(CachedWorkout(id: baseID + "|water1", name: visibleName, date: d, durationSec: minutes, type: "water", updatedAt: Date()))
                }
                if saunaL > 0 {
                    out.append(CachedWorkout(id: baseID + "|sauna", name: visibleName, date: d, durationSec: minutes, type: "sauna", updatedAt: Date()))
                }
                if waterArr.count > 1, let w2 = waterArr.dropFirst().first, w2 > 0 {
                    out.append(CachedWorkout(id: baseID + "|water2", name: visibleName, date: d, durationSec: minutes, type: "water", updatedAt: Date()))
                }
                continue
            }

            out.append(CachedWorkout(id: baseID, name: visibleName, date: d, durationSec: minutes, type: finalType, updatedAt: Date()))
        }
        return out
    }
}
