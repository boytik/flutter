import Foundation
import SwiftUI

// MARK: - Универсальный JSON-декодер
enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil()                      { self = .null;   return }
        if let v = try? c.decode(Bool.self)   { self = .bool(v);   return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self)         { self = .array(v);  return }
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

// MARK: - VM
@MainActor
final class WorkoutDetailViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var metadata: [String: JSONValue] = [:]
    @Published var metrics:  [String: JSONValue] = [:]

    private let client = HTTPClient.shared
    private let workoutID: String

    init(workoutID: String) { self.workoutID = workoutID }

    // Грузим /metadata и /get_diagram_data независимо + с фолбэком workoutId
    func load() async {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            errorMessage = "No email"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Основные URL
        let metaURL1 = ApiRoutes.Workouts.metadata(workoutKey: workoutID, email: email)
        let metrURL1 = ApiRoutes.Workouts.metrics(workoutKey: workoutID, email: email)

        // Фолбэк URL с параметром workoutId
        let metaURL2 = Self.altURL(path: "metadata", query: ["workoutId": workoutID, "email": email])
        let metrURL2 = Self.altURL(path: "get_diagram_data", query: ["workoutId": workoutID, "email": email])

        var metaObj: [String: JSONValue] = [:]
        var metrObj: [String: JSONValue] = [:]
        var errs: [String] = []

        // 1) Метаданные (изображения диаграмм)
        do {
            metaObj = try await fetchObject(url: metaURL1)
        } catch {
            if case NetworkError.server = error {
                do { metaObj = try await fetchObject(url: metaURL2) }
                catch { errs.append(Self.shortError(error)) }
            } else { errs.append(Self.shortError(error)) }
        }

        // 2) Метрики (живые графики)
        do {
            metrObj = try await fetchObject(url: metrURL1)
        } catch {
            if case NetworkError.server = error {
                do { metrObj = try await fetchObject(url: metrURL2) }
                catch { errs.append(Self.shortError(error)) }
            } else { errs.append(Self.shortError(error)) }
        }

        // 3) Обновляем стейт
        self.metadata = metaObj
        self.metrics  = metrObj

        if !errs.isEmpty { self.errorMessage = errs.joined(separator: " • ") }
    }

    // MARK: helpers (network)

    private func fetchObject(url: URL) async throws -> [String: JSONValue] {
        // Пытаемся декодировать объект; если пришёл массив — оборачиваем как {"items":[...]}
        do {
            return try await client.request([String: JSONValue].self, url: url)
        } catch {
            if let arr: [JSONValue] = try? await client.request([JSONValue].self, url: url) {
                return ["items": .array(arr)]
            }
            throw error
        }
    }

    private static func shortError(_ error: Error) -> String {
        if case let NetworkError.server(status, _) = error { return "Server error (\(status))" }
        return error.localizedDescription
    }

    private static func altURL(path: String, query: [String:String]) -> URL {
        var url = APIEnv.baseURL.appendingPathComponent(path)
        if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.queryItems = query.map { .init(name: $0.key, value: $0.value) }
            url = comps.url ?? url
        }
        return url
    }

    // Диагностические строки (не для графиков)
    var metadataLines: [(String, String)] {
        metadata.keys.sorted().map { ($0, metadata[$0]!.pretty) }
    }
    var metricsLines: [(String, String)] {
        metrics.keys.sorted().map { ($0, metrics[$0]!.pretty) }
    }
}

// MARK: - Robust series extraction for array-of-objects payloads
// MARK: - Robust series extraction for array-of-objects payloads
extension WorkoutDetailViewModel {
    // MARK: helpers JSON
    func number(in value: JSONValue) -> Double? {
        switch value {
        case .number(let n): return n
        case .string(let s): return Double(s.replacingOccurrences(of: ",", with: "."))
        case .array(let arr): return arr.compactMap { number(in: $0) }.first
        default: return nil
        }
    }

