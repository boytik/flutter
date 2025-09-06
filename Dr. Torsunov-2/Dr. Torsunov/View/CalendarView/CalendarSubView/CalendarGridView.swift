import SwiftUI

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

// Собираем фреймы ячеек в одном именованном координатном пространстве
private struct DayCellFrameKey: PreferenceKey {
    static var defaultValue: [Date: CGRect] = [:]
    static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct CalendarGridView: View {
    let monthDates: [WorkoutDay]
    let displayMonth: Date

    // Тап/лонгтап/выбор цели
    var onDayTap: ((Date) -> Void)? = nil
    var onDayLongPress: ((Date) -> Void)? = nil
    var onSelectMoveTarget: ((Date) -> Void)? = nil

    // Контент ячейки
    var itemsProvider: (Date) -> [CalendarGridDayContext] = { _ in [] }
    var selectedDate: Date? = nil

    // Перенос
    var isMoveMode: Bool = false
    var moveHighlightWeekOf: Date? = nil
    var moveSourceDate: Date? = nil

    // Drag state
    @State private var cellFrames: [Date: CGRect] = [:]
    @State private var isDragging: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var hoverDate: Date? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    private let spaceName = "calendarGridSpace"

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
            // Ряд дней недели
            HStack {
                ForEach(localizedWeekdaysISO(), id: \.self) { s in
                    Text(s.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white.opacity(0.65))
                        .frame(maxWidth: .infinity)
                }
            }

            // Фикс высоты: не даём гриду схлопнуться в ноль
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // Сетка
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(gridDays) { cell in
                            dayCell(cell)
                        }
                    }

                    // Прозрачный ловец драга (не влияет на layout)
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named(spaceName))
                                .onChanged { value in
                                    guard isMoveMode,
                                          let src = moveSourceDate,
                                          let frame = cellFrames[isoCal.startOfDay(for: src)] else { return }
                                    if !isDragging { isDragging = true }
                                    // смещаем призрак относительно центра исходной ячейки
                                    dragOffset = CGSize(width: value.location.x - frame.midX,
                                                        height: value.location.y - frame.midY)
                                    let newHover = date(at: value.location)
                                    if newHover != hoverDate {
                                        #if os(iOS)
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        #endif
                                        hoverDate = newHover
                                    }
                                }
                                .onEnded { value in
                                    guard isMoveMode else { return }
                                    isDragging = false
                                    dragOffset = .zero
                                    if let target = date(at: value.location),
                                       isInSameWeek(target, moveHighlightWeekOf) {
                                        onSelectMoveTarget?(target)
                                    }
                                    hoverDate = nil
                                }
                        )
                        .allowsHitTesting(isMoveMode) // в обычном режиме не перехватываем касания

                    // «Призрак»
                    if isMoveMode, isDragging, let src = moveSourceDate {
                        let key = isoCal.startOfDay(for: src)
                        if let frame = cellFrames[key] {
                            ghostCell(for: src, size: frame.size)
                                .position(x: frame.midX + dragOffset.width,
                                          y: frame.midY + dragOffset.height)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .coordinateSpace(name: spaceName)
            }
            .frame(minHeight: 260) // гарантированная минимальная высота грида
        }
        .padding(.horizontal)
        .onPreferenceChange(DayCellFrameKey.self) { frames in
            self.cellFrames = frames
        }
    }

    // MARK: - Ячейка

    @ViewBuilder
    private func dayCell(_ cell: GridDay) -> some View {
        let startOfToday = isoCal.startOfDay(for: Date())
        let isPast = isoCal.startOfDay(for: cell.date) < startOfToday

        let isSelected: Bool = {
            guard let s = selectedDate else { return false }
            return isoCal.isDate(s, inSameDayAs: cell.date)
        }()

        let isInMoveWeek: Bool = {
            guard let w = moveHighlightWeekOf else { return false }
            return isoCal.component(.weekOfYear, from: w) == isoCal.component(.weekOfYear, from: cell.date)
                && isoCal.component(.yearForWeekOfYear, from: w) == isoCal.component(.yearForWeekOfYear, from: cell.date)
        }()

        let isSource: Bool = {
            guard let src = moveSourceDate else { return false }
            return isoCal.isDate(src, inSameDayAs: cell.date)
        }()

        let isHover: Bool = {
            guard let h = hoverDate else { return false }
            return isoCal.isDate(h, inSameDayAs: cell.date)
        }()

        let markers = CalendarGridMarkersLayer(items: itemsProvider(cell.date))

        let v = VStack(alignment: .center) {
            Text("\(Calendar.current.component(.day, from: cell.date))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(cell.isCurrentMonth ? .white : .white.opacity(0.45))
                .padding(.top, 4)
            Spacer(minLength: 2)
            markers
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
                        : (isMoveMode && isInMoveWeek ? (isHover ? Color.green : Color.green.opacity(0.6)) : Color.white.opacity(0.10)),
                    lineWidth: isSelected ? 2 : (isMoveMode && isInMoveWeek ? (isHover ? 2 : 1.5) : 1)
                )
        )
        .cornerRadius(12)
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DayCellFrameKey.self,
                    value: [isoCal.startOfDay(for: cell.date): proxy.frame(in: .named(spaceName))]
                )
            }
        )
        .allowsHitTesting(!isMoveMode || isInMoveWeek || isSource)
        .opacity(isMoveMode && !isInMoveWeek && !isSource ? 0.45 : 1.0)
        .onTapGesture {
            if isMoveMode && isInMoveWeek {
                onSelectMoveTarget?(cell.date)
            } else if !isMoveMode {
                onDayTap?(cell.date)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5, maximumDistance: 20)
                .onEnded { _ in
                    guard cell.isCurrentMonth else { return }
                    onDayLongPress?(cell.date)
                }
        )

        v
    }

    // MARK: - Внешний вид «призрака»

    @ViewBuilder
    private func ghostCell(for date: Date, size: CGSize) -> some View {
        let markers = CalendarGridMarkersLayer(items: itemsProvider(date))
        VStack(alignment: .center) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.top, 4)
            Spacer(minLength: 2)
            markers
                .padding(.horizontal, 2)
            Spacer(minLength: 2)
        }
        .frame(width: max(size.width, 44), height: max(size.height, 52))
        .background(Color.white.opacity(0.18))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green, lineWidth: 2))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
        .scaleEffect(1.06)
        .opacity(0.98)
    }

    private func bgColor(isCurrentMonth: Bool, isPast: Bool) -> Color {
        if !isCurrentMonth { return Color.white.opacity(0.06) }
        if isPast          { return Color.white.opacity(0.10) }
        return Color.white.opacity(0.12)
    }

    // MARK: - Helpers

    private func date(at point: CGPoint) -> Date? {
        for (date, frame) in cellFrames where frame.contains(point) {
            return date
        }
        return nil
    }

    private func isInSameWeek(_ a: Date, _ bOpt: Date?) -> Bool {
        guard let b = bOpt else { return false }
        return isoCal.component(.weekOfYear, from: a) == isoCal.component(.weekOfYear, from: b)
            && isoCal.component(.yearForWeekOfYear, from: a) == isoCal.component(.yearForWeekOfYear, from: b)
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
