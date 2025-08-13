
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

// MARK: - Репо планировщика
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

    // История
    @Published var filteredItems: [CalendarItem] = []

    // Кэши
    private var monthPlanner: [PlannerEntry] = []      // user
    private var inspectorActivities: [Activity] = []   // inspector

    // Репозитории
    private let plannerRepo: PlannerRepository
    private let inspectorRepo: InspectorRepository
    private let activitiesRepo: ActivityRepository

    init(plannerRepo: PlannerRepository = PlannerRepositoryImpl(),
         inspectorRepo: InspectorRepository = InspectorRepositoryImpl(),
         activitiesRepo: ActivityRepository = ActivityRepositoryImpl()) {
        self.plannerRepo = plannerRepo
        self.inspectorRepo = inspectorRepo
        self.activitiesRepo = activitiesRepo

        // показать сетку сразу (без точек), пока грузится
        self.monthDates = makeMonthDays(for: self.currentMonthDate, planner: [])
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
        switch role {
        case .user:
            Task { await loadCalendarForMonth(d) }
        case .inspector:
            self.monthDates = makeMonthDays(for: d, activities: inspectorActivities)
        }
    }

    func nextMonth() {
        guard let d = Calendar.current.date(byAdding: .month, value: 1, to: currentMonthDate) else { return }
        currentMonthDate = d
        switch role {
        case .user:
            Task { await loadCalendarForMonth(d) }
        case .inspector:
            self.monthDates = makeMonthDays(for: d, activities: inspectorActivities)
        }
    }

    // MARK: Loading — USER
    private func loadCalendarForMonth(_ monthDate: Date) async {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            self.monthPlanner = []
            self.monthDates = makeMonthDays(for: monthDate, planner: [])
            self.filteredItems = []
            return
        }
        let (startS, endS) = monthRangeStrings(monthDate)

        do {
            let items = try await plannerRepo.fetchRange(email: email, start: startS, end: endS)
            self.monthPlanner = items
            self.monthDates = makeMonthDays(for: monthDate, planner: items)

            self.filteredItems = items
                .map { pe in
                    CalendarItem.workout(
                        Workout(id: pe.id, name: pe.activity, description: nil, duration: 0, date: pe.date)
                    )
                }
                .sorted { $0.date > $1.date }
        } catch {
            print("Calendar (planner) load error:", error.localizedDescription)
            self.monthPlanner = []
            self.monthDates = makeMonthDays(for: monthDate, planner: [])
            self.filteredItems = []
        }
    }

    // MARK: Loading — INSPECTOR
    /// 1) /list_workouts_for_check + /list_workouts_for_check_full (через InspectorRepository → [Activity])
    /// 2) при ошибке — фолбэк: /list_workouts (через ActivityRepository → [Activity])
    private func loadInspector() async {
        do {
            async let a: [Activity] = inspectorRepo.getActivitiesForCheck()
            async let b: [Activity] = inspectorRepo.getActivitiesFullCheck()
            let (toCheck, full) = try await (a, b)

            // объединяем по id
            var uniq: [String: Activity] = [:]
            for x in (toCheck + full) { uniq[x.id] = x }
            let all = Array(uniq.values)

            self.inspectorActivities = all

            self.filteredItems = all
                .map { CalendarItem.activity($0) }
                .sorted { $0.date > $1.date }

            self.monthDates = makeMonthDays(for: currentMonthDate, activities: all)

            print("✅ Inspector activities loaded: \(all.count)")
        } catch {
            print("Inspector load error:", error.localizedDescription)
            await loadInspectorActivitiesFallback()
        }
    }

    private func loadInspectorActivitiesFallback() async {
        do {
            let acts = try await activitiesRepo.fetchAll() // /list_workouts
            self.inspectorActivities = acts

            self.filteredItems = acts
                .map { CalendarItem.activity($0) }
                .sorted { $0.date > $1.date }

            self.monthDates = makeMonthDays(for: currentMonthDate, activities: acts)

            print("✅ Inspector fallback ACTIVITIES loaded: \(acts.count)")
        } catch {
            print("Inspector activities fallback error:", error.localizedDescription)
            self.inspectorActivities = []
            self.filteredItems = []
            self.monthDates = makeMonthDays(for: currentMonthDate, planner: [])
        }
    }

    // MARK: Month grid builders
    private func makeMonthDays(for monthDate: Date, planner: [PlannerEntry]) -> [WorkoutDay] {
        // для user используем даты из планировщика
        let dates = planner.map { $0.date }
        return buildDots(for: monthDate, dates: dates)
    }

    private func makeMonthDays(for monthDate: Date, activities: [Activity]) -> [WorkoutDay] {
        // для inspector — точки по датам созданий активностей
        let dates = activities.compactMap { $0.createdAt }
        return buildDots(for: monthDate, dates: dates)
    }

    private func buildDots(for monthDate: Date, dates: [Date]) -> [WorkoutDay] {
        let cal = Calendar.current
        guard
            let start = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)),
            let range = cal.range(of: .day, in: .month, for: monthDate)
        else { return [] }

        let grouped = Dictionary(grouping: dates.map { cal.startOfDay(for: $0) }) { $0 }
        let palette: [Color] = [.purple, .orange, .blue]

        return range.compactMap { day in
            guard let date = cal.date(byAdding: .day, value: day - 1, to: start) else { return nil }
            let count = grouped[cal.startOfDay(for: date)]?.count ?? 0
            let dots = (0..<min(3, count)).map { palette[$0 % palette.count] }
            return WorkoutDay(date: date, dots: dots)
        }
    }

    // MARK: Helpers
    private func monthRangeStrings(_ monthDate: Date) -> (String, String) {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"

        let start = cal.date(from: cal.dateComponents([.year, .month], from: monthDate))!
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)! // последнее число месяца
        return (f.string(from: start), f.string(from: end))
    }
}
