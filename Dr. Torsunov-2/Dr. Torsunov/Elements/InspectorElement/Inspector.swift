import Foundation

protocol InspectorRepository {
    func getActivitiesForCheck() async throws -> [Activity]
    func getActivitiesFullCheck() async throws -> [Activity]
    func checkWorkout(id: String) async throws
    func sendLayers(workoutId: String,
                    email: String,
                    level: Int,
                    sublevel: Int,
                    comment: String) async throws
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

    func sendLayers(workoutId: String,
                    email: String,
                    level: Int,
                    sublevel: Int,
                    comment: String) async throws {
        var comps = URLComponents(url: ApiRoutes.Inspector.checkWorkout, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "workoutId", value: workoutId),
            .init(name: "email", value: email),
            .init(name: "currentLayerChecked", value: String(level)),
            .init(name: "currentsubLayerChecked", value: String(sublevel)),
            .init(name: "comment", value: comment)
        ]
        try await client.requestVoid(url: comps.url!, method: .POST)
    }

    // MARK: - map
    private func mapToActivity(_ dto: ActivityForCheckDTO) -> Activity {
        Activity(
            id: dto.workoutKey ?? UUID().uuidString,
            name: dto.workoutActivityType ?? "Activity",
            description: dto.comment,
            isCompleted: false,
            createdAt: dto.startedAt,
            updatedAt: nil,
            userEmail: dto.emailFromAnyAvailablePath
        )
    }
}

// MARK: - Email из любого поля-пути (надёжнее)
private extension ActivityForCheckDTO {
    var emailFromAnyAvailablePath: String? {
        for candidate in [photoBefore, photoAfter, activityGraph, heartRateGraph, map] {
            if let e = Self.extractEmail(fromPath: candidate) { return e }
        }
        return nil
    }

    static func extractEmail(fromPath s: String?) -> String? {
        guard let s = s, !s.isEmpty else { return nil }
        let comps1: [String]
        if let u = URL(string: s), !u.path.isEmpty {
            comps1 = u.pathComponents
        } else {
            comps1 = s.split(separator: "/").map(String.init)
        }
        let comps = comps1.filter { $0 != "/" && !$0.isEmpty }
        guard comps.count >= 3 else { return nil }
        return comps[comps.count - 3]
    }
}
