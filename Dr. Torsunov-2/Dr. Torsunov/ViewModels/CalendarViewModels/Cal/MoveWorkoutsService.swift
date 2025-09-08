import Foundation

struct MoveWorkoutsService {
    /// Реальный API-вызов переноса на сервере
    func sendMoveRequest(email: String, targetDate: Date, selectedIDs: [String]) async throws {
        struct MoveItem: Codable {
            let workout_uuid: String
            let date: String  // yyyy-MM-dd
        }
        let ymd = DateUtils.ymd.string(from: targetDate)
        let body: [MoveItem] = selectedIDs.map { .init(workout_uuid: $0, date: ymd) }

        let url = APIEnv.baseURL.appendingPathComponent("/workout_calendar/\(email)")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        if let token = UserDefaults.standard.string(forKey: "auth_token") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "MoveAPI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(msg)"])
        }
    }

    /// Синхронизация офлайн-кэша для источника и назначения
    func updateOfflineCache(prevPlanned: [Workout], updatedMonthPlanned: [Workout], movedIDs: [String], newDate: Date, offlineStore: WorkoutCacheStore) {
        // Источники — по «старым» датам
        let srcMonthKeys = Set(prevPlanned
            .filter { movedIDs.contains($0.id) }
            .map { MonthKey.from(date: $0.date) })

        // Месяц назначения
        let dstMonthKey = MonthKey.from(date: newDate)

        // 1) Источники: убрать перенесённые
        for mk in srcMonthKeys {
            if var env = try? offlineStore.loadMonth(mk) {
                env.workouts.removeAll { movedIDs.contains($0.id) }
                env.fetchedAt = Date()
                try? offlineStore.saveMonth(env)
            }
        }

        // 2) Назначение: добавить перенесённые (de-dup по id)
        let moved: [CachedWorkout] = updatedMonthPlanned
            .filter { movedIDs.contains($0.id) }
            .map {
                CachedWorkout(id: $0.id,
                              name: $0.name,
                              date: newDate,
                              durationSec: $0.duration,
                              type: $0.activityType,
                              updatedAt: Date())
            }

        if var dst = try? offlineStore.loadMonth(dstMonthKey) {
            let existing = Set(dst.workouts.map(\.id))
            dst.workouts.append(contentsOf: moved.filter { !existing.contains($0.id) })
            dst.fetchedAt = Date()
            try? offlineStore.saveMonth(dst)
        } else {
            let env = CachedMonthEnvelope(monthKey: dstMonthKey,
                                          fetchedAt: Date(),
                                          etag: nil,
                                          workouts: moved,
                                          softDeletedIDs: [])
            try? offlineStore.saveMonth(env)
        }
    }

    /// базовый UUID без суффиксов протокола типа "|water1"
    func baseID(from full: String) -> String {
        full.split(separator: "|", maxSplits: 1).first.map(String.init) ?? full
    }
}
