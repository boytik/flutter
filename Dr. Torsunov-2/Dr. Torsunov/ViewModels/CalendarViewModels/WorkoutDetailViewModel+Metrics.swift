//
//  WorkoutDetailViewModel+Metrics.swift
//  Фикс: позы йоги + время/длительность для слоёв (совместимо с Flutter).
//

import Foundation
import ObjectiveC.runtime

// MARK: - Lightweight cache (per-instance)
private final class _MetricsCache {
    var dtoMinutes: Int?
    var tsMinutes: Int?
    var preferredMinutes: Int?
    var layer: Int?
    var subLayer: Int?
    var subLayerProgress: String?
}

// Универсальный JSON экстрактор
private enum __JV {
    static func int(_ v: Any?) -> Int? {
        if let x = v as? Int { return x }
        if let x = v as? Double { return Int(x.rounded()) }
        if let x = v as? Float  { return Int(x.rounded()) }
        if let x = v as? NSNumber { return x.intValue }
        if let x = v as? String {
            let s = x.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            if let n = Int(s) { return n }
            if let d = Double(s) { return Int(d.rounded()) }
        }
        if let x = v as? Bool { return x ? 1 : 0 }
        return nil
    }
    static func double(_ v: Any?) -> Double? {
        if let x = v as? Double { return x }
        if let x = v as? Float  { return Double(x) }
        if let x = v as? Int    { return Double(x) }
        if let x = v as? NSNumber { return x.doubleValue }
        if let x = v as? String {
            let s = x.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            return Double(s)
        }
        return nil
    }
    static func string(_ v: Any?) -> String? {
        if let x = v as? String { return x }
        if let x = v as? NSNumber { return x.stringValue }
        if let x = v as? Bool { return x ? "true" : "false" }
        return nil
    }
}

extension WorkoutDetailViewModel {

    // MARK: Published access
    private var _metricsAny: Any?  { __readPublishedAny(labelContains: "_metrics") }
    private var _metadataAny: Any? { __readPublishedAny(labelContains: "_metadata") }

    // MARK: Cache
    private struct _AssociatedKeys { static var cache = "_metrics_cache_key" }
    private var __cache: _MetricsCache {
        if let c = objc_getAssociatedObject(self, &_AssociatedKeys.cache) as? _MetricsCache { return c }
        let c = _MetricsCache(); objc_setAssociatedObject(self, &_AssociatedKeys.cache, c, .OBJC_ASSOCIATION_RETAIN_NONATOMIC); return c
    }

    // === КАК ВО FLUTTER ===
    // Минуты из metadata/metrics → предпочтительный источник длительности
    var dtoDurationMinutes: Int? {
        if let cached = __cache.dtoMinutes { return cached }
        if let v = __findInt(keys: ["duration","workout_duration","duration_min_total"]) {
            let res = max(0, v); __cache.dtoMinutes = res; return res
        }
        if let m = __findInt(keys: ["durationMinutes","duration_min","minutes","mins"]) {
            let res = max(0, m); __cache.dtoMinutes = res; return res
        }
        let hrs = __findInt(keys: ["durationHours","duration_hours","hours","hrs","h"])
        let min = __findInt(keys: ["durationMinutes","duration_min","minutes","mins","m"])
        if hrs != nil || min != nil {
            let total = (hrs ?? 0) * 60 + (min ?? 0)
            if total > 0 { __cache.dtoMinutes = total; return total }
        }
        if let s = __findString(keys: ["durationText","durationString","timeText","totalTimeText","duration_label","durationHuman","duration_human"]),
           let parsed = __parseDurationString(s) {
            __cache.dtoMinutes = parsed; return parsed
        }
        __cache.dtoMinutes = nil
        return nil
    }

    /// Δt по timeSeries (секунды)
    var timeSeriesDurationMinutes: Int? {
        if let cached = __cache.tsMinutes { return cached }
        guard let sec = __anyTimeSeriesDeltaSeconds() else { __cache.tsMinutes = nil; return nil }
        let mins = Int((sec / 60.0).rounded(.down))
        __cache.tsMinutes = mins > 0 ? mins : nil
        return __cache.tsMinutes
    }

    /// Главный источник длительности для UI/оси времени
    var preferredDurationMinutes: Int? {
        if let cached = __cache.preferredMinutes { return cached }
        if let m = dtoDurationMinutes { __cache.preferredMinutes = m; return m }
        if let m = durationMinutesInt { __cache.preferredMinutes = m; return m }
        let v = timeSeriesDurationMinutes
        __cache.preferredMinutes = v
        return v
    }

