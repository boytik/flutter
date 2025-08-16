import Foundation
import UIKit

// MARK: - Public model used across the app
struct Activity: Identifiable, Codable, Equatable {
    var id: String
    var name: String?
    var description: String?
    var isCompleted: Bool
    var createdAt: Date?
    var updatedAt: Date?
    var userEmail: String?
}

// MARK: - DTO used by inspector endpoints (/for_check, /full_check)
struct ActivityForCheckDTO: Decodable {
    let workoutKey: String?
    let workoutActivityType: String?
    let workoutStartDate: String?
    let minStartTime: String?
    let comment: String?
    let photoAfter: String?
    let photoBefore: String?

    let activityGraph: String?
    let heartRateGraph: String?
    let map: String?

    enum CodingKeys: String, CodingKey {
        case workoutKey
        case workoutActivityType
        case workoutStartDate
        case minStartTime
        case comment

        case photoAfter  = "photo_after"
        case photoBefore = "photo_before"

        case activityGraph = "activity_graph"
        case heartRateGraph
        case map

        // сервер может прислать кучу лишних полей — игнорируем:
        case avg_humidity, avg_temp, distance, duration, list_positions
        case maxLayer, maxSubLayer
        case currentLayerChecked, currentsubLayerChecked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workoutKey          = try c.decodeIfPresent(String.self, forKey: .workoutKey)
        workoutActivityType = try c.decodeIfPresent(String.self, forKey: .workoutActivityType)
        workoutStartDate    = try c.decodeIfPresent(String.self, forKey: .workoutStartDate)
        minStartTime        = try c.decodeIfPresent(String.self, forKey: .minStartTime)
        comment             = try c.decodeIfPresent(String.self, forKey: .comment)
        photoAfter          = try c.decodeIfPresent(String.self, forKey: .photoAfter)
        photoBefore         = try c.decodeIfPresent(String.self, forKey: .photoBefore)
        activityGraph       = try c.decodeIfPresent(String.self, forKey: .activityGraph)
        heartRateGraph      = try c.decodeIfPresent(String.self, forKey: .heartRateGraph)
        map                 = try c.decodeIfPresent(String.self, forKey: .map)
        // все остальные ключи намеренно игнорируем
    }

    var startedAt: Date? {
        for raw in [workoutStartDate, minStartTime] {
            if let s = raw, let d = ActivityRepositoryImpl.parseDateSmart(s) { return d }
        }
        return nil
    }
}

// MARK: - Repository API
protocol ActivityRepository {
    func fetchAll() async throws -> [Activity]
    func upload(activity: Activity) async throws
    func submit(activityId: String,
                comment: String?,
                beforeImage: UIImage?,
                afterImage: UIImage?) async throws
}

// MARK: - Implementation
final class ActivityRepositoryImpl: ActivityRepository {
    private let client = HTTPClient.shared

    // ---- Public API

    /// Возвращает всю историю завершённых активностей пользователя.
    /// Понимает разные формы ответа: `[HistoryV2]`, `{ "data": [HistoryV1] }`, либо `[HistoryV1]`.
    func fetchAll() async throws -> [Activity] {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            return []
        }

        // Берём большой срез истории
        let fiveYearsAgo = Calendar.current.date(byAdding: .year, value: -5, to: Date())!
        let dfDay = DateFormatter()
        dfDay.locale = .init(identifier: "en_US_POSIX")
        dfDay.timeZone = .current
        dfDay.dateFormat = "yyyy-MM-dd"
        let lastDate = dfDay.string(from: fiveYearsAgo)

        let url = ApiRoutes.Activities.listWorkouts(email: email, lastDate: lastDate)

        // V2: плоский массив
        if let v2: [HistoryV2] = try? await client.request([HistoryV2].self, url: url) {
            return v2.map { $0.asActivity(email: email) }
                     .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }

        // V1: обёртка { data: [...] }
        if let wrapped: HistoryWrappedV1 = try? await client.request(HistoryWrappedV1.self, url: url) {
            return wrapped.data.map { $0.asActivity(email: email) }
                               .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }

        // V1 без обёртки
        if let v1: [HistoryV1] = try? await client.request([HistoryV1].self, url: url) {
            return v1.map { $0.asActivity(email: email) }
                     .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }

        throw NSError(domain: "ActivityRepositoryImpl",
                      code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Не удалось декодировать ответ /list_workouts"])
    }

    func upload(activity: Activity) async throws {
        try await client.requestVoid(
            url: ApiRoutes.Activities.legacy_upload,
            method: .POST,
            body: activity
        )
    }

    func submit(
        activityId: String,
        comment: String?,
        beforeImage: UIImage?,
        afterImage: UIImage?
    ) async throws {
        var parts: [HTTPClient.UploadPart] = []
        if let data = beforeImage?.jpegData(compressionQuality: 0.85) {
            parts.append(.init(name: "photo_before", filename: "before.jpg", mime: "image/jpeg", data: data))
        }
        if let data = afterImage?.jpegData(compressionQuality: 0.85) {
            parts.append(.init(name: "photo_after", filename: "after.jpg", mime: "image/jpeg", data: data))
        }
        var fields: [String: String] = [:]
        if let comment, !comment.isEmpty { fields["comment"] = comment }

        try await client.uploadMultipart(
            url: ApiRoutes.Activities.legacy_submit(id: activityId),
            fields: fields,
            parts: parts
        )
    }

    // ---- Private helpers

    /// Универсальный парсер дат под все варианты, встречавшиеся в проекте.
    static func parseDateSmart(_ s: String) -> Date? {
        for f in Self.dateParsers {
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private static let dateParsers: [DateFormatter] = {
        let make: (String) -> DateFormatter = { fmt in
            let f = DateFormatter()
            f.locale = .init(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = fmt
            return f
        }
        // ISO: 2024-05-13T18:08:27+0300
        // Space: 2024-05-13 18:08:27
        // Date only: 2024-05-13
        return [
            make("yyyy-MM-dd'T'HH:mm:ssZ"),
            make("yyyy-MM-dd HH:mm:ss"),
            make("yyyy-MM-dd")
        ]
    }()
}

// MARK: - Server response shapes we need to support

/// Старый вариант: { "data": [ {id,name,description,created_at} ] }
private struct HistoryWrappedV1: Decodable {
    let data: [HistoryV1]
}

private struct HistoryV1: Decodable {
    let id: String
    let name: String
    let description: String?
    let created_at: String

    func asActivity(email: String) -> Activity {
        Activity(
            id: id,
            name: name,
            description: description,
            isCompleted: true,
            createdAt: ActivityRepositoryImpl.parseDateSmart(created_at),
            updatedAt: nil,
            userEmail: email
        )
    }
}

/// Текущий вариант: [ { workoutKey, workoutActivityType, workoutStartDate } ]
private struct HistoryV2: Decodable {
    let workoutKey: String
    let workoutActivityType: String
    let workoutStartDate: String

    func asActivity(email: String) -> Activity {
        Activity(
            id: workoutKey,
            name: workoutActivityType,
            description: nil,
            isCompleted: true,
            createdAt: ActivityRepositoryImpl.parseDateSmart(workoutStartDate),
            updatedAt: nil,
            userEmail: email
        )
    }
}
