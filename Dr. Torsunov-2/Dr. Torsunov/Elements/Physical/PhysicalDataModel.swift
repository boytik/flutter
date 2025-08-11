
import Foundation
struct PhysicalData: Codable, Equatable {
    var startDate: Date
    var age: Int
    var gender: String
    var height: Int
    var weight: Int
    var dailyRoutine: Bool
    var badHabits: Bool
    var chronicDiseases: Bool
    var chronicDescription: String

    // Добавим дефолтный инициализатор
    init(
        startDate: Date = Date(),
        age: Int = 40,
        gender: String = "Male",
        height: Int = 190,
        weight: Int = 70,
        dailyRoutine: Bool = true,
        badHabits: Bool = false,
        chronicDiseases: Bool = false,
        chronicDescription: String = ""
    ) {
        self.startDate = startDate
        self.age = age
        self.gender = gender
        self.height = height
        self.weight = weight
        self.dailyRoutine = dailyRoutine
        self.badHabits = badHabits
        self.chronicDiseases = chronicDiseases
        self.chronicDescription = chronicDescription
    }
}

