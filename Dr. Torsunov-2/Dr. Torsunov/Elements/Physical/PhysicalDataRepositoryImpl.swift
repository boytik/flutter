import Foundation
import UIKit
import OSLog

// MARK: - Модель
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

// MARK: - Контракт
protocol PhysicalDataRepository {
    func load() async throws -> PhysicalData
    func save(data: PhysicalData) async throws
    func uploadAvatar(_ image: UIImage) async throws
}

private enum PhysicalRepoError: LocalizedError {
    case noEmail
    var errorDescription: String? { "No email to load/update physical data" }
}

// MARK: - Логгер
private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app",
                         category: "PhysicalDataRepo")

// MARK: - Реализация
final class PhysicalDataRepositoryImpl: PhysicalDataRepository {
    private let client = HTTPClient.shared

    func load() async throws -> PhysicalData {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            throw PhysicalRepoError.noEmail
        }

        let primary: [URL] = [
            ApiRoutes.Users.physical(email: email),
            ApiRoutes.Users.physicalByQuery(email: email)
        ]

        for u in primary {
            do {
                let res: PhysicalData = try await client.request(PhysicalData.self, url: u)
                log.info("[Physical] loaded (primary) \(u.absoluteString, privacy: .public)")
                return res
            } catch NetworkError.server(let code, _) where code == 404 || code == 500 {
                log.error("[Physical] \(code) on \(u.absoluteString, privacy: .public) → try fallback")
            } catch {
                log.error("[Physical] primary failed: \(error.localizedDescription, privacy: .public)")
            }
        }

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
            let starting_date: String?
        }

        func parseDate(_ s: String?) -> Date? {
            guard let s, !s.isEmpty else { return nil }
            let f = DateFormatter()
            f.locale = .init(identifier: "en_US_POSIX")
            f.timeZone = .init(secondsFromGMT: 0)
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let d = f.date(from: s) { return d }
            return ISO8601DateFormatter().date(from: s)
        }

        let fullURL = ApiRoutes.Users.get(email: email, short: false)
        do {
            let raw: ServerUserRaw = try await client.request(ServerUserRaw.self, url: fullURL)
            log.info("[Physical] loaded via /users/<email> (full)")
            return PhysicalData(
                startDate: parseDate(raw.starting_date),
                age: raw.age.map(Int.init),
                gender: raw.sex,
                height: raw.height.map(Int.init),
                weight: raw.weight.map(Int.init),
                dailyRoutine: raw.maintaining_a_daily_routine.map { $0 != 0 },
                badHabits: raw.bad_habits.map { $0 != 0 },
                chronicDiseases: raw.chronic_diseases.map { $0 != 0 },
                chronicDescription: raw.list_of_diseases
            )
        } catch {
            let shortURL = ApiRoutes.Users.get(email: email, short: true)
            let raw: ServerUserRaw = try await client.request(ServerUserRaw.self, url: shortURL)
            log.info("[Physical] loaded via /users/<email>/short")
            return PhysicalData(
                startDate: parseDate(raw.starting_date),
                age: raw.age.map(Int.init),
                gender: raw.sex,
                height: raw.height.map(Int.init),
                weight: raw.weight.map(Int.init),
                dailyRoutine: raw.maintaining_a_daily_routine.map { $0 != 0 },
                badHabits: raw.bad_habits.map { $0 != 0 },
                chronicDiseases: raw.chronic_diseases.map { $0 != 0 },
                chronicDescription: raw.list_of_diseases
            )
        }
    }

    func save(data: PhysicalData) async throws {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            throw PhysicalRepoError.noEmail
        }

        let urls = [
            ApiRoutes.Users.physical(email: email),
            ApiRoutes.Users.physicalByQuery(email: email)
        ]

        var lastError: Error = PhysicalRepoError.noEmail
        for u in urls {
            do {
                try await client.requestVoid(url: u, method: .PATCH, body: data)
                log.info("[Physical] saved via \(u.absoluteString, privacy: .public)")
                return
            } catch NetworkError.server(let code, let data) where code == 404 || code == 500 {
                log.error("[Physical] \(code) on \(u.absoluteString, privacy: .public) → try next")
                lastError = NetworkError.server(status: code, data: data)
            } catch {
                log.error("[Physical] save failed: \(error.localizedDescription, privacy: .public)")
                lastError = error
            }
        }
        throw lastError
    }

    func uploadAvatar(_ image: UIImage) async throws {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            throw PhysicalRepoError.noEmail
        }
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
        log.info("[Physical] avatar uploaded")
    }
}
