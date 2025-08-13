
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

    // Снимок текущих значений для сравнения/сохранения
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
        Task { await load() }
    }
    func uploadAvatar(_ image: UIImage) async {
        do { try await repository.uploadAvatar(image) }
        catch { print("❌ uploadAvatar error:", error.localizedDescription) }
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

            // Берём значения с сервера, при отсутствии — оставляем текущие
            startDate         = data.startDate         ?? startDate
            age               = data.age               ?? age
            gender            = data.gender            ?? gender
            height            = data.height            ?? height
            weight            = data.weight            ?? weight
            dailyRoutine      = data.dailyRoutine      ?? dailyRoutine
            badHabits         = data.badHabits         ?? badHabits
            chronicDiseases   = data.chronicDiseases   ?? chronicDiseases
            chronicDescription = data.chronicDescription ?? chronicDescription

            // Фиксируем «оригинал» после загрузки
            originalData = currentData
        } catch {
            print("❌ Failed to load physical data:", error)
        }
    }
}

enum PickerType: Identifiable {
    case date, age, gender, height, weight
    var id: Self { self }
}

