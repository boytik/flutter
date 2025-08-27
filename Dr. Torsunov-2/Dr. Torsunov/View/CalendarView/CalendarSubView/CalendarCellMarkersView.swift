import SwiftUI

/// Отрисовывает цветные "пунктирные" полоски-индикаторы внутри ячейки календаря.
/// Поддерживает до 4 строк. По умолчанию 6 сегментов на строку.
/// Визуально соответствует референсу (скрин №2).
public struct CalendarCellMarkersView: View {

    /// Маркер одной строки (цвет линии).
    public struct Marker: Identifiable, Hashable {
        public let id = UUID()
        public let color: Color
        public init(color: Color) { self.color = color }
    }

    private let markers: [Marker]
    private let linesPerRow: Int
    private let segmentHeight: CGFloat
    private let rowSpacing: CGFloat
    private let segmentSpacing: CGFloat
    private let cornerRadius: CGFloat

    /// Основной инициализатор (через массив Marker)
    public init(
        markers: [Marker],
        linesPerRow: Int = 6,
        segmentHeight: CGFloat = 3,
        rowSpacing: CGFloat = 3,
        segmentSpacing: CGFloat = 2,
        cornerRadius: CGFloat = 2.5
    ) {
        // максимум 4 строки, как на референсе
        self.markers = Array(markers.prefix(4))
        self.linesPerRow = max(3, min(8, linesPerRow))
        self.segmentHeight = segmentHeight
        self.rowSpacing = rowSpacing
        self.segmentSpacing = segmentSpacing
        self.cornerRadius = cornerRadius
    }

    /// Удобный инициализатор (если в проекте передаются только цвета)
    public init(
        colors: [Color],
        linesPerRow: Int = 6,
        segmentHeight: CGFloat = 3,
        rowSpacing: CGFloat = 3,
        segmentSpacing: CGFloat = 2,
        cornerRadius: CGFloat = 2.5
    ) {
        self.init(
            markers: colors.map { Marker(color: $0) },
            linesPerRow: linesPerRow,
            segmentHeight: segmentHeight,
            rowSpacing: rowSpacing,
            segmentSpacing: segmentSpacing,
            cornerRadius: cornerRadius
        )
    }

    public var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(markers) { marker in
                HStack(spacing: segmentSpacing) {
                    ForEach(0..<linesPerRow, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(marker.color)
                            .frame(height: segmentHeight)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityHidden(true)
    }
}

// На случай, если где-то в коде использовался старый псевдоним
public typealias CalendarCellMarker = CalendarCellMarkersView.Marker
