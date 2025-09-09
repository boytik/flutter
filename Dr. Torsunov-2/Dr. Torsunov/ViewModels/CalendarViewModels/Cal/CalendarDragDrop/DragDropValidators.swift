
import Foundation
import OSLog

// MARK: - ActivityKind / Violations

enum ActivityKind: String {
    case run = "run"        // бег/ходьба
    case sauna = "sauna"
    case post = "post"      // пост/fasting
    case water = "water"    // вода/плавание
    case yoga = "yoga"
    case other = "other"
}

fileprivate let dragLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "DragDrop")

enum DropRuleViolation: LocalizedError, Equatable {
    case differentWeek
    case duplicateType(kind: ActivityKind)
    case incompatibleSameDay(drag: ActivityKind, existing: Set<ActivityKind>)
    case saunaBeforeRun
    case runAfterSauna
    case postBeforeRun
    case postAfterSauna

    var errorDescription: String? {
        switch self {
        case .differentWeek:
            return "Можно переносить только в пределах одной недели."
        case .duplicateType(let kind):
            return "В день уже есть тренировка типа \(pretty(kind))."
        case .incompatibleSameDay(let drag, let existing):
            return "Нельзя совмещать \(pretty(drag)) с: \(existing.map(pretty).joined(separator: ", "))."
        case .saunaBeforeRun:
            return "Баня не может быть накануне бега."
        case .runAfterSauna:
            return "Бег не может быть на следующий день после бани."
        case .postBeforeRun:
            return "Пост не может быть накануне бега."
        case .postAfterSauna:
            return "Пост не может быть на следующий день после бани."
        }
    }

    private func pretty(_ k: ActivityKind) -> String {
        switch k {
        case .run:   return "Бег/Ходьба"
        case .sauna: return "Баня"
        case .post:  return "Пост"
        case .water: return "Вода"
        case .yoga:  return "Йога"
        case .other: return "Другое"
        }
    }
}

// MARK: - Validators

enum DragDropValidators {
    static func normalize(_ raw: String?) -> ActivityKind {
        let s = (raw ?? "").lowercased()
        let kind: ActivityKind
        if s.contains("run") || s.contains("walk") || s.contains("бег") || s.contains("ход") { kind = .run }
        else if s.contains("sauna") || s.contains("баня") || s.contains("хаммам") { kind = .sauna }
        else if s.contains("post") || s.contains("fast") || s.contains("пост") || s.contains("голод") { kind = .post }
        else if s.contains("water") || s.contains("swim") || s.contains("плав") || s.contains("вода") { kind = .water }
        else if s.contains("yoga") || s.contains("йога") { kind = .yoga }
        else { kind = .other }
        dragLog.debug("normalize(raw): '\(s, privacy: .public)' -> \(kind.rawValue, privacy: .public)")
        return kind
    }

    static func normalize(workout: Workout) -> ActivityKind {
        let result: ActivityKind
        if let t = workout.activityType, !t.isEmpty { result = normalize(t) }
        else if !workout.name.isEmpty { result = normalize(workout.name) }
        else { result = normalize(workout.description) }
        dragLog.debug("normalize(workout): id=\(workout.id, privacy: .public) name=\(workout.name, privacy: .public) -> \(result.rawValue, privacy: .public)")
        return result
    }

    private static func isSameISOWeek(_ a: Date, _ b: Date) -> Bool {
        let cal = CalendarMath.iso
        return cal.component(.weekOfYear, from: a) == cal.component(.weekOfYear, from: b)
            && cal.component(.yearForWeekOfYear, from: a) == cal.component(.yearForWeekOfYear, from: b)
    }

