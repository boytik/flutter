import Foundation
import SwiftUI

// MARK: - Источник мини-превью для истории
protocol ActivityThumbsRepository {
    func fetchThumbURL(workoutKey: String, email: String) async throws -> URL?
}

final class ActivityThumbsRepositoryImpl: ActivityThumbsRepository {
    private let client = HTTPClient.shared

    private struct MetadataDTO: Decodable {
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
        let url = ApiRoutes.Workouts.metadata(workoutKey: workoutKey, email: email)
        let meta: MetadataDTO = try await client.request(MetadataDTO.self, url: url)

        // приоритет: photo_after → photo_before → activity_graph → heartRateGraph → map
        let candidates = [meta.photoAfter, meta.photoBefore, meta.activityGraph, meta.heartRateGraph, meta.map]
        for s in candidates {
            if let u = makeURL(s) { return u }
        }
        return nil
    }

    private func makeURL(_ s: String?) -> URL? {
        guard let s, !s.isEmpty else { return nil }
        if let u = URL(string: s), u.scheme != nil { return u }
        if s.hasPrefix("/") { return URL(string: s, relativeTo: APIEnv.baseURL) }
        return nil
    }
}

// MARK: - ViewModel
@MainActor
final class CalendarViewModel: ObservableObject {

    enum PickersModes: String, CaseIterable {
        case calendar = "Календарь"
        case history  = "История"
    }
    enum HistoryFilter: String, CaseIterable {
        case completed = "Завершённые" // завершённые за ТЕКУЩИЙ месяц
        case all       = "Все"          // все завершённые за ВСЁ время
    }

    @Published var role: PersonalViewModel.Role = .user
    @Published var pickerMode: PickersModes = .calendar
    @Published var historyFilter: HistoryFilter = .completed {
        didSet { rebuildHistory() }
    }

    // Календарь
    @Published var monthDates: [WorkoutDay] = []
    @Published var currentMonthDate: Date = Date()
    @Published var byDay: [Date: [CalendarItem]] = [:]

    // История (для списка)
    @Published var filteredItems: [CalendarItem] = []

    // Кэши
    private var monthPlanned: [Workout] = []     // план в выбранном месяце
    private var monthActivities: [Activity] = [] // завершённые в выбранном месяце
    private var allActivities: [Activity] = []   // вся история завершённых (из /list_workouts)
    private var inspectorActivities: [Activity] = []

    // thumbs для истории (по id активности)
    @Published var thumbs: [String: URL] = [:]

    // Репозитории
    private let workoutPlannerRepo: WorkoutPlannerRepository
    private let inspectorRepo: InspectorRepository
    private let activitiesRepo: ActivityRepository
    private let thumbsRepo: ActivityThumbsRepository

    init(workoutPlannerRepo: WorkoutPlannerRepository = WorkoutPlannerRepositoryImpl(),
         inspectorRepo: InspectorRepository = InspectorRepositoryImpl(),
         activitiesRepo: ActivityRepository = ActivityRepositoryImpl(),
         thumbsRepo: ActivityThumbsRepository = ActivityThumbsRepositoryImpl()) {
        self.workoutPlannerRepo = workoutPlannerRepo
        self.inspectorRepo = inspectorRepo
        self.activitiesRepo = activitiesRepo
        self.thumbsRepo = thumbsRepo
    }

    // MARK: Lifecycle
    func applyRole(_ role: PersonalViewModel.Role) async {
        self.role = role
        await refresh()
    }

    func refresh() async {
        switch role {
        case .user:
            await loadCalendarForMonth(currentMonthDate)
        case .inspector:
            await loadInspector()
        }
    }

