// ActivityRepositoryImpl.swift
import Foundation
import UIKit

// MARK: - Public model (как и было)
struct Activity: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var description: String?
    var isCompleted: Bool
    var createdAt: Date?
    var updatedAt: Date?
}

// MARK: - DTO под /list_workouts
private struct ActivityFeedDTO: Decodable {
    let workoutKey: String?
    let workoutActivityType: String?
    let workoutStartDate: String?

    enum CodingKeys: String, CodingKey {
        case workoutKey
        case workoutActivityType
        case workoutStartDate
    }

    var startDate: Date? {
        Self.df.date(from: workoutStartDate ?? "")
    }

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}

// MARK: - Protocol
protocol ActivityRepository {
    /// История проведённых тренировок (из /list_workouts)
    func fetchAll() async throws -> [Activity]

    /// Нужны в проекте (создание/отправка материалов) — не удаляем
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
            return []
        }

        // Flutter-бэку нужен lastDate — берём сегодня (история "до сегодня")
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        let lastDate = df.string(from: Date())

        let url = ApiRoutes.Activities.listWorkouts(email: email, lastDate: lastDate)
        let dtos: [ActivityFeedDTO] = try await client.request([ActivityFeedDTO].self, url: url)

        let items = dtos.map { dto in
            Activity(
                id: dto.workoutKey ?? UUID().uuidString,
                name: dto.workoutActivityType ?? "Activity",
                description: nil,
                isCompleted: true,
                createdAt: dto.startDate,
                updatedAt: nil
            )
        }
        return items.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    // Эти два метода реально используются (создание/отправка) — оставляем
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
            parts.append(.init(name: "before", filename: "before.jpg", mime: "image/jpeg", data: data))
        }
        if let data = afterImage?.jpegData(compressionQuality: 0.85) {
            parts.append(.init(name: "after", filename: "after.jpg", mime: "image/jpeg", data: data))
        }

        let fields: [String: String] = comment.map { ["comment": $0] } ?? [:]

        try await client.uploadMultipart(
            url: ApiRoutes.Activities.legacy_submit(id: activityId),
            fields: fields,
            parts: parts
        )
    }
}
