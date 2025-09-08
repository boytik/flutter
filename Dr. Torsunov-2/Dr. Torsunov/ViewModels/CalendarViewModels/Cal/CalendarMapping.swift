import Foundation

enum CalendarMapping {
    /// Универсальный детектор типа
    static func inferTypeKey(from strings: [String?]) -> String? {
        let hay = strings.compactMap { $0?.lowercased() }.joined(separator: " | ")
        if hay.contains("swim") || hay.contains("плав") || hay.contains("water") { return "swim" }
        if hay.contains("run") || hay.contains("бег") || hay.contains("walk") || hay.contains("ход") { return "run" }
        if hay.contains("bike") || hay.contains("velo") || hay.contains("вел") || hay.contains("cycl") { return "bike" }
        if hay.contains("yoga") || hay.contains("йога") || hay.contains("strength") || hay.contains("сил") { return "yoga" }
        if hay.contains("sauna") || hay.contains("баня") || hay.contains("хаммам") { return "sauna" }
        return nil
    }

    /// Маппинг PlannerItemDTO → [Workout] с поддержкой протоколов (вода → баня → вода)
    static func workouts(from dto: PlannerItemDTO) -> [Workout] {
        let rawDate = dto.date ?? dto.startDate ?? dto.plannedDate ?? dto.workoutDate
        guard let d = DateUtils.parse(rawDate) else { return [] }

        let minutes = (dto.durationHours ?? 0) * 60 + (dto.durationMinutes ?? 0)
        let baseID = dto.workoutUuid ?? dto.workoutKey ?? dto.id ?? UUID().uuidString
        let visibleName = dto.name ?? dto.type ?? dto.description ?? "Тренировка"

        let fromBackend = dto.activityType?.lowercased()
        let inferred = inferTypeKey(from: [dto.activityType, dto.type, dto.name, dto.description])
        let finalType = (fromBackend?.isEmpty == false ? fromBackend : inferred) ?? "other"

        // --- ПРОТОКОЛ: баня + вода слева/справа
        let waterArr = dto.swimLayers ?? []
        let saunaL = dto.layers ?? 0
        let isSaunaProtocol = finalType.contains("sauna") || finalType.contains("баня")

        if isSaunaProtocol && (saunaL > 0 || !waterArr.isEmpty) {
            var res: [Workout] = []

            if let w1 = waterArr.first, w1 > 0 {
                res.append(Workout(
                    id: baseID + "|water1",
                    name: visibleName,
                    description: dto.description,
                    duration: minutes,
                    date: d,
                    activityType: "water",
                    plannedLayers: min(5, w1),
                    swimLayers: nil
                ))
            }

            if saunaL > 0 {
                res.append(Workout(
                    id: baseID + "|sauna",
                    name: visibleName,
                    description: dto.description,
                    duration: minutes,
                    date: d,
                    activityType: "sauna",
                    plannedLayers: min(5, saunaL),
                    swimLayers: nil
                ))
            }

            if waterArr.count > 1, let w2 = waterArr.dropFirst().first, w2 > 0 {
                res.append(Workout(
                    id: baseID + "|water2",
                    name: visibleName,
                    description: dto.description,
                    duration: minutes,
                    date: d,
                    activityType: "water",
                    plannedLayers: min(5, w2),
                    swimLayers: nil
                ))
            }

            if !res.isEmpty { return res }
        }

        // Обычный (не протокол) — один элемент
        let single = Workout(
            id: baseID,
            name: visibleName,
            description: dto.description,
            duration: minutes,
            date: d,
            activityType: finalType,
            plannedLayers: dto.layers,
            swimLayers: dto.swimLayers
        )
        return [single]
    }

    /// Дедуп по id/дню+названию
    static func dedup(_ plans: [Workout]) -> [Workout] {
        var byID: [String: Workout] = [:]
        var seenKeys: Set<String> = []
        for w in plans {
            if !w.id.isEmpty {
                byID[w.id] = w
            } else {
                let key = DateUtils.ymd.string(from: w.date) + "|" + w.name.lowercased()
                if !seenKeys.contains(key) {
                    seenKeys.insert(key)
                    byID[key] = w
                }
            }
        }
        return Array(byID.values)
    }

    // Offline helper
    static func workout(from c: CachedWorkout) -> Workout {
        Workout(
            id: c.id,
            name: c.name,
            description: nil,
            duration: c.durationSec ?? 0,
            date: c.date,
            activityType: c.type,
            plannedLayers: nil,
            swimLayers: nil
        )
    }
}
