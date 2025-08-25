import SwiftUI

/// Индикаторы тренировок для ячейки календаря:
/// - цвет бара зависит от типа тренировки
/// - количество делений = количество слоёв
/// - выполненные помечаются бейджем (галочка)
public struct CalendarCellMarkersView: View {
    // MARK: - Public API

    public struct Marker: Identifiable, Hashable {
        public let id = UUID()
        public let workoutType: String           // например: "swim", "run", "bike" и т.п.
        public let plannedLayers: Int            // сколько слоёв запланировано
        public let doneLayers: Int?              // сколько слоёв выполнено (если nil — неизвестно)
        public let isPlanned: Bool               // пометка «запланировано»
        public let isDone: Bool                  // пометка «выполнено»

        public init(
            workoutType: String,
            plannedLayers: Int,
            doneLayers: Int? = nil,
            isPlanned: Bool,
            isDone: Bool
        ) {
            self.workoutType = workoutType
            self.plannedLayers = max(1, plannedLayers)
            self.doneLayers = doneLayers
            self.isPlanned = isPlanned
            self.isDone = isDone
        }
    }

    public let markers: [Marker]
    public let maxRows: Int
    public let segmentHeight: CGFloat
    public let cornerRadius: CGFloat

    /// Создавайте вью с массивом маркеров за конкретный день
    public init(
        markers: [Marker],
        maxRows: Int = 3,
        segmentHeight: CGFloat = 6,
        cornerRadius: CGFloat = 3
    ) {
        self.markers = markers
        self.maxRows = maxRows
        self.segmentHeight = segmentHeight
        self.cornerRadius = cornerRadius
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 3) {
            let rows = Array(markers.prefix(maxRows))
            ForEach(rows) { marker in
                HStack(spacing: 4) {
                    SegmentedBar(
                        segments: marker.plannedLayers,
                        // заполняем «выполненные» слои, если они известны
                        filled: marker.doneLayers ?? (marker.isDone ? marker.plannedLayers : 0),
                        color: color(for: marker.workoutType),
                        height: segmentHeight,
                        radius: cornerRadius
                    )
                    .frame(maxWidth: .infinity)

                    if marker.isDone {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.green)
                            .accessibilityLabel("Выполнено")
                    } else if marker.isPlanned {
                        Image(systemName: "clock")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Запланировано")
                    }
                }
            }

            // Если тренировок больше, чем maxRows — покажем компактный счётчик
            if markers.count > maxRows {
                Text("+\(markers.count - maxRows)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Color mapping

    private func color(for workoutType: String) -> Color {
        // Простая мапа по типам, синхронная подходу Flutter (тип -> цвет).
        // При необходимости расширим, чтобы точно совпасть с вашей схемой.
        switch workoutType.lowercased() {
        case "swim", "swimming", "плавание":
            return .teal
        case "run", "running", "бег":
            return .red
        case "bike", "cycling", "велосипед", "велотренировка":
            return .orange
        case "strength", "силовая":
            return .blue
        case "yoga", "йога", "stretch":
            return .purple
        case "walk", "ходьба":
            return .green
        default:
            return .gray
        }
    }
}

// MARK: - Segmented bar

fileprivate struct SegmentedBar: View {
    let segments: Int
    let filled: Int
    let color: Color
    let height: CGFloat
    let radius: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(i < filled ? color.opacity(0.95) : color.opacity(0.35))
                    .frame(height: height)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        Text("Ячейка календаря — демо")
            .font(.headline)

        CalendarCellMarkersView(markers: [
            .init(workoutType: "swim", plannedLayers: 4, doneLayers: 2, isPlanned: true, isDone: false),
            .init(workoutType: "run", plannedLayers: 3, doneLayers: 3, isPlanned: true, isDone: true),
            .init(workoutType: "bike", plannedLayers: 2, isPlanned: true, isDone: false)
        ])

        Divider()

        CalendarCellMarkersView(
            markers: [
                .init(workoutType: "swim", plannedLayers: 5, doneLayers: 5, isPlanned: true, isDone: true),
                .init(workoutType: "run", plannedLayers: 4, isPlanned: true, isDone: false),
                .init(workoutType: "strength", plannedLayers: 2, isPlanned: true, isDone: false),
                .init(workoutType: "yoga", plannedLayers: 3, isPlanned: true, isDone: false)
            ],
            maxRows: 3
        )
    }
    .padding()
    .frame(width: 220)
}
