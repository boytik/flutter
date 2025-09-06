import SwiftUI

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

struct CalendarGridView: View {
    let monthDates: [WorkoutDay]
    let displayMonth: Date

    // короткий тап
    var onDayTap: ((Date) -> Void)? = nil
    // длительное нажатие по дню — включаем режим переноса и запоминаем «неделю-источник»
    var onDayLongPress: ((Date) -> Void)? = nil
    // выбор целевого дня внутри подсвеченной недели
    var onSelectMoveTarget: ((Date) -> Void)? = nil

    /// провайдер элементов дня
    var itemsProvider: (Date) -> [CalendarGridDayContext] = { _ in [] }

    /// выбранная дата — для зелёной рамки
    var selectedDate: Date? = nil

    /// режим переноса + неделя, которую подсвечиваем как «доступные цели»
    var isMoveMode: Bool = false
    var moveHighlightWeekOf: Date? = nil

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

                    // принадлежит ли ячейка той же неделе, что и moveHighlightWeekOf
                    let isInMoveWeek: Bool = {
                        guard let w = moveHighlightWeekOf else { return false }
                        return isoCal.component(.weekOfYear, from: w) == isoCal.component(.weekOfYear, from: cell.date)
                        && isoCal.component(.yearForWeekOfYear, from: w) == isoCal.component(.yearForWeekOfYear, from: cell.date)
                    }()

                    // ⛔️ УБРАЛИ Button, чтобы long-press не конфликтовал. Управляем жестами вручную.
                    let cellView = VStack(alignment: .center) {
                        Text("\(Calendar.current.component(.day, from: cell.date))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(cell.isCurrentMonth ? .white : .white.opacity(0.45))
                            .padding(.top, 4)
                        Spacer(minLength: 2)
                        CalendarGridMarkersLayer(items: itemsProvider(cell.date))
                            .padding(.horizontal, 2)
                        Spacer(minLength: 2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(bgColor(isCurrentMonth: cell.isCurrentMonth, isPast: isPast))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected
                                    ? Color.green
                                    : (isMoveMode && isInMoveWeek ? Color.green.opacity(0.6) : Color.white.opacity(0.10)),
                                lineWidth: isSelected ? 2 : (isMoveMode && isInMoveWeek ? 1.5 : 1)
                            )
                    )
                    .cornerRadius(12)
                    .contentShape(Rectangle())

                    // Жесты: long-press включает перенос; обычный тап — либо выбор дня, либо выбор цели
                    cellView
                        .allowsHitTesting(!isMoveMode || isInMoveWeek)
                        .opacity(isMoveMode && !isInMoveWeek ? 0.45 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: isMoveMode)
                        .onTapGesture {
                            if isMoveMode && isInMoveWeek {
                                onSelectMoveTarget?(cell.date)
                            } else if !isMoveMode {
                                onDayTap?(cell.date)
                            }
                        }
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.55, maximumDistance: 20)
                                .onEnded { _ in
                                    guard cell.isCurrentMonth else { return }
                                    onDayLongPress?(cell.date)
                                }
                        )
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
