import SwiftUI
import Foundation
import Combine
import OSLog
import UIKit

// MARK: - Логгер
private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app",
                         category: "PhysicalDataVM")

@MainActor
final class PhysicalDataViewModel: ObservableObject {
    // MARK: - Поля физ.данных
    @Published var startDate = Date()
    @Published var age = 40
    @Published var gender = "Male"
    @Published var height = 190
    @Published var weight = 70
    @Published var dailyRoutine = true
    @Published var badHabits = false
    @Published var chronicDiseases = false
    @Published var chronicDescription = ""
    @Published var isCheckingPlan: Bool = false
    @Published var showChronicAlert = false
    @Published var showChronicTextField = false
    @Published var activePicker: PickerType?

    // MARK: - Планировщик
    @Published var email: String = ""
    @Published var hasPlan: Bool = false
    @Published var isBusy: Bool = false
    @Published var errorMessage: String?

    private var originalData = PhysicalData()
    private let repository: PhysicalDataRepository
    private let plannerRepo = PlannerRepositoryImpl()

    private let ns = "physical_data"
    private let kvKey = "self"
    private let kvTTL: TimeInterval = 60 * 60 * 24

    private var currentData: PhysicalData {
        PhysicalData(
            startDate: startDate,
            age: age,
            gender: gender,
            height: height,
            weight: weight,
            dailyRoutine: dailyRoutine,
            badHabits: badHabits,
            chronicDiseases: chronicDiseases,
            chronicDescription: chronicDescription
        )
    }

    var hasChanges: Bool { currentData != originalData }

    init(repository: PhysicalDataRepository = PhysicalDataRepositoryImpl()) {
        self.repository = repository
        Task { [weak self] in
            await self?.load()
        }
    }

    // MARK: - Публичные методы интеграции

    /// Пробросить e-mail из PersonalViewModel и сразу проверить наличие плана
    func bindEmail(_ newEmail: String) {
        self.email = newEmail
        log.info("[Bind] email=\(self.email, privacy: .private(mask: .hash))")
        Task { await refreshPlanState() }
    }

    /// Единая кнопка «создать/удалить» как во Flutter
    func togglePlan() {
        hasPlan ? deletePlan() : createPlan()
    }

    /// Проверка, создан ли план: грузим календарь на выбранную дату
    func refreshPlanState() async {
        guard !email.isEmpty else {
            await MainActor.run {
                self.hasPlan = false
                self.errorMessage = "Email is empty"
                self.isCheckingPlan = false
            }
            log.error("[Planner] ❌ refreshPlanState: email empty")
            return
        }

        if isCheckingPlan { return }              // защита от дублей
        isCheckingPlan = true
        defer { isCheckingPlan = false }

        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: startDate)
        let url = ApiRoutes.Workouts.calendarDay(email: email, date: dateStr)

