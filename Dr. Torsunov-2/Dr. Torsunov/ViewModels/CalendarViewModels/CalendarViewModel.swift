import Foundation
import SwiftUI
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app",
                         category: "CacheJSONClient")

protocol CacheRequesting {
    func request<T: Codable>(_ url: URL, ttl: TimeInterval) async throws -> T
}

struct CacheJSONClient: CacheRequesting {
    func request<T: Codable>(_ url: URL, ttl: TimeInterval) async throws -> T {
        let key = HTTPCacheKey.make(url: url, method: "GET", headers: [:])

        if let cached = HTTPCacheStore.shared.load(for: key),
           let decoded = try? JSONDecoder().decode(T.self, from: cached) {
            log.debug("[cache] HIT \(url.absoluteString, privacy: .public)")
            return decoded
        } else {
            log.debug("[cache] MISS \(url.absoluteString, privacy: .public)")
        }

        let value: T = try await HTTPClient.shared.request(url, method: .GET, headers: [:], body: nil)

        if let data = try? JSONEncoder().encode(value) {
            HTTPCacheStore.shared.save(data, for: key, ttl: ttl)
            log.debug("[cache] STORE \(url.absoluteString, privacy: .public) — \(data.count) bytes, ttl=\(Int(ttl))s")
        }
        return value
    }
}


// MARK: - Потокобезопасные сервисы

/// Чтобы не отправлять параллельно одинаковые префетчи
private actor ThumbsPrefetchState {
    private var inFlight = Set<String>()
    func start(_ id: String) -> Bool {
        if inFlight.contains(id) { return false }
        inFlight.insert(id); return true
    }
    func finish(_ id: String) { inFlight.remove(id) }
}

/// Негативный кэш (памятка о 500 на ключе) на короткий TTL
private actor NegativeKeyCache {
    private var store: [String: Date] = [:]
    private let ttl: TimeInterval
    init(ttl: TimeInterval = 300) { self.ttl = ttl } // 5 минут

    func contains(_ key: String) -> Bool {
        if let ts = store[key], Date().timeIntervalSince(ts) < ttl { return true }
        store.removeValue(forKey: key); return false
    }
    func noteFailure(_ key: String) { store[key] = Date() }
    func clear() { store.removeAll() }
}

// MARK: - Репозиторий превью активностей

protocol ActivityThumbsRepository {
    func fetchThumbURL(workoutKey: String, email: String) async throws -> URL?
}

final class ActivityThumbsRepositoryImpl: ActivityThumbsRepository {
    private static let failCache = NegativeKeyCache(ttl: 300)
    private let client: CacheRequesting
    init(client: CacheRequesting = CacheJSONClient()) { self.client = client }

    private struct MetadataDTO: Codable {
        let activityGraph: String?
        let heartRateGraph: String?
        let map: String?
        let photoBefore: String?
        let photoAfter: String?

        enum CodingKeys: String, CodingKey {
            case activityGraph = "activity_graph"
            case heartRateGraph
            case map
            case photoBefore = "photo_before"
            case photoAfter  = "photo_after"
        }
    }

    func fetchThumbURL(workoutKey: String, email: String) async throws -> URL? {
        if await Self.failCache.contains(workoutKey) { return nil }

        let url = ApiRoutes.Workouts.metadata(workoutKey: workoutKey, email: email)
        do {
            let meta: MetadataDTO = try await client.request(url, ttl: 60)

            let candidates = [meta.photoAfter, meta.photoBefore, meta.activityGraph, meta.heartRateGraph, meta.map]
            for s in candidates {
                guard let s, !s.isEmpty else { continue }
                if let u = URL(string: s), u.scheme != nil { return u }
                if s.hasPrefix("/") { return URL(string: s, relativeTo: APIEnv.baseURL) }
            }
            return nil
        } catch {
            if case let NetworkError.server(status, _) = error, status == 500 {
                await Self.failCache.noteFailure(workoutKey)
                return nil
            }
            throw error
        }
    }
}

// MARK: - ViewModel

@MainActor
final class CalendarViewModel: ObservableObject {

