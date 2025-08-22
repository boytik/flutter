
import Foundation
import SwiftUI
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app",
                         category: "Calendar")

// MARK: - Cache JSON client

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

// MARK: - Utils

enum DateUtils {
    static let ymd: DateFormatter = {
        let f = DateFormatter(); f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static let ymdhmsT: DateFormatter = {
        let f = DateFormatter(); f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .current; f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"; return f
    }()
    static let ymdhmsSp: DateFormatter = {
        let f = DateFormatter(); f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .current; f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()
    static func parse(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }
        if let d = ymdhmsT.date(from: s) { return d }
        if let d = ymdhmsSp.date(from: s) { return d }
        if let d = ymd.date(from: s) { return d }
        return nil
    }
}

@MainActor
final class CalendarViewModel: ObservableObject {

    enum PickersModes: String, CaseIterable { case calendar = "Календарь"; case history = "История" }
    enum HistoryFilter: String, CaseIterable { case completed = "Завершённые"; case all = "Все" }

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

    private let inspectorRepo: InspectorRepository
    private let activitiesRepo: ActivityRepository
    private let client: CacheRequesting

    init(inspectorRepo: InspectorRepository = InspectorRepositoryImpl(),
         activitiesRepo: ActivityRepository = ActivityRepositoryImpl(),
         client: CacheRequesting = CacheJSONClient()) {
        self.inspectorRepo = inspectorRepo
        self.activitiesRepo = activitiesRepo
        self.client = client
    }

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
        byDay[isoCal.startOfDay(for: date)] ?? []
    }
    func thumbFor(_ item: CalendarItem) -> URL? { nil } // thumb логика опущена для краткости для этой задачи

    // MARK: Load

    private func loadCalendarForMonth(_ monthDate: Date) async {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else { reset(); return }

        let (gridStart, gridEnd) = visibleGridRange(for: monthDate)
        log.info("[Calendar] Fetch planner & activities…")

        // 1) Планы по диапазону
        let rangeDTOs = try? await fetchPlannerRange(email: email, start: gridStart, end: gridEnd)
        let rangePlanned = (rangeDTOs ?? []).compactMap { Self.workout(from: $0) }
        // 2) Fallback подневно для прошедших дней без планов
        var plannedDict = Dictionary(uniqueKeysWithValues: rangePlanned.map { ($0.id, $0) })

        let days = daysArray(from: gridStart, to: gridEnd)
        for d in days where d <= isoCal.startOfDay(for: Date()) {
            let hasForDay = rangePlanned.contains { isoCal.isDate($0.date, inSameDayAs: d) }
            if !hasForDay {
                if let arr = try? await fetchPlannerDay(email: email, date: d) {
                    for dto in arr {
                        if let w = Self.workout(from: dto) {
                            plannedDict[w.id] = w // de-dup by id
                        }
                    }
                }
            }
        }
        // Доп.дедуп: на случай, если id отсутствует
        let deduped = Self.dedup(Array(plannedDict.values))


        self.monthPlanned = deduped.filter { $0.date >= gridStart && $0.date <= gridEnd }

        // Активности
        let allActs = try? await activitiesRepo.fetchAll()
        self.allActivities = allActs ?? []
        self.monthActivities = (allActs ?? []).filter { a in
            guard let dt = a.createdAt else { return false }
            return dt >= gridStart && dt <= gridEnd
        }

        // Сборка элементов
        let workoutItems  = monthPlanned.map { CalendarItem.workout($0) }
        let activityItems = monthActivities.map { CalendarItem.activity($0) }
        self.byDay = Dictionary(grouping: (workoutItems + activityItems)) { isoCal.startOfDay(for: $0.date) }

        self.monthDates = buildMarkersGrid(from: gridStart, to: gridEnd, planned: monthPlanned, done: monthActivities)

        rebuildHistory()
    }

    // MARK: Planner DTO / fetch

    private struct PlannerItemDTO: Codable {
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

        enum CodingKeys: String, CodingKey {
            case date, description, type, name, id
            case startDate   = "start_date"
            case plannedDate = "planned_date"
            case workoutDate = "workout_date"
            case durationHours   = "duration_hours"
            case durationMinutes = "duration_minutes"
            case activityType    = "activity_type"
            case workoutUuid     = "workout_uuid"
            case workoutKey      = "workout_key"
        }
    }

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

    private static func workout(from dto: PlannerItemDTO) -> Workout? {
        let rawDate = dto.date ?? dto.startDate ?? dto.plannedDate ?? dto.workoutDate
        guard let d = DateUtils.parse(rawDate) else { return nil }
        let minutes = (dto.durationHours ?? 0) * 60 + (dto.durationMinutes ?? 0)
        let name = dto.activityType ?? dto.type ?? dto.name ?? dto.description ?? "Тренировка"
        let id = dto.workoutUuid ?? dto.workoutKey ?? dto.id ?? UUID().uuidString
        return Workout(id: id, name: name, description: dto.description, duration: minutes, date: d)
    }

