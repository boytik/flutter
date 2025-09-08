import Foundation
import SwiftUI
import OSLog

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

    // 🔄 Глобовый индикатор загрузки
    @Published var isLoading: Bool = false

    // ⬇️ ОФЛАЙН: для «быстрого отображения как во Flutter»
    @Published var items: [CachedWorkout] = []
    @Published var isOfflineFallback: Bool = false
    private let offlineStore = WorkoutCacheStore()

    private var monthPlanned: [Workout] = []
    private var monthActivities: [Activity] = []
    private var allActivities: [Activity] = []
    private var inspectorActivities: [Activity] = []

    private let inspectorRepo: InspectorRepository
    private let activitiesRepo: ActivityRepository

    // Services
    private let calendarService: CalendarService
    private let moveService = MoveWorkoutsService()

    init(inspectorRepo: InspectorRepository = InspectorRepositoryImpl(),
         activitiesRepo: ActivityRepository = ActivityRepositoryImpl(),
         client: CacheRequesting = CacheJSONClient()) {
        self.inspectorRepo = inspectorRepo
        self.activitiesRepo = activitiesRepo
        self.calendarService = CalendarService(activitiesRepo: activitiesRepo, client: client, offlineStore: offlineStore)
    }

    func reload(role: PersonalViewModel.Role) async {
        self.role = role

        // ===== OFFLINE PREFILL — показать тренировки из кэша мгновенно =====
        if role == .user, let prefill = calendarService.preloadOffline(currentMonthDate: currentMonthDate) {
            self.items = prefill.items
            self.isOfflineFallback = true
            self.monthPlanned = prefill.monthPlanned
            self.byDay = prefill.byDay
            self.monthDates = prefill.monthDates
        }

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
        byDay[CalendarMath.iso.startOfDay(for: date)] ?? []
    }
    func thumbFor(_ item: CalendarItem) -> URL? { nil } // thumbs вне задачи

    // MARK: Load (USER)

    private func loadCalendarForMonth(_ monthDate: Date) async {
        isLoading = true
        defer { isLoading = false }

        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else { reset(); return }

        do {
            let loaded = try await calendarService.loadMonth(email: email, currentMonthDate: monthDate)

            // если ETag вернул 304 — monthPlanned уже проставлен из офлайна на этапе preload
            if !loaded.usedETag || !isOfflineFallback {
                self.monthPlanned = loaded.monthPlanned
            }
            self.monthActivities = loaded.monthActivities
            self.allActivities = loaded.allActivities
            self.byDay = loaded.byDay
            self.monthDates = loaded.monthDates
            self.isOfflineFallback = false

            rebuildHistory()
        } catch {
            // В случае ошибки оставляем то, что было (возможно офлайн)
        }
    }

    // MARK: Inspector

    func setInspectorFilter(_ type: String?) { inspectorTypeFilter = type; applyInspectorFilter() }
    @Published var inspectorTypeFilter: String? = nil
    private var inspectorTypesRaw: [String] {
        Array(Set(inspectorActivities.compactMap { $0.name?.lowercased() })).sorted()
    }
    var inspectorTypes: [String] { inspectorTypesRaw.map { CalendarColors.prettyType($0) } }

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

            let (s, e) = CalendarMath.visibleGridRange(for: currentMonthDate)
            monthDates = CalendarGridBuilder.build(from: s, to: e, planned: [], done: inspectorActivities)
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

    // MARK: - Move Workouts

    /// Все даты (startOfDay), где есть плановые тренировки
    func datesWithPlannedWorkouts() -> [Date] {
        let dates = monthPlanned.map { CalendarMath.iso.startOfDay(for: $0.date) }
        return Array(Set(dates)).sorted()
    }

    /// Плановые тренировки на конкретный день
    func plannedWorkouts(on date: Date) -> [Workout] {
        let day = CalendarMath.iso.startOfDay(for: date)
        return monthPlanned.filter { CalendarMath.iso.isDate($0.date, inSameDayAs: day) }
    }

    /// Переместить выбранные тренировки на дату targetDate (время = 00:00)
    func moveWorkouts(withIDs ids: [String], to targetDate: Date) async {
        guard !ids.isEmpty else { return }

        let prevPlanned = monthPlanned
        let newDate = CalendarMath.iso.startOfDay(for: targetDate)

        // Оптимистичное обновление локального состояния
        monthPlanned = monthPlanned.map { w in
            guard ids.contains(w.id) else { return w }
            return Workout(
                id: w.id,
                name: w.name,
                description: w.description,
                duration: w.duration,
                date: newDate,
                activityType: w.activityType,
                plannedLayers: w.plannedLayers,
                swimLayers: w.swimLayers
            )
        }
        recomputeCalendarArtifacts()

        // email из токен-хранилища или UserDefaults
        let email = (TokenStorage.shared.currentEmail() ?? UserDefaults.standard.string(forKey: "profile_email")) ?? ""
        guard !email.isEmpty else { return }

        do {
            try await moveService.sendMoveRequest(
                email: email,
                targetDate: newDate,
                selectedIDs: ids.map(moveService.baseID(from:))
            )

            // === sync offline cache for source & destination months ===
            moveService.updateOfflineCache(prevPlanned: prevPlanned,
                                           updatedMonthPlanned: monthPlanned,
                                           movedIDs: ids,
                                           newDate: newDate,
                                           offlineStore: offlineStore)

        } catch {
            // откат
            monthPlanned = prevPlanned
            recomputeCalendarArtifacts()
        }
    }

    /// Пересборка monthDates и byDay
    private func recomputeCalendarArtifacts() {
        let (s, e) = CalendarMath.visibleGridRange(for: currentMonthDate)
        monthDates = CalendarGridBuilder.build(from: s, to: e, planned: monthPlanned, done: monthActivities)

        let workoutItems  = monthPlanned.map { CalendarItem.workout($0) }
        let activityItems = monthActivities.map { CalendarItem.activity($0) }
        byDay = Dictionary(grouping: (workoutItems + activityItems)) { CalendarMath.iso.startOfDay(for: $0.date) }
    }
}
