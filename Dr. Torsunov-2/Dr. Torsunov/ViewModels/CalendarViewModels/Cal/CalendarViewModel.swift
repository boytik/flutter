import Foundation
import SwiftUI
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app",
                         category: "CalendarViewModel")

@MainActor
final class CalendarViewModel: ObservableObject {

    enum PickersModes: String, CaseIterable { case calendar = "Календарь"; case history = "История" }
    enum HistoryFilter: String, CaseIterable { case completed = "Завершённые"; case all = "Все" }

    @Published var role: PersonalViewModel.Role = .user
    @Published var pickerMode: PickersModes = .calendar
    @Published var historyFilter: HistoryFilter = .all {
        didSet { rebuildHistory() }
    }

    @Published var monthDates: [WorkoutDay] = []
    @Published var currentMonthDate: Date = Date()
    @Published var byDay: [Date: [CalendarItem]] = [:]

    @Published var filteredItems: [CalendarItem] = []
    @Published var thumbs: [String: URL] = [:]

    // Индикатор загрузки
    @Published var isLoading: Bool = false

    // Офлайн-префилл
    @Published var items: [CachedWorkout] = []
    @Published var isOfflineFallback: Bool = false
    private let offlineStore = WorkoutCacheStore()

    // Источники данных
    private var monthPlanned: [Workout] = []
    private var monthActivities: [Activity] = []
    private var allActivities: [Activity] = []
    private var inspectorActivities: [Activity] = []

    private let inspectorRepo: InspectorRepository
    private let activitiesRepo: ActivityRepository

    private let calendarService: CalendarService
    private let moveService = MoveWorkoutsService()

    init(inspectorRepo: InspectorRepository = InspectorRepositoryImpl(),
         activitiesRepo: ActivityRepository = ActivityRepositoryImpl(),
         client: CacheRequesting = CacheJSONClient()) {
        self.inspectorRepo = inspectorRepo
        self.activitiesRepo = activitiesRepo
        self.calendarService = CalendarService(activitiesRepo: activitiesRepo,
                                               client: client,
                                               offlineStore: offlineStore)
    }

    // MARK: - Public props

    var currentMonth: String {
        let f = DateFormatter(); f.locale = .current
        f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return f.string(from: currentMonthDate).capitalized
    }

    // MARK: - Loaders

    func reload(role: PersonalViewModel.Role) async {
        self.role = role

        // офлайн мгновенный показ
        if role == .user, let prefill = calendarService.preloadOffline(currentMonthDate: currentMonthDate) {
            self.items = prefill.items
            self.isOfflineFallback = true
            self.monthPlanned = prefill.monthPlanned
            self.byDay = prefill.byDay
            self.monthDates = prefill.monthDates
        }

        switch role {
        case .user:
            await loadCalendarForMonth(currentMonthDate)
        case .inspector:
            await loadInspector()
        }
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

    private func loadCalendarForMonth(_ monthDate: Date) async {
        isLoading = true
        defer { isLoading = false }

        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            reset(); return
        }

        do {
            let loaded = try await calendarService.loadMonth(email: email, currentMonthDate: monthDate)

            if !loaded.monthPlanned.isEmpty {
                // штатная загрузка
                self.monthPlanned = loaded.monthPlanned
                self.monthActivities = loaded.monthActivities
                self.allActivities = loaded.allActivities
                self.byDay = loaded.byDay
                self.monthDates = loaded.monthDates
                self.isOfflineFallback = false
            } else if isOfflineFallback {
                // сеть упала — оставляем офлайн и обновляем активности
                self.monthActivities = loaded.monthActivities
                self.allActivities = loaded.allActivities
                recomputeCalendarArtifacts()
            } else {
                // пусто, но без офлайна — просто проставим как пришло
                self.monthPlanned = loaded.monthPlanned
                self.monthActivities = loaded.monthActivities
                self.allActivities = loaded.allActivities
                self.byDay = loaded.byDay
                self.monthDates = loaded.monthDates
                self.isOfflineFallback = false
            }
            rebuildHistory()
        } catch {
            // оставляем офлайн-данные
        }
    }