    /// Дедупликатор планов: вначале по id, если их нет — по ключу (ymd+lowercased name)
    private static func dedup(_ plans: [Workout]) -> [Workout] {
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

    // MARK: Inspector

    func setInspectorFilter(_ type: String?) { inspectorTypeFilter = type; applyInspectorFilter() }
    @Published var inspectorTypeFilter: String? = nil
    private var inspectorTypesRaw: [String] {
        Array(Set(inspectorActivities.compactMap { $0.name?.lowercased() })).sorted()
    }
    var inspectorTypes: [String] { inspectorTypesRaw.map { Self.prettyType($0) } }

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

            let (s, e) = visibleGridRange(for: currentMonthDate)
            monthDates = buildMarkersGrid(from: s, to: e, planned: [], done: inspectorActivities)
        } catch {
            inspectorActivities = []
            filteredItems = []
            monthDates = []
        }
    }

    private func applyInspectorFilter() {
        var base = inspectorActivities
        if let t = inspectorTypeFilter?.lowercased() {
            base = base.filter { ($0.name?.lowercased() ?? "") == t }
        }
        filteredItems = base.map { .activity($0) }.sorted { $0.date > $1.date }
    }

    private static func prettyType(_ raw: String) -> String {
        let s = raw.lowercased()
        if s.contains("yoga") || s.contains("йога") { return "Йога" }
        if s.contains("walk") || s.contains("run") || s.contains("ход") || s.contains("бег") { return "Бег/Ходьба" }
        if s.contains("water") || s.contains("вода") || s.contains("swim") || s.contains("плав") { return "Вода" }
        if s.contains("sauna") || s.contains("баня") || s.contains("хаммам") { return "Баня" }
        if s.contains("fast")  || s.contains("пост")  || s.contains("голод") { return "Пост" }
        return raw.capitalized
    }

    // MARK: Build markers

    private func buildMarkersGrid(from start: Date, to end: Date, planned: [Workout], done: [Activity]) -> [WorkoutDay] {
        let startDay = isoCal.startOfDay(for: start)
        let endDay   = isoCal.startOfDay(for: end)

        // Уникализируем плановые внутри дня по ключу «name+id» → набор цветов без дублей
        var plannedColorsByDay: [Date: [Color]] = [:]
        let order: [Color] = [.purple, .orange, .blue, .red, .yellow, .green]
        func sortColors(_ arr: [Color]) -> [Color] {
            arr.sorted { (a, b) in (order.firstIndex(of: a) ?? 99) < (order.firstIndex(of: b) ?? 99) }
        }

        for w in planned {
            let day = isoCal.startOfDay(for: w.date)
            let color = Self.color(for: w.name)
            var colors = plannedColorsByDay[day] ?? []
            if !colors.contains(color) { colors.append(color) }
            plannedColorsByDay[day] = colors
        }
        for (k, v) in plannedColorsByDay { plannedColorsByDay[k] = Array(v.prefix(6)) }

        let doneDays: Set<Date> = Set(done.compactMap { $0.createdAt.map { isoCal.startOfDay(for: $0) } })

        var result: [WorkoutDay] = []
        var d = startDay
        while d <= endDay {
            var colors = plannedColorsByDay[d] ?? []
            colors = sortColors(colors)
            if doneDays.contains(d) {
                if !colors.contains(.green) { colors.append(.green) }
            }
            result.append(WorkoutDay(date: d, dots: Array(colors.prefix(6))))
            d = isoCal.date(byAdding: .day, value: 1, to: d)!
        }
        return result
    }

    private static func color(for name: String) -> Color {
        let s = name.lowercased()
        if s.contains("yoga") || s.contains("йога") { return .purple }
        if s.contains("walk") || s.contains("run") || s.contains("ход") || s.contains("бег") { return .orange }
        if s.contains("water") || s.contains("вода") || s.contains("swim") || s.contains("плав") { return .blue }
        if s.contains("sauna") || s.contains("баня") || s.contains("хаммам") { return .red }
        if s.contains("fast")  || s.contains("пост")  || s.contains("голод") { return .yellow }
        return .green
    }

    private func rebuildHistory() {
        switch historyFilter {
        case .completed: filteredItems = monthActivities.map { .activity($0) }.sorted { $0.date > $1.date }
        case .all:       filteredItems = allActivities.map { .activity($0) }.sorted { $0.date > $1.date }
        }
    }

    private func reset() {
        monthPlanned = []; monthActivities = []; allActivities = []
        monthDates = []; byDay = [:]; filteredItems = []; thumbs = [:]
    }

    // MARK: Helpers

    private var isoCal: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.locale = .current; c.firstWeekday = 2
        return c
    }

    private func visibleGridRange(for monthDate: Date) -> (Date, Date) {
        let cal = isoCal
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: monthDate))!
        let endOfMonth = cal.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!

        let weekdayStart = cal.component(.weekday, from: startOfMonth)
        let leading = (weekdayStart - cal.firstWeekday + 7) % 7
        let gridStart = cal.date(byAdding: .day, value: -leading, to: startOfMonth)!

        let weekdayEnd = cal.component(.weekday, from: endOfMonth)
        let trailing = (7 - ((weekdayEnd - cal.firstWeekday + 7) % 7) - 1 + 7) % 7
        let gridEnd = cal.date(byAdding: .day, value: trailing, to: endOfMonth)!

        return (gridStart, gridEnd)
    }

    private func daysArray(from start: Date, to end: Date) -> [Date] {
        var res: [Date] = []
        var d = isoCal.startOfDay(for: start)
        let last = isoCal.startOfDay(for: end)
        while d <= last {
            res.append(d)
            d = isoCal.date(byAdding: .day, value: 1, to: d)!
        }
        return res
    }
}