    // Исторический геттер (оставлен)
    var durationMinutesInt: Int? {
        if let d = __findInt(keys: [
            "durationMinutes","duration_min","totalMinutes","total_min",
            "minutes","mins","time_total_minutes","workout_time_minutes",
            "duration_in_minutes","durationMin","min_total"
        ]) { return d }

        if let s = __findInt(keys: ["durationSeconds","totalSeconds","seconds","sec","duration_in_seconds"]) {
            return max(0, Int((Double(s) / 60.0).rounded(.down)))
        }
        if let ms = __findInt(keys: ["durationMillis","durationMs","totalMillis","total_ms","milliseconds","duration_in_ms"]) {
            return max(0, Int((Double(ms) / 60000.0).rounded(.down)))
        }

        if let s = __findString(keys: ["durationText","durationString","timeText","totalTimeText","duration_label","durationHuman","duration_human"]),
           let v = __parseDurationString(s) {
            return v
        }

        if let start = __findDate(keys: ["startTime","startDate","begin","from","started_at","start_ts","start_timestamp"]),
           let end   = __findDate(keys: ["endTime","endDate","finish","to","ended_at","end_ts","end_timestamp"]) {
            let mins = Int(end.timeIntervalSince(start) / 60.0)
            if mins > 0 { return mins }
        }

        if let sec = __anyTimeSeriesDeltaSeconds() {
            return Int((sec / 60.0).rounded(.down))
        }
        return nil
    }

    // Слои (текущий/подслой/прогресс) — без изменений логики
    var currentLayerCheckedInt: Int? {
        if let cached = __cache.layer { return cached }
        if let v = __findInt(keys: ["currentLayerChecked","currentLayer","layer_checked","layer","layerIndex","layer_now","stage","phase"]) {
            __cache.layer = v; return v
        }
        if let v = __lookupIntOnSelf(keys: ["currentLayerChecked","currentLayer","layer","layerIndex","stage","phase"]) {
            __cache.layer = v; return v
        }
        __cache.layer = nil; return nil
    }

    var currentSubLayerCheckedInt: Int? {
        if let cached = __cache.subLayer { return cached }
        if let v = __findInt(keys: ["currentsubLayerChecked","currentSubLayerChecked","subLayer","sub_layer","sublayer","subLayerIndex","sublayer_now","subStage","subPhase"]) {
            __cache.subLayer = v; return v
        }
        if let v = __lookupIntOnSelf(keys: ["currentsubLayerChecked","currentSubLayerChecked","subLayer","sub_layer","subLayerIndex","subStage","subPhase"]) {
            __cache.subLayer = v; return v
        }
        __cache.subLayer = nil; return nil
    }

    var subLayerProgressText: String? {
        if let cached = __cache.subLayerProgress { return cached }
        if let s = __findString(keys: ["subLayerProgress","sub_layer_progress","progress_subLayer","subLayerText","subprogress"]) {
            __cache.subLayerProgress = s; return s
        }
        let done  = __findInt(keys: ["currentsubLayerChecked","currentSubLayerChecked","subLayerDone","sublayer_done","sub_layer_done","sublayer_completed","sub_completed"])
        let total = __findInt(keys: ["subLayerTotal","totalSubLayers","sublayers_total","sub_layers_total","sub_total"])
        if let d = done, let t = total, t > 0 {
            let s = "\(d)/\(t)"; __cache.subLayerProgress = s; return s
        }
        __cache.subLayerProgress = nil; return nil
    }

    // Удобные форматтеры
    var durationHumanized: String? {
        guard let m = preferredDurationMinutes else { return nil }
        let h = m / 60, mm = m % 60
        if h > 0 && mm > 0 { return "\(h) ч \(mm) мин" }
        if h > 0 { return "\(h) ч" }
        return "\(mm) мин"
    }
    var durationHHmm: String? {
        guard let m = preferredDurationMinutes else { return nil }
        let h = m / 60, mm = m % 60
        return String(format: "%02d:%02d", h, mm)
    }

    // === Позы йоги (оставлено как у вас) ===
    func rebuildDerivedSeries() {
        guard let rows = self.metricObjectsArray else {
            self.yogaPoseTimeline = []
            self.yogaPoseLabels   = []
            self.yogaPoseIndices  = []
            return
        }
        let poseKeys = [
            "bodyPosition","body_position","position","pose","yogaPose","yoga_pose",
            "asana","posture","state","class","category","label"
        ]
        var labels: [String] = ["Lotus","Half lotus","Diamond","Standing","Kneeling","Butterfly","Other"]
        var timeline: [String] = []; timeline.reserveCapacity(rows.count)
        var last: String? = nil
        for row in rows {
            var s: String? = nil
            for key in poseKeys {
                if let v = value(for: [key], in: row) {
                    switch v {
                    case .string(let str): s = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    case .number(let d):
                        let i = Int(round(d))
                        if labels.indices.contains(i) { s = labels[i] } else { s = "\(i)" }
                    default: break
                    }
                    if s != nil { break }
                }
            }
            if s == nil { s = last ?? "Other" }
            if let s = s, !s.isEmpty {
                if !labels.contains(s) { labels.append(s) }
                timeline.append(s); last = s
            } else {
                timeline.append(last ?? "Other")
            }
        }
        let indexBy = Dictionary(uniqueKeysWithValues: labels.enumerated().map { ($1, $0) })
        let indices = timeline.map { Double(indexBy[$0] ?? 0) }

        self.yogaPoseTimeline = timeline
        self.yogaPoseLabels   = labels
        self.yogaPoseIndices  = indices
    }

