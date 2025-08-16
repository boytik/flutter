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

        // приоритет как в старой реализации
        let candidates = [meta.photoAfter, meta.photoBefore, meta.activityGraph, meta.heartRateGraph, meta.map]
        for s in candidates {
            if let s, !s.isEmpty {
                if let u = URL(string: s), u.scheme != nil { return u }
                if s.hasPrefix("/") { return URL(string: s, relativeTo: APIEnv.baseURL) }
            }
        }
        return nil
    }
}

// -------------------------------------------------------------

import Foundation
import SwiftUI

// …(ActivityThumbsRepository и его реализация — без изменений)…

@MainActor
final class CalendarViewModel: ObservableObject {

    enum PickersModes: String, CaseIterable { case calendar = "Календарь"; case history = "История" }
    enum HistoryFilter: String, CaseIterable { case completed = "Завершённые"; case all = "Все" }

    @Published var role: PersonalViewModel.Role = .user
    @Published var pickerMode: PickersModes = .calendar
    // стартуем с "Все", чтобы не было пустого экрана, если в текущем месяце нет завершённых
    @Published var historyFilter: HistoryFilter = .all { didSet { rebuildHistory() } }

    @Published var monthDates: [WorkoutDay] = []
    @Published var currentMonthDate: Date = Date()
    @Published var byDay: [Date: [CalendarItem]] = [:]

    @Published var filteredItems: [CalendarItem] = []

    private var monthPlanned: [Workout] = []
    private var monthActivities: [Activity] = []
    private var allActivities: [Activity] = []
    private var inspectorActivities: [Activity] = []
    @Published var thumbs: [String: URL] = [:]

    private let workoutPlannerRepo: WorkoutPlannerRepository
    private let inspectorRepo: InspectorRepository
    private let activitiesRepo: ActivityRepository
    private let thumbsRepo: ActivityThumbsRepository

    @Published var inspectorTypeFilter: String? = nil
    var inspectorTypes: [String] {
        let set = Set(inspectorActivities.compactMap { normalizedType($0.name) })
        return Array(set).sorted()
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

    func reload(role: PersonalViewModel.Role) async {
        self.role = role
        switch role {
        case .user:      await loadCalendarForMonth(currentMonthDate)
        case .inspector: await loadInspector()
        }
    }

    var currentMonth: String {
        let f = DateFormatter(); f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return f.string(from: currentMonthDate).capitalized
    }

    func previousMonth() {
        guard let d = Calendar.current.date(byAdding: .month, value: -1, to: currentMonthDate) else { return }
        currentMonthDate = d
        Task { await loadCalendarForMonth(d) }
    }

    func nextMonth() {
        guard let d = Calendar.current.date(byAdding: .month, value: 1, to: currentMonthDate) else { return }
        currentMonthDate = d
        Task { await loadCalendarForMonth(d) }
    }

    func items(on date: Date) -> [CalendarItem] {
        byDay[Calendar.current.startOfDay(for: date)] ?? []
    }

    func thumbFor(_ item: CalendarItem) -> URL? {
        if case let .activity(a) = item { return thumbs[a.id] }
        return nil
    }

    // MARK: USER
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
            // План месяца
            let plannerDTOs = try await workoutPlannerRepo.getPlannerCalendar(filterMonth: yyyyMM)
            let planned: [Workout] = plannerDTOs.compactMap { dto in
                guard let date = Self.parseDate(dto.date) else { return nil }
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

            // История завершённых
            let allActs = try await activitiesRepo.fetchAll()
            self.allActivities = allActs

            let monthActs = allActs.filter { a in
                guard let dt = a.createdAt else { return false }
                return dt >= cal.startOfDay(for: startD) &&
                       dt <= cal.date(bySettingHour: 23, minute: 59, second: 59, of: endD)!
            }
            self.monthActivities = monthActs

            // Контент по дням
            let workoutItems  = planned.map { CalendarItem.workout($0) }
            let activityItems = monthActs.map { CalendarItem.activity($0) }
            self.byDay = Dictionary(grouping: (workoutItems + activityItems)) {
                cal.startOfDay(for: $0.date)
            }

            // Маркеры на сетку
            self.monthDates = buildMarkers(for: monthDate, planned: planned, done: monthActs)

            // История
            rebuildHistory()

            // Fallback: если «Завершённые» пусто — переключаем на «Все»
            if filteredItems.isEmpty, historyFilter == .completed, !allActivities.isEmpty {
                historyFilter = .all
                rebuildHistory()
            }

            // Предзагрузка превью
            await prefetchThumbs(for: filteredItems.prefix(24))

        } catch {
            print("Calendar load error:", error.localizedDescription)
            monthPlanned = []; monthActivities = []; allActivities = []
            monthDates = []; byDay = [:]; filteredItems = []; thumbs = [:]
        }
    }

    private func rebuildHistory() {
        switch historyFilter {
        case .completed:
            filteredItems = monthActivities.map { .activity($0) }.sorted { $0.date > $1.date }
        case .all:
            filteredItems = allActivities.map { .activity($0) }.sorted { $0.date > $1.date }
        }
    }

    private func prefetchThumbs<S: Sequence>(for items: S) async where S.Element == CalendarItem {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else { return }
        var new: [String: URL] = [:]
        await withTaskGroup(of: (String, URL?).self) { group in
            for item in items {
                guard case let .activity(a) = item, thumbs[a.id] == nil else { continue }
                group.addTask { [thumbsRepo] in
                    let u = try? await thumbsRepo.fetchThumbURL(workoutKey: a.id, email: email)
                    return (a.id, u)
                }
            }
            for await (id, url) in group {
                if let url { new[id] = url }
            }
        }
        if !new.isEmpty { thumbs.merge(new) { old, _ in old } }
    }

    // MARK: INSPECTOR (без изменений по сути)
    private func loadInspector() async {
        do {
            async let a: [Activity] = inspectorRepo.getActivitiesForCheck()
            async let b: [Activity] = inspectorRepo.getActivitiesFullCheck()
            let (toCheck, full) = try await (a, b)

            var uniq: [String: Activity] = [:]
            for x in (toCheck + full) { uniq[x.id] = x }
            let all = Array(uniq.values)

            inspectorActivities = all
            applyInspectorFilter()

            monthDates = buildMarkers(for: currentMonthDate, planned: [], done: all)
        } catch {
            print("Inspector load error:", error.localizedDescription)
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
            inspectorActivities = []
            filteredItems = []
            monthDates = []
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

    // MARK: Маркеры/даты
    private func buildMarkers(for monthDate: Date, planned: [Workout], done: [Activity]) -> [WorkoutDay] {
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
        let f = DateFormatter(); f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .init(secondsFromGMT: 0); f.dateFormat = "yyyy-MM"; return f
    }()

    private static func parseDate(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }
        if let d = dfDateTimeISO.date(from: s) { return d }
        if let d = dfDateTimeSpace.date(from: s) { return d }
        if let d = dfDate.date(from: s) { return d }
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
