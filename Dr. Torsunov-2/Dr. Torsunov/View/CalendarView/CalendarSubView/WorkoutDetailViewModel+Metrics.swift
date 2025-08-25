//
// WorkoutDetailViewModel+Metrics.swift
// Берём длительность как во Flutter: сначала из metadata/metrics (durationHours/minutes),
// если нет — считаем по timeSeries. Плюс слой/подслой. Работает рекурсивно с любой вложенностью.
//

import Foundation

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

    // Пытаемся достать Published-поля как Any; дальше идём рекурсией, без завязки на внутренности Published.
    private var _metricsAny: Any?  { __readPublishedAny(labelContains: "_metrics") }
    private var _metadataAny: Any? { __readPublishedAny(labelContains: "_metadata") }

    // === КАК ВО FLUTTER ===
    /// Минуты из metadata/metrics: durationHours + durationMinutes (если есть), либо durationMinutes.
    var dtoDurationMinutes: Int? {
        // 1) Явные минутки
        if let m = __findInt(keys: ["durationMinutes","duration_min","minutes","mins"]) { return max(0, m) }

        // 2) Hours + Minutes
        let hrs = __findInt(keys: ["durationHours","duration_hours","hours","hrs"])
        let min = __findInt(keys: ["durationMinutes","duration_min","minutes","mins"])
        if hrs != nil || min != nil {
            let total = (hrs ?? 0) * 60 + (min ?? 0)
            return total > 0 ? total : nil
        }

        // 3) Текст duration ("HH:mm", "H:mm:ss", "105 мин")
        if let s = __findString(keys: ["durationText","durationString","timeText","totalTimeText","duration_label"]),
           let parsed = __parseDurationString(s) {
            return parsed
        }

        return nil
    }

    /// Минуты по timeSeries (fallback): (last-first)/60, если массив секунд; если начинается с 0 — last/60.
    var timeSeriesDurationMinutes: Int? {
        guard let ts = self.timeSeries, !ts.isEmpty else { return nil }
        let first = ts.first ?? 0
        let last  = ts.last  ?? first
        var delta = last - first
        if delta <= 0 { delta = last } // если старт с 0
        if delta > 0 { return Int((delta / 60.0).rounded(.down)) }
        return nil
    }

    /// Главный геттер для UI: предпочитаем значения из DTO/metadata, иначе считаем по timeSeries.
    var preferredDurationMinutes: Int? {
        if let m = dtoDurationMinutes { return m }
        if let m = durationMinutesInt /* старые ключи, если вдруг есть */ { return m }
        return timeSeriesDurationMinutes
    }

    /// Исторический геттер: пытаемся найти «длительность» по любым ключам / start-end / timeSeries.
    var durationMinutesInt: Int? {
        // 1) Минуты напрямую (ищем на любом уровне)
        if let d = __findInt(keys: [
            "durationMinutes","duration_min","totalMinutes","total_min",
            "minutes","mins","time_total_minutes","workout_time_minutes"
        ]) { return d }

        // 2) Секунды/миллисекунды
        if let s = __findInt(keys: ["durationSeconds","totalSeconds","seconds","sec"]) {
            return Int((Double(s) / 60.0).rounded(.down))
        }
        if let ms = __findInt(keys: ["durationMillis","durationMs","totalMillis","total_ms","milliseconds"]) {
            return Int((Double(ms) / 60000.0).rounded(.down))
        }

        // 3) Текст "HH:mm" / "H:mm:ss" / "105 мин"
        if let s = __findString(keys: ["durationText","durationString","timeText","totalTimeText","duration_label"]),
           let v = __parseDurationString(s) {
            return v
        }

        // 4) Start / End
        if let start = __findDate(keys: ["startTime","startDate","begin","from"]),
           let end   = __findDate(keys: ["endTime","endDate","finish","to"]) {
            let mins = Int(end.timeIntervalSince(start) / 60.0)
            if mins > 0 { return mins }
        }

        // 5) Любой временной ряд → Δt секунд → минуты
        if let sec = __anyTimeSeriesDeltaSeconds() {
            return Int(sec / 60.0)
        }
        return nil
    }

    /// Текущий слой
    var currentLayerCheckedInt: Int? {
        if let v = __findInt(keys: ["currentLayerChecked","currentLayer","layer_checked","layer","layerIndex","layer_now"]) {
            return v
        }
        return __lookupIntOnSelf(keys: ["currentLayerChecked","currentLayer","layer","layerIndex"])
    }

    /// Текущий подслой
    var currentSubLayerCheckedInt: Int? {
        if let v = __findInt(keys: ["currentsubLayerChecked","currentSubLayerChecked","subLayer","sub_layer","sublayer","subLayerIndex","sublayer_now"]) {
            return v
        }
        return __lookupIntOnSelf(keys: ["currentsubLayerChecked","currentSubLayerChecked","subLayer","sub_layer"])
    }

    /// Прогресс подслоя "6/7"
    var subLayerProgressText: String? {
        if let s = __findString(keys: ["subLayerProgress","sub_layer_progress","progress_subLayer","subLayerText"]) { return s }
        let done  = __findInt(keys: ["currentsubLayerChecked","currentSubLayerChecked","subLayerDone","sublayer_done","sub_layer_done"])
        let total = __findInt(keys: ["subLayerTotal","totalSubLayers","sublayers_total","sub_layers_total"])
        if let d = done, let t = total, t > 0 { return "\(d)/\(t)" }
        return nil
    }

    // MARK: - Published access
    fileprivate func __readPublishedAny(labelContains: String) -> Any? {
        let mirror = Mirror(reflecting: self)
        return mirror.children.first(where: { ($0.label ?? "").contains(labelContains) })?.value
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
    fileprivate func __searchJSON(_ any: Any, keyMatches: (String) -> Bool, depth: Int = 0) -> Any? {
        if depth > 8 { return nil }
        let m = Mirror(reflecting: any)
        switch m.displayStyle {
        case .dictionary:
            for child in m.children {
                let pair = Mirror(reflecting: child.value).children.map { $0.value }
                if pair.count == 2 {
                    if let k = pair[0] as? String, keyMatches(k) { return __unwrapJSONEnum(pair[1]) }
                    if let found = __searchJSON(pair[1], keyMatches: keyMatches, depth: depth + 1) { return found }
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
    fileprivate func __anyTimeSeriesDeltaSeconds() -> Double? {
        func delta(from any: Any) -> Double? {
            if let dates = any as? [Date], dates.count >= 2 { return dates.last!.timeIntervalSince(dates.first!) }
            if let doubles = any as? [Double], doubles.count >= 2 { return max(0, doubles.last! - doubles.first!) }
            if let ints = any as? [Int],     ints.count >= 2 { return max(0, Double(ints.last! - ints.first!)) }
            if let nums = any as? [NSNumber], nums.count >= 2 { return max(0, nums.last!.doubleValue - nums.first!.doubleValue) }
            return nil
        }
        let candidateKeys = ["timeSeries","timestamps","times","time","x","samples_time"]
        for key in candidateKeys {
            if let any = __findValue(for: [key]), let d = delta(from: any) { return d }
        }
        return nil
    }

    // MARK: - Duration string parser
    fileprivate func __parseDurationString(_ s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = trimmed.split(separator: ":")
        if parts.count == 2 || parts.count == 3 {
            let nums = parts.compactMap { Int($0) }
            if nums.count == parts.count {
                if nums.count == 2 { return nums[0] }      // mm:ss
                else { return nums[0] * 60 + nums[1] }     // hh:mm:ss
            }
        }
        if let number = Int(trimmed.filter("0123456789".contains)) { return number }
        return nil
    }

    // MARK: - форматтеры
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