    enum PickersModes: String, CaseIterable { case calendar = "Календарь"; case history = "История" }
    enum HistoryFilter: String, CaseIterable { case completed = "Завершённые"; case all = "Все" }

    private static let thumbsState = ThumbsPrefetchState()
    private let maxThumbsPrefetch = 12

    @Published var role: PersonalViewModel.Role = .user
    @Published var pickerMode: PickersModes = .calendar
    @Published var historyFilter: HistoryFilter = .all { didSet { rebuildHistory() } }

    @Published var monthDates: [WorkoutDay] = []
    @Published var currentMonthDate: Date = Date()
    @Published var byDay: [Date: [CalendarItem]] = [:]

    @Published var filteredItems: [CalendarItem] = []
    @Published var thumbs: [String: URL] = [:]

    private var monthPlanned: [Workout] = []
    private var monthActivities: [Activity] = []
    private var allActivities: [Activity] = []
    private var inspectorActivities: [Activity] = []

    private let workoutPlannerRepo: WorkoutPlannerRepository
    private let inspectorRepo: InspectorRepository
    private let activitiesRepo: ActivityRepository
    private let thumbsRepo: ActivityThumbsRepository

    @Published var inspectorTypeFilter: String? = nil
    var inspectorTypes: [String] {
        Array(Set(inspectorActivities.compactMap { normalizedType($0.name) })).sorted()
    }

    init(workoutPlannerRepo: WorkoutPlannerRepository = WorkoutPlannerRepositoryImpl(),
         inspectorRepo: InspectorRepository = InspectorRepositoryImpl(),
         activitiesRepo: ActivityRepository = ActivityRepositoryImpl(),
         thumbsRepo: ActivityThumbsRepository = ActivityThumbsRepositoryImpl()) {
        self.workoutPlannerRepo = workoutPlannerRepo
        self.inspectorRepo = inspectorRepo
        self.activitiesRepo = activitiesRepo
        self.thumbsRepo = thumbsRepo
    }

    // MARK: Public API

    func reload(role: PersonalViewModel.Role) async {
        self.role = role
        switch role {
        case .user:      await loadCalendarForMonth(currentMonthDate)
        case .inspector: await loadInspector()
        }
    }

    var currentMonth: String {
        let f = DateFormatter(); f.locale = .current
        f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return f.string(from: currentMonthDate).capitalized
    }

    func previousMonth() {
        if let d = Calendar.current.date(byAdding: .month, value: -1, to: currentMonthDate) {
            currentMonthDate = d
            Task { await loadCalendarForMonth(d) }
        }
    }
    func nextMonth() {
        if let d = Calendar.current.date(byAdding: .month, value: 1, to: currentMonthDate) {
            currentMonthDate = d
            Task { await loadCalendarForMonth(d) }
        }
    }

    func items(on date: Date) -> [CalendarItem] {
        byDay[Calendar.current.startOfDay(for: date)] ?? []
    }
    func thumbFor(_ item: CalendarItem) -> URL? {
        if case let .activity(a) = item { return thumbs[a.id] }
        return nil
    }

    // MARK: Основная загрузка (роль: user)

    private func loadCalendarForMonth(_ monthDate: Date) async {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            reset(); return
        }

        let yyyyMM = Self.yyyyMM.string(from: monthDate)
        let (startD, endD) = monthRangeDates(monthDate)
        let cal = Calendar.current

        if let cached: [Workout] = try? KVStore.shared.get([Workout].self, namespace: "calendar", key: "planner_\(yyyyMM)") {
            self.monthPlanned = cached
        }
        if let cachedActs: [Activity] = try? KVStore.shared.get([Activity].self, namespace: "calendar", key: "activities_all") {
            self.allActivities = cachedActs
        }

