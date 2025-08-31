import SwiftUI

// --- Fallback мэппинг по названию, если нет тип-ключа
private func inferTypeKey(fromName name: String?) -> String {
    let s = (name ?? "").lowercased()
    if s.contains("yoga") || s.contains("йога") { return "yoga" }
    if s.contains("run")  || s.contains("walk") || s.contains("бег") || s.contains("ход") { return "run" }
    if s.contains("swim") || s.contains("water") || s.contains("плав") || s.contains("вода") { return "swim" }
    if s.contains("bike") || s.contains("cycl")  || s.contains("velo") || s.contains("вел") { return "bike" }
    return "other"
}

// ВАЖНО: именно это место определяет тип/слои/статусы для клеток календаря
extension CalendarItem: CalendarGridDayContext {

    public var workoutTypeKey: String {
        switch self {
        case .workout(let w):
            if let t = w.activityType, !t.isEmpty {
                return t.lowercased()
            }
            return inferTypeKey(fromName: w.name)

        case .activity(let a):
            return inferTypeKey(fromName: a.name)
        }
    }

    // Кол-во «ярких» точек у плановой тренировки: для воды — по числу подпланов, иначе — по plannedLayers.
    public var plannedLayers: Int {
        switch self {
        case .workout(let w):
            let type = (w.activityType ?? "").lowercased()
            if (type.contains("swim") || type.contains("water")), let arr = w.swimLayers, !arr.isEmpty {
                return max(1, min(5, arr.count))
            }
            if let l = w.plannedLayers { return max(1, min(5, l)) }
            return 1
        case .activity:
            return 0
        }
    }

    public var doneLayers: Int? { nil }

    public var isPlanned: Bool {
        if case .workout = self { return true }
        return false
    }

    public var isDone: Bool {
        if case let .activity(a) = self { return a.isCompleted }
        return false
    }
}
