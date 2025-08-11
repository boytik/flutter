import SwiftUI
import Foundation

struct Workout: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var description: String?
    var duration: Int
    var date: Date

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
        case description
        case duration
        case date
    }
}



struct WorkoutDay: Identifiable {
    let id = UUID()
    let date: Date
    let dots: [Color]
}

