

import Foundation
import Foundation
import SwiftUI

// Универсальный JSON-декодер (подойдёт на любой форме ответа)
enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v):   try c.encode(v)
        case .array(let v):  try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null:          try c.encodeNil()
        }
    }

    var pretty: String {
        switch self {
        case .string(let s): return "\"\(s)\""
        case .number(let n):
            if n.rounded() == n { return String(Int(n)) }
            return String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let arr):
            if arr.isEmpty { return "[]" }
            return "[ " + arr.map { $0.pretty }.joined(separator: ", ") + " ]"
        case .object(let obj):
            if obj.isEmpty { return "{}" }
            let lines = obj.keys.sorted().map { key in
                "• \(key): \(obj[key]!.pretty)"
            }
            return lines.joined(separator: "\n")
        }
    }
}

@MainActor
final class WorkoutDetailViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var metadata: [String: JSONValue] = [:]
    @Published var metrics:  [String: JSONValue] = [:]

    private let client = HTTPClient.shared
    private let workoutID: String

    init(workoutID: String) {
        self.workoutID = workoutID
    }

    func load() async {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            errorMessage = "No email"
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let meta = fetchObject(url: ApiRoutes.Workouts.metadata(workoutKey: workoutID, email: email))
            async let metr = fetchObject(url: ApiRoutes.Workouts.metrics(workoutKey: workoutID, email: email))
            let (m1, m2) = try await (meta, metr)
            self.metadata = m1
            self.metrics  = m2
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func fetchObject(url: URL) async throws -> [String: JSONValue] {
        // пробуем словарь; если придёт массив — принимаем как {"items": [...]}
        do {
            return try await client.request([String: JSONValue].self, url: url)
        } catch {
            // возможно, верхний уровень — массив
            if let arr: [JSONValue] = try? await client.request([JSONValue].self, url: url) {
                return ["items": .array(arr)]
            }
            throw error
        }
    }

    // Удобные представления для UI
    var metadataLines: [(String, String)] {
        metadata.keys.sorted().map { ($0, metadata[$0]!.pretty) }
    }
    var metricsLines: [(String, String)] {
        metrics.keys.sorted().map { ($0, metrics[$0]!.pretty) }
    }
}
