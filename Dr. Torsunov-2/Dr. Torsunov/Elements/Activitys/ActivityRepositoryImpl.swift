import Foundation
import UIKit

// MARK: - Public model
struct Activity: Identifiable, Codable, Equatable {
    var id: String
    var name: String?
    var description: String?
    var isCompleted: Bool
    var createdAt: Date?
    var updatedAt: Date?
}

// MARK: - DTO для /list_workouts_for_check (+ full)
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

    let avg_humidity: JSONValue?
    let avg_temp:     JSONValue?
    let distance:     JSONValue?
    let duration:     JSONValue?
    let list_positions: JSONValue?
    let maxLayer:     JSONValue?
    let maxSubLayer:  JSONValue?

    enum CodingKeys: String, CodingKey {
        case activityGraph, avg_humidity, avg_temp, comment
        case distance, duration, heartRateGraph, list_positions, map
        case maxLayer, maxSubLayer, photoAfter, photoBefore
        case workoutActivityType, workoutKey, workoutStartDate, minStartTime
        case currentLayerChecked, currentsubLayerChecked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workoutKey           = try c.decodeIfPresent(String.self, forKey: .workoutKey)
        workoutActivityType  = try c.decodeIfPresent(String.self, forKey: .workoutActivityType)
        workoutStartDate     = try c.decodeIfPresent(String.self, forKey: .workoutStartDate)
        minStartTime         = try c.decodeIfPresent(String.self, forKey: .minStartTime)
        comment              = try c.decodeIfPresent(String.self, forKey: .comment)
        photoAfter           = try c.decodeIfPresent(String.self, forKey: .photoAfter)
        photoBefore          = try c.decodeIfPresent(String.self, forKey: .photoBefore)
        activityGraph        = try c.decodeIfPresent(String.self, forKey: .activityGraph)
        heartRateGraph       = try c.decodeIfPresent(String.self, forKey: .heartRateGraph)
        map                  = try c.decodeIfPresent(String.self, forKey: .map)

        avg_humidity         = try c.decodeIfPresent(JSONValue.self, forKey: .avg_humidity)
        avg_temp             = try c.decodeIfPresent(JSONValue.self, forKey: .avg_temp)
        distance             = try c.decodeIfPresent(JSONValue.self, forKey: .distance)
        duration             = try c.decodeIfPresent(JSONValue.self, forKey: .duration)
        list_positions       = try c.decodeIfPresent(JSONValue.self, forKey: .list_positions)
        maxLayer             = try c.decodeIfPresent(JSONValue.self, forKey: .maxLayer)
        maxSubLayer          = try c.decodeIfPresent(JSONValue.self, forKey: .maxSubLayer)

        _ = try? c.decodeIfPresent(String.self, forKey: .currentLayerChecked)
        _ = try? c.decodeIfPresent(String.self, forKey: .currentsubLayerChecked)
    }

    var startedAt: Date? {
        for raw in [workoutStartDate, minStartTime] {
            if let s = raw, let d = Self.parseDate(s) { return d }
        }
        return nil
    }

    private static func parseDate(_ s: String) -> Date? {
        let fmts = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"]
        let df = DateFormatter()
        df.locale = .init(identifier: "en_US_POSIX")
        df.timeZone = .current
        for f in fmts {
            df.dateFormat = f
            if let d = df.date(from: s) { return d }
        }
        return nil
    }
}

// MARK: - DTO под /list_workouts
private struct ActivityFeedDTO: Decodable {
    let workoutKey: String?
    let workoutActivityType: String?
    let workoutStartDate: String?

    enum CodingKeys: String, CodingKey {
        case workoutKey, workoutActivityType, workoutStartDate
    }

    var startDate: Date? {
        Self.df.date(from: workoutStartDate ?? "")
    }

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}

// MARK: - Protocol
protocol ActivityRepository {
    func fetchAll() async throws -> [Activity]        // история (completed)
    func upload(activity: Activity) async throws
    func submit(activityId: String,
                comment: String?,
                beforeImage: UIImage?,
                afterImage: UIImage?) async throws
}

// MARK: - Impl
final class ActivityRepositoryImpl: ActivityRepository {
    private let client = HTTPClient.shared

    func fetchAll() async throws -> [Activity] {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            print("⚠️ ActivityRepo: no email → empty")
            return []
        }

        // Как во Flutter: lastDate = сегодня - 5 лет (забрать весь срез истории)
        let fiveYearsAgo = Calendar.current.date(byAdding: .year, value: -5, to: Date())!
        let dfDay = DateFormatter()
        dfDay.locale = .init(identifier: "en_US_POSIX")
        dfDay.timeZone = .current
        dfDay.dateFormat = "yyyy-MM-dd"
        let lastDate = dfDay.string(from: fiveYearsAgo)

        let url = ApiRoutes.Activities.listWorkouts(email: email, lastDate: lastDate)
        print("🛰️ GET history:", url.absoluteString)

        do {
            let dtos: [ActivityFeedDTO] = try await client.request([ActivityFeedDTO].self, url: url)
            let items = dtos.map {
                Activity(
                    id: $0.workoutKey ?? UUID().uuidString,
                    name: $0.workoutActivityType,
                    description: nil,
                    isCompleted: true,
                    createdAt: $0.startDate,
                    updatedAt: nil
                )
            }
            let sorted = items.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            print("✅ history /list_workouts items=\(sorted.count)")
            return sorted
        } catch {
            print("↩️ /list_workouts error:", error.localizedDescription)
            return []
        }
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
}
