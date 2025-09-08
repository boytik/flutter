import Foundation

enum CalendarMath {
    static var iso: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.locale = .current; c.firstWeekday = 2
        return c
    }

    static func visibleGridRange(for monthDate: Date) -> (Date, Date) {
        let cal = iso
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: monthDate))!
        let endOfMonth = cal.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!

        let weekdayStart = cal.component(.weekday, from: startOfMonth)
        let leading = (weekdayStart - cal.firstWeekday + 7) % 7
        let gridStart = cal.date(byAdding: .day, value: -leading, to: startOfMonth)!

        let weekdayEnd = cal.component(.weekday, from: endOfMonth)
        let trailing = (7 - ((weekdayEnd - cal.firstWeekday + 7) % 7) - 1 + 7) % 7
        let gridEnd = cal.date(byAdding: .day, value: trailing, to: endOfMonth)!

        return (gridStart, gridEnd)
    }

    static func daysArray(from start: Date, to end: Date) -> [Date] {
        var res: [Date] = []
        var d = iso.startOfDay(for: start)
        let last = iso.startOfDay(for: end)
        while d <= last {
            res.append(d)
            d = iso.date(byAdding: .day, value: 1, to: d)!
        }
        return res
    }
}
