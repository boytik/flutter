import SwiftUI

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

struct CalendarGridView: View {
    let monthDates: [WorkoutDay]
    var onDayTap: ((Date) -> Void)? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 7)

    // ISO-календарь (понедельник — первый)
    private var isoCal: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.locale = .current
        c.firstWeekday = 2
        return c
    }

    // Строим расширенную сетку: пред. месяц + текущий + след. месяц
    private var gridDays: [GridDay] {
        // Берём любую дату текущего месяца; если нет — fallback на сегодня
        let cal = isoCal
        let anchor = monthDates.first?.date ?? Date()

        // 1) первый день текущего месяца
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: anchor))!

        // 2) кол-во дней в текущем месяце
        let daysInMonth = cal.range(of: .day, in: .month, for: startOfMonth)!.count

        // 3) сколько пустых ячеек перед «1»
        let weekday = cal.component(.weekday, from: startOfMonth) // 1..7 в рамках isoCal
        let leading = (weekday - cal.firstWeekday + 7) % 7       // 0..6

        // 4) предыдущий месяц (безопасно формируем список дат)
        let prevMonth = cal.date(byAdding: .month, value: -1, to: startOfMonth)!
        let prevStart = cal.date(from: cal.dateComponents([.year, .month], from: prevMonth))!
        let prevCount = cal.range(of: .day, in: .month, for: prevStart)!.count

        let prevDates: [Date]
        if leading == 0 {
            prevDates = []
        } else {
            // последние `leading` дней предыдущего месяца
            prevDates = (prevCount - leading + 1 ... prevCount).compactMap { day in
                cal.date(byAdding: .day, value: day - 1, to: prevStart)
            }
        }

        // 5) текущий месяц
        let currentDates: [Date] = (1 ... daysInMonth).compactMap { day in
            cal.date(byAdding: .day, value: day - 1, to: startOfMonth)
        }

        // 6) сколько ячеек добить в конце, чтобы кратно 7
        let totalSoFar = leading + daysInMonth
        let trailing = (7 - (totalSoFar % 7)) % 7

        // 7) следующий месяц
        let nextMonth = cal.date(byAdding: .month, value: 1, to: startOfMonth)!
        let nextStart = cal.date(from: cal.dateComponents([.year, .month], from: nextMonth))!
        let nextDates: [Date] = (0..<trailing).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: nextStart)
        }

        // 8) точки для текущего месяца (по startOfDay)
        let dotsByDay: [Date: [Color]] = Dictionary(uniqueKeysWithValues:
            monthDates.map { let d = cal.startOfDay(for: $0.date); return (d, $0.dots) }
        )

        func makeGridDay(_ date: Date, isCurrent: Bool) -> GridDay {
            let key = cal.startOfDay(for: date)
            let dots = isCurrent ? (dotsByDay[key] ?? []) : [] // чужим месяцам точки не рисуем
            return GridDay(date: date, isCurrentMonth: isCurrent, dots: dots)
        }

        return prevDates.map { makeGridDay($0, isCurrent: false) }
            + currentDates.map { makeGridDay($0, isCurrent: true) }
            + nextDates.map { makeGridDay($0, isCurrent: false) }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Пн…Вс (всегда понедельник первым)
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

                    Button {
                        onDayTap?(cell.date)
                    } label: {
                        VStack(spacing: 8) {
                            Text("\(Calendar.current.component(.day, from: cell.date))")
                                .font(.headline)
                                .foregroundColor(cell.isCurrentMonth ? .white : .white.opacity(0.45))

                            // до 6 маркеров-капсул
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
                        .background(Color(.systemGray6).opacity(0.12))
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
}

// MARK: - Модель ячейки сетки
struct GridDay: Identifiable {
    let id = UUID()
    let date: Date
    let isCurrentMonth: Bool
    let dots: [Color]
}

// MARK: - Helpers

/// Локализованные заголовки недель Пн…Вс
private func localizedWeekdaysISO() -> [String] {
    var cal = Calendar(identifier: .iso8601)
    cal.locale = Locale.current
    cal.firstWeekday = 2 // Monday

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

