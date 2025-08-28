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

// ВАЖНО: именно это место определяет цвет/тип для planned и done в клетках календаря
extension CalendarItem: CalendarGridDayContext {

    public var workoutTypeKey: String {
        switch self {
        case .workout(let w):
            // 1) приоритет — явный тип из бэка (протянутый в Workout.activityType)
            if let t = w.activityType, !t.isEmpty {
                return t.lowercased()
            }
            // 2) fallback — пытаемся вывести по имени
            return inferTypeKey(fromName: w.name)

        case .activity(let a):
            // факты выполнения обычно имеют осмысленное name ("Yoga"/"Run"/"Swim")
            return inferTypeKey(fromName: a.name)
        }
    }

    public var plannedLayers: Int { 1 }
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
