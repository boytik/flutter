
import Foundation
import Foundation

struct Activity: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var description: String?
    var isCompleted: Bool
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
        case description
        case isCompleted
        case createdAt
        case updatedAt
    }
}
