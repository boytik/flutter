import Foundation
import OSLog
import SwiftUI

struct OfflinePrefill {
    let items: [CachedWorkout]
    let monthPlanned: [Workout]
    let byDay: [Date: [CalendarItem]]
    let monthDates: [WorkoutDay]
}

struct LoadedMonth {
    let monthPlanned: [Workout]
    let monthActivities: [Activity]
    let allActivities: [Activity]
    let byDay: [Date: [CalendarItem]]
    let monthDates: [WorkoutDay]
    let usedETag: Bool
}

final class CalendarService {
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "Calendar")
    private let activitiesRepo: ActivityRepository
    private let client: CacheRequesting
    private let offlineStore: WorkoutCacheStore

    init(activitiesRepo: ActivityRepository,
         client: CacheRequesting = CacheJSONClient(),
         offlineStore: WorkoutCacheStore = WorkoutCacheStore()) {
        self.activitiesRepo = activitiesRepo
        self.client = client
        self.offlineStore = offlineStore
    }

    // ===== OFFLINE PREFILL =====
    func preloadOffline(currentMonthDate: Date) -> OfflinePrefill? {
        let mk = MonthKey.from(date: currentMonthDate)
        do {
            if let env = try offlineStore.loadMonth(mk), !env.workouts.isEmpty {
                let cached = env.workouts
                let cachedWorkouts: [Workout] = cached.map(CalendarMapping.workout(from:))
                let workoutItems  = cachedWorkouts.map { CalendarItem.workout($0) }
                let byDay = Dictionary(grouping: workoutItems) { CalendarMath.iso.startOfDay(for: $0.date) }

                let (s, e) = CalendarMath.visibleGridRange(for: currentMonthDate)
                let monthDates = CalendarGridBuilder.build(from: s, to: e, planned: cachedWorkouts, done: [])

                return .init(items: cached,
                             monthPlanned: cachedWorkouts,
                             byDay: byDay,
                             monthDates: monthDates)
            }
        } catch {
            // нет кэша — ок
        }
        return nil
    }

    // ===== LOAD MONTH =====
    func loadMonth(email: String, currentMonthDate: Date) async throws -> LoadedMonth {
        let (gridStart, gridEnd) = CalendarMath.visibleGridRange(for: currentMonthDate)
        log.info("[Calendar] Fetch planner & activities…")

        var monthPlanned: [Workout] = []
        var usedETag = false

        // === Новый путь: месячная загрузка через ETag
        if let etagRes = try? await loadMonthViaETag(currentMonthDate: currentMonthDate) {
            if etagRes.notModified {
                // monthPlanned останется из офлайна (ViewModel установит до вызова)
            } else {
                monthPlanned = etagRes.workouts
            }
            usedETag = true
        }

        // === Fallback: старые ручки (range/day), если ETag недоступен/упал
        if !usedETag {
            // 1) Планы по диапазону
            let rangeDTOs = try? await fetchPlannerRange(email: email, start: gridStart, end: gridEnd)
            let rangePlanned = (rangeDTOs ?? []).flatMap { CalendarMapping.workouts(from: $0) }

            // 2) Fallback подневно для прошедших дней без планов
            var plannedDict = Dictionary(uniqueKeysWithValues: rangePlanned.map { ($0.id, $0) })
            let days = CalendarMath.daysArray(from: gridStart, to: gridEnd)
            for d in days where d <= CalendarMath.iso.startOfDay(for: Date()) {
                let hasForDay = rangePlanned.contains { CalendarMath.iso.isDate($0.date, inSameDayAs: d) }
                if !hasForDay {
                    if let arr = try? await fetchPlannerDay(email: email, date: d) {
                        for dto in arr {
                            for w in CalendarMapping.workouts(from: dto) {
                                plannedDict[w.id] = w // de-dup by id
                            }
                        }
                    }
                }
            }
            // Доп.дедуп: на случай, если id отсутствует
            let deduped = CalendarMapping.dedup(Array(plannedDict.values))
            monthPlanned = deduped.filter { $0.date >= gridStart && $0.date <= gridEnd }
        }

        // 3) Активности (факты)
        let allActs = try? await activitiesRepo.fetchAll()
        let allActivities = allActs ?? []
        let monthActivities = (allActs ?? []).filter { a in
            guard let dt = a.createdAt else { return false }
            return dt >= gridStart && dt <= gridEnd
        }

        // 4) Сборка элементов для экрана
        let workoutItems  = monthPlanned.map { CalendarItem.workout($0) }
        let activityItems = monthActivities.map { CalendarItem.activity($0) }
        let byDay = Dictionary(grouping: (workoutItems + activityItems)) { CalendarMath.iso.startOfDay(for: $0.date) }

        // 5) «Точки» месяца
        let monthDates = CalendarGridBuilder.build(from: gridStart, to: gridEnd, planned: monthPlanned, done: monthActivities)

        // 6) Если работали по fallback-пути — положим месяц в офлайн-кэш
        if !usedETag {
            do {
                let mk = MonthKey.from(date: currentMonthDate)
                let cached: [CachedWorkout] = monthPlanned.map {
                    CachedWorkout(id: $0.id,
                                  name: $0.name,
                                  date: $0.date,
                                  durationSec: $0.duration,
                                  type: $0.activityType,
                                  updatedAt: Date())
                }
                let envelope = CachedMonthEnvelope(monthKey: mk,
                                                   fetchedAt: Date(),
                                                   etag: nil,
                                                   workouts: cached,
                                                   softDeletedIDs: [])
                try offlineStore.saveMonth(envelope)
            } catch {
                // best-effort
            }
        }

        // 7) Прелоад соседних месяцев (±1)
        let store = offlineStore
        Task.detached { [currentMonthDate, store] in
            let cal = Calendar(identifier: .iso8601)
            for delta in [-1, 1] {
                if let date = cal.date(byAdding: .month, value: delta, to: currentMonthDate) {
                    let mk = MonthKey.from(date: date)
                    if (try? store.loadMonth(mk)) != nil { continue }
                    if let result = try? await CalendarAPIMapping.fetchMonthMapped(monthKey: mk, ifNoneMatch: nil),
                       !result.workouts.isEmpty {
                        let env = CachedMonthEnvelope(monthKey: mk,
                                                      fetchedAt: Date(),
                                                      etag: result.etag,
                                                      workouts: result.workouts,
                                                      softDeletedIDs: [])
                        try? store.saveMonth(env)
                    }
                }
            }
        }

        return .init(monthPlanned: monthPlanned,
                     monthActivities: monthActivities,
                     allActivities: allActivities,
                     byDay: byDay,
                     monthDates: monthDates,
                     usedETag: usedETag)
    }

    // MARK: ETag-month loader
    /// Загружает месяц через ETag.
    private func loadMonthViaETag(currentMonthDate: Date) async throws -> (workouts: [Workout], notModified: Bool) {
        let mk = MonthKey.from(date: currentMonthDate)

        var ifNone: String? = nil
        do {
            if let env = try offlineStore.loadMonth(mk) {
                ifNone = env.etag
            }
        } catch {
            // ignore
        }

        let result = try await CalendarAPIMapping.fetchMonthMapped(monthKey: mk, ifNoneMatch: ifNone)

        if let prevTag = ifNone, result.workouts.isEmpty, result.etag == prevTag {
            return ([], true) // 304 Not Modified
        }

        let workouts = result.workouts.map(CalendarMapping.workout(from:))
        let envelope = CachedMonthEnvelope(
            monthKey: mk,
            fetchedAt: Date(),
            etag: result.etag,
            workouts: result.workouts,
            softDeletedIDs: []
        )
        try? offlineStore.saveMonth(envelope)
        return (workouts, false)
    }

    // MARK: Planner DTO / fetch (fallback)
    private func fetchPlannerRange(email: String, start: Date, end: Date) async throws -> [PlannerItemDTO] {
        var comps = URLComponents(url: APIEnv.baseURL.appendingPathComponent("/workout_calendar/\(email)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "start_date", value: DateUtils.ymd.string(from: start)),
            URLQueryItem(name: "end_date",   value: DateUtils.ymd.string(from: end))
        ]
        let url = comps.url!
        let arr: [PlannerItemDTO] = try await client.request(url, ttl: 60)
        log.info("[planner] range_path ok: \(arr.count, privacy: .public) items — \(url.absoluteString, privacy: .public)")
        return arr
    }

    private func fetchPlannerDay(email: String, date: Date) async throws -> [PlannerItemDTO] {
        let ymd = DateUtils.ymd.string(from: date)
        let url = ApiRoutes.Workouts.calendarDay(email: email, date: ymd)
        return try await client.request(url, ttl: 60)
    }
}
