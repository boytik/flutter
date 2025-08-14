

import Foundation
struct ScheduledWorkout: Codable, Identifiable {
    let id: String
    let date: String
    let title: String
}


protocol CalendarRepository {
    func getCalendar(for email: String) async throws -> [ScheduledWorkout]
    func addWorkout(for email: String, workout: ScheduledWorkout) async throws
    func deleteWorkout(for email: String, workoutId: String) async throws
}

final class CalendarRepositoryImpl: CalendarRepository {
    private let client = HTTPClient.shared

    func getCalendar(for email: String) async throws -> [ScheduledWorkout] {
        try await client.request([ScheduledWorkout].self,
                                 url: ApiRoutes.Calendar.get(email: email))
    }

    func addWorkout(for email: String, workout: ScheduledWorkout) async throws {
        try await client.requestVoid(url: ApiRoutes.Calendar.add(email: email),
                                     method: .POST,
                                     body: workout)
    }

    func deleteWorkout(for email: String, workoutId: String) async throws {
        struct Body: Encodable { let id: String }
        try await client.requestVoid(url: ApiRoutes.Calendar.delete(email: email),
                                     method: .DELETE,
                                     body: Body(id: workoutId))
    }
}