        let t0 = Date()
        do {
            let workouts: [ScheduledWorkoutDTO] =
                try await HTTPClient.shared.request(url, method: .GET)
            let exists = !workouts.isEmpty
            await MainActor.run {
                self.hasPlan = exists
                self.errorMessage = nil
            }
            log.info("[Planner] ℹ️ refreshPlanState: \(exists ? "exists" : "empty") count=\(workouts.count) (elapsed: \(self.ms(t0)) ms)")
        } catch {
            await MainActor.run { self.hasPlan = false }
            log.error("[Planner] ⚠️ refreshPlanState error: \(error.localizedDescription, privacy: .public) → treat as no plan (elapsed: \(self.ms(t0)) ms)")
        }
    }



    // MARK: - Planner API

    /// Создать план тренировок с даты `startDate`
    func createPlan() {
        guard !email.isEmpty else {
            self.errorMessage = "Email is empty"
            log.error("[Planner] ❌ createPlan: email empty")
            return
        }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let start = df.string(from: startDate)

        self.isBusy = true; self.errorMessage = nil
        let t0 = Date()
        log.info("[Planner] ▶︎ createPlan email=\(self.email, privacy: .private(mask: .hash)) start_date=\(start, privacy: .public)")

        Task {
            do {
                _ = try await plannerRepo.createPlan(email: email, startDate: start)
                self.hasPlan = true
                self.isBusy = false
                log.info("[Planner] ✅ plan created (elapsed: \(self.ms(t0)) ms) hasPlan=\(self.hasPlan)")
            } catch {
                self.errorMessage = String(describing: error)
                self.isBusy = false
                log.error("[Planner] ❌ create failed: \(self.errorMessage ?? "-", privacy: .public) (elapsed: \(self.ms(t0)) ms)")
            }
        }
    }

    /// Удалить весь план тренировок
    func deletePlan() {
        guard !email.isEmpty else {
            self.errorMessage = "Email is empty"
            log.error("[Planner] ❌ deletePlan: email empty")
            return
        }

        self.isBusy = true; self.errorMessage = nil
        let t0 = Date()
        log.info("[Planner] ▶︎ deletePlan email=\(self.email, privacy: .private(mask: .hash))")

        Task {
            do {
                try await plannerRepo.deletePlan(email: email)
                self.hasPlan = false
                self.isBusy = false
                log.info("[Planner] ✅ plan deleted (elapsed: \(self.ms(t0)) ms) hasPlan=\(self.hasPlan)")
            } catch {
                self.errorMessage = String(describing: error)
                self.isBusy = false
                log.error("[Planner] ❌ delete failed: \(self.errorMessage ?? "-", privacy: .public) (elapsed: \(self.ms(t0)) ms)")
            }
        }
    }

    // MARK: - Сохранение профиля / загрузка

    func uploadAvatar(_ image: UIImage) async {
        let t0 = Date()
        do {
            try await self.repository.uploadAvatar(image)
            log.info("[Avatar] ✅ uploaded (elapsed: \(self.ms(t0)) ms)")
        } catch {
            log.error("[Avatar] ❌ upload failed: \(error.localizedDescription, privacy: .public) (elapsed: \(self.ms(t0)) ms)")
        }
    }

    func saveChanges() async {
        let newData = self.currentData
        let t0 = Date()
        do {
            try await self.repository.save(data: newData)
            self.originalData = newData
            try? KVStore.shared.put(newData, namespace: self.ns, key: self.kvKey, ttl: self.kvTTL)
            log.info("[Save] ✅ saved; KV put \(self.ns)/\(self.kvKey) (elapsed: \(self.ms(t0)) ms)")
        } catch {
            log.error("[Save] ❌ failed: \(error.localizedDescription, privacy: .public) (elapsed: \(self.ms(t0)) ms)")
        }
    }

    func load() async {
        let t0 = Date()
        if let cached: PhysicalData = try? KVStore.shared.get(PhysicalData.self,
                                                              namespace: self.ns,
                                                              key: self.kvKey) {
            self.apply(data: cached)
            self.originalData = self.currentData
            log.debug("[KV] HIT \(self.ns)/\(self.kvKey)")
        } else {
            log.debug("[KV] MISS \(self.ns)/\(self.kvKey)")
        }

        do {
            let data = try await self.repository.load()
            self.apply(data: data)
            self.originalData = self.currentData
            try? KVStore.shared.put(data, namespace: self.ns, key: self.kvKey, ttl: self.kvTTL)
            log.info("[Load] ✅ loaded; KV SAVE \(self.ns)/\(self.kvKey) (elapsed: \(self.ms(t0)) ms)")
        } catch {
            log.error("[Load] ❌ failed: \(error.localizedDescription, privacy: .public) (elapsed: \(self.ms(t0)) ms)")
        }
    }

    // MARK: - Helpers

    private func apply(data: PhysicalData) {
        self.startDate          = data.startDate         ?? self.startDate
        self.age                = data.age               ?? self.age
        self.gender             = data.gender            ?? self.gender
        self.height             = data.height            ?? self.height
        self.weight             = data.weight            ?? self.weight
        self.dailyRoutine       = data.dailyRoutine      ?? self.dailyRoutine
        self.badHabits          = data.badHabits         ?? self.badHabits
        self.chronicDiseases    = data.chronicDiseases   ?? self.chronicDiseases
        self.chronicDescription = data.chronicDescription ?? self.chronicDescription

        log.debug("[Apply] startDate=\(self.startDate.ISO8601Format(), privacy: .public) age=\(self.age) gender=\(self.gender, privacy: .public) height=\(self.height) weight=\(self.weight)")
    }

    func clearOffline() {
        try? KVStore.shared.delete(namespace: self.ns, key: self.kvKey)
        log.info("[KV] DELETE \(self.ns)/\(self.kvKey)")
    }

    private func ms(_ t0: Date) -> Int { Int(Date().timeIntervalSince(t0) * 1000) }
}

enum PickerType: Identifiable {
    case date, age, gender, height, weight
    var id: Self { self }
}
