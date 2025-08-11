
import SwiftUI
import Foundation

@MainActor
@Observable
final class CalendarViewModel {
    // MARK: - Role
    var role: PersonalViewModel.Role = .user

    // MARK: - UI state
    var pickerMode: PickersModes = .calendar
    var currentMonthDate: Date = Date() {
        didSet { updateMonthData() }
    }
    var currentMonth: String = Date().monthYearString
    var monthDates: [WorkoutDay] = []

    enum PickersModes: String, CaseIterable {
        case calendar = "Календарь"
        case history  = "История"
    }

    // MARK: - Data (user)
    private(set) var workouts: [Workout] = []
    private(set) var activities: [Activity] = []

    // MARK: - Data (inspector)
    private(set) var toCheck: [Workout] = []
    private(set) var fullCheck: [Workout] = []

    // MARK: - Computed items for grid/list
    var calendarItems: [CalendarItem] {
        workouts.map { .workout($0) } + activities.map { .activity($0) }
    }

    var filteredItems: [CalendarItem] {
        if role == .user {
            return calendarItems.sorted { $0.date > $1.date }
        } else {
            // для инспектора показываем оба списка; при желании — разделять секциями
            let all = (toCheck + fullCheck).map { CalendarItem.workout($0) }
            return all.sorted { $0.date > $1.date }
        }
    }

    // MARK: - Deps
    private let workoutRepo: WorkoutRepository
    private let activityRepo: ActivityRepository
    private let inspectorRepo: InspectorRepository

    // MARK: - Init
    init(
        workoutRepo: WorkoutRepository = WorkoutRepositoryImpl(),
        activityRepo: ActivityRepository = ActivityRepositoryImpl(),
        inspectorRepo: InspectorRepository = InspectorRepositoryImpl()
    ) {
        self.workoutRepo = workoutRepo
        self.activityRepo = activityRepo
        self.inspectorRepo = inspectorRepo
        updateMonthData()
    }

    // MARK: - Public API
    func applyRole(_ newRole: PersonalViewModel.Role) async {
        guard role != newRole else { return }
        role = newRole
        await loadForCurrentRole()
    }

    func refresh() async {
        await loadForCurrentRole()
    }

    func previousMonth() {
        if let newDate = Calendar.current.date(byAdding: .month, value: -1, to: currentMonthDate) {
            currentMonthDate = newDate
        }
    }

    func nextMonth() {
        if let newDate = Calendar.current.date(byAdding: .month, value: 1, to: currentMonthDate) {
            currentMonthDate = newDate
        }
    }

    // MARK: - Loading
    private func loadForCurrentRole() async {
        if role == .user {
            await loadUserData()
        } else {
            await loadInspectorData()
        }
        updateMonthData()
    }

    private func loadUserData() async {
        do {
            async let w: [Workout] = workoutRepo.fetchAll()
            async let a: [Activity] = activityRepo.fetchAll()
            (workouts, activities) = try await (w, a)
        } catch {
            print("❌ loadUserData error:", error.localizedDescription)
            workouts = []; activities = []
        }
    }

    private func loadInspectorData() async {
        do {
            async let t: [Workout] = inspectorRepo.getActivitiesForCheck()
            async let f: [Workout] = inspectorRepo.getActivitiesFullCheck()
            (toCheck, fullCheck) = try await (t, f)
        } catch {
            print("❌ loadInspectorData error:", error.localizedDescription)
            toCheck = []; fullCheck = []
        }
    }

    // MARK: - Month helpers
    private func updateMonthData() {
        currentMonth = currentMonthDate.monthYearString
        monthDates = generateMonthDays(for: currentMonthDate)
    }

    private func generateMonthDays(for date: Date) -> [WorkoutDay] {
        var days: [WorkoutDay] = []
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday

        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let range = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }

        // leading placeholders
        let weekdayOfFirstDay = calendar.component(.weekday, from: monthStart)
        let shift = (weekdayOfFirstDay - calendar.firstWeekday + 7) % 7
        if shift > 0 {
            let previousMonth = calendar.date(byAdding: .month, value: -1, to: monthStart)!
            let prevMonthRange = calendar.range(of: .day, in: .month, for: previousMonth)!
            let prevMonthDaysCount = prevMonthRange.count

            for day in (prevMonthDaysCount - shift + 1)...prevMonthDaysCount {
                if let prevDate = calendar.date(bySetting: .day, value: day, of: previousMonth) {
                    days.append(WorkoutDay(date: prevDate, dots: []))
                }
            }
        }

        // current month
        for day in range {
            let currentDay = calendar.date(byAdding: .day, value: day - 1, to: monthStart)!
            let colorsForDay = calendarItems
                .filter { calendar.isDate($0.date, inSameDayAs: currentDay) }
                .map { $0.isWorkout ? Color.green : Color.blue }

            days.append(WorkoutDay(date: currentDay, dots: colorsForDay))
        }

        // trailing placeholders to fill 5 weeks grid (35 cells)
        let totalCells = 35
        if days.count < totalCells {
            let remaining = totalCells - days.count
            let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            for i in 0..<remaining {
                if let nextDate = calendar.date(byAdding: .day, value: i, to: nextMonthStart) {
                    days.append(WorkoutDay(date: nextDate, dots: []))
                }
            }
        }

        return days
    }
}