    func array(in value: JSONValue) -> [JSONValue]? {
        if case let .array(a) = value { return a }
        return nil
    }

    func firstObjectArray(in value: JSONValue) -> [[String: JSONValue]]? {
        switch value {
        case .array(let arr):
            let objs = arr.compactMap { elem -> [String: JSONValue]? in
                if case let .object(o) = elem { return o } else { return nil }
            }
            return objs.isEmpty ? nil : objs
        case .object(let obj):
            for (_, v) in obj {
                if let res = firstObjectArray(in: v) { return res }
            }
            return nil
        default:
            return nil
        }
    }

    // ✅ ИСПРАВЛЕНО: без пробелов в имени параметра и без "anyOf"
    func value(for keys: [String], in obj: [String: JSONValue]) -> JSONValue? {
        let wanted = Set(keys.map { $0.lowercased() })
        for (k, v) in obj where wanted.contains(k.lowercased()) { return v }
        return nil
    }

    // MARK: locate rows
    var metricObjectsArray: [[String: JSONValue]]? {
        let candidates = ["metricsData", "items", "data", "points"]

        // прямые ключи (без .flatMap(array) по optional)
        for key in candidates {
            if let val = metrics[key],
               let arr = array(in: val) {
                let objs = arr.compactMap { el -> [String: JSONValue]? in
                    if case let .object(o) = el { return o } else { return nil }
                }
                if !objs.isEmpty { return objs }
            }
        }
        // рекурсивный поиск глубже
        for (_, v) in metrics {
            if let res = firstObjectArray(in: v) { return res }
        }
        return nil
    }

    // MARK: public series for UI
    var timeSeries: [Double]? {
        series(for: ["time_numeric","timeNumeric","time","t","seconds","secs","minutes","mins"])
    }
    var heartRateSeries: [Double]? {
        pairedY(for: ["heart_rate","heartrate","heartrateavg","heartRate","pulse","bpm","hr"])
    }
    var waterTempSeries: [Double]? {
        pairedY(for: ["water_temp","water_temperature","waterTemperature",
                      "temperature_c","temperatureCelsius","temp_c","temp"])
    }
    // опционально:
    var speedSeries: [Double]? {
        pairedY(for: ["speed_kmh","speedKmh","speed","kmh"])
    }
    var distanceSeries: [Double]? {
        pairedY(for: ["distance_meters","distanceMeters","distance","dist"])
    }

    private func series(for xKeys: [String]) -> [Double]? {
        guard let rows = metricObjectsArray else { return nil }
        let xs: [Double] = rows.compactMap { row in
            if let v = value(for: xKeys, in: row), let n = number(in: v) { return n } else { return nil }
        }
        return xs.count >= 2 ? xs : nil
    }

    private func pairedY(for yKeys: [String]) -> [Double]? {
        guard let rows = metricObjectsArray else { return nil }
        let tKeys = ["time_numeric","timeNumeric","time","t","seconds","secs","minutes","mins"]

        var pairs: [(Double, Double)] = []
        pairs.reserveCapacity(rows.count)
        for row in rows {
            guard let tv = value(for: tKeys, in: row), let t = number(in: tv) else { continue }
            guard let yv = value(for: yKeys, in: row), let y = number(in: yv) else { continue }
            pairs.append((t, y))
        }
        guard pairs.count >= 2 else { return nil }
        pairs.sort { $0.0 < $1.0 }
        return pairs.map { $0.1 }
    }

    // MARK: diagram images from /metadata
    var diagramImageURLs: [URL] {
        let candidates = metadata.values.compactMap { v -> URL? in
            if case let .string(s) = v, (s.hasPrefix("http") || s.hasPrefix("https")),
               let u = URL(string: s) { return u }
            return nil
        }
        return Array(NSOrderedSet(array: candidates)).compactMap { $0 as? URL }
    }
}
