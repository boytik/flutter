import Foundation
import OSLog

fileprivate let moveLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app",
    category: "MoveAPI"
)

extension MoveWorkoutsService {
    struct MoveItemFull: Codable {
        let workout_uuid: String
        let date: String               // "yyyy-MM-dd HH:mm:ss" — полночь локального дня
        let activity: String?
        let layers: Int
        let swim_layers: [Int]
        let day_of_week: Int           // ISO: Mon=1..Sun=7
        let duration_minutes: Int
        let temperature: Int?
        let is_deleted: Bool
    }

    func sendMoveRequestFull(email: String, targetDate: Date, workouts: [Workout]) async throws {
        // 00:00 локального дня, как во Flutter
        let midnight = CalendarMath.iso.startOfDay(for: targetDate)
        let dateString = DateUtils.ymdhmsSp.string(from: midnight)  // "yyyy-MM-dd HH:mm:ss"

        // ISO weekday: Mon=1..Sun=7
        let wk = Calendar.current.component(.weekday, from: midnight) // Sun=1..Sat=7
        let isoWeekday = ((wk + 5) % 7) + 1

        let items: [MoveItemFull] = workouts.map { w in
            let mins = max(1, Int((w.duration + 59) / 60))
            return MoveItemFull(
                workout_uuid: baseID(from: w.id),      // базовый UUID без суффиксов
                date: dateString,
                activity: w.activityType,
                layers: w.plannedLayers ?? 0,
                swim_layers: w.swimLayers ?? [],
                day_of_week: isoWeekday,
                duration_minutes: mins,
                temperature: nil,
                is_deleted: false
            )
        }

        let url = APIEnv.baseURL.appendingPathComponent("/workout_calendar/\(email)")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(items)

        if let token = UserDefaults.standard.string(forKey: "auth_token"), !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            moveLog.debug("auth token present: yes")
        } else {
            moveLog.debug("auth token present: no")
        }

        let ids = workouts.map(\.id).joined(separator: ",")
        let preview = String(data: (req.httpBody ?? Data()).prefix(2048), encoding: .utf8) ?? ""
        moveLog.info("➡️ MOVE FULL POST \(url.absoluteString, privacy: .public) items=\(workouts.count, privacy: .public) ids=\(ids, privacy: .public) bytes=\(req.httpBody?.count ?? 0, privacy: .public) preview=\(preview, privacy: .public)")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        moveLog.info("⬅️ MOVE FULL status=\(code, privacy: .public) bytes=\(data.count, privacy: .public)")

        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "MoveAPI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(msg)"])
        }
    }
}
