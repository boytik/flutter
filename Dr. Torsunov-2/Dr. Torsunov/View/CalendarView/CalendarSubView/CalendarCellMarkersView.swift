import SwiftUI

public struct CalendarCellMarkersView: View {

    public struct Marker: Identifiable, Hashable {
        public let id = UUID()
        public let workoutType: String
        public let isSolid: Bool          // true = завершено (сплошная), false = план (точки)
        public let filledCount: Int?      // для плана: сколько «ярких» точек из totalDots

        public init(workoutType: String, isSolid: Bool, filledCount: Int? = nil) {
            self.workoutType = workoutType
            self.isSolid = isSolid
            self.filledCount = filledCount
        }
    }

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
    /// Максимум 5 точек для планов по ТЗ
    private let linesPerRow: Int
    private let segmentHeight: CGFloat
    private let rowSpacing: CGFloat
    private let segmentSpacing: CGFloat
    private let cornerRadius: CGFloat
    private let horizontalInset: CGFloat
    private let bottomInset: CGFloat

    public init(
        markers: [Marker],
        linesPerRow: Int = 5,
        segmentHeight: CGFloat = 3,
        rowSpacing: CGFloat = 3,
        segmentSpacing: CGFloat = 2,
        cornerRadius: CGFloat = 2.5,
        horizontalInset: CGFloat = 2,
        bottomInset: CGFloat = 0
    ) {
        self.markers = Array(markers.prefix(4))
        // несмотря на параметр, гарантируем не больше 5 по ТЗ
        self.linesPerRow = min(5, max(3, linesPerRow))
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
                    // Завершённая — сплошная линия (как и было)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(color)
                        .frame(height: segmentHeight)
                } else {
                    // План — 5 «точек»: первые N = яркие, остальные = приглушённые
                    let filled = max(0, min(linesPerRow, m.filledCount ?? 1))
                    HStack(spacing: segmentSpacing) {
                        ForEach(0..<linesPerRow, id: \.self) { idx in
                            let opaque: Double = idx < filled ? 1.0 : 0.25
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(color.opacity(opaque))
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
