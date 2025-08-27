import SwiftUI

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

struct CalendarGridView: View {
    let monthDates: [WorkoutDay]
    let displayMonth: Date
    var onDayTap: ((Date) -> Void)? = nil

    /// провайдер элементов дня
    var itemsProvider: (Date) -> [CalendarGridDayContext] = { _ in [] }

    /// выбранная дата — для зелёной рамки
    var selectedDate: Date? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    private var isoCal: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.locale = .current
        c.firstWeekday = 2
        return c
    }

    private var gridDays: [GridDay] {
        let cal = isoCal
        let anchor = displayMonth

        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: anchor))!
        let daysInMonth = cal.range(of: .day, in: .month, for: startOfMonth)!.count

        let weekday = cal.component(.weekday, from: startOfMonth)
        let leading = (weekday - cal.firstWeekday + 7) % 7

        let prevMonth = cal.date(byAdding: .month, value: -1, to: startOfMonth)!
        let prevStart = cal.date(from: cal.dateComponents([.year, .month], from: prevMonth))!
        let prevCount = cal.range(of: .day, in: .month, for: prevStart)!.count

        let prevDates: [Date] =
            leading == 0 ? [] :
            (prevCount - leading + 1 ... prevCount).compactMap { day in
                cal.date(byAdding: .day, value: day - 1, to: prevStart)
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
            let dots = dotsByDay[key] ?? []
            return GridDay(date: date, isCurrentMonth: isCurrent, dots: dots)
        }

        return prevDates.map { makeGridDay($0, isCurrent: false) }
            + currentDates.map { makeGridDay($0, isCurrent: true) }
            + nextDates.map  { makeGridDay($0, isCurrent: false) }
    }

    var body: some View {
        VStack(spacing: 8) {
            // ряд дней недели
            HStack {
                ForEach(localizedWeekdaysISO(), id: \.self) { s in
                    Text(s.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white.opacity(0.65))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(gridDays) { cell in
                    let startOfToday = isoCal.startOfDay(for: Date())
                    let isPast = isoCal.startOfDay(for: cell.date) < startOfToday

                    let isSelected: Bool = {
                        guard let s = selectedDate else { return false }
                        return isoCal.isDate(s, inSameDayAs: cell.date)
                    }()

                    Button {
                        onDayTap?(cell.date)
                    } label: {
                        VStack(alignment: .center) {
                                Text("\(Calendar.current.component(.day, from: cell.date))")
                                    .font(.system(size: 12, weight: .semibold))           // меньше
                                    .foregroundColor(cell.isCurrentMonth ? .white : .white.opacity(0.45))
                                    .padding(.top, 4)
                            Spacer()
                            CalendarGridMarkersLayer(items: itemsProvider(cell.date))
                                .padding(.horizontal, 2)
                            Spacer()
                            
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(bgColor(isCurrentMonth: cell.isCurrentMonth, isPast: isPast))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.green : Color.white.opacity(0.10),
                                        lineWidth: isSelected ? 2 : 1)
                        )
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal)
    }

    private func bgColor(isCurrentMonth: Bool, isPast: Bool) -> Color {
        if !isCurrentMonth { return Color.white.opacity(0.06) }
        if isPast          { return Color.white.opacity(0.10) }
        return Color.white.opacity(0.12)
    }
}

// MARK: - Модель ячейки
struct GridDay: Identifiable {
    let id = UUID()
    let date: Date
    let isCurrentMonth: Bool
    let dots: [Color]
}

// MARK: - Helpers

private func localizedWeekdaysISO() -> [String] {
    var cal = Calendar(identifier: .iso8601)
    cal.locale = .current
    cal.firstWeekday = 2

    let df = DateFormatter()
    df.locale = cal.locale
    df.calendar = cal

    let base: [String] = (df.shortStandaloneWeekdaySymbols ?? df.shortWeekdaySymbols)
    let arr = base.count == 7 ? Array(base[1...6]) + [base[0]] : base
    return arr.map { $0.capitalized }
}
