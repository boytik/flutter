
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
        log.info("CalendarService initialized.")
    }

    // ===== OFFLINE PREFILL =====
    func preloadOffline(currentMonthDate: Date) -> OfflinePrefill? {
        log.info("Preloading offline data for month: \(currentMonthDate, privacy: .public)")

        let mk = MonthKey.from(date: currentMonthDate)
        do {
            if let env = try offlineStore.loadMonth(mk), !env.workouts.isEmpty {
                log.info("Offline data loaded successfully for \(currentMonthDate, privacy: .public)")

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
            } else {
                log.info("No offline data for month \(currentMonthDate, privacy: .public)")
            }
        } catch {
            log.error("Failed to load offline data for month \(currentMonthDate, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    // ===== LOAD MONTH =====
    func loadMonth(email: String, currentMonthDate: Date) async throws -> LoadedMonth {
        log.info("Loading month data for user \(email, privacy: .public) for month: \(currentMonthDate, privacy: .public)")

        let (gridStart, gridEnd) = CalendarMath.visibleGridRange(for: currentMonthDate)
        var monthPlanned: [Workout] = []
        var usedETag = false

        // Attempt to load via ETag
        if let etagRes = try? await loadMonthViaETag(currentMonthDate: currentMonthDate) {
            usedETag = true
            if etagRes.notModified {
                log.info("ETag: No changes for \(currentMonthDate, privacy: .public). Using cached data.")
            } else {
                monthPlanned = etagRes.workouts
                log.info("ETag: Data updated for \(currentMonthDate, privacy: .public). workouts=\(monthPlanned.count, privacy: .public)")
            }
        } else {
            log.info("ETag path unavailable — fallback to range/day API")
        }

        // Fallback: Fetch using range if ETag is not used
        if !usedETag {
            log.info("Using fallback method to load month data for \(currentMonthDate, privacy: .public)")

            let rangeDTOs = try? await fetchPlannerRange(email: email, start: gridStart, end: gridEnd)
            if rangeDTOs == nil {
                log.error("planner range failed; will try day-by-day fallback")
            }
            let rangePlanned = (rangeDTOs ?? []).flatMap { CalendarMapping.workouts(from: $0) }
            log.info("fallback range planned=\(rangePlanned.count, privacy: .public)")

            var plannedDict = Dictionary(uniqueKeysWithValues: rangePlanned.map { ($0.id, $0) })
            let days = CalendarMath.daysArray(from: gridStart, to: gridEnd)
            for d in days where d <= CalendarMath.iso.startOfDay(for: Date()) {
                let hasForDay = rangePlanned.contains { CalendarMath.iso.isDate($0.date, inSameDayAs: d) }
                if !hasForDay {
                    if let arr = try? await fetchPlannerDay(email: email, date: d) {
                        for dto in arr {
                            for w in CalendarMapping.workouts(from: dto) {
                                plannedDict[w.id] = w
                            }
                        }
                    } else {
                        log.error("planner day fetch failed for \(DateUtils.ymd.string(from: d), privacy: .public)")
                    }
                }
            }

            let deduped = CalendarMapping.dedup(Array(plannedDict.values))
            monthPlanned = deduped.filter { $0.date >= gridStart && $0.date <= gridEnd }
            log.info("fallback month planned final=\(monthPlanned.count, privacy: .public)")
        }

        // Fetch activities
        let allActs = try? await activitiesRepo.fetchAll()
        let allActivities = allActs ?? []
        let monthActivities = (allActs ?? []).filter { a in
            guard let dt = a.createdAt else { return false }
            return dt >= gridStart && dt <= gridEnd
        }
        log.info("activities: all=\(allActivities.count, privacy: .public) month=\(monthActivities.count, privacy: .public)")

        // Assemble items
        let workoutItems  = monthPlanned.map { CalendarItem.workout($0) }
        let activityItems = monthActivities.map { CalendarItem.activity($0) }
        let byDay = Dictionary(grouping: (workoutItems + activityItems)) { CalendarMath.iso.startOfDay(for: $0.date) }

        // Month dates
        let monthDates = CalendarGridBuilder.build(from: gridStart, to: gridEnd, planned: monthPlanned, done: monthActivities)

        // Save offline cache — only when we actually have data
        if !usedETag {
            if monthPlanned.isEmpty {
                log.info("skip offline save: empty monthPlanned due to server errors — keep previous cache")
            } else {
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
                    log.info("Offline cache saved for \(currentMonthDate, privacy: .public). count=\(cached.count, privacy: .public)")
                } catch {
                    log.error("Failed to save offline cache for \(currentMonthDate, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        // Preload neighboring months in the background
        Task.detached { [currentMonthDate] in
            let cal = Calendar(identifier: .iso8601)
            for delta in [-1, 1] {
                if let date = cal.date(byAdding: .month, value: delta, to: currentMonthDate) {
                    self.log.info("Preloading data for neighboring month: \(date, privacy: .public)")
                    let mk = MonthKey.from(date: date)
                    if (try? self.offlineStore.loadMonth(mk)) != nil { continue }
                    if let result = try? await CalendarAPIMapping.fetchMonthMapped(monthKey: mk, ifNoneMatch: nil),
                       !result.workouts.isEmpty {
                        let env = CachedMonthEnvelope(monthKey: mk,
                                                      fetchedAt: Date(),
                                                      etag: result.etag,
                                                      workouts: result.workouts,
                                                      softDeletedIDs: [])
                        try? self.offlineStore.saveMonth(env)
                        self.log.info("Preloaded and saved data for neighboring month: \(date, privacy: .public).")
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
    private func loadMonthViaETag(currentMonthDate: Date) async throws -> (workouts: [Workout], notModified: Bool) {
        let mk = MonthKey.from(date: currentMonthDate)

        var ifNone: String? = nil
        do {
            if let env = try offlineStore.loadMonth(mk) {
                ifNone = env.etag
                log.info("Using ETag from offline cache: \(ifNone ?? "None", privacy: .public) for month \(currentMonthDate, privacy: .public)")
            }
        } catch {
            log.error("Failed to load ETag for month \(currentMonthDate, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        let result = try await CalendarAPIMapping.fetchMonthMapped(monthKey: mk, ifNoneMatch: ifNone)

        if let prevTag = ifNone, result.workouts.isEmpty, result.etag == prevTag {
            log.info("ETag: No updates (304 Not Modified) for month \(currentMonthDate, privacy: .public).")
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
        log.info("Loaded workouts via ETag for month \(currentMonthDate, privacy: .public), \(workouts.count) workouts found.")
        return (workouts, false)
    }

    // MARK: Planner DTO / fetch (fallback)
    private func fetchPlannerRange(email: String, start: Date, end: Date) async throws -> [PlannerItemDTO] {
        log.info("Fetching planner range for \(email, privacy: .public) from \(start, privacy: .public) to \(end, privacy: .public)")
        var comps = URLComponents(url: APIEnv.baseURL.appendingPathComponent("/workout_calendar/\(email)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "start_date", value: DateUtils.ymd.string(from: start)),
            URLQueryItem(name: "end_date",   value: DateUtils.ymd.string(from: end))
        ]
        let url = comps.url!
        do {
            let arr: [PlannerItemDTO] = try await client.request(url, ttl: 60)
            log.info("[planner] range_path ok: \(arr.count, privacy: .public) items — \(url.absoluteString, privacy: .public)")
            return arr
        } catch {
            log.error("[planner] range_path error for \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func fetchPlannerDay(email: String, date: Date) async throws -> [PlannerItemDTO] {
        let ymd = DateUtils.ymd.string(from: date)
        let url = ApiRoutes.Workouts.calendarDay(email: email, date: ymd)
        log.info("Fetching planner day for \(email, privacy: .public) on \(date, privacy: .public)")
        do {
            let arr: [PlannerItemDTO] = try await client.request(url, ttl: 60)
            log.info("[planner] day_path ok: \(arr.count, privacy: .public) items — \(url.absoluteString, privacy: .public)")
            return arr
        } catch {
            log.error("[planner] day_path error for \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
