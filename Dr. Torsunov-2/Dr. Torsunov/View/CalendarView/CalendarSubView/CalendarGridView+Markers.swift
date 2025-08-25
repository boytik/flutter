import SwiftUI

// MARK: - Контракт данных дня (минимум, чтобы не тянуть ваши модели)

/// Любой элемент дня, который можно показать в календарной ячейке.
/// Ваша модель (например, CalendarItem/Workout/Activity) может быть легко
/// адаптирована в этот протокол через простую extension.
public protocol CalendarGridDayContext {
    /// "Тип" тренировки для цветового кодирования (как во Flutter).
    var workoutTypeKey: String { get }
    /// Сколько слоёв запланировано (если неизвестно — 1).
    var plannedLayers: Int { get }
    /// Сколько слоёв выполнено (nil — неизвестно / не применимо).
    var doneLayers: Int? { get }
    /// Флаг, что это запланированная тренировка.
    var isPlanned: Bool { get }
    /// Флаг, что тренировка выполнена.
    var isDone: Bool { get }
}

// MARK: - Адаптер: любые элементы дня -> маркеры отрисовки

public struct CalendarGridMarkersAdapter {
    public init() {}

    public func markers(from items: [CalendarGridDayContext]) -> [CalendarCellMarkersView.Marker] {
        items.map {
            CalendarCellMarkersView.Marker(
                workoutType: $0.workoutTypeKey,
                plannedLayers: max(1, $0.plannedLayers),
                doneLayers: $0.doneLayers,
                isPlanned: $0.isPlanned,
                isDone: $0.isDone
            )
        }
    }
}

// MARK: - Готовый слой для ячейки календаря

/// Вью-слой, который можно встроить в контент ячейки дня.
/// Просто передайте массив ваших "элементов дня" в виде `CalendarGridDayContext`.
public struct CalendarGridMarkersLayer: View {
    private let items: [CalendarGridDayContext]
    private let maxRows: Int
    private let segmentHeight: CGFloat

    private let adapter = CalendarGridMarkersAdapter()

    /// - Parameters:
    ///   - items: элементы текущего дня, удовлетворяющие `CalendarGridDayContext`
    ///   - maxRows: максимум строк маркеров (по умолчанию 3)
    ///   - segmentHeight: высота сегмента мини-бара
    public init(
        items: [CalendarGridDayContext],
        maxRows: Int = 3,
        segmentHeight: CGFloat = 6
    ) {
        self.items = items
        self.maxRows = maxRows
        self.segmentHeight = segmentHeight
    }

    public var body: some View {
        let markers = adapter.markers(from: items)
        CalendarCellMarkersView(
            markers: markers,
            maxRows: maxRows,
            segmentHeight: segmentHeight,
            cornerRadius: 3
        )
    }
}

// MARK: - Пример адаптации вашей модели (можно удалить, это только демо)

/// Пример абстрактной модели из проекта.
/// Замените/удалите после подключения реальной модели.
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
