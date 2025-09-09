
import Foundation
import SwiftUI
import OSLog

fileprivate let gridLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "CalGrid")

enum CalendarGridBuilder {
    static func build(from start: Date, to end: Date, planned: [Workout], done: [Activity]) -> [WorkoutDay] {
        let startDay = CalendarMath.iso.startOfDay(for: start)
        let endDay   = CalendarMath.iso.startOfDay(for: end)

        gridLog.info("Grid build start: start=\(DateUtils.ymd.string(from: startDay), privacy: .public) end=\(DateUtils.ymd.string(from: endDay), privacy: .public) planned=\(planned.count, privacy: .public) done=\(done.count, privacy: .public)")

        // Уникализируем плановые внутри дня по цвету
        var plannedColorsByDay: [Date: [Color]] = [:]
        let order: [Color] = [.purple, .orange, .blue, .red, .yellow, .green]

        func colorName(_ c: Color) -> String {
            if c == .purple { return "purple" }
            if c == .orange { return "orange" }
            if c == .blue   { return "blue" }
            if c == .red    { return "red" }
            if c == .yellow { return "yellow" }
            if c == .green  { return "green" }
            return "custom"
        }
        func sortColors(_ arr: [Color]) -> [Color] {
            arr.sorted { (a, b) in (order.firstIndex(of: a) ?? 99) < (order.firstIndex(of: b) ?? 99) }
        }

        // Логируем каждую плановую тренировку и её цвет
        for w in planned {
            let day = CalendarMath.iso.startOfDay(for: w.date)
            let color = CalendarColors.color(for: w)
            var colors = plannedColorsByDay[day] ?? []
            if !colors.contains(color) { colors.append(color) }
            plannedColorsByDay[day] = colors

            let type = w.activityType ?? "nil"
//            gridLog.debug("plan add: day=\(DateUtils.ymd.string(from: day), privacy: .public) type=\(type, privacy: .public) name=\(w.name, privacy: .public) color=\(colorName(color), privacy: .public)")
        }

        // Обрезаем до 6 точек и логируем краткую сводку по дням
        for (k, v) in plannedColorsByDay {
            let limited = Array(v.prefix(6))
            plannedColorsByDay[k] = limited
            let names = limited.map { colorName($0) }.joined(separator: ",")
//            gridLog.debug("plannedColorsByDay: \(DateUtils.ymd.string(from: k), privacy: .public) -> [\(names, privacy: .public)]")
        }

        let doneDays: Set<Date> = Set(done.compactMap { $0.createdAt.map { CalendarMath.iso.startOfDay(for: $0) } })
        gridLog.info("done days count=\(doneDays.count, privacy: .public)")

        var result: [WorkoutDay] = []
        var d = startDay
        var dayIndex = 0
        while d <= endDay {
            var colors = plannedColorsByDay[d] ?? []
            let beforeSortNames = colors.map { colorName($0) }.joined(separator: ",")
            colors = sortColors(colors)
            let afterSortNames = colors.map { colorName($0) }.joined(separator: ",")

            var hadDone = false
            if doneDays.contains(d) {
                hadDone = true
                if !colors.contains(.green) { colors.append(.green) } // индикатор наличия выполненной активности
            }

            // Итоговые точки
            let final = Array(colors.prefix(6))
            let finalNames = final.map { colorName($0) }.joined(separator: ",")

//            gridLog.debug("day[\(dayIndex, privacy: .public)] \(DateUtils.ymd.string(from: d), privacy: .public): planned=\(beforeSortNames, privacy: .public) sorted=\(afterSortNames, privacy: .public) hasDone=\(hadDone, privacy: .public) final=\(finalNames, privacy: .public)")

            result.append(WorkoutDay(date: d, dots: final))
            guard let next = CalendarMath.iso.date(byAdding: .day, value: 1, to: d) else {
                gridLog.error("date math failed for day \(DateUtils.ymd.string(from: d), privacy: .public)")
                break
            }
            d = next
            dayIndex += 1
        }
        gridLog.info("Grid build finished: days=\(result.count, privacy: .public)")
        return result
    }
}