    // MARK: - Inspector

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
            inspectorActivities = []; filteredItems = []; monthDates = []
        }
    }

    private func applyInspectorFilter() {
        var base = inspectorActivities
        if let t = inspectorTypeFilter?.lowercased() { base = base.filter { ($0.name?.lowercased() ?? "") == t } }
        filteredItems = base.map { .activity($0) }.sorted { $0.date > $1.date }
    }

    // MARK: - History & reset

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

    // MARK: - Queries for UI

    func items(on date: Date) -> [CalendarItem] {
        byDay[CalendarMath.iso.startOfDay(for: date)] ?? []
    }

    func datesWithPlannedWorkouts() -> [Date] {
        let dates = monthPlanned.map { CalendarMath.iso.startOfDay(for: $0.date) }
        return Array(Set(dates)).sorted()
    }

    func plannedWorkouts(on date: Date) -> [Workout] {
        let day = CalendarMath.iso.startOfDay(for: date)
        return monthPlanned.filter { CalendarMath.iso.isDate($0.date, inSameDayAs: day) }
    }

    // MARK: - Move Workouts

    /// Переместить выбранные тренировки на дату targetDate (время = 00:00)
    func moveWorkouts(withIDs ids: [String], to targetDate: Date) async {
        guard !ids.isEmpty else { return }

        // Предвалидация: те же правила, что и во Flutter
        let check = validateDraggedIDs(ids, to: targetDate)
        let allowedIDs = check.allowedIDs
        guard !allowedIDs.isEmpty else { return }
        if allowedIDs.count != ids.count {
            log.warning("⚠️ Validation trimmed IDs: requested=\(ids.count) allowed=\(allowedIDs.count)")
        }

        let prevPlanned = monthPlanned
        let newDate = CalendarMath.iso.startOfDay(for: targetDate)

        // Оптимистичное обновление — только для allowedIDs
        monthPlanned = monthPlanned.map { w in
            guard allowedIDs.contains(w.id) else { return w }
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

        // email
        let email = (TokenStorage.shared.currentEmail() ?? UserDefaults.standard.string(forKey: "profile_email")) ?? ""
        guard !email.isEmpty else { return }

        // Полный payload из уже обновлённого состояния (дата уже новая)
        let moved = monthPlanned.filter { allowedIDs.contains($0.id) }

        do {
            // 1) Flutter-совместимый расширенный payload
            try await moveService.sendMoveRequestFull(email: email, targetDate: newDate, workouts: moved)
        } catch {
            // 2) Фолбэк: минимальный payload
            do {
                try await moveService.sendMoveRequest(
                    email: email,
                    targetDate: newDate,
                    selectedIDs: allowedIDs.map(moveService.baseID(from:))
                )
            } catch {
                // Откат
                monthPlanned = prevPlanned
                recomputeCalendarArtifacts()
                return
            }
        }

        // Офлайн-кэш (инвалидируем ETag у затронутых месяцев)
        moveService.updateOfflineCache(
            prevPlanned: prevPlanned,
            updatedMonthPlanned: monthPlanned,
            movedIDs: allowedIDs,
            newDate: newDate,
            offlineStore: offlineStore
        )

        // Пост-проверка (учитывает возможную смену ID на сервере)
        Task {
            await PostMoveVerifier().verifyAndHeal(
                viewModel: self,
                email: email,
                targetDate: newDate,
                movedWorkouts: moved,
                autoReload: true
            )
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

    // MARK: - Drag/Drop validation API (UI hooks)

    func workoutsByIDs(_ ids: [String]) -> [Workout] {
        monthPlanned.filter { ids.contains($0.id) }
    }

    func validateDraggedIDs(_ ids: [String], to targetDate: Date) -> (allowedIDs: [String], firstError: DropRuleViolation?) {
        let dragged = monthPlanned.filter { ids.contains($0.id) }
        let targetDay = plannedWorkouts(on: targetDate)
        return DragDropValidators.validateDropListData(
            targetDate: targetDate,
            targetDayWorkouts: targetDay,
            dragged: dragged,
            monthPlanned: monthPlanned
        )
    }
}

// MARK: - Server healing hooks (ID remap / date correction)

extension CalendarViewModel {
    /// Применить карту serverID-ремапа к локальному состоянию и офлайн-кэшу.
    func applyServerIDRemap(_ map: [String: String], inMonthOf date: Date) {
        guard !map.isEmpty else { return }

        monthPlanned = monthPlanned.map { w in
            if let newID = map[w.id] {
                return Workout(id: newID,
                               name: w.name,
                               description: w.description,
                               duration: w.duration,
                               date: w.date,
                               activityType: w.activityType,
                               plannedLayers: w.plannedLayers,
                               swimLayers: w.swimLayers)
            } else {
                return w
            }
        }
        recomputeCalendarArtifacts()
        moveService.remapIDsInOfflineCache(idMap: map, targetDate: date, offlineStore: offlineStore)
    }

    /// Исправить даты записей по карте: workoutID -> новая дата (startOfDay).
    func applyServerDateCorrection(_ idToDate: [String: Date]) {
        guard !idToDate.isEmpty else { return }

        monthPlanned = monthPlanned.map { w in
            if let d = idToDate[w.id] {
                return Workout(id: w.id,
                               name: w.name,
                               description: w.description,
                               duration: w.duration,
                               date: CalendarMath.iso.startOfDay(for: d),
                               activityType: w.activityType,
                               plannedLayers: w.plannedLayers,
                               swimLayers: w.swimLayers)
            } else {
                return w
            }
        }
        recomputeCalendarArtifacts()
        moveService.correctDatesInOfflineCache(idToDate: idToDate, offlineStore: offlineStore)
    }
}