        do {
            log.info("[Calendar] Fetch planner & activities…")

            let plannerDTOs = try await workoutPlannerRepo.getPlannerCalendar(filterMonth: yyyyMM)
            let planned: [Workout] = plannerDTOs.compactMap { dto in
                guard let date = Self.parseDate(dto.date) else { return nil }
                guard date >= cal.startOfDay(for: startD),
                      date <= cal.date(bySettingHour: 23, minute: 59, second: 59, of: endD)! else { return nil }
                let minutes = (dto.durationHours ?? 0) * 60 + (dto.durationMinutes ?? 0)
                let name = dto.activityType ?? "Тренировка"
                return Workout(id: dto.workoutUuid ?? UUID().uuidString,
                               name: name,
                               description: dto.description,
                               duration: minutes,
                               date: date)
            }
            self.monthPlanned = planned
            try? KVStore.shared.put(planned, namespace: "calendar", key: "planner_\(yyyyMM)", ttl: 60*60*24)

            let allActs = try await activitiesRepo.fetchAll()
            self.allActivities = allActs
            try? KVStore.shared.put(allActs, namespace: "calendar", key: "activities_all", ttl: 60*10)

            let monthActs = allActs.filter { a in
                guard let dt = a.createdAt else { return false }
                return dt >= cal.startOfDay(for: startD) &&
                       dt <= cal.date(bySettingHour: 23, minute: 59, second: 59, of: endD)!
            }
            self.monthActivities = monthActs

            let workoutItems  = planned.map { CalendarItem.workout($0) }
            let activityItems = monthActs.map { CalendarItem.activity($0) }
            self.byDay = Dictionary(grouping: (workoutItems + activityItems)) { cal.startOfDay(for: $0.date) }

            self.monthDates = buildMarkers(for: monthDate, planned: planned, done: monthActs)

            rebuildHistory()
            if filteredItems.isEmpty, historyFilter == .completed, !allActivities.isEmpty {
                historyFilter = .all
                rebuildHistory()
            }

            await prefetchThumbs(for: filteredItems.prefix(24))

            log.info("[Calendar] Loaded successfully")
        } catch {
            log.error("[Calendar] Load error: \(error.localizedDescription, privacy: .public)")
            reset()
        }
    }

    private func reset() {
        monthPlanned = []; monthActivities = []; allActivities = []
        monthDates = []; byDay = [:]; filteredItems = []; thumbs = [:]
    }

    private func rebuildHistory() {
        switch historyFilter {
        case .completed: filteredItems = monthActivities.map { .activity($0) }.sorted { $0.date > $1.date }
        case .all:       filteredItems = allActivities.map { .activity($0) }.sorted { $0.date > $1.date }
        }
    }

    // MARK: Префетч превью (без дублей)
    private func prefetchThumbs<S: Sequence>(for items: S) async where S.Element == CalendarItem {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else { return }

        var ids: [String] = []
        for item in items {
            guard case let .activity(a) = item else { continue }
            if thumbs[a.id] != nil { continue }
            if await CalendarViewModel.thumbsState.start(a.id) {
                ids.append(a.id); if ids.count >= maxThumbsPrefetch { break }
            }
        }
        guard !ids.isEmpty else { return }

        await withTaskGroup(of: (String, URL?).self) { group in
            for id in ids {
                group.addTask { [thumbsRepo] in
                    let url = try? await thumbsRepo.fetchThumbURL(workoutKey: id, email: email)
                    await CalendarViewModel.thumbsState.finish(id)
                    return (id, url)
                }
            }
            var new: [String: URL] = [:]
            for await (id, url) in group { if let url { new[id] = url } }
            if !new.isEmpty { thumbs.merge(new) { old, _ in old } }
        }
    }

    // MARK: INSPECTOR (как в оригинале, без шумных логов)
    private func loadInspector() async {
        do {
            async let a: [Activity] = inspectorRepo.getActivitiesForCheck()
            async let b: [Activity] = inspectorRepo.getActivitiesFullCheck()
            let (toCheck, full) = try await (a, b)

            var dedup: [String: Activity] = [:]
            for x in toCheck { if dedup[x.id] == nil { dedup[x.id] = x } }
            for x in full    { if dedup[x.id] == nil { dedup[x.id] = x } }

            inspectorActivities = Array(dedup.values)
            applyInspectorFilter()
            monthDates = buildMarkers(for: currentMonthDate, planned: [], done: inspectorActivities)
        } catch {
            log.error("[Inspector] Load error: \(error.localizedDescription, privacy: .public)")
            await loadInspectorActivitiesFallback()
        }
    }

    private func loadInspectorActivitiesFallback() async {
        do {
            let acts = try await activitiesRepo.fetchAll()
            inspectorActivities = acts
            applyInspectorFilter()
            monthDates = buildMarkers(for: currentMonthDate, planned: [], done: acts)
        } catch {
            inspectorActivities = []; filteredItems = []; monthDates = []
        }
    }

    func setInspectorFilter(_ type: String?) { inspectorTypeFilter = type; applyInspectorFilter() }
    private func applyInspectorFilter() {
        var base = inspectorActivities
        if let t = inspectorTypeFilter { base = base.filter { normalizedType($0.name) == t } }
        filteredItems = base.map { .activity($0) }.sorted { $0.date > $1.date }
    }
    private func normalizedType(_ raw: String?) -> String? {
        guard let s = raw?.lowercased() else { return nil }
        if s.contains("yoga") || s.contains("йога") { return "Йога" }
        if s.contains("water") || s.contains("вода") || s.contains("swim") { return "Вода" }
        if s.contains("walk") || s.contains("run") || s.contains("ход") || s.contains("бег") { return "Бег/Ходьба" }
        if s.contains("sauna") || s.contains("баня") { return "Баня" }
        if s.contains("fast")  || s.contains("пост") { return "Пост" }
        return nil
    }

    // MARK: Helpers
    private func buildMarkers(for monthDate: Date, planned: [Workout], done: [Activity]) -> [WorkoutDay] {
        var cal = Calendar(identifier: .iso8601); cal.firstWeekday = 2
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)),
              let range = cal.range(of: .day, in: .month, for: monthDate) else { return [] }

        let plannedG: [Date: [Color]] = Dictionary(grouping: planned) { cal.startOfDay(for: $0.date) }
            .mapValues { $0.map { Self.color(for: $0.name) } }
        let doneDays: Set<Date> = Set(done.compactMap { a in a.createdAt.map { cal.startOfDay(for: $0) } })

        return range.compactMap { day -> WorkoutDay? in
            guard let date = cal.date(byAdding: .day, value: day - 1, to: start) else { return nil }
            let d = cal.startOfDay(for: date)
            var colors = Array((plannedG[d] ?? []).prefix(6))
            if doneDays.contains(d), colors.count < 6 { colors.append(.green) }
            return WorkoutDay(date: date, dots: colors)
        }
    }

    private static func color(for name: String) -> Color {
        let s = name.lowercased()
        if s.contains("yoga") || s.contains("йога") { return .purple }
        if s.contains("walk") || s.contains("run") || s.contains("ход") || s.contains("бег") { return .orange }
        if s.contains("water") || s.contains("вода") || s.contains("swim") { return .blue }
        if s.contains("sauna") || s.contains("баня") { return .red }
        if s.contains("fast") || s.contains("пост") { return .yellow }
        return .green
    }

    private func monthRangeDates(_ monthDate: Date) -> (Date, Date) {
        var cal = Calendar(identifier: .iso8601); cal.firstWeekday = 2
        let start = cal.date(from: cal.dateComponents([.year, .month], from: monthDate))!
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        return (start, end)
    }

    private static let yyyyMM: DateFormatter = {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .init(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static func parseDate(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }
        if let d = dfDateTimeISO.date(from: s)   { return d }
        if let d = dfDateTimeSpace.date(from: s) { return d }
        if let d = dfDate.date(from: s)          { return d }
        return nil
    }
    private static let dfDateTimeISO: DateFormatter = {
        let f = DateFormatter(); f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .current; f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"; return f
    }()
    private static let dfDateTimeSpace: DateFormatter = {
        let f = DateFormatter(); f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .current; f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()
    private static let dfDate: DateFormatter = {
        let f = DateFormatter(); f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f
    }()
}
