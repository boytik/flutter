import Foundation
import SwiftUI

// MARK: - Planner DTO из /workout_calendar (для роли user)
struct PlannerEntry: Decodable, Identifiable, Equatable {
    let id: String            // workout_uuid
    let activity: String
    let dateString: String    // "yyyy-MM-dd HH:mm:ss"
    let passed: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "workout_uuid"
        case activity
        case dateString = "date"
        case passed
    }

    var date: Date {
        PlannerEntry.df.date(from: dateString) ?? Date()
    }

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = .current
        return f
    }()
}

// MARK: - Репозиторий планировщика
protocol PlannerRepository {
    func fetchRange(email: String, start: String, end: String) async throws -> [PlannerEntry]
}

final class PlannerRepositoryImpl: PlannerRepository {
    private let client = HTTPClient.shared

    func fetchRange(email: String, start: String, end: String) async throws -> [PlannerEntry] {
        let url = ApiRoutes.Workouts.calendarRange(email: email, startDate: start, endDate: end)
        let items: [PlannerEntry] = try await client.request([PlannerEntry].self, url: url)
        print("✅ Planner loaded from:", url.absoluteString)
        return items
    }
}



// MARK: - ViewModel
import Foundation
import SwiftUI

@MainActor
final class CalendarViewModel: ObservableObject {

    enum PickersModes: String, CaseIterable {
        case calendar = "Календарь"
        case history  = "История"
    }

    @Published var role: PersonalViewModel.Role = .user
    @Published var pickerMode: PickersModes = .calendar

    // Календарь
    @Published var monthDates: [WorkoutDay] = []
    @Published var currentMonthDate: Date = Date()
    /// Содержимое по дням (startOfDay): плановые и выполненные элементы
    @Published var byDay: [Date: [CalendarItem]] = [:]

    // История (для списка)
    @Published var filteredItems: [CalendarItem] = []

    // Кэши
    private var monthPlanned: [Workout] = []          // запланированные в выбранном месяце
    private var inspectorActivities: [Activity] = []  // для роли инспектора

    // Репозитории
    private let workoutPlannerRepo: WorkoutPlannerRepository
    private let inspectorRepo: InspectorRepository
    private let activitiesRepo: ActivityRepository

    init(workoutPlannerRepo: WorkoutPlannerRepository = WorkoutPlannerRepositoryImpl(),
         inspectorRepo: InspectorRepository = InspectorRepositoryImpl(),
         activitiesRepo: ActivityRepository = ActivityRepositoryImpl()) {
        self.workoutPlannerRepo = workoutPlannerRepo
        self.inspectorRepo = inspectorRepo
        self.activitiesRepo = activitiesRepo
        self.monthDates = [] // покажем пустую сетку до загрузки
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

    // MARK: Header helpers
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

    // MARK: Loading — USER (план + история месяца)
    private func loadCalendarForMonth(_ monthDate: Date) async {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            self.monthPlanned = []
            self.monthDates = []
            self.filteredItems = []
            self.byDay = [:]
            return
        }

        let yyyyMM = Self.yyyyMM.string(from: monthDate)
        let (startD, endD) = monthRangeDates(monthDate)
        let cal = Calendar.current

        do {
            // 1) План на месяц (как во Flutter — по месяцу)
            let plannerDTOs = try await workoutPlannerRepo.getPlannerCalendar(filterMonth: yyyyMM)

            // Преобразуем и ФИЛЬТРУЕМ строго в выбранный месяц (на бэке у тебя бывает много записей)
            let plannedWorkouts: [Workout] = plannerDTOs.compactMap { dto in
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
            self.monthPlanned = plannedWorkouts

            // 2) История: все активности → оставим только внутри месяца
            let allActs = try await activitiesRepo.fetchAll()
            let monthActs = allActs.filter { a in
                guard let dt = a.createdAt else { return false }
                return dt >= cal.startOfDay(for: startD) &&
                       dt <= cal.date(bySettingHour: 23, minute: 59, second: 59, of: endD)!
            }

            // 3) Собираем byDay для шита и списка
            let workoutItems: [CalendarItem]  = plannedWorkouts.map { .workout($0) }
            let activityItems: [CalendarItem] = monthActs.map { .activity($0) }

            self.byDay = Dictionary(grouping: (workoutItems + activityItems)) {
                cal.startOfDay(for: $0.date)
            }

            // 4) Маркеры в сетке: цвет = тип активности, до 6 штук/день
            self.monthDates = buildMarkers(for: monthDate,
                                           planned: plannedWorkouts,
                                           done: monthActs)

            // «История» в списке — прошедшие активности, свежие сверху
            self.filteredItems = activityItems.sorted { $0.date > $1.date }

            print("✅ Planner items (filtered to month): \(plannedWorkouts.count), activities this month: \(monthActs.count)")
        } catch {
            print("Calendar load error:", error.localizedDescription)
            self.monthPlanned = []
            self.monthDates = []
            self.filteredItems = []
            self.byDay = [:]
        }
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

            self.inspectorActivities = all

            self.filteredItems = all
                .map { CalendarItem.activity($0) }
                .sorted { $0.date > $1.date }

            self.monthDates = buildMarkers(for: currentMonthDate,
                                           planned: [],
                                           done: all)

            print("✅ Inspector activities loaded: \(all.count)")
        } catch {
            print("Inspector load error:", error.localizedDescription)
            await loadInspectorActivitiesFallback()
        }
    }

