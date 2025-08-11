
import SwiftUI
import Foundation
import Combine

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

    var hasChanges: Bool {
        currentData != originalData
    }

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

    init(repository: PhysicalDataRepository = PhysicalDataRepositoryImpl()) {
        self.repository = repository
        Task { await load() }
    }

    func saveChanges() async {
        let newData = currentData
        do {
            try await repository.save(data: newData)
            originalData = newData
        } catch {
            print("❌ Failed to save physical data:", error)
        }
    }

    func load() async {
        do {
            let data = try await repository.load()
            startDate = data.startDate
            age = data.age
            gender = data.gender
            height = data.height
            weight = data.weight
            dailyRoutine = data.dailyRoutine
            badHabits = data.badHabits
            chronicDiseases = data.chronicDiseases
            chronicDescription = data.chronicDescription
            originalData = data
        } catch {
            print("❌ Failed to load physical data:", error)
        }
    }
}

enum PickerType: Identifiable {
    case date, age, gender, height, weight
    var id: Self { self }
}
