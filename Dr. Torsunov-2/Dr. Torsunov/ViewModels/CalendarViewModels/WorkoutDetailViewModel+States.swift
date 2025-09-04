import Foundation

// MARK: - Model for state line segments (как во Flutter)
public struct StateTransition: Hashable {
    public let stateKey: String      // "1".."5" (или строковый ключ состояния/слоя)
    public let timeSeconds: Double   // сек от старта
    public let isFirstLayer: Bool    // первый маркер слоя (для подписи/вертикали)
}

extension WorkoutDetailViewModel {

    // === Вспомогательные утилиты для поиска значений в metrics/metadata ===

    private func __toAny(_ v: JSONValue) -> Any {
        switch v {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b):   return b
        case .array(let arr): return arr.map { __toAny($0) }
        case .object(let obj):
            var out: [String: Any] = [:]
            for (k, vv) in obj { out[k] = __toAny(vv) }
            return out
        case .null: return NSNull()
        }
    }

    private var __metricsAny_forStates: Any?  { metrics.isEmpty ? nil : metrics.mapValues { __toAny($0) } }
    private var __metadataAny_forStates: Any? { metadata.isEmpty ? nil : metadata.mapValues { __toAny($0) } }

    private func __states_findValue(keys: [String]) -> Any? {
        let wanted = keys.map { $0.lowercased() }
        func search(_ any: Any, depth: Int = 0) -> Any? {
            if depth > 10 { return nil }
            if let d = any as? [String: Any] {
                for (k, v) in d {
                    if wanted.contains(k.lowercased()) { return v }
                    if let found = search(v, depth: depth + 1) { return found }
                }
                return nil
            }
            if let arr = any as? [Any] {
                for el in arr {
                    if let found = search(el, depth: depth + 1) { return found }
                }
                return nil
            }
            return nil
        }
        if let m = __metricsAny_forStates, let v = search(m) { return v }
        if let m = __metadataAny_forStates, let v = search(m) { return v }
        return nil
    }

    private func __states_findDouble(keys: [String]) -> Double? {
        guard let any = __states_findValue(keys: keys) else { return nil }
        if let x = any as? Double { return x }
        if let x = any as? Float  { return Double(x) }
        if let x = any as? Int    { return Double(x) }
        if let x = any as? NSNumber { return x.doubleValue }
        if let s = any as? String {
            if let d = Double(s.replacingOccurrences(of: ",", with: ".")) { return d }
        }
        return nil
    }

    private func __states_findDate(keys: [String]) -> Date? {
        guard let any = __states_findValue(keys: keys) else { return nil }
        if let d = any as? Date { return d }
        if let s = any as? String {
            let iso = ISO8601DateFormatter()
            if let d = iso.date(from: s) { return d }
            if let t = Double(s.replacingOccurrences(of: ",", with: ".")) {
                let sec = t > 10_000_000_000 ? (t/1000.0) : t
                return Date(timeIntervalSince1970: sec)
            }
        }
        if let n = any as? NSNumber {
            let t = n.doubleValue
            let sec = t > 10_000_000_000 ? (t/1000.0) : t
            return Date(timeIntervalSince1970: sec)
        }
        if let t = any as? Double {
            let sec = t > 10_000_000_000 ? (t/1000.0) : t
            return Date(timeIntervalSince1970: sec)
        }
        if let t = any as? Int {
            let sec = Double(t) > 10_000_000_000 ? (Double(t)/1000.0) : Double(t)
            return Date(timeIntervalSince1970: sec)
        }
        return nil
    }

    // Нормализация значения времени (мин/сек/мс → сек)
    private func __normalizeToSeconds(_ any: Any) -> Double? {
        func norm(_ d: Double) -> Double {
            if d > 12 * 3600 { return d / 1000.0 } // похоже на миллисекунды
            if d > 360.0     { return d }          // секунды
            return d * 60.0                         // минуты
        }
        if let d = any as? Double { return norm(d) }
        if let i = any as? Int    { return norm(Double(i)) }
        if let n = any as? NSNumber { return norm(n.doubleValue) }
        if let s = any as? String, let d = Double(s.replacingOccurrences(of: ",", with: ".")) { return norm(d) }
        return nil
    }

    // Общая длительность (сек) — с корректной нормализацией
    public var totalDurationSeconds: Double? {
        if let s = __states_findDouble(keys: ["totalSeconds","durationSeconds","duration_sec","seconds_total"]), s > 0 { return s }
        if let ms = __states_findDouble(keys: ["totalMs","durationMs","milliseconds","duration_in_ms"]), (ms/1000.0) > 0 { return ms / 1000.0 }
        if let m = __states_findDouble(keys: ["totalMinutes","durationMinutes","duration_min","minutes_total"]), (m*60.0) > 0 { return m * 60.0 }
        if let start = __states_findDate(keys: ["startTime","startDate","begin","from","started_at"]),
           let end   = __states_findDate(keys: ["endTime","endDate","finish","to","ended_at"]) {
            let s = end.timeIntervalSince(start); if s > 0 { return s }
        }
        if let ts = __states_findValue(keys: ["timeSeries","time_series","times","timeline"]) as? [Any] {
            if let lastSec = ts.compactMap({ __normalizeToSeconds($0) }).last, lastSec > 0 {
                return lastSec
            }
        }
        return nil
    }

    /// Переходы СЛОЁВ (без подслоёв) во времени от старта (сек) — как во Flutter.
    /// - Важно: учитываем смену только `layer`, подслои игнорируем;
    /// - Антидребезг: смена слоя фиксируется, только если подтвердилась на следующей валидной точке,
    ///   либо если это последняя точка (финальный слой).
    public var stateTransitions: [StateTransition] {

        // ----------- Варианты A/B/C: готовые таймлайны из данных -----------
        if let rawStates = __states_findValue(keys: ["states","layers","stateTimeline","state_timeline","zones"]) {

            var result: [StateTransition] = []

            if let dict = rawStates as? [String: Any] {
                var treatedAsA = true
                for (k, v) in dict {
                    if Double(k) != nil { treatedAsA = false; break }
                    if let arr = v as? [Any] {
                        for (idx, tv) in arr.enumerated() {
                            if let t = __normalizeToSeconds(tv) {
                                result.append(StateTransition(stateKey: k, timeSeconds: t, isFirstLayer: idx == 0))
                            }
                        }
                    } else if let one = __normalizeToSeconds(v) {
                        result.append(StateTransition(stateKey: k, timeSeconds: one, isFirstLayer: true))
                    }
                }
                if treatedAsA == false {
                    for (k, v) in dict {
                        guard let t = __normalizeToSeconds(k) else { continue }
                        if let obj = v as? [String: Any] {
                            if let state = obj["state"] as? String {
                                result.append(StateTransition(stateKey: state, timeSeconds: t, isFirstLayer: true))
                            } else if let (state, flag) = obj.first(where: { ($0.value as? Bool) == true }) {
                                _ = flag
                                result.append(StateTransition(stateKey: state, timeSeconds: t, isFirstLayer: true))
                            }
                        } else if let s = v as? String {
                            result.append(StateTransition(stateKey: s, timeSeconds: t, isFirstLayer: true))
                        }
                    }
                }
            } else if let arr = rawStates as? [Any] {
                for item in arr {
                    if let obj = item as? [String: Any] {
                        let s = (obj["state"] as? String) ?? (obj["name"] as? String) ?? (obj["key"] as? String)
                        let t = (obj["t"] ?? obj["time"] ?? obj["offset"] ?? obj["seconds"] ?? obj["min"]).flatMap { __normalizeToSeconds($0) }
                        if let s = s, let t = t {
                            result.append(StateTransition(stateKey: s, timeSeconds: t, isFirstLayer: true))
                        }
                    }
                }
            }

            result.sort { $0.timeSeconds < $1.timeSeconds }
            var seen: Set<String> = []
            result = result.map { tr in
                let first = !seen.contains(tr.stateKey)
                if first { seen.insert(tr.stateKey) }
                return StateTransition(stateKey: tr.stateKey, timeSeconds: tr.timeSeconds, isFirstLayer: first)
            }

            if let total = totalDurationSeconds, total > 0 {
                result = result.filter { $0.timeSeconds <= total + 1 }
            }
            if !result.isEmpty { return result }
        }

        // ----------- ФОЛБЭК: строим из metricObjectsArray (слои без подслоёв) -----------
        guard let rows = self.metricObjectsArray, !rows.isEmpty else { return [] }

        let tKeys     = ["time_numeric","timeNumeric","time","t","seconds","secs","minutes","mins"]
        let layerKeys = ["currentLayerChecked","currentLayer","layer_checked","layer","layerIndex","layer_now","stage","phase"]
        let subKeys   = ["currentsubLayerChecked","currentSubLayerChecked","subLayer","sub_layer","sublayer","subLayerIndex","sublayer_now","subStage","subPhase"]

        struct RowPoint { let t: Double; let layer: Int?; let sub: Int? }
        var points: [RowPoint] = []
        points.reserveCapacity(rows.count)

        for row in rows {
            guard let tv = self.value(for: tKeys, in: row), let tRaw = self.number(in: tv),
                  let tSec = __normalizeToSeconds(tRaw) else { continue }
            var L: Int? = nil, S: Int? = nil
            if let lv = self.value(for: layerKeys, in: row), let l = self.number(in: lv) {
                L = Int(l.rounded(.towardZero)) // ТОЛЬКО усечение, как во Flutter
            }
            if let sv = self.value(for: subKeys, in: row), let s = self.number(in: sv) {
                S = Int(s.rounded(.towardZero))
            }
            points.append(.init(t: tSec, layer: L, sub: S))
        }

        guard !points.isEmpty else { return [] }
        points.sort { $0.t < $1.t }

        // --- считаем ТОЛЬКО границы СЛОЁВ + простой debounce ---
        var res: [StateTransition] = []
        var seen = Set<String>()

        // первая валидная точка слоя
        var i = 0
        while i < points.count && points[i].layer == nil { i += 1 }
        guard i < points.count, let firstL = points[i].layer else { return [] }

        var currLayer = firstL
        let firstKey = String(currLayer)
        res.append(StateTransition(stateKey: firstKey, timeSeconds: max(0, points[i].t), isFirstLayer: true))
        seen.insert(firstKey)

        func nextValidLayerIndex(from idx: Int) -> Int? {
            var j = idx + 1
            while j < points.count && points[j].layer == nil { j += 1 }
            return j < points.count ? j : nil
        }

        while let j = nextValidLayerIndex(from: i) {
            guard let cand = points[j].layer else { i = j; continue }
            if cand != currLayer {
                // Debounce: подтверждаем, что на следующей валидной точке слой остался cand
                if let k = nextValidLayerIndex(from: j), let confirm = points[k].layer {
                    if confirm == cand {
                        currLayer = cand
                        let key = String(cand)
                        let first = !seen.contains(key)
                        if first { seen.insert(key) }
                        res.append(StateTransition(stateKey: key, timeSeconds: max(0, points[j].t), isFirstLayer: first))
                        i = j
                        continue
                    } else {
                        // дребезг — пропускаем
                        i = j
                        continue
                    }
                } else {
                    // Нет следующей валидной точки (конец ряда): принимаем финальную смену
                    currLayer = cand
                    let key = String(cand)
                    let first = !seen.contains(key)
                    if first { seen.insert(key) }
                    res.append(StateTransition(stateKey: key, timeSeconds: max(0, points[j].t), isFirstLayer: first))
                    i = j
                    continue
                }
            }
            i = j
        }

        if let total = totalDurationSeconds, total > 0 {
            res = res.filter { $0.timeSeconds <= total + 1 }
        }
        res.sort { (a, b) in
            if a.timeSeconds == b.timeSeconds { return a.stateKey < b.stateKey }
            return a.timeSeconds < b.timeSeconds
        }
        return res
    }

    /// Отдельные переходы ПОДСЛОЁВ (не используются во всех UI, но доступны при желании).
    public var subLayerTransitions: [StateTransition] {
        guard let rows = self.metricObjectsArray, !rows.isEmpty else { return [] }
        let tKeys   = ["time_numeric","timeNumeric","time","t","seconds","secs","minutes","mins"]
        let subKeys = ["currentsubLayerChecked","currentSubLayerChecked","subLayer","sub_layer","sublayer","subLayerIndex","sublayer_now","subStage","subPhase"]

        struct P { let t: Double; let s: Int? }
        var pts: [P] = []
        for row in rows {
            guard let tv = self.value(for: tKeys, in: row), let tRaw = self.number(in: tv),
                  let tSec = __normalizeToSeconds(tRaw) else { continue }
            var sub: Int? = nil
            if let sv = self.value(for: subKeys, in: row), let s = self.number(in: sv) {
                sub = Int(s.rounded(.towardZero))
            }
            pts.append(.init(t: tSec, s: sub))
        }
        pts.sort { $0.t < $1.t }
        var out: [StateTransition] = []
        var prev: Int? = nil
        for p in pts {
            guard let s = p.s else { continue }
            if let pp = prev, pp != s {
                out.append(StateTransition(stateKey: "sub-\(s)", timeSeconds: p.t, isFirstLayer: false))
            }
            prev = s
        }
        if let total = totalDurationSeconds, total > 0 {
            out = out.filter { $0.timeSeconds <= total + 1 }
        }
        return out
    }

    /// Старт тренировки (если есть) — удобно для оси Date
    public var workoutStartDate: Date? {
        return __states_findDate(keys: ["startTime","startDate","begin","from","started_at"])
    }
}
