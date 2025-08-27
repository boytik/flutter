import SwiftUI

// MARK: - Контракт данных дня

public protocol CalendarGridDayContext {
    var workoutTypeKey: String { get }  // тип тренировки для цветового кода
    var plannedLayers: Int { get }      // сколько запланировано (может не использоваться)
    var doneLayers: Int? { get }        // сколько выполнено (может не использоваться)
    var isPlanned: Bool { get }
    var isDone: Bool { get }
}

// MARK: - Палитра и маппинг типов -> цвет

private enum MarkerPalette {
    // Цвета подобраны под скрин №2
    static let blue   = Color(red: 0.38, green: 0.57, blue: 0.97) // swim
    static let purple = Color(red: 0.73, green: 0.54, blue: 1.00) // run/walk
    static let yellow = Color(red: 0.99, green: 0.84, blue: 0.24) // bike
    static let green  = Color(red: 0.36, green: 0.84, blue: 0.39) // прочее/другое

    static func color(for typeKey: String) -> Color {
        let key = typeKey.lowercased()
        // swim
        if key.contains("swim") || key.contains("плав") { return blue }
        // run / walk
        if key.contains("run") || key.contains("walk") || key.contains("бег") || key.contains("ход") { return purple }
        // bike / cycling
        if key.contains("bike") || key.contains("cycl") || key.contains("вел") { return yellow }
        // fallback
        return green
    }
}

// MARK: - Адаптер: элементы дня -> массив цветов

public struct CalendarGridMarkersAdapter {
    public init() {}

    public func colors(from items: [CalendarGridDayContext]) -> [Color] {
        items.map { MarkerPalette.color(for: $0.workoutTypeKey) }
    }
}

// MARK: - Слой маркеров для ячейки календаря

public struct CalendarGridMarkersLayer: View {
    private let items: [CalendarGridDayContext]
    private let maxRows: Int
    private let segmentHeight: CGFloat
    private let linesPerRow: Int
    private let segmentSpacing: CGFloat
    private let rowSpacing: CGFloat

    private let adapter = CalendarGridMarkersAdapter()

    /// - Parameters:
    ///   - items: элементы текущего дня
    ///   - maxRows: максимум строк маркеров (по умолчанию 3)
    ///   - segmentHeight: высота одного сегмента в строке (по умолчанию 3 — тонкие полоски)
    ///   - linesPerRow: сколько сегментов в строке (по умолчанию 6)
    ///   - segmentSpacing: расстояние между сегментами
    ///   - rowSpacing: расстояние между строками
    public init(
        items: [CalendarGridDayContext],
        maxRows: Int = 3,
        segmentHeight: CGFloat = 3,
        linesPerRow: Int = 6,
        segmentSpacing: CGFloat = 2,
        rowSpacing: CGFloat = 3
    ) {
        self.items = items
        self.maxRows = maxRows
        self.segmentHeight = segmentHeight
        self.linesPerRow = linesPerRow
        self.segmentSpacing = segmentSpacing
        self.rowSpacing = rowSpacing
    }

    public var body: some View {
        let colors = Array(adapter.colors(from: items).prefix(maxRows))
        CalendarCellMarkersView(
            colors: colors,
            linesPerRow: linesPerRow,
            segmentHeight: segmentHeight,
            rowSpacing: rowSpacing,
            segmentSpacing: segmentSpacing,
            cornerRadius: 2.5
        )
    }
}

// MARK: - Демомодель (если где-то использовалась) — можно удалить

public struct DemoDayItem: CalendarGridDayContext {
    public var workoutTypeKey: String
    public var plannedLayers: Int
    public var doneLayers: Int?
    public var isPlanned: Bool
    public var isDone: Bool

    public init(
        workoutTypeKey: String,
        plannedLayers: Int,
        doneLayers: Int? = nil,
        isPlanned: Bool,
        isDone: Bool
    ) {
        self.workoutTypeKey = workoutTypeKey
        self.plannedLayers = plannedLayers
        self.doneLayers = doneLayers
        self.isPlanned = isPlanned
        self.isDone = isDone
    }
}
