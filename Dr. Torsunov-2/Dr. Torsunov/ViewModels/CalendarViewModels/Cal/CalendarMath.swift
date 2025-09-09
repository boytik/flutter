
import Foundation
import OSLog

fileprivate let mathLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "CalMath")

enum CalendarMath {
    static var iso: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.locale = .current
        c.firstWeekday = 2
        return c
    }

    static func visibleGridRange(for monthDate: Date) -> (Date, Date) {
        let cal = iso
        mathLog.info("visibleGridRange(in): monthDate=\(DateUtils.ymd.string(from: monthDate), privacy: .public) fw=\(cal.firstWeekday, privacy: .public)")

        guard let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)),
              let endOfMonth = cal.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) else {
            mathLog.error("visibleGridRange: failed to compute start/end of month")
            return (monthDate, monthDate)
        }

        let weekdayStart = cal.component(.weekday, from: startOfMonth)
        let leading = (weekdayStart - cal.firstWeekday + 7) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -leading, to: startOfMonth) else {
            mathLog.error("visibleGridRange: failed to compute gridStart")
            return (startOfMonth, endOfMonth)
        }

        let weekdayEnd = cal.component(.weekday, from: endOfMonth)
        let trailing = (7 - ((weekdayEnd - cal.firstWeekday + 7) % 7) - 1 + 7) % 7
        guard let gridEnd = cal.date(byAdding: .day, value: trailing, to: endOfMonth) else {
            mathLog.error("visibleGridRange: failed to compute gridEnd")
            return (gridStart, endOfMonth)
        }

        let daysCount = (cal.dateComponents([.day], from: cal.startOfDay(for: gridStart), to: cal.startOfDay(for: gridEnd)).day ?? -1) + 1
        mathLog.info("visibleGridRange(out): start=\(DateUtils.ymd.string(from: gridStart), privacy: .public) end=\(DateUtils.ymd.string(from: gridEnd), privacy: .public) days=\(daysCount, privacy: .public) leading=\(leading, privacy: .public) trailing=\(trailing, privacy: .public)")

        return (gridStart, gridEnd)
    }

    static func daysArray(from start: Date, to end: Date) -> [Date] {
        let cal = iso
        let s = cal.startOfDay(for: start)
        let e = cal.startOfDay(for: end)
        if e < s {
            mathLog.error("daysArray: end < start (start=\(DateUtils.ymd.string(from: s), privacy: .public), end=\(DateUtils.ymd.string(from: e), privacy: .public))")
            return []
        }

        var res: [Date] = []
        var d = s
        let last = e
        while d <= last {
            res.append(d)
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else {
                mathLog.error("daysArray: failed to add day to \(DateUtils.ymd.string(from: d), privacy: .public)")
                break
            }
            d = next
        }
        mathLog.info("daysArray: start=\(DateUtils.ymd.string(from: s), privacy: .public) end=\(DateUtils.ymd.string(from: e), privacy: .public) count=\(res.count, privacy: .public)")
        return res
    }
}