    @discardableResult
    static func validateDropSingle(drag: Workout, targetDate: Date, targetDayWorkouts: [Workout], monthPlanned: [Workout]) -> Result<Void, DropRuleViolation> {
        let kind = normalize(workout: drag)
        dragLog.info("validateSingle: id=\(drag.id, privacy: .public) kind=\(kind.rawValue, privacy: .public) target=\(DateUtils.ymd.string(from: targetDate), privacy: .public)")

        guard isSameISOWeek(drag.date, targetDate) else {
            dragLog.error("❌ differentWeek id=\(drag.id, privacy: .public)")
            return .failure(.differentWeek)
        }

        let existingKinds: Set<ActivityKind> = Set(targetDayWorkouts.map { normalize(workout: $0) })
        if existingKinds.contains(kind) {
            dragLog.error("❌ duplicateType id=\(drag.id, privacy: .public) kind=\(kind.rawValue, privacy: .public) targetKinds=\(existingKinds.map{$0.rawValue}.joined(separator: ", "), privacy: .public)")
            return .failure(.duplicateType(kind: kind))
        }

        if (kind == .run || kind == .sauna || kind == .post) &&
            (existingKinds.contains(.run) || existingKinds.contains(.sauna) || existingKinds.contains(.post)) {
            let clash = existingKinds.intersection([.run, .sauna, .post]).map{$0.rawValue}.joined(separator: ", ")
            dragLog.error("❌ incompatibleSameDay id=\(drag.id, privacy: .public) drag=\(kind.rawValue, privacy: .public) with=\(clash, privacy: .public)")
            return .failure(.incompatibleSameDay(drag: kind, existing: existingKinds.intersection([.run, .sauna, .post])))
        }

        let cal = CalendarMath.iso
        let prevDay = cal.date(byAdding: .day, value: -1, to: targetDate)!
        let nextDay = cal.date(byAdding: .day, value: 1, to: targetDate)!

        let prevKinds: Set<ActivityKind> = Set(monthPlanned
            .filter { cal.isDate($0.date, inSameDayAs: prevDay) }
            .map { normalize(workout: $0) })

        let nextKinds: Set<ActivityKind> = Set(monthPlanned
            .filter { cal.isDate($0.date, inSameDayAs: nextDay) }
            .map { normalize(workout: $0) })

        dragLog.debug("neighbors: prev=\(prevKinds.map{$0.rawValue}.joined(separator: ", "), privacy: .public) next=\(nextKinds.map{$0.rawValue}.joined(separator: ", "), privacy: .public)")

        switch kind {
        case .sauna:
            if nextKinds.contains(.run) {
                dragLog.error("❌ saunaBeforeRun id=\(drag.id, privacy: .public)")
                return .failure(.saunaBeforeRun)
            }
        case .run:
            if prevKinds.contains(.sauna) {
                dragLog.error("❌ runAfterSauna id=\(drag.id, privacy: .public)")
                return .failure(.runAfterSauna)
            }
        case .post:
            if nextKinds.contains(.run) {
                dragLog.error("❌ postBeforeRun id=\(drag.id, privacy: .public)")
                return .failure(.postBeforeRun)
            }
            if prevKinds.contains(.sauna) {
                dragLog.error("❌ postAfterSauna id=\(drag.id, privacy: .public)")
                return .failure(.postAfterSauna)
            }
        default: break
        }

        dragLog.info("✅ validateSingle passed id=\(drag.id, privacy: .public)")
        return .success(())
    }

    static func validateDropListData(targetDate: Date, targetDayWorkouts: [Workout], dragged: [Workout], monthPlanned: [Workout]) -> (allowedIDs: [String], firstError: DropRuleViolation?) {
        let dragIDs = dragged.map { $0.id }
        dragLog.info("validateList: target=\(DateUtils.ymd.string(from: targetDate), privacy: .public) dragged=\(dragIDs.joined(separator: ", "), privacy: .public) targetCount=\(targetDayWorkouts.count, privacy: .public) allMonth=\(monthPlanned.count, privacy: .public)")

        var ok: [String] = []
        var firstErr: DropRuleViolation? = nil

        for w in dragged {
            switch validateDropSingle(drag: w, targetDate: targetDate, targetDayWorkouts: targetDayWorkouts, monthPlanned: monthPlanned) {
            case .success:
                ok.append(w.id)
            case .failure(let err):
                if firstErr == nil { firstErr = err }
            }
        }

        dragLog.info("validateList result: allowed=\(ok.joined(separator: ", "), privacy: .public) firstErr=\(String(describing: firstErr?.localizedDescription ?? "nil"), privacy: .public)")
        return (ok, firstErr)
    }
}
