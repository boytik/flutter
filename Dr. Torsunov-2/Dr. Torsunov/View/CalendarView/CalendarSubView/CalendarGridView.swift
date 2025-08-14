import SwiftUI

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

struct CalendarGridView: View {
    let monthDates: [WorkoutDay]
    var onDayTap: ((Date) -> Void)? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 7)

    // ISO-календарь (понедельник — первый)
    private var isoCal: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.locale = Locale.current
        c.firstWeekday = 2
        return c
    }

    // Строим расширенную сетку: пред. месяц + текущий + след. месяц
    private var gridDays: [GridDay] {
        guard let anyDate = monthDates.first?.date else { return [] }

        let cal = isoCal

        // 1) первый день текущего месяца
        let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: anyDate))!

        // 2) сколько пустых ячеек нужно перед «1»
        let weekday = cal.component(.weekday, from: firstOfMonth) // 1..7
        let leading = (weekday - cal.firstWeekday + 7) % 7

        // 3) предыдущий месяц
        let prevMonthStart = cal.date(byAdding: .month, value: -1, to: firstOfMonth)!
        let prevStart = cal.date(from: cal.dateComponents([.year, .month], from: prevMonthStart))!
        let prevRange = cal.range(of: .day, in: .month, for: prevStart)!
        let prevLastDay = prevRange.count

        let prevDates: [Date] = (prevLastDay - leading + 1 ... prevLastDay).map { day in
            cal.date(byAdding: .day, value: day - 1, to: prevStart)!
        }

        // 4) текущий месяц — подложим точки из `monthDates`
        let dotsByDay: [Date: [Color]] = Dictionary(uniqueKeysWithValues:
            monthDates.map { (cal.startOfDay(for: $0.date), $0.dots) }
        )
        let currentDates = monthDates.map { cal.startOfDay(for: $0.date) }
                                     .sorted()

        // 5) добьём хвост до кратного 7 днями следующего месяца
        let totalSoFar = leading + currentDates.count
        let trailing = (7 - (totalSoFar % 7)) % 7
        let nextMonthStart = cal.date(byAdding: .month, value: 1, to: firstOfMonth)!
        let nextStart = cal.date(from: cal.dateComponents([.year, .month], from: nextMonthStart))!
        let nextDates: [Date] = (0..<trailing).map { off in
            cal.date(byAdding: .day, value: off, to: nextStart)!
        }

        // 6) Собираем итоговую ленту
        let prevCells  = prevDates.map  { GridDay(date: $0, dots: [], isCurrentMonth: false) }
        let currCells  = currentDates.map { d in GridDay(date: d, dots: dotsByDay[d] ?? [], isCurrentMonth: true) }
        let nextCells  = nextDates.map  { GridDay(date: $0, dots: [], isCurrentMonth: false) }

        return prevCells + currCells + nextCells
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
private struct GridDay: Identifiable {
    let id = UUID()
    let date: Date
    let dots: [Color]
    let isCurrentMonth: Bool
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

