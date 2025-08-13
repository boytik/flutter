
// Elements/Profile/PhysicalDataRepository.swift
import Foundation
import UIKit

struct PhysicalData: Codable, Equatable {
    var startDate: Date?
    var age: Int?
    var gender: String?
    var height: Int?
    var weight: Int?
    var dailyRoutine: Bool?
    var badHabits: Bool?
    var chronicDiseases: Bool?
    var chronicDescription: String?
}

protocol PhysicalDataRepository {
    func load() async throws -> PhysicalData
    func save(data: PhysicalData) async throws
    func uploadAvatar(_ image: UIImage) async throws
}

private enum PhysicalRepoError: LocalizedError {
    case noEmail
    var errorDescription: String? { "No email to load/update physical data" }
}

final class PhysicalDataRepositoryImpl: PhysicalDataRepository {
    private let client = HTTPClient.shared

    func load() async throws -> PhysicalData {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty
        else { throw PhysicalRepoError.noEmail }

        // 1) пробуем «старые» варианты — вдруг потом появятся
        let primary: [URL] = [
            ApiRoutes.Users.physical(email: email),            // 404 сейчас
            ApiRoutes.Users.physicalByQuery(email: email)      // 404 сейчас
        ]

        for u in primary {
            do {
                let res: PhysicalData = try await client.request(PhysicalData.self, url: u)
                print("✅ Physical loaded from:", u.absoluteString)
                return res
            } catch NetworkError.server(let code, _) where code == 404 || code == 500 {
                print("↩️ \(code) on \(u.absoluteString), trying fallback…")
            }
        }

        // 2) Фоллбек: берём из /users/<email> (или /short) и конвертим
        struct ServerUserRaw: Decodable {
            let userEmail: String?
            let name: String?
            let sex: String?
            let age: Double?
            let height: Double?
            let weight: Double?
            let maintaining_a_daily_routine: Int?
            let bad_habits: Int?
            let chronic_diseases: Int?
            let list_of_diseases: String?
            let starting_date: String? // "2025-01-13 20:00:00"
        }

        func parseDate(_ s: String?) -> Date? {
            guard let s, !s.isEmpty else { return nil }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)   // ← вместо .utc
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let d = f.date(from: s) { return d }
            let iso = ISO8601DateFormatter()
            return iso.date(from: s)
        }

        let fullURL = ApiRoutes.Users.get(email: email, short: false)
        do {
            let raw: ServerUserRaw = try await client.request(ServerUserRaw.self, url: fullURL)
            print("✅ Physical via /users/<email>")
            return PhysicalData(
                startDate: parseDate(raw.starting_date),
                age: raw.age.map { Int($0) },
                gender: raw.sex,
                height: raw.height.map { Int($0) },
                weight: raw.weight.map { Int($0) },
                dailyRoutine: raw.maintaining_a_daily_routine.map { $0 != 0 },
                badHabits: raw.bad_habits.map { $0 != 0 },
                chronicDiseases: raw.chronic_diseases.map { $0 != 0 },
                chronicDescription: raw.list_of_diseases
            )
        } catch {
            // затем «короткий»
            let shortURL = ApiRoutes.Users.get(email: email, short: true)
            let raw: ServerUserRaw = try await client.request(ServerUserRaw.self, url: shortURL)
            print("✅ Physical via /users/<email>/short")
            return PhysicalData(
                startDate: parseDate(raw.starting_date),
                age: raw.age.map { Int($0) },
                gender: raw.sex,
                height: raw.height.map { Int($0) },
                weight: raw.weight.map { Int($0) },
                dailyRoutine: raw.maintaining_a_daily_routine.map { $0 != 0 },
                badHabits: raw.bad_habits.map { $0 != 0 },
                chronicDiseases: raw.chronic_diseases.map { $0 != 0 },
                chronicDescription: raw.list_of_diseases
            )
        }
    }


    func save(data: PhysicalData) async throws {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty
        else { throw PhysicalRepoError.noEmail }

        let urls = [
            ApiRoutes.Users.physical(email: email),
            ApiRoutes.Users.physicalByQuery(email: email)
        ]

        var lastError: Error = PhysicalRepoError.noEmail
        for u in urls {
            do {
                try await client.requestVoid(url: u, method: .PATCH, body: data)
                print("✅ Physical saved via:", u.absoluteString)
                return
            } catch NetworkError.server(let code, let data) where code == 404 || code == 500 {
                print("↩️ \(code) on \(u.absoluteString), trying next…")
                lastError = NetworkError.server(status: code, data: data)
                continue
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    func uploadAvatar(_ image: UIImage) async throws {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty
        else { throw PhysicalRepoError.noEmail }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NetworkError.other(NSError(domain: "ImageEncoding", code: -1))
        }
        try await client.uploadMultipart(
            url: ApiRoutes.Users.avatar(email: email),
            fields: [:],
            parts: [
                HTTPClient.UploadPart(
                    name: "file",
                    filename: "avatar.jpg",
                    mime: "image/jpeg",
                    data: data
                )
            ]
        )
    }
}