    private func loadInspectorActivitiesFallback() async {
        do {
            let acts = try await activitiesRepo.fetchAll()
            self.inspectorActivities = acts

            self.filteredItems = acts
                .map { CalendarItem.activity($0) }
                .sorted { $0.date > $1.date }

            self.monthDates = buildMarkers(for: currentMonthDate,
                                           planned: [],
                                           done: acts)

            print("✅ Inspector fallback ACTIVITIES loaded: \(acts.count)")
        } catch {
            print("Inspector activities fallback error:", error.localizedDescription)
            self.inspectorActivities = []
            self.filteredItems = []
            self.monthDates = []
        }
    }

    // MARK: Month grid markers
    /// Цвет для типа активности (подогнал под Flutter-скрин)
    private static func color(for activityName: String) -> Color {
        switch activityName.lowercased() {
        case "yoga":
            return .purple
        case "walking/running", "walking", "running", "run", "walk":
            return .yellow
        case "water", "swim", "pool":
            return .cyan
        case "sauna":
            return .pink
        case "fasting":
            return .green
        default:
            return .blue
        }
    }

    private func buildMarkers(for monthDate: Date,
                              planned: [Workout],
                              done: [Activity]) -> [WorkoutDay] {
        var cal = Calendar(identifier: .iso8601)  // понедельник — первый
        cal.locale = Locale.current
        cal.firstWeekday = 2

        guard
            let start = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)),
            let range = cal.range(of: .day, in: .month, for: monthDate)
        else { return [] }

        // группировка: planned по дню → массив цветов
        let plannedG: [Date: [Color]] = Dictionary(grouping: planned) {
            cal.startOfDay(for: $0.date)
        }.mapValues { items in
            items.map { Self.color(for: $0.name) }
        }

        // группировка: done по дню (маркер «выполнено»)
        let doneDays: Set<Date> = Set(done.compactMap { a in
            a.createdAt.map { cal.startOfDay(for: $0) }
        })

        return range.compactMap { day -> WorkoutDay? in
            guard let date = cal.date(byAdding: .day, value: day - 1, to: start) else { return nil }
            let d = cal.startOfDay(for: date)

            var colors = plannedG[d] ?? []
            // Чтобы не «съедались» цвета, ограничим, но щедро (до 6)
            colors = Array(colors.prefix(6))
            // Если в этот день есть выполненные активности — добавим зелёную «точку»
            if doneDays.contains(d), colors.count < 6 {
                colors.append(.green)
            }

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
        // поддержим "yyyy-MM-dd HH:mm:ss" и "yyyy-MM-dd"
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
