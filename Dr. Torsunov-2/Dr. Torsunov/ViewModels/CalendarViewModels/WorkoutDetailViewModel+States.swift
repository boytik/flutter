import Foundation

// MARK: - Model for state line segments (как во Flutter)
public struct StateTransition: Hashable {
    public let stateKey: String      // "1".."5" (или строковый ключ состояния)
    public let timeSeconds: Double   // сек от старта
    public let isFirstLayer: Bool    // первый маркер слоя (для подписи/вертикали)
}

extension WorkoutDetailViewModel {

    // MARK: - Утилиты локально для этого файла (не конфликтуют с fileprivate из других файлов)

    /// Преобразование нашего JSONValue → Foundation Any.
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

    /// Рекурсивный поиск значения по ключам (без учёта регистра) в metrics/metadata.
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

    private func __states_findInt(keys: [String]) -> Int? {
        if let d = __states_findDouble(keys: keys) { return Int(d) }
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

    // MARK: - Публичные свойства, которые дергают графики

    /// Общая длительность тренировки (сек). Используем те же эвристики, что во Flutter.
    public var totalDurationSeconds: Double? {
        // 1) явные секунды
        if let s = __states_findDouble(keys: ["totalSeconds","durationSeconds","duration_sec","seconds_total"]) {
            if s > 0 { return s }
        }
        // 2) миллисекунды
        if let ms = __states_findDouble(keys: ["totalMs","durationMs","milliseconds","duration_in_ms"]) {
            let s = ms / 1000.0
            if s > 0 { return s }
        }
        // 3) минуты
        if let m = __states_findDouble(keys: ["totalMinutes","durationMinutes","duration_min","minutes_total"]) {
            let s = m * 60.0
            if s > 0 { return s }
        }
        // 4) по старту/финишу
        if let start = __states_findDate(keys: ["startTime","startDate","begin","from","started_at"]),
           let end   = __states_findDate(keys:   ["endTime","endDate","finish","to","ended_at"]) {
            let s = end.timeIntervalSince(start)
            if s > 0 { return s }
        }
        // 5) по timeSeries (минуты) — берём последний offset
        if let ts = __states_findValue(keys: ["timeSeries","time_series","times","timeline"]) as? [Any] {
            let last = ts.compactMap { (x: Any) -> Double? in
                if let d = x as? Double { return d }
                if let i = x as? Int    { return Double(i) }
                if let s = x as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
                return nil
            }.last
            if let m = last, m > 0 { return m * 60.0 }
        }
        return nil
    }

    /// Переходы состояний (слоёв) во времени от старта (сек), как во Flutter.
    public var stateTransitions: [StateTransition] {
        guard let rawStates = __states_findValue(keys: ["states","layers","stateTimeline","state_timeline","zones"]) else {
            return []
        }

        func normalizedTimeSec(_ any: Any) -> Double? {
            if let d = any as? Double {
                // Heuristics: значения в Flutter обычно в минутах; если явно большие — секунды/мс.
                if d > 12*3600 { return d / 1000.0 } // похоже на миллисекунды
                if d > 360.0   { return d }          // уже в секундах (более 6 минут)
                return d * 60.0                      // иначе трактуем как минуты
            }
            if let i = any as? Int { return normalizedTimeSec(Double(i)) }
            if let s = any as? String, let d = Double(s.replacingOccurrences(of: ",", with: ".")) { return normalizedTimeSec(d) }
            if let n = any as? NSNumber { return normalizedTimeSec(n.doubleValue) }
            return nil
        }

        var result: [StateTransition] = []

        // Вариант A: словарь "state" -> [times]
        if let dict = rawStates as? [String: Any] {
            var treatedAsA = true
            // если ключи похожи на числа — это другой формат (В), ниже
            for (k, v) in dict {
                if Double(k) != nil { treatedAsA = false; break }
                // массив времен
                if let arr = v as? [Any] {
                    for (idx, tAny) in arr.enumerated() {
                        if let t = normalizedTimeSec(tAny) {
                            let isFirst = (idx == 0)
                            result.append(StateTransition(stateKey: k, timeSeconds: t, isFirstLayer: isFirst))
                        }
                    }
                } else if let one = normalizedTimeSec(v) {
                    result.append(StateTransition(stateKey: k, timeSeconds: one, isFirstLayer: true))
                }
            }
            if treatedAsA == false {
                // Вариант B: словарь "time" -> {state: "..."} или {<state>: true}
                for (k, v) in dict {
                    guard let t = normalizedTimeSec(k) else { continue }
                    if let obj = v as? [String: Any] {
                        if let state = obj["state"] as? String {
                            result.append(StateTransition(stateKey: state, timeSeconds: t, isFirstLayer: true))
                        } else {
                            // ищем первый ключ с true
                            if let (state, flag) = obj.first(where: { ($0.value as? Bool) == true }) {
                                result.append(StateTransition(stateKey: state, timeSeconds: t, isFirstLayer: true))
                            }
                        }
                    } else if let s = v as? String {
                        result.append(StateTransition(stateKey: s, timeSeconds: t, isFirstLayer: true))
                    }
                }
            }
        }
        // Вариант C: массив объектов [{state:"..", t: 12.0}, ...]
        else if let arr = rawStates as? [Any] {
            for item in arr {
                if let obj = item as? [String: Any] {
                    let s = (obj["state"] as? String)
                         ?? (obj["name"] as? String)
                         ?? (obj["key"] as? String)
                    let t = normalizedTimeSec(obj["t"] ?? obj["time"] ?? obj["offset"] ?? obj["seconds"] ?? obj["min"])
                    if let s = s, let t = t {
                        result.append(StateTransition(stateKey: s, timeSeconds: t, isFirstLayer: true))
                    }
                }
            }
        }

        // Отсортируем и проставим isFirstLayer при первой встрече состояния
        result.sort { $0.timeSeconds < $1.timeSeconds }
        var seen: Set<String> = []
        result = result.enumerated().map { (i, tr) in
            let first = !seen.contains(tr.stateKey)
            if first { seen.insert(tr.stateKey) }
            return StateTransition(stateKey: tr.stateKey, timeSeconds: tr.timeSeconds, isFirstLayer: first)
        }

        // Отрежем за пределами общей длительности, если она известна
        if let total = totalDurationSeconds, total > 0 {
            result = result.filter { $0.timeSeconds <= total + 1 }
        }

        return result
    }
}
