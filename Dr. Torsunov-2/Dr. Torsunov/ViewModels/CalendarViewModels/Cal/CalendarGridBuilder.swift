import Foundation
import SwiftUI

enum CalendarGridBuilder {
    static func build(from start: Date, to end: Date, planned: [Workout], done: [Activity]) -> [WorkoutDay] {
        let startDay = CalendarMath.iso.startOfDay(for: start)
        let endDay   = CalendarMath.iso.startOfDay(for: end)

        // Уникализируем плановые внутри дня по цвету
        var plannedColorsByDay: [Date: [Color]] = [:]
        let order: [Color] = [.purple, .orange, .blue, .red, .yellow, .green]
        func sortColors(_ arr: [Color]) -> [Color] {
            arr.sorted { (a, b) in (order.firstIndex(of: a) ?? 99) < (order.firstIndex(of: b) ?? 99) }
        }

        for w in planned {
            let day = CalendarMath.iso.startOfDay(for: w.date)
            let color = CalendarColors.color(for: w)
            var colors = plannedColorsByDay[day] ?? []
            if !colors.contains(color) { colors.append(color) }
            plannedColorsByDay[day] = colors
        }
        for (k, v) in plannedColorsByDay { plannedColorsByDay[k] = Array(v.prefix(6)) }

        let doneDays: Set<Date> = Set(done.compactMap { $0.createdAt.map { CalendarMath.iso.startOfDay(for: $0) } })

        var result: [WorkoutDay] = []
        var d = startDay
        while d <= endDay {
            var colors = plannedColorsByDay[d] ?? []
            colors = sortColors(colors)
            if doneDays.contains(d) {
                if !colors.contains(.green) { colors.append(.green) } // индикатор наличия выполненной активности
            }
            result.append(WorkoutDay(date: d, dots: Array(colors.prefix(6))))
            d = CalendarMath.iso.date(byAdding: .day, value: 1, to: d)!
        }
        return result
    }
}
