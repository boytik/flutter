import SwiftUI

/// Полоски-индикаторы в ячейке календаря.
/// Цвет определяется по `workoutType` (как было изначально),
/// стиль: done = сплошная, planned = пунктир.
public struct CalendarCellMarkersView: View {

    public struct Marker: Identifiable, Hashable {
        public let id = UUID()
        public let workoutType: String
        public let isSolid: Bool   // true = завершено (сплошная), false = запланировано (пунктир)
        public init(workoutType: String, isSolid: Bool) {
            self.workoutType = workoutType
            self.isSolid = isSolid
        }
    }

    // палитра — как во Flutter
    private enum Palette {
        static func color(for raw: String) -> Color {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if key == "water" || key == "swim" || key.contains("water") || key.contains("swim")
                || key.contains("вода") || key.contains("плав") { return .blue }

            if key == "run" || key == "walk" || key.contains("run") || key.contains("walk")
                || key.contains("ход") || key.contains("бег")
                || key.contains("walking/running") { return .orange }

            if key == "yoga" || key.contains("yoga") || key.contains("йога") { return .purple }

            if key == "sauna" || key.contains("sauna") || key.contains("баня") || key.contains("хаммам") { return .red }

            if key == "fast" || key == "fasting" || key.contains("fast") || key.contains("пост") || key.contains("голод") {
                return .yellow
            }

            if key == "other" || key.contains("strength") || key.contains("сил") { return .green }

            return .green
        }
    }


    private let markers: [Marker]
    private let linesPerRow: Int
    private let segmentHeight: CGFloat
    private let rowSpacing: CGFloat
    private let segmentSpacing: CGFloat
    private let cornerRadius: CGFloat
    private let horizontalInset: CGFloat
    private let bottomInset: CGFloat

    public init(
        markers: [Marker],
        linesPerRow: Int = 6,
        segmentHeight: CGFloat = 3,
        rowSpacing: CGFloat = 3,
        segmentSpacing: CGFloat = 2,
        cornerRadius: CGFloat = 2.5,
        horizontalInset: CGFloat = 2,
        bottomInset: CGFloat = 0
    ) {
        self.markers = Array(markers.prefix(4))
        self.linesPerRow = max(3, min(8, linesPerRow))
        self.segmentHeight = segmentHeight
        self.rowSpacing = rowSpacing
        self.segmentSpacing = segmentSpacing
        self.cornerRadius = cornerRadius
        self.horizontalInset = horizontalInset
        self.bottomInset = bottomInset
    }

    public var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(markers) { m in
                let color = Palette.color(for: m.workoutType)
                if m.isSolid {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(color)
                        .frame(height: segmentHeight)
                } else {
                    HStack(spacing: segmentSpacing) {
                        ForEach(0..<linesPerRow, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(color)
                                .frame(height: segmentHeight)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityHidden(true)
    }
}

public typealias CalendarCellMarker = CalendarCellMarkersView.Marker
