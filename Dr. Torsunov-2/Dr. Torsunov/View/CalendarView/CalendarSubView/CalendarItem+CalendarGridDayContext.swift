import SwiftUI

// MARK: - CalendarItem -> CalendarGridDayContext

extension CalendarItem: CalendarGridDayContext {
    public var workoutTypeKey: String {
        // Приводим имя к простому ключу типа (как во Flutter-мэппинге цветов)
        let s = name.lowercased()
        if s.contains("swim") || s.contains("water") || s.contains("вода") { return "swim" }
        if s.contains("run")  || s.contains("walk") || s.contains("бег") || s.contains("ходь") { return "run" }
        if s.contains("bike") || s.contains("velo") || s.contains("велотр") || s.contains("велос") { return "bike" }
        if s.contains("yoga") || s.contains("йога") { return "yoga" }
        if s.contains("sauna") || s.contains("баня") { return "sauna" }
        if s.contains("strength") || s.contains("силов") { return "strength" }
        return "other"
    }

    public var plannedLayers: Int {
        switch self {
        case .workout(let w):
            // Пытаемся достать слои, если в модели они есть.
            // Это 100% безопасно: через Mirror, без крашей.
            if let v = Mirror.lookupInt(w, keys: ["layers", "plannedLayers"]) {
                return max(1, v)
            }
            if let arrCount = Mirror.lookupArrayCount(w, keys: ["swimLayers", "layersArray"]) {
                return max(1, arrCount)
            }
            return 1
        case .activity:
            return 1
        }
    }

    public var doneLayers: Int? {
        switch self {
        case .workout(let w):
            if let v = Mirror.lookupInt(w, keys: ["doneLayers", "completedLayers", "performedLayers"]) {
                return max(0, v)
            }
            return nil
        case .activity(let a):
            // Если в активности хранится выполненное кол-во, попробуем вытащить
            if let v = Mirror.lookupInt(a, keys: ["doneLayers", "completedLayers"]) {
                return max(0, v)
            }
            return nil
        }
    }

    public var isPlanned: Bool {
        switch self {
        case .workout:
            return true
        case .activity:
            // Активность — это уже факт выполнения, не план
            return false
        }
    }

    public var isDone: Bool {
        switch self {
        case .workout(let w):
            // Пытаемся найти булево поле статуса
            if let b = Mirror.lookupBool(w, keys: ["isDone", "isCompleted", "completed", "done"]) {
                return b
            }
            // Если число выполненных слоев равно плану — считаем выполнено
            if let d = doneLayers, d >= plannedLayers { return true }
            return false
        case .activity:
            // Активность трактуем как выполненную отметку дня
            return true
        }
    }
}

// MARK: - Хелперы через Mirror (безопасные попытки достать поля, если они есть)

private extension Mirror {
    static func lookupInt(_ any: Any, keys: [String]) -> Int? {
        let m = Mirror(reflecting: any)
        for child in m.children {
            guard let label = child.label?.lowercased() else { continue }
            if keys.contains(where: { label.contains($0.lowercased()) }) {
                if let v = child.value as? Int { return v }
                if let v = child.value as? Int32 { return Int(v) }
                if let v = child.value as? Int64 { return Int(v) }
                if let s = child.value as? String, let v = Int(s) { return v }
            }
        }
        return nil
    }

    static func lookupArrayCount(_ any: Any, keys: [String]) -> Int? {
        let m = Mirror(reflecting: any)
        for child in m.children {
            guard let label = child.label?.lowercased() else { continue }
            if keys.contains(where: { label.contains($0.lowercased()) }) {
                if let arr = child.value as? [Any] {
                    return arr.count
                }
            }
        }
        return nil
    }

    static func lookupBool(_ any: Any, keys: [String]) -> Bool? {
        let m = Mirror(reflecting: any)
        for child in m.children {
            guard let label = child.label?.lowercased() else { continue }
            if keys.contains(where: { label.contains($0.lowercased()) }) {
                if let v = child.value as? Bool { return v }
                if let s = child.value as? String {
                    let l = s.lowercased()
                    if ["true","yes","1","done","completed"].contains(l) { return true }
                    if ["false","no","0","planned","pending"].contains(l) { return false }
                }
            }
        }
        return nil
    }
}

// MARK: - Утилита для сетки: собрать элементы дня

/// Вернёт элементы, относящиеся к `date`, приведённые к `CalendarGridDayContext`.
/// Просто передайте это в `CalendarGridMarkersLayer(items: ...)`.
 func calendarItemsForDate(_ date: Date, from all: [CalendarItem]) -> [CalendarGridDayContext] {
    let cal = Calendar.current
    return all.filter { cal.isDate($0.date, inSameDayAs: date) }
}
