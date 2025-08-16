import Foundation

protocol InspectorRepository {
    func getActivitiesForCheck() async throws -> [Activity]
    func getActivitiesFullCheck() async throws -> [Activity]
    func checkWorkout(id: String) async throws
}

final class InspectorRepositoryImpl: InspectorRepository {
    private let client = HTTPClient.shared

    func getActivitiesForCheck() async throws -> [Activity] {
        let dtos: [ActivityForCheckDTO] = try await client.request(
            [ActivityForCheckDTO].self,
            url: ApiRoutes.Activities.forCheck
        )
        return dtos.map(mapToActivity(_:))
    }

    func getActivitiesFullCheck() async throws -> [Activity] {
        let dtos: [ActivityForCheckDTO] = try await client.request(
            [ActivityForCheckDTO].self,
            url: ApiRoutes.Activities.fullCheck
        )
        return dtos.map(mapToActivity(_:))
    }

    func checkWorkout(id: String) async throws {
        struct Body: Encodable { let id: String }
        try await client.requestVoid(
            url: ApiRoutes.Inspector.checkWorkout,
            method: .POST,
            body: Body(id: id)
        )
    }

    private func mapToActivity(_ dto: ActivityForCheckDTO) -> Activity {
        Activity(
            id: dto.workoutKey ?? UUID().uuidString,
            name: dto.workoutActivityType ?? "Activity",
            description: dto.comment,
            isCompleted: false,
            createdAt: dto.startedAt,
            updatedAt: nil,
            userEmail: dto.emailFromPhotoPath   // ← email берём отсюда
        )
    }
}

// ОСТАВЛЯЕМ экстеншен ТОЛЬКО ЗДЕСЬ
private extension ActivityForCheckDTO {
    /// Вытаскиваем email из пути `photo_before` (…/email/.../photo_before.jpg)
    var emailFromPhotoPath: String? {
        guard let s = photoBefore, !s.isEmpty else { return nil }
        let parts = s.split(separator: "/")
        return parts.count >= 3 ? String(parts[parts.count - 3]) : nil
    }
}
