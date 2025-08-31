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

// MARK: - Models returned by backend
private struct PlannerItemDTO: Codable {
    let date: String?
    let startDate: String?
    let plannedDate: String?
    let workoutDate: String?
    let description: String?
    let durationHours: Int?
    let durationMinutes: Int?
    let activityType: String?   // итоговое поле; берём из "activity" или "activity_type"
    let type: String?
    let name: String?
    let workoutUuid: String?
    let workoutKey: String?
    let id: String?

    // ⬇️ Доп. поля для протоколов/слоёв
    let layers: Int?            // общее количество слоёв (например, сауна)
    let swimLayers: [Int]?      // водные слои слева/справа

    private enum CodingKeys: String, CodingKey {
        case date, description, type, name, id
        case startDate        = "start_date"
        case plannedDate      = "planned_date"
        case workoutDate      = "workout_date"
        case durationHours    = "duration_hours"
        case durationMinutes  = "duration_minutes"
        // поддерживаем оба названия ключа от бэка
        case activityLower    = "activity"
        case activitySnake    = "activity_type"
        case workoutUuid      = "workout_uuid"
        case workoutKey       = "workout_key"
        // новые
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

// MARK: - ViewModel

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

    // 🔄 Глобовый индикатор загрузки для экрана
    @Published var isLoading: Bool = false

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
    func thumbFor(_ item: CalendarItem) -> URL? { nil } // thumbs вне задачи

    // MARK: Load (USER)

    private func loadCalendarForMonth(_ monthDate: Date) async {
        isLoading = true
        defer { isLoading = false }

        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else { reset(); return }

        let (gridStart, gridEnd) = visibleGridRange(for: monthDate)
        log.info("[Calendar] Fetch planner & activities…")

        // 1) Планы по диапазону
        let rangeDTOs = try? await fetchPlannerRange(email: email, start: gridStart, end: gridEnd)
        let rangePlanned = (rangeDTOs ?? []).flatMap { Self.workouts(from: $0) }

        // 2) Fallback подневно для прошедших дней без планов
        var plannedDict = Dictionary(uniqueKeysWithValues: rangePlanned.map { ($0.id, $0) })
        let days = daysArray(from: gridStart, to: gridEnd)
        for d in days where d <= isoCal.startOfDay(for: Date()) {
            let hasForDay = rangePlanned.contains { isoCal.isDate($0.date, inSameDayAs: d) }
            if !hasForDay {
                if let arr = try? await fetchPlannerDay(email: email, date: d) {
                    for dto in arr {
                        for w in Self.workouts(from: dto) {
                            plannedDict[w.id] = w // de-dup by id
                        }
                    }
                }
            }
        }
        // Доп.дедуп: на случай, если id отсутствует
        let deduped = Self.dedup(Array(plannedDict.values))

        self.monthPlanned = deduped.filter { $0.date >= gridStart && $0.date <= gridEnd }

        // 3) Активности (факты)
        let allActs = try? await activitiesRepo.fetchAll()
        self.allActivities = allActs ?? []
        self.monthActivities = (allActs ?? []).filter { a in
            guard let dt = a.createdAt else { return false }
            return dt >= gridStart && dt <= gridEnd
        }

        // 4) Сборка элементов для экрана
        let workoutItems  = monthPlanned.map { CalendarItem.workout($0) }
        let activityItems = monthActivities.map { CalendarItem.activity($0) }
        self.byDay = Dictionary(grouping: (workoutItems + activityItems)) { isoCal.startOfDay(for: $0.date) }

        // 5) «Точки» календаря (план по типу, done — зелёный индикатор)
        self.monthDates = buildMarkersGrid(from: gridStart, to: gridEnd, planned: monthPlanned, done: monthActivities)

        rebuildHistory()
    }

    // MARK: Planner DTO / fetch

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

    /// Универсальный детектор типа по нескольким строкам (учитываем синонимы/локали)
    private static func inferTypeKey(from strings: [String?]) -> String? {
        let hay = strings.compactMap { $0?.lowercased() }.joined(separator: " | ")
        if hay.contains("swim") || hay.contains("плав") || hay.contains("water") { return "swim" }
        if hay.contains("run") || hay.contains("бег") || hay.contains("walk") || hay.contains("ход") { return "run" }
        if hay.contains("bike") || hay.contains("velo") || hay.contains("вел") || hay.contains("cycl") { return "bike" }
        if hay.contains("yoga") || hay.contains("йога") || hay.contains("strength") || hay.contains("сил") { return "yoga" }
        if hay.contains("sauna") || hay.contains("баня") || hay.contains("хаммам") { return "sauna" }
        return nil
    }

    /// Маппинг PlannerItemDTO → [Workout] с поддержкой протоколов (вода → баня → вода)
    private static func workouts(from dto: PlannerItemDTO) -> [Workout] {
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
        isLoading = true
        defer { isLoading = false }

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

    // MARK: Build markers (month dots)

    private func buildMarkersGrid(from start: Date, to end: Date, planned: [Workout], done: [Activity]) -> [WorkoutDay] {
        let startDay = isoCal.startOfDay(for: start)
        let endDay   = isoCal.startOfDay(for: end)

        // Уникализируем плановые внутри дня по цвету
        var plannedColorsByDay: [Date: [Color]] = [:]
        let order: [Color] = [.purple, .orange, .blue, .red, .yellow, .green]
        func sortColors(_ arr: [Color]) -> [Color] {
            arr.sorted { (a, b) in (order.firstIndex(of: a) ?? 99) < (order.firstIndex(of: b) ?? 99) }
        }

        for w in planned {
            let day = isoCal.startOfDay(for: w.date)
            let color = Self.color(for: w)
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
                if !colors.contains(.green) { colors.append(.green) } // индикатор наличия выполненной активности
            }
            result.append(WorkoutDay(date: d, dots: Array(colors.prefix(6))))
            d = isoCal.date(byAdding: .day, value: 1, to: d)!
        }
        return result
    }

    // MARK: Цвета для «точек» месяца

    private static func color(for w: Workout) -> Color {
        if let t = w.activityType, !t.isEmpty {
            return color(forTypeKey: t)
        }
        return color(forName: w.name)
    }

    private static func color(forName name: String) -> Color {
        let s = name.lowercased()
        if s.contains("yoga") || s.contains("йога") { return .purple }
        if s.contains("walk") || s.contains("run") || s.contains("ход") || s.contains("бег") { return .orange }
        if s.contains("water") || s.contains("вода") || s.contains("swim") || s.contains("плав") { return .blue }
        if s.contains("sauna") || s.contains("баня") || s.contains("хаммам") { return .red }
        if s.contains("fast")  || s.contains("пост")  || s.contains("голод") { return .yellow }
        return .green
    }

    private static func color(forTypeKey keyRaw: String) -> Color {
        let key = keyRaw.lowercased()
        if key.contains("yoga") { return .purple }
        if key.contains("run")  || key.contains("walk") { return .orange }
        if key.contains("swim") || key.contains("water") { return .blue }
        if key.contains("bike") || key.contains("cycl") || key.contains("вел") { return .yellow }
        if key.contains("sauna") || key.contains("баня") { return .red }
        return .green
    }

    // MARK: History & reset

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
