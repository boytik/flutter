
import Foundation
import UIKit

import Foundation
import UIKit

protocol ActivityRepository {
    func fetchAll() async throws -> [Activity]
    func fetch(by id: String) async throws -> Activity
    func upload(activity: Activity) async throws
    func submit(activityId: String,
                comment: String?,
                beforeImage: UIImage?,
                afterImage: UIImage?) async throws
}

final class ActivityRepositoryImpl: ActivityRepository {
    private let client = HTTPClient.shared

    func fetchAll() async throws -> [Activity] {
        try await client.request([Activity].self,
                                 url: ApiRoutes.Activities.list)
    }

    func fetch(by id: String) async throws -> Activity {
        try await client.request(Activity.self,
                                 url: ApiRoutes.Activities.by(id: id))
    }

    func upload(activity: Activity) async throws {
        try await client.requestVoid(url: ApiRoutes.Activities.upload,
                                     method: .POST,
                                     body: activity)
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
            url: ApiRoutes.Activities.submit(id: activityId),
            fields: fields,
            parts: parts
        )
    }

}

