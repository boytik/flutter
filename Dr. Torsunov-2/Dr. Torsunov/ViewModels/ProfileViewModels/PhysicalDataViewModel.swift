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
    @Published var startDate = Date()
    @Published var age = 40
    @Published var gender = "Male"
    @Published var height = 190
    @Published var weight = 70
    @Published var dailyRoutine = true
    @Published var badHabits = false
    @Published var chronicDiseases = false
    @Published var chronicDescription = ""

    @Published var showChronicAlert = false
    @Published var showChronicTextField = false
    @Published var activePicker: PickerType?

    private var originalData = PhysicalData()
    private let repository: PhysicalDataRepository

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

    // MARK: - Actions

    func uploadAvatar(_ image: UIImage) async {
        do {
            try await self.repository.uploadAvatar(image)
            log.info("[Avatar] uploaded")
        } catch {
            log.error("[Avatar] upload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func saveChanges() async {
        let newData = self.currentData
        do {
            try await self.repository.save(data: newData)
            self.originalData = newData
            try? KVStore.shared.put(newData, namespace: self.ns, key: self.kvKey, ttl: self.kvTTL)
            log.debug("[KV] SAVE \(self.ns)/\(self.kvKey)")
        } catch {
            log.error("[Save] failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func load() async {
        if let cached: PhysicalData = try? KVStore.shared.get(PhysicalData.self,
                                                              namespace: self.ns,
                                                              key: self.kvKey) {
            self.apply(data: cached)
            self.originalData = self.currentData
            log.debug("[KV] HIT \(self.ns)/\(self.kvKey)")
        }

        do {
            let data = try await self.repository.load()
            self.apply(data: data)
            self.originalData = self.currentData
            try? KVStore.shared.put(data, namespace: self.ns, key: self.kvKey, ttl: self.kvTTL)
            log.debug("[KV] SAVE \(self.ns)/\(self.kvKey)")
        } catch {
            log.error("[Load] failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Helpers

    private func apply(data: PhysicalData) {
        self.startDate         = data.startDate         ?? self.startDate
        self.age               = data.age               ?? self.age
        self.gender            = data.gender            ?? self.gender
        self.height            = data.height            ?? self.height
        self.weight            = data.weight            ?? self.weight
        self.dailyRoutine      = data.dailyRoutine      ?? self.dailyRoutine
        self.badHabits         = data.badHabits         ?? self.badHabits
        self.chronicDiseases   = data.chronicDiseases   ?? self.chronicDiseases
        self.chronicDescription = data.chronicDescription ?? self.chronicDescription
    }

    func clearOffline() {
        try? KVStore.shared.delete(namespace: self.ns, key: self.kvKey)
        log.info("[KV] DELETE \(self.ns)/\(self.kvKey)")
    }
}

enum PickerType: Identifiable {
    case date, age, gender, height, weight
    var id: Self { self }
}