    // ===== Служебные методы =====

    fileprivate func __readPublishedAny(labelContains: String) -> Any? {
        let mirror = Mirror(reflecting: self)
        return mirror.children.first(where: { ($0.label ?? "").lowercased().contains(labelContains.lowercased()) })?.value
    }

    fileprivate func __findInt(keys: [String]) -> Int? {
        if let any = __findValue(for: keys) { return __JV.int(any) }
        return nil
    }
    fileprivate func __findString(keys: [String]) -> String? {
        if let any = __findValue(for: keys) { return __JV.string(any) }
        return nil
    }
    fileprivate func __findDate(keys: [String]) -> Date? {
        guard let any = __findValue(for: keys) else { return nil }
        if let d = any as? Date { return d }
        if let s = __JV.string(any) {
            if let d = __iso8601Full.date(from: s) ?? __iso8601Short.date(from: s) { return d }
            if let t = Double(s) { return Date(timeIntervalSince1970: t > 10_000_000_000 ? t/1000.0 : t) }
        }
        if let n = __JV.double(any) { return Date(timeIntervalSince1970: n > 10_000_000_000 ? n/1000.0 : n) }
        return nil
    }
    fileprivate func __findValue(for keys: [String]) -> Any? {
        let lowered = keys.map { $0.lowercased() }
        if let any = _metricsAny, let v = __searchJSON(any, keyMatches: { lowered.contains($0.lowercased()) }) { return v }
        if let any = _metadataAny, let v = __searchJSON(any, keyMatches: { lowered.contains($0.lowercased()) }) { return v }
        return nil
    }
    fileprivate func __searchJSON(_ any: Any, keyMatches: (String) -> Bool, depth: Int = 0) -> Any? {
        if depth > 10 { return nil }
        let m = Mirror(reflecting: any)
        switch m.displayStyle {
        case .dictionary:
            for child in m.children {
                let pair = Mirror(reflecting: child.value).children.map { $0.value }
                if pair.count == 2 {
                    if let k = pair[0] as? String {
                        if keyMatches(k) { return __unwrapJSONEnum(pair[1]) }
                        if let found = __searchJSON(pair[1], keyMatches: keyMatches, depth: depth + 1) { return found }
                    } else {
                        if let found = __searchJSON(pair[1], keyMatches: keyMatches, depth: depth + 1) { return found }
                    }
                }
            }
        case .collection:
            for child in m.children {
                if let found = __searchJSON(child.value, keyMatches: keyMatches, depth: depth + 1) { return found }
            }
        case .struct, .class:
            for child in m.children {
                if let label = child.label, keyMatches(label) { return __unwrapJSONEnum(child.value) }
                if let found = __searchJSON(child.value, keyMatches: keyMatches, depth: depth + 1) { return found }
            }
        default: break
        }
        return nil
    }
    fileprivate func __unwrapJSONEnum(_ any: Any) -> Any {
        if let v = any as? JSONValue {
            switch v {
            case .string(let s): return s
            case .number(let d): return d
            case .bool(let b):   return b
            case .array(let a):  return a
            case .object(let o): return o
            case .null:          return NSNull()
            }
        }
        return any
    }

    fileprivate var __iso8601Full: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }
    fileprivate var __iso8601Short: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    /// Разбор строк длительности
    fileprivate func __parseDurationString(_ s: String) -> Int? {
        let str = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = str.split(separator: ":").map { String($0) }
        if parts.count == 2 || parts.count == 3,
           let h = Int(parts[0]), let m = Int(parts[1]) { return h * 60 + m }

        let digits = str.replacingOccurrences(of: ",", with: ".")
        if let n = Int(digits.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()),
           str.contains("мин") || str.contains("min") || str.contains("m ") { return n }

        let hMatch = digits.range(of: #"(\d+)\s*(ч|h)"#, options: .regularExpression)
        let mMatch = digits.range(of: #"(\d+)\s*(м|min|m)"#, options: .regularExpression)
        var total = 0
        if let r = hMatch, let v = Int(String(digits[r]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) { total += v * 60 }
        if let r = mMatch, let v = Int(String(digits[r]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) { total += v }
        return total > 0 ? total : nil
    }

    /// Δt по timeSeries (секунды)
    fileprivate func __anyTimeSeriesDeltaSeconds() -> Double? {
        guard let xs = self.timeSeries, xs.count >= 2 else { return nil }
        let first = xs.first!, last = xs.last!
        var delta = last - first
        if delta <= 0 { return nil }
        if delta > 10_000 { delta = delta / 1000.0 } // мс → сек
        return delta
    }

    fileprivate func __lookupIntOnSelf(keys: [String]) -> Int? {
        let wanted = Set(keys.map { $0.lowercased() })
        let m = Mirror(reflecting: self)
        for c in m.children {
            guard let label = c.label?.lowercased() else { continue }
            if wanted.contains(label) { return __JV.int(c.value) }
            let inner = Mirror(reflecting: c.value).children.first?.value
            if let v = inner, wanted.contains(label) { return __JV.int(v) }
        }
        return nil
    }
}
