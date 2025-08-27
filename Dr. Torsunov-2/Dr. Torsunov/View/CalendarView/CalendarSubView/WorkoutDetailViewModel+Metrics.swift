//
//  WorkoutDetailViewModel+Metrics.swift
//  ReviveMobile (Swift port)
//  Берём длительность как во Flutter: сначала из metadata/metrics (durationHours/minutes),
//  если нет — считаем по timeSeries. Плюс слой/подслой. Работает рекурсивно с любой вложенностью.
//  Дополнено: умный парсер длительности (hh:mm, mm:ss, “1ч 30м”, “105 min”), больше синонимов ключей,
//  обработка timeSeries как [Double]/[Int]/[Date]/[[String:Any]], эпоха в сек/мс, кэш, форматтеры.
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

// Универсальный JSON экстрактор — String / Int / Double / NSNumber / Bool
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
    // Пытаемся достать Published-поля как Any; дальше идём рекурсией, без завязки на внутренности Published.
    private var _metricsAny: Any?  { __readPublishedAny(labelContains: "_metrics") }
    private var _metadataAny: Any? { __readPublishedAny(labelContains: "_metadata") }

    // MARK: Cache
    private struct _AssociatedKeys { static var cache = "_metrics_cache_key" }
    private var __cache: _MetricsCache {
        if let c = objc_getAssociatedObject(self, &_AssociatedKeys.cache) as? _MetricsCache { return c }
        let c = _MetricsCache(); objc_setAssociatedObject(self, &_AssociatedKeys.cache, c, .OBJC_ASSOCIATION_RETAIN_NONATOMIC); return c
    }

    // === КАК ВО FLUTTER ===
    /// Минуты из metadata/metrics: durationHours + durationMinutes (если есть), либо durationMinutes, либо durationText.
    var dtoDurationMinutes: Int? {
        if let cached = __cache.dtoMinutes { return cached }
        // Иногда хранят просто "duration" числом в минутах.
        if let v = __findInt(keys: ["duration","workout_duration","duration_min_total"]) {
            let res = max(0, v); __cache.dtoMinutes = res; return res
        }
        // Явные минутки
        if let m = __findInt(keys: ["durationMinutes","duration_min","minutes","mins"]) {
            let res = max(0, m); __cache.dtoMinutes = res; return res
        }
        // Hours + Minutes
        let hrs = __findInt(keys: ["durationHours","duration_hours","hours","hrs","h"])
        let min = __findInt(keys: ["durationMinutes","duration_min","minutes","mins","m"])
        if hrs != nil || min != nil {
            let total = (hrs ?? 0) * 60 + (min ?? 0)
            if total > 0 { __cache.dtoMinutes = total; return total }
        }
        // Текст duration ("HH:mm", "H:mm:ss", "1ч 30м", "105 мин")
        if let s = __findString(keys: ["durationText","durationString","timeText","totalTimeText","duration_label","durationHuman","duration_human"]),
           let parsed = __parseDurationString(s) {
            __cache.dtoMinutes = parsed; return parsed
        }
        __cache.dtoMinutes = nil
        return nil
    }

    /// Минуты по timeSeries (fallback): поддержка массивов секунд/миллисекунд/Date/словарей {time|t|ts}.
    var timeSeriesDurationMinutes: Int? {
        if let cached = __cache.tsMinutes { return cached }
        guard let sec = __anyTimeSeriesDeltaSeconds() else { __cache.tsMinutes = nil; return nil }
        let mins = Int((sec / 60.0).rounded(.down))
        __cache.tsMinutes = mins > 0 ? mins : nil
        return __cache.tsMinutes
    }

    /// Главный геттер для UI: предпочитаем значения из DTO/metadata, иначе считаем по timeSeries.
    var preferredDurationMinutes: Int? {
        if let cached = __cache.preferredMinutes { return cached }
        if let m = dtoDurationMinutes { __cache.preferredMinutes = m; return m }
        if let m = durationMinutesInt /* старые ключи, если вдруг есть */ { __cache.preferredMinutes = m; return m }
        let v = timeSeriesDurationMinutes
        __cache.preferredMinutes = v
        return v
    }

    /// Исторический геттер: пытаемся найти «длительность» по любым ключам / start-end / timeSeries.
    var durationMinutesInt: Int? {
        // 1) Минуты напрямую (ищем на любом уровне)
        if let d = __findInt(keys: [
            "durationMinutes","duration_min","totalMinutes","total_min",
            "minutes","mins","time_total_minutes","workout_time_minutes",
            "duration_in_minutes","durationMin","min_total"
        ]) { return d }

        // 2) Секунды/миллисекунды
        if let s = __findInt(keys: ["durationSeconds","totalSeconds","seconds","sec","duration_in_seconds"]) {
            return max(0, Int((Double(s) / 60.0).rounded(.down)))
        }
        if let ms = __findInt(keys: ["durationMillis","durationMs","totalMillis","total_ms","milliseconds","duration_in_ms"]) {
            return max(0, Int((Double(ms) / 60000.0).rounded(.down)))
        }

        // 3) Текст "HH:mm" / "H:mm:ss" / "1ч 30м" / "105 мин"
        if let s = __findString(keys: ["durationText","durationString","timeText","totalTimeText","duration_label","durationHuman","duration_human"]),
           let v = __parseDurationString(s) {
            return v
        }

        // 4) Start / End
        if let start = __findDate(keys: ["startTime","startDate","begin","from","started_at","start_ts","start_timestamp"]),
           let end   = __findDate(keys: ["endTime","endDate","finish","to","ended_at","end_ts","end_timestamp"]) {
            let mins = Int(end.timeIntervalSince(start) / 60.0)
            if mins > 0 { return mins }
        }

        // 5) Любой временной ряд → Δt секунд → минуты
        if let sec = __anyTimeSeriesDeltaSeconds() {
            return Int((sec / 60.0).rounded(.down))
        }
        return nil
    }

    /// Текущий слой
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

    /// Текущий подслой
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

    /// Прогресс подслоя "6/7"
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

    // MARK: - Удобные форматтеры для UI
    /// "1 ч 45 мин" / "45 мин"
    var durationHumanized: String? {
        guard let m = preferredDurationMinutes else { return nil }
        let h = m / 60, mm = m % 60
        if h > 0 && mm > 0 { return "\(h) ч \(mm) мин" }
        if h > 0 { return "\(h) ч" }
        return "\(mm) мин"
    }

    /// "HH:mm" (для шапки графика)
    var durationHHmm: String? {
        guard let m = preferredDurationMinutes else { return nil }
        let h = m / 60, mm = m % 60
        return String(format: "%02d:%02d", h, mm)
    }

    // MARK: - Published access impl
    fileprivate func __readPublishedAny(labelContains: String) -> Any? {
        let mirror = Mirror(reflecting: self)
        return mirror.children.first(where: { ($0.label ?? "").lowercased().contains(labelContains.lowercased()) })?.value
    }

    // MARK: - Рекурсивный поиск
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

    /// Ограничиваем глубину, обрабатываем словари, коллекции, enum-wrappers, структуры, классы.
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
        case .enum:
            let unwrapped = __unwrapJSONEnum(any)
            if "\(type(of: unwrapped))" == "\(type(of: any))" { return nil }
            return __searchJSON(unwrapped, keyMatches: keyMatches, depth: depth + 1)
        case .struct, .class, .tuple:
            for child in m.children {
                if let label = child.label?.lowercased(), keyMatches(label) { return __unwrapJSONEnum(child.value) }
                if let found = __searchJSON(child.value, keyMatches: keyMatches, depth: depth + 1) { return found }
            }
        default: break
        }
        return nil
    }

    fileprivate func __unwrapJSONEnum(_ any: Any) -> Any {
        let m = Mirror(reflecting: any)
        if m.displayStyle == .enum, let assoc = m.children.first?.value {
            let mm = Mirror(reflecting: assoc)
            if mm.children.count == 0 { return assoc }
            if mm.displayStyle == .tuple { return mm.children.first?.value ?? assoc }
            return assoc
        }
        return any
    }

    fileprivate func __lookupIntOnSelf(keys: [String]) -> Int? {
        let mirror = Mirror(reflecting: self)
        let lowered = keys.map { $0.lowercased() }
        for child in mirror.children {
            guard let label = child.label?.lowercased() else { continue }
            if lowered.contains(where: { label.contains($0) }) {
                if let v = child.value as? Int { return v }
                if let n = child.value as? NSNumber { return n.intValue }
                if let s = child.value as? String, let v = Int(s) { return v }
            }
        }
        return nil
    }

    // MARK: - Time-series delta
    /// Считает Δt в секундах из разных форм представления timeSeries:
    /// [Date], [Double], [Int], [NSNumber], [[String:Any]] где ключи времени: "time","timestamp","ts","t","date","x","epoch","at"
    fileprivate func __anyTimeSeriesDeltaSeconds() -> Double? {
        // прямые массивы
        if let any = __findValue(for: ["timeSeries","timestamps","times","time","x","samples_time","timeline"]) {
            if let d = __delta(from: any) { return d }
        }
        // иногда хранятся под вложенными ключами
        for key in ["series","data","points","samples"] {
            if let any = __findValue(for: [key]), let d = __delta(from: any) { return d }
        }
        return nil
    }

    private func __delta(from any: Any) -> Double? {
        // 1) Плоские массивы
        if let dates = any as? [Date], dates.count >= 2 { return max(0, dates.last!.timeIntervalSince(dates.first!)) }
        if let doubles = any as? [Double], doubles.count >= 2 { return max(0, doubles.last! - doubles.first!) }
        if let ints = any as? [Int],     ints.count >= 2 { return max(0, Double(ints.last! - ints.first!)) }
        if let nums = any as? [NSNumber], nums.count >= 2 { return max(0, nums.last!.doubleValue - nums.first!.doubleValue) }

        // 2) Массив словарей/структур с полем времени
        if let arr = any as? [Any], arr.count >= 2 {
            func extractTime(_ e: Any) -> Double? {
                let timeKeys = ["time","timestamp","ts","t","date","x","epoch","at"]
                if let dict = e as? [String: Any] {
                    for k in timeKeys {
                        if let raw = dict[k] ?? dict[k.capitalized] ?? dict[k.uppercased()] {
                            if let dd = raw as? Date { return dd.timeIntervalSince1970 }
                            if let n = __JV.double(raw) { return n > 10_000_000_000 ? n / 1000.0 : n }
                            if let s = __JV.string(raw),
                               let d = __iso8601Full.date(from: s) ?? __iso8601Short.date(from: s) {
                                return d.timeIntervalSince1970
                            }
                        }
                    }
                } else {
                    let m = Mirror(reflecting: e)
                    for child in m.children {
                        if let label = child.label?.lowercased(), timeKeys.contains(label) {
                            if let dd = child.value as? Date { return dd.timeIntervalSince1970 }
                            if let n = __JV.double(child.value) { return n > 10_000_000_000 ? n/1000.0 : n }
                            if let s = __JV.string(child.value),
                               let d = __iso8601Full.date(from: s) ?? __iso8601Short.date(from: s) {
                                return d.timeIntervalSince1970
                            }
                        }
                    }
                }
                return nil
            }

            if let first = extractTime(arr.first!), let last = extractTime(arr.last!) {
                return max(0, last - first)
            }
            // Иногда серия начинается с 0
            if let last = extractTime(arr.last!), last > 0 { return last }
        }

        // 3) Ничего не вышло — ищем глубже
        let m = Mirror(reflecting: any)
        if m.displayStyle == .collection || m.displayStyle == .dictionary || m.displayStyle == .struct || m.displayStyle == .class {
            for child in m.children {
                if let d = __delta(from: child.value) { return d }
            }
        }
        return nil
    }

    // MARK: - Duration string parser
    /// Поддерживает:
    /// - "HH:mm", "H:mm:ss", "mm:ss"
    /// - "1h 30m", "1 ч 30 м", "1ч30м", "105 min", "45м", "90сек"
    /// - "1 час 5 минут", "2 часа", "75 минут"
    fileprivate func __parseDurationString(_ s: String) -> Int? {
        var trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        trimmed = trimmed.replacingOccurrences(of: ",", with: ".")
        // 1) Форматы с двоеточием
        let parts = trimmed.split(separator: ":").map { String($0) }
        if parts.count == 3, let hh = Int(parts[0]), let mm = Int(parts[1]) {
            return max(0, hh * 60 + mm)
        }
        if parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]) {
            // эвристика: если второй компонент < 60 → это hh:mm; иначе считаем как mm:ss и берём a минут
            if b < 60 { return max(0, a * 60 + b) }
            return max(0, a) // mm:ss — берём только полные минуты
        }

        // 2) Текстовые единицы: h/hr/час/ч, m/min/мин/м, s/sec/сек/с
        let unitPatterns = [
            ("hours", #"(?:\b|_)(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours|час(?:а|ов)?|ч)\b"#),
            ("minutes", #"(?:\b|_)(\d+(?:\.\d+)?)\s*(?:m|min|mins|minute|minutes|мин(?:ута|уты|ут)?|м)\b"#),
            ("seconds", #"(?:\b|_)(\d+(?:\.\d+)?)\s*(?:s|sec|secs|second|seconds|сек(?:унда|унды|унд)?|с)\b"#)
        ]
        var h: Double = 0, m: Double = 0, sec: Double = 0
        for (kind, pattern) in unitPatterns {
            if let rgx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let matches = rgx.matches(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count))
                for match in matches where match.numberOfRanges >= 2 {
                    if let range = Range(match.range(at: 1), in: trimmed) {
                        let numStr = String(trimmed[range])
                        let val = Double(numStr) ?? 0
                        switch kind {
                        case "hours":   h += val
                        case "minutes": m += val
                        case "seconds": sec += val
                        default: break
                        }
                    }
                }
            }
        }
        if h > 0 || m > 0 || sec > 0 {
            let totalMin = h * 60 + m + floor(sec / 60.0)
            return Int(totalMin)
        }

        // 3) Голое число → считаем как минуты
        if let number = Int(trimmed.filter("0123456789".contains)) { return number }

        return nil
    }

    // MARK: - форматтеры дат
    private var __iso8601Full: DateFormatter {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .init(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return f
    }
    private var __iso8601Short: DateFormatter {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .init(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }
}
