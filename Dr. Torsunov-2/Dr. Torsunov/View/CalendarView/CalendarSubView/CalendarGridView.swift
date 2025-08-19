import SwiftUI

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

struct CalendarGridView: View {
    let monthDates: [WorkoutDay]
    var onDayTap: ((Date) -> Void)? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 7)

    private var isoCal: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.locale = .current
        c.firstWeekday = 2
        return c
    }

    private var gridDays: [GridDay] {
        let cal = isoCal
        let anchor = monthDates.first?.date ?? Date()

        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: anchor))!

        let daysInMonth = cal.range(of: .day, in: .month, for: startOfMonth)!.count

        let weekday = cal.component(.weekday, from: startOfMonth)
        let leading = (weekday - cal.firstWeekday + 7) % 7

        let prevMonth = cal.date(byAdding: .month, value: -1, to: startOfMonth)!
        let prevStart = cal.date(from: cal.dateComponents([.year, .month], from: prevMonth))!
        let prevCount = cal.range(of: .day, in: .month, for: prevStart)!.count

        let prevDates: [Date]
        if leading == 0 {
            prevDates = []
        } else {
            prevDates = (prevCount - leading + 1 ... prevCount).compactMap { day in
                cal.date(byAdding: .day, value: day - 1, to: prevStart)
            }
        }
        let currentDates: [Date] = (1 ... daysInMonth).compactMap { day in
            cal.date(byAdding: .day, value: day - 1, to: startOfMonth)
        }
        let totalSoFar = leading + daysInMonth
        let trailing = (7 - (totalSoFar % 7)) % 7

        let nextMonth = cal.date(byAdding: .month, value: 1, to: startOfMonth)!
        let nextStart = cal.date(from: cal.dateComponents([.year, .month], from: nextMonth))!
        let nextDates: [Date] = (0..<trailing).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: nextStart)
        }
        let dotsByDay: [Date: [Color]] = Dictionary(uniqueKeysWithValues:
            monthDates.map { let d = cal.startOfDay(for: $0.date); return (d, $0.dots) }
        )

        func makeGridDay(_ date: Date, isCurrent: Bool) -> GridDay {
            let key = cal.startOfDay(for: date)
            let dots = isCurrent ? (dotsByDay[key] ?? []) : []
            return GridDay(date: date, isCurrentMonth: isCurrent, dots: dots)
        }

        return prevDates.map { makeGridDay($0, isCurrent: false) }
            + currentDates.map { makeGridDay($0, isCurrent: true) }
            + nextDates.map { makeGridDay($0, isCurrent: false) }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(localizedWeekdaysISO(), id: \.self) { s in
                    Text(s.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(gridDays) { cell in
                    let isToday = Calendar.current.isDateInToday(cell.date)
                    let startOfToday = isoCal.startOfDay(for: Date())
                    let isPast = isoCal.startOfDay(for: cell.date) < startOfToday

                    Button {
                        onDayTap?(cell.date)
                    } label: {
                        VStack(spacing: 8) {
                            Text("\(Calendar.current.component(.day, from: cell.date))")
                                .font(.headline)
                                .foregroundColor(cell.isCurrentMonth ? .white : .white.opacity(0.45))

                            HStack(spacing: 4) {
                                ForEach(Array(cell.dots.prefix(6)).indices, id: \.self) { idx in
                                    Capsule()
                                        .fill(cell.dots[idx])
                                        .frame(width: 10, height: 4)
                                }
                            }
                            .frame(height: 8)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(bgColor(isCurrentMonth: cell.isCurrentMonth, isToday: isToday, isPast: isPast))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isToday ? Color.green : Color.clear, lineWidth: 2)
                        )
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal)
    }

    private func bgColor(isCurrentMonth: Bool, isToday: Bool, isPast: Bool) -> Color {
        if !isCurrentMonth { return Color(.systemGray6).opacity(0.06) }
        if isToday        { return Color(.systemGray6).opacity(0.22) }
        if isPast         { return Color(.systemGray6).opacity(0.12) }
        return Color(.systemGray6).opacity(0.16)
    }
}

// MARK: - Модель ячейки сетки
struct GridDay: Identifiable {
    let id = UUID()
    let date: Date
    let isCurrentMonth: Bool
    let dots: [Color]
}

// MARK: - Helpers

private func localizedWeekdaysISO() -> [String] {
    var cal = Calendar(identifier: .iso8601)
    cal.locale = Locale.current
    cal.firstWeekday = 2 

    let df = DateFormatter()
    df.locale = cal.locale
    df.calendar = cal

    let base: [String]
    if let standalone = df.shortStandaloneWeekdaySymbols, standalone.count == 7 {
        base = standalone
    } else {
        base = df.shortWeekdaySymbols
    }

    if base.count == 7 {
        let mondayFirst = Array(base[1...6]) + [base[0]]
        return mondayFirst.map { $0.capitalized }
    } else {
        return base.map { $0.capitalized }
    }
}