    // Header
    var currentMonth: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return f.string(from: currentMonthDate).capitalized
    }

    func previousMonth() {
        guard let d = Calendar.current.date(byAdding: .month, value: -1, to: currentMonthDate) else { return }
        currentMonthDate = d
        Task { await refresh() }
    }

    func nextMonth() {
        guard let d = Calendar.current.date(byAdding: .month, value: 1, to: currentMonthDate) else { return }
        currentMonthDate = d
        Task { await refresh() }
    }

    // MARK: Loading — USER
    private func loadCalendarForMonth(_ monthDate: Date) async {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            monthPlanned = []; monthActivities = []; allActivities = []
            monthDates = []; byDay = [:]; filteredItems = []; thumbs = [:]
            return
        }

        let yyyyMM = Self.yyyyMM.string(from: monthDate)
        let (startD, endD) = monthRangeDates(monthDate)
        let cal = Calendar.current

        do {
            // 1) План на месяц (по Flutter-подходу — по месяцу)
            let plannerDTOs = try await workoutPlannerRepo.getPlannerCalendar(filterMonth: yyyyMM)
            let planned: [Workout] = plannerDTOs.compactMap { dto in
                guard let date = Self.parseDate(dto.date) else { return nil }
                // ограничим текущим месяцем
                guard date >= cal.startOfDay(for: startD),
                      date <= cal.date(bySettingHour: 23, minute: 59, second: 59, of: endD)! else { return nil }
                let minutes = (dto.durationHours ?? 0) * 60 + (dto.durationMinutes ?? 0)
                let name = dto.activityType ?? "Тренировка"
                return Workout(
                    id: dto.workoutUuid ?? UUID().uuidString,
                    name: name,
                    description: dto.description,
                    duration: minutes,
                    date: date
                )
            }
            self.monthPlanned = planned

            // 2) История завершённых: вся история (до сегодня) из /list_workouts
            let allActs = try await activitiesRepo.fetchAll()
            self.allActivities = allActs

            // …и версия, отфильтрованная в границах месяца:
            let monthActs = allActs.filter { a in
                guard let dt = a.createdAt else { return false }
                return dt >= cal.startOfDay(for: startD) &&
                       dt <= cal.date(bySettingHour: 23, minute: 59, second: 59, of: endD)!
            }
            self.monthActivities = monthActs

            // 3) Контент по дням для шита
            let workoutItems: [CalendarItem]  = planned.map { .workout($0) }
            let activityItems: [CalendarItem] = monthActs.map { .activity($0) }
            self.byDay = Dictionary(grouping: (workoutItems + activityItems)) {
                cal.startOfDay(for: $0.date)
            }

            // 4) точки на сетке
            self.monthDates = buildMarkers(for: monthDate,
                                           planned: planned,
                                           done: monthActs)

            // 5) история с учётом фильтра:
            rebuildHistory()

            // 6) мини-превью для верхней части списка
            await prefetchThumbs(for: filteredItems.prefix(24))

            print("✅ Planner (month): \(planned.count), month activities: \(monthActs.count), all activities: \(allActs.count)")
        } catch {
            print("Calendar load error:", error.localizedDescription)
            monthPlanned = []; monthActivities = []; allActivities = []
            monthDates = []; byDay = [:]; filteredItems = []; thumbs = [:]
        }
    }

    // Перестраиваем список «История» под выбранный фильтр
    private func rebuildHistory() {
        switch historyFilter {
        case .completed:
            // завершённые ТОЛЬКО за текущий месяц
            let activityItems = monthActivities.map { CalendarItem.activity($0) }
            filteredItems = activityItems.sorted { $0.date > $1.date }

        case .all:
            // все завершённые за ВСЁ время (как в оригинальном приложении)
            let allItems = allActivities.map { CalendarItem.activity($0) }
            filteredItems = allItems.sorted { $0.date > $1.date }
        }
    }

    // Мини-превью (для активностей)
    func thumbFor(_ item: CalendarItem) -> URL? {
        if case let .activity(a) = item { return thumbs[a.id] }
        return nil
    }

    private func prefetchThumbs<S: Sequence>(for items: S) async where S.Element == CalendarItem {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else { return }
        var new: [String: URL] = [:]

        await withTaskGroup(of: (String, URL?).self) { group in
            for item in items {
                guard case let .activity(a) = item else { continue }
                if thumbs[a.id] != nil { continue } // уже есть
                group.addTask {
                    let u = try? await self.thumbsRepo.fetchThumbURL(workoutKey: a.id, email: email)
                    return (a.id, u)
                }
            }
            for await (id, url) in group {
                if let url { new[id] = url }
            }
        }
        if !new.isEmpty { self.thumbs.merge(new) { old, _ in old } }
    }

    // MARK: Loading — INSPECTOR
    private func loadInspector() async {
        do {
            async let a: [Activity] = inspectorRepo.getActivitiesForCheck()
            async let b: [Activity] = inspectorRepo.getActivitiesFullCheck()
            let (toCheck, full) = try await (a, b)

            var uniq: [String: Activity] = [:]
            for x in (toCheck + full) { uniq[x.id] = x }
            let all = Array(uniq.values)

            inspectorActivities = all
            filteredItems = all
                .map { CalendarItem.activity($0) }
                .sorted { $0.date > $1.date }

            monthDates = buildMarkers(for: currentMonthDate, planned: [], done: all)

            print("✅ Inspector activities loaded: \(all.count)")
        } catch {
            print("Inspector load error:", error.localizedDescription)
            await loadInspectorActivitiesFallback()
        }
    }

    private func loadInspectorActivitiesFallback() async {
        do {
            let acts = try await activitiesRepo.fetchAll()
            inspectorActivities = acts
            filteredItems = acts
                .map { CalendarItem.activity($0) }
                .sorted { $0.date > $1.date }

            monthDates = buildMarkers(for: currentMonthDate, planned: [], done: acts)
        } catch {
            inspectorActivities = []
            filteredItems = []
            monthDates = []
        }
    }

    // MARK: Markers
    private static func color(for activityName: String) -> Color {
        switch activityName.lowercased() {
        case "yoga", "йога": return .purple
        case "walking/running", "walking", "running", "run", "walk", "ходьба", "бег": return .yellow
        case "water", "swim", "pool", "вода", "плавание": return .cyan
        case "sauna", "сауна": return .pink
        case "fasting", "пост": return .green
        default: return .blue
        }
    }

    private func buildMarkers(for monthDate: Date,
                              planned: [Workout],
                              done: [Activity]) -> [WorkoutDay] {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2

        guard
            let start = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)),
            let range = cal.range(of: .day, in: .month, for: monthDate)
        else { return [] }

        let plannedG: [Date: [Color]] = Dictionary(grouping: planned) {
            cal.startOfDay(for: $0.date)
        }.mapValues { $0.map { Self.color(for: $0.name) } }

        let doneDays: Set<Date> = Set(done.compactMap { a in
            a.createdAt.map { cal.startOfDay(for: $0) }
        })

        return range.compactMap { day -> WorkoutDay? in
            guard let date = cal.date(byAdding: .day, value: day - 1, to: start) else { return nil }
            let d = cal.startOfDay(for: date)
            var colors = plannedG[d] ?? []
            colors = Array(colors.prefix(6))
            if doneDays.contains(d), colors.count < 6 { colors.append(.green) }
            return WorkoutDay(date: date, dots: colors)
        }
    }

    func items(on day: Date) -> [CalendarItem] {
        let d = Calendar.current.startOfDay(for: day)
        return byDay[d] ?? []
    }

    // MARK: Helpers
    private func monthRangeDates(_ monthDate: Date) -> (Date, Date) {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
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
        guard let s, !s.isEmpty else { return nil }
        if let d = dfDateTime.date(from: s) { return d }
        if let d = dfDate.date(from: s)     { return d }
        return ISO8601DateFormatter().date(from: s)
    }

    private static let dfDateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let dfDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
