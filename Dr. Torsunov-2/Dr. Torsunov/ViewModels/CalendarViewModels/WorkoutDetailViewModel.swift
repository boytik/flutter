import Foundation
import SwiftUI
import OSLog

// MARK: - Логгер для этого модуля
private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app",
                         category: "WorkoutDetail")

// MARK: - Универсальный JSON-декодер (как было)
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
        case .number(let n): return n.rounded() == n ? String(Int(n)) : String(n)
        case .bool(let b):   return b ? "true" : "false"
        case .null:          return "null"
        case .array(let arr):
            return arr.isEmpty ? "[]" : "[ " + arr.map { $0.pretty }.joined(separator: ", ") + " ]"
        case .object(let obj):
            if obj.isEmpty { return "{}" }
            let lines = obj.keys.sorted().compactMap { key -> String? in
                guard let v = obj[key] else { return nil }
                return "• \(key): \(v.pretty)"
            }
            return lines.joined(separator: "\n")
        }
    }
}

// MARK: - Используем наш клиент поверх кэша
@MainActor
final class WorkoutDetailViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var metadata: [String: JSONValue] = [:]
    @Published var metrics:  [String: JSONValue] = [:]

    private let client: CacheRequesting = CacheJSONClient()
    private let workoutID: String

    private let ns = "workout_detail"
    private var kvKeyMeta: String { "meta_\(workoutID)" }
    private var kvKeyMetr: String { "metr_\(workoutID)" }

    private let httpTTLMeta: TimeInterval = 60 * 15
    private let httpTTLMetr: TimeInterval = 60 * 2
    private let kvTTLMeta: TimeInterval  = 60 * 60
    private let kvTTLMetr: TimeInterval  = 60 * 10

    init(workoutID: String) { self.workoutID = workoutID }
    
    // ВРЕМЕННО: отладочный дамп полей VM
    func dumpVMKeys(_ vm: Any) {
        let mirror = Mirror(reflecting: vm)
        for c in mirror.children {
            if let l = c.label {
                print("VM field:", l, "→", type(of: c.value))
            }
        }
    }


    func load() async {
        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else {
            errorMessage = "No email"
            log.error("[Load] Missing user email")
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        log.info("[Load] Start, workout=\(self.workoutID, privacy: .public)")

        if let m: [String: JSONValue] = try? KVStore.shared.get([String: JSONValue].self,
                                                                namespace: ns, key: kvKeyMeta) {
            self.metadata = m
        }
        if let m: [String: JSONValue] = try? KVStore.shared.get([String: JSONValue].self,
                                                                namespace: ns, key: kvKeyMetr) {
            self.metrics = m
        }

        let metaPrimary   = ApiRoutes.Workouts.metadata(workoutKey: workoutID, email: email)
        let metrPrimary   = ApiRoutes.Workouts.metrics(workoutKey: workoutID, email: email)
        let metaFallback  = Self.altURL(path: "metadata",         query: ["workoutId": workoutID, "email": email])
        let metrFallback  = Self.altURL(path: "get_diagram_data", query: ["workoutId": workoutID, "email": email])

        var errs: [String] = []

        do {
            log.info("[META] Request primary…")
            let metaObj = try await fetchObject(url: metaPrimary, ttl: httpTTLMeta)
            self.metadata = metaObj
            try? KVStore.shared.put(metaObj, namespace: ns, key: kvKeyMeta, ttl: kvTTLMeta)
            log.info("[META] OK (primary) → cached")
        } catch {
            let se = Self.shortError(error)
            log.error("[META] Primary failed: \(se, privacy: .public) → fallback")
            do {
                log.info("[META] Request fallback…")
                let metaObj = try await fetchObject(url: metaFallback, ttl: httpTTLMeta)
                self.metadata = metaObj
                try? KVStore.shared.put(metaObj, namespace: ns, key: kvKeyMeta, ttl: kvTTLMeta)
                log.info("[META] OK (fallback) → cached")
            } catch {
                let se2 = Self.shortError(error)
                log.error("[META] Fallback failed: \(se2, privacy: .public)")
                errs.append("Meta: \(se) / \(se2)")
            }
        }

        do {
            log.info("[METRICS] Request primary…")
            let metrObj = try await fetchObject(url: metrPrimary, ttl: httpTTLMetr)
            self.metrics = metrObj
            try? KVStore.shared.put(metrObj, namespace: ns, key: kvKeyMetr, ttl: kvTTLMetr)
            log.info("[METRICS] OK (primary) → cached")
        } catch {
            let se = Self.shortError(error)
            log.error("[METRICS] Primary failed: \(se, privacy: .public) → fallback")
            do {
                log.info("[METRICS] Request fallback…")
                let metrObj = try await fetchObject(url: metrFallback, ttl: httpTTLMetr)
                self.metrics = metrObj
                try? KVStore.shared.put(metrObj, namespace: ns, key: kvKeyMetr, ttl: kvTTLMetr)
                log.info("[METRICS] OK (fallback) → cached")
            } catch {
                let se2 = Self.shortError(error)
                log.error("[METRICS] Fallback failed: \(se2, privacy: .public)")
                errs.append("Metrics: \(se) / \(se2)")
            }
        }

        if !errs.isEmpty {
            let msg = errs.joined(separator: " • ")
            self.errorMessage = msg
            log.error("[Load] Completed with errors: \(msg, privacy: .public)")
        } else {
            log.info("[Load] Completed successfully")
        }
    }

    // MARK: helpers (network)

    private func fetchObject(url: URL, ttl: TimeInterval) async throws -> [String: JSONValue] {
        do {
            let obj: [String: JSONValue] = try await client.request(url, ttl: ttl)
            return obj
        } catch {
            if let arr: [JSONValue] = try? await client.request(url, ttl: ttl) {
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

    var metadataLines: [(String, String)] {
        metadata.keys.sorted().compactMap { key in
            guard let v = metadata[key] else { return nil }
            return (key, v.pretty)
        }
    }
    var metricsLines: [(String, String)] {
        metrics.keys.sorted().compactMap { key in
            guard let v = metrics[key] else { return nil }
            return (key, v.pretty)
        }
    }
}

// MARK: - Series helpers (как было)
extension WorkoutDetailViewModel {
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

    func value(for keys: [String], in obj: [String: JSONValue]) -> JSONValue? {
        let wanted = Set(keys.map { $0.lowercased() })
        for (k, v) in obj where wanted.contains(k.lowercased()) { return v }
        return nil
    }

    var metricObjectsArray: [[String: JSONValue]]? {
        let candidates = ["metricsData", "items", "data", "points"]

        for key in candidates {
            if let val = metrics[key], let arr = array(in: val) {
                let objs = arr.compactMap { el -> [String: JSONValue]? in
                    if case let .object(o) = el { return o } else { return nil }
                }
                if !objs.isEmpty { return objs }
            }
        }
        for (_, v) in metrics {
            if let res = firstObjectArray(in: v) { return res }
        }
        return nil
    }

    var timeSeries: [Double]? {
        series(for: ["time_numeric","timeNumeric","time","t","seconds","secs","minutes","mins"])
    }
    var heartRateSeries: [Double]? {
        pairedY(for: ["heart_rate","heartrate","heartrateavg","heartRate","pulse","bpm","hr"])
    }
    var waterTempSeries: [Double]? {
        pairedY(for: [
            "water_temp","water_temperature","waterTemperature",
            "temperature_c","temperatureCelsius","temp_c","temp"
        ])
    }
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

    var diagramImageURLs: [URL] {
        let candidates = metadata.values.compactMap { v -> URL? in
            if case let .string(s) = v, (s.hasPrefix("http") || s.hasPrefix("https")), let u = URL(string: s) {
                return u
            }
            return nil
        }
        return Array(NSOrderedSet(array: candidates)).compactMap { $0 as? URL }
    }
}
