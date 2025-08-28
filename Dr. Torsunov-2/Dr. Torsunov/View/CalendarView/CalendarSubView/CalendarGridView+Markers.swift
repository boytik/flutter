import SwiftUI

public protocol CalendarGridDayContext {
    var workoutTypeKey: String { get }  // "swim" | "run" | "yoga" | "other" | ...
    var plannedLayers: Int { get }
    var doneLayers: Int? { get }
    var isPlanned: Bool { get }
    var isDone: Bool { get }
}

public struct CalendarGridMarkersAdapter {
    public init() {}

    public func markers(from items: [CalendarGridDayContext]) -> [CalendarCellMarkersView.Marker] {
        
        items.map { item in
            return CalendarCellMarkersView.Marker(
                workoutType: item.workoutTypeKey,
                isSolid: item.isDone   
            )
        }
    }
}

public struct CalendarGridMarkersLayer: View {
    private let items: [CalendarGridDayContext]
    private let maxRows: Int
    private let segmentHeight: CGFloat
    private let linesPerRow: Int
    private let segmentSpacing: CGFloat
    private let rowSpacing: CGFloat
    private let horizontalInset: CGFloat
    private let bottomInset: CGFloat

    private let adapter = CalendarGridMarkersAdapter()

    public init(
        items: [CalendarGridDayContext],
        maxRows: Int = 3,
        segmentHeight: CGFloat = 3,
        linesPerRow: Int = 6,
        segmentSpacing: CGFloat = 2,
        rowSpacing: CGFloat = 3,
        horizontalInset: CGFloat = 2,
        bottomInset: CGFloat = 4
    ) {
        self.items = items
        self.maxRows = maxRows
        self.segmentHeight = segmentHeight
        self.linesPerRow = linesPerRow
        self.segmentSpacing = segmentSpacing
        self.rowSpacing = rowSpacing
        self.horizontalInset = horizontalInset
        self.bottomInset = bottomInset
    }

    public var body: some View {
        let markers = Array(adapter.markers(from: items).prefix(maxRows))
        CalendarCellMarkersView(
            markers: markers,
            linesPerRow: linesPerRow,
            segmentHeight: segmentHeight,
            rowSpacing: rowSpacing,
            segmentSpacing: segmentSpacing,
            cornerRadius: 2.5,
            horizontalInset: horizontalInset,
            bottomInset: bottomInset
        )
    }
}
