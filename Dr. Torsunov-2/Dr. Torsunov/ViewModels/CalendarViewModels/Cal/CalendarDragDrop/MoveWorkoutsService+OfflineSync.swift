import Foundation
import OSLog

extension MoveWorkoutsService {

    /// Перенумерация ID в офлайн-кэше целевого месяца (когда сервер меняет ID).
    func remapIDsInOfflineCache(idMap: [String: String],
                                targetDate: Date,
                                offlineStore: WorkoutCacheStore) {
        guard !idMap.isEmpty else { return }
        let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "MoveAPI")

        let destKey = MonthKey.from(date: targetDate)
        do {
            if var env = try offlineStore.loadMonth(destKey) {
                var changed = 0
                for i in env.workouts.indices {
                    if let newID = idMap[env.workouts[i].id] {
                        env.workouts[i].id = newID
                        env.workouts[i].updatedAt = Date()
                        changed += 1
                    }
                }
                if changed > 0 {
                    env.etag = nil
                    env.fetchedAt = Date()
                    try offlineStore.saveMonth(env)
                    log.info("🧩 offline ID remap in \(String(describing: destKey), privacy: .public): \(changed, privacy: .public) items")
                }
            }
        } catch {
            log.error("offline ID remap failed: \(String(describing: error.localizedDescription), privacy: .public)")
        }
    }

    /// Корректирует дату записей в офлайн-кэше.
    /// Группируем по строке "yyyy-MM", чтобы не требовать `Hashable` у `MonthKey`.
    func correctDatesInOfflineCache(idToDate: [String: Date],
                                    offlineStore: WorkoutCacheStore) {
        guard !idToDate.isEmpty else { return }
        let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "MoveAPI")

        let fmt = DateFormatter()
        fmt.locale = .init(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM"

        let grouped: [String: [(id: String, day: Date)]] = Dictionary(
            grouping: idToDate.map { ($0.key, CalendarMath.iso.startOfDay(for: $0.value)) },
            by: { fmt.string(from: $0.1) }
        )

        for (monthStr, pairs) in grouped {
            guard let sampleDate = pairs.first?.day else { continue }
            let mk = MonthKey.from(date: sampleDate)

            do {
                if var env = try offlineStore.loadMonth(mk) {
                    var changed = 0
                    for i in env.workouts.indices {
                        if let newDay = pairs.first(where: { $0.id == env.workouts[i].id })?.day {
                            env.workouts[i].date = newDay
                            env.workouts[i].updatedAt = Date()
                            changed += 1
                        }
                    }
                    if changed > 0 {
                        env.etag = nil
                        env.fetchedAt = Date()
                        try offlineStore.saveMonth(env)
                        log.info("🗓️ offline date fix in \(monthStr, privacy: .public): \(changed, privacy: .public) items")
                    }
                }
            } catch {
                log.error("offline date fix failed for \(monthStr, privacy: .public): \(String(describing: error.localizedDescription), privacy: .public)")
            }
        }
    }
}
