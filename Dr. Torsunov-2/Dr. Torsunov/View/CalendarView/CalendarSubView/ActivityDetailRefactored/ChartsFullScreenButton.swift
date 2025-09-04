import SwiftUI

/// Кнопка, открывающая графики на весь экран.
/// Встраивается в любой тулбар/хедер/вью, где есть доступ к данным графиков.
///
/// Пример использования:
/// ChartsFullScreenButton(series: buildSeries())
///     .buttonStyle(.bordered)
public struct ChartsFullScreenButton: View {
    let series: [ChartSeries]
    let title: String
    let systemImage: String

    @State private var isPresented = false

    public init(
        series: [ChartSeries],
        title: String = "На весь экран",
        systemImage: String = "arrow.up.left.and.arrow.down.right"
    ) {
        self.series = series
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        }
        .fullScreenCover(isPresented: $isPresented) {
            FullScreenChartsView(series: series)
        }
        .accessibilityIdentifier("charts_fullscreen_button")
    }
}

#Preview {
    // Мини‑демо
    let now = Date()
    let s1 = ChartSeries(
        name: "ЧСС",
        points: (0..<300).map { i in
            let t = now.addingTimeInterval(Double(i) * 5)
            let val = 120 + 15 * sin(Double(i) / 15)
            return ChartPoint(time: t, value: val)
        }
    )
    let s2 = ChartSeries(
        name: "Темп",
        points: (0..<300).map { i in
            let t = now.addingTimeInterval(Double(i) * 5)
            let val = 6.0 - 0.4 * sin(Double(i) / 12)
            return ChartPoint(time: t, value: val)
        }
    )
    return NavigationStack {
        VStack(spacing: 16) {
            Text("Детали тренировки")
            ChartsFullScreenButton(series: [s1, s2])
                .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Тренировка")
    }
}
