import SwiftUI
import UIKit
import Charts


extension Notification.Name { static let workoutApproved = Notification.Name("workoutApproved") }

struct WorkoutDetailView: View {
    let item: CalendarItem
    let role: PersonalViewModel.Role

    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable { case charts = "Графики", review = "На проверку" }
    @State private var tab: Tab = .charts

    @State private var comment = ""
    @State private var beforeImage: UIImage?
    @State private var afterImage: UIImage?
    @State private var showBeforePicker = false
    @State private var showAfterPicker = false
    @State private var isSubmitting = false
    @State private var submissionSuccess: Bool?

    @StateObject private var vm: WorkoutDetailViewModel

    /// Как во Flutter: запланированность определяем по типу сущности (Workout), а не по дате
    private var isPlanned: Bool { item.asActivity == nil }

    @State private var planned: PlannedInfo?
    @State private var plannedIsLoading = false

    private var workout: Workout? { item.asWorkout }

    init(item: CalendarItem, role: PersonalViewModel.Role) {
        self.item = item
        self.role = role
        let workoutID = item.asWorkout?.id ?? ""
        _vm = StateObject(wrappedValue: WorkoutDetailViewModel(workoutID: workoutID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if isPlanned {
                    if plannedIsLoading {
                        ProgressView().tint(.white)
                    } else {
                        plannedCard
                    }
                } else {
                    Picker("", selection: $tab) {
                        Text(Tab.charts.rawValue).tag(Tab.charts)
                        if role == .user { Text(Tab.review.rawValue).tag(Tab.review) }
                    }
                    .pickerStyle(.segmented)
                    .tint(.green)
                    .zIndex(2)

                    if tab == .charts { chartsSection } else { reviewSection }
                }
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPlannedInfo()              // для Workout всегда грузим план
            if !isPlanned {                      // если вдруг это Activity — грузим метрики
                await vm.load()
                #if DEBUG
//                await MainActor.run { debugListVMSets(vm) }
                #endif
            }
        }
        .sheet(isPresented: $showBeforePicker) { ImagePicker(image: $beforeImage) }
        .sheet(isPresented: $showAfterPicker) { ImagePicker(image: $afterImage) }
    }

    // MARK: - Header (иконка/имя как в DayItemsSheet)
    private var header: some View {
        HStack(spacing: 12) {
            headerIcon(for: item)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleEN(for: item))
                    .font(.title3.bold())
                    .foregroundColor(.white)
                Text(item.date.formatted(date: .long, time: .shortened))
                    .foregroundColor(.gray)
                    .font(.subheadline)
            }
            Spacer()
        }
    }

    @State private var syncEnabled = false

    // MARK: - Charts (оставлено для done-активностей)
    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if vm.isLoading { ProgressView().tint(.white) }
            if let err = vm.errorMessage, !err.isEmpty {
                Text(err).font(.footnote).foregroundColor(.gray)
            }

            Toggle("Синхронизация", isOn: $syncEnabled)
                .toggleStyle(.switch)
                .tint(.green)
                .foregroundColor(.white)

            // 1) ЧСС
            if let hr = vm.heartRateSeries, !hr.isEmpty {
                ChartSectionView(
                    title: "Диаграмма частоты сердцебиения",
                    unit: "bpm",
                    seriesName: "ЧСС",
                    values: hr,
                    timeOffsets: vm.timeSeries,
                    totalMinutes: vm.preferredDurationMinutes,
                    layer: vm.currentLayerCheckedInt,
                    subLayer: vm.currentSubLayerCheckedInt,
                    subLayerProgress: vm.subLayerProgressText,
                    preferredHeight: 240
                )
            } else if let url = vm.diagramImageURLs.first(where: {
                $0.absoluteString.localizedCaseInsensitiveContains("heart")
                || $0.lastPathComponent.localizedCaseInsensitiveContains("pulse")
            }) {
                sectionTitle("Диаграмма частоты сердцебиения")
                FixedRemoteImage(url: url, aspect: 3/4, corner: 12)
            }

            // 2) Температура воды
            if let wt = vm.waterTempSeries, !wt.isEmpty {
                ChartSectionView(
                    title: "Диаграмма температуры воды",
                    unit: "°C",
                    seriesName: "Температура воды",
                    values: wt,
                    timeOffsets: vm.timeSeries,
                    totalMinutes: vm.preferredDurationMinutes,
                    layer: vm.currentLayerCheckedInt,
                    subLayer: vm.currentSubLayerCheckedInt,
                    subLayerProgress: vm.subLayerProgressText,
                    preferredHeight: 220
                )
            } else if let url = vm.diagramImageURLs.first(where: {
                $0.absoluteString.localizedCaseInsensitiveContains("temp")
                || $0.absoluteString.localizedCaseInsensitiveContains("water")
            }) {
                sectionTitle("Диаграмма температуры воды")
                FixedRemoteImage(url: url, aspect: 3/4, corner: 12)
            }

            // 3) Скорость
            if let spd = vm.speedSeries, !spd.isEmpty {
                ChartSectionView(
                    title: "Скорость, км/ч",
                    unit: "км/ч",
                    seriesName: "Скорость",
                    values: spd,
                    timeOffsets: vm.timeSeries,
                    totalMinutes: vm.preferredDurationMinutes,
                    layer: vm.currentLayerCheckedInt,
                    subLayer: vm.currentSubLayerCheckedInt,
                    subLayerProgress: vm.subLayerProgressText,
                    preferredHeight: 200
                )
            }
        }
    }

    // MARK: - Review (оставлено)
    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            PhotoPickRow(
                beforeImage: $beforeImage,
                afterImage: $afterImage,
                onPickBefore: { showBeforePicker = true },
                onPickAfter: { showAfterPicker = true },
                aspect: 3.0/4.0,
                corner: 18
            )
            .zIndex(0)

            Text("Комментарий")
                .foregroundColor(.white)
                .font(.subheadline)

            TextField("Опишите самочувствие, усилия и т.п.", text: $comment, axis: .vertical)
                .lineLimit(3...6)
                .padding()
                .background(Color(.systemGray6).opacity(0.2))
                .cornerRadius(8)
                .foregroundColor(.white)

            Button {
                Task { await submitReview() }
            } label: {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity).padding()
                } else {
                    Text("Отправить на проверку")
                        .frame(maxWidth: .infinity).padding()
                        .background((beforeImage != nil && afterImage != nil) ? Color.green : Color.gray)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                }
            }
            .disabled(beforeImage == nil || afterImage == nil || isSubmitting)

            if let success = submissionSuccess {
                Text(success ? "Отправлено" : "Ошибка отправки")
                    .foregroundColor(success ? .green : .red)
                    .padding(.top, 6)
            }
        }
    }

    private func submitReview() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        submissionSuccess = nil
        defer { isSubmitting = false }
        try? await Task.sleep(nanoseconds: 300_000_000)
        submissionSuccess = true
    }

    // MARK: - Planned info (для карточки будущей тренировки)
    private func loadPlannedInfo() async {
        plannedIsLoading = true
        defer { plannedIsLoading = false }

        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else { return }

        let ymd = Self.ymd(item.date)
        let url = ApiRoutes.Workouts.calendarDay(email: email, date: ymd)
        do {
            let arr = try await HTTPClient.shared.request([PlannedInfo.DTO].self, url: url)
            let dto = arr.first(where: { $0.workoutUuid == workout?.id })
                ?? arr.first(where: { ($0.date ?? "").hasPrefix(ymd) })
            self.planned = dto.map(PlannedInfo.init(dto:))
        } catch {
            print("Planner load error: \(error)")
        }
    }

    private static func ymd(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .init(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    // тип текущей тренировки (нормализованный)
    private var currentType: String {
        let raw = item.asWorkout?.activityType?.lowercased()
            ?? inferType(from: item.asWorkout?.name ?? item.name)
        return canonicalType(raw)
    }

    // MARK: - ПЛАН — карточка (как во Flutter)
    private var plannedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(titleEN(for: item))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                plannedRow(icon: "calendar",
                           title: "Запланированная дата тренировки:",
                           value: formattedPlannedDate(item.date))

                plannedRow(icon: "timer",
                           title: "Длительность:",
                           value: planned?.durationText ?? "—")

                // ✅ как во Flutter — показываем, если пришло rest_days_after
                if let after = planned?.restDaysAfter {
                    plannedRow(icon: "calendar.badge.clock",
                               title: "Дни отдыха после:",
                               value: "\(after)")
                }

                // (опционально) просто дни отдыха, если есть поле
                if let rd = planned?.restDays {
                    plannedRow(icon: "bed.double.fill",
                               title: "Дни отдыха:",
                               value: "\(rd)")
                }

                // (опционально) тип поста/голодания, если есть
                if let ft = planned?.fastingType, !ft.isEmpty {
                    plannedRow(icon: "fork.knife",
                               title: "Тип поста:",
                               value: ft)
                }

                plannedLayersRow

                if shouldShowProtocolBox {
                    protocolBox
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
            )
        }
    }

    @ViewBuilder
    private var plannedLayersRow: some View {
        let t = currentType
        if t == "water", let arr = planned?.swimLayers, !arr.isEmpty {
            // Вода — показываем массив "1: 5  2: 1 ..."
            let str = arr.enumerated().map { "\($0.offset + 1): \($0.element)" }
                .joined(separator: "  ")
            plannedRow(icon: "square.grid.3x3",
                       title: "Количество слоёв:",
                       value: str)
        } else if let l = planned?.layers {
            plannedRow(icon: "square.grid.3x3",
                       title: "Количество слоёв:",
                       value: "\(l)")
        } else {
            plannedRow(icon: "square.grid.3x3",
                       title: "Количество слоёв:",
                       value: "—")
        }
    }

    // Показываем протокол только для бани и если есть водные слои
    private var shouldShowProtocolBox: Bool {
        currentType == "sauna" && (planned?.swimLayers?.isEmpty == false) && planned?.layers != nil
    }

    @ViewBuilder
    private var protocolBox: some View {
        let water1 = planned?.swimLayers?.first ?? 0
        let saunaL = planned?.layers ?? 0
        let water2 = planned?.swimLayers?.dropFirst().first ?? 0

        VStack(alignment: .leading, spacing: 8) {
            Text("Протокол:")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Комплекс процедур*")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                }

                // горизонтальная лента, чтобы ничего не переносилось и не растягивало экран
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        if water1 > 0 { protocolStep(type: "water", count: water1) }
                        Image(systemName: "chevron.right")
                            .foregroundColor(.white.opacity(0.6))
                        protocolStep(type: "sauna", count: saunaL)
                        if water2 > 0 {
                            Image(systemName: "chevron.right")
                                .foregroundColor(.white.opacity(0.6))
                            protocolStep(type: "water", count: water2)
                        }
                    }
                    .padding(.horizontal, 2)
                }

                Text("*Последовательное выполнение процедур в течение дня с указанным количеством слоёв")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
            )
        }
    }

    private func protocolStep(type: String, count: Int) -> some View {
        VStack(spacing: 6) {
            smallTypeIcon(type)
                .frame(width: 34, height: 34)

            Text(type == "water" ? "Вода" : "Баня")
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))

                VStack(spacing: 0) {
                    Text("\(count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text(pluralLayers(count))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.vertical, 6)
            }
            .frame(width: 66, height: 40)
        }
        .frame(minWidth: 72) // фиксируем ширину, чтобы не ломались подписи
    }

    private func smallTypeIcon(_ type: String) -> some View {
        let system = (type == "water") ? "drop.fill" : "flame.fill"
        let bg: Color = (type == "water") ? .blue : .red
        return ZStack {
            Circle().fill(bg.opacity(0.18))
            Circle().stroke(bg.opacity(0.35), lineWidth: 1)
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(bg)
        }
    }

    private func pluralLayers(_ n: Int) -> String {
        if n == 1 { return "Слой" }
        let d = n % 10, h = n % 100
        if (2...4).contains(d) && !(11...14).contains(h) { return "Слоя" }
        return "Слоёв"
    }

    private func plannedRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Text(value)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
            }
            Spacer()
        }
    }

    private func formattedPlannedDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss EEEE"
        let s = df.string(from: date)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    // MARK: - Header icon & title helpers (паритет с DayItemsSheet)
    @ViewBuilder
    private func headerIcon(for item: CalendarItem) -> some View {
        let baseType = item.asWorkout?.activityType?.lowercased()
            ?? inferType(from: item.asWorkout?.name ?? item.name)
        let t = canonicalType(baseType)

        if let asset = iconAssetName(for: t),
           UIImage(named: asset) != nil {
            circleIcon(image: Image(asset), bg: colorByType(t))
        } else {
            let symbol = glyphSymbolByType(t)
            circleIcon(system: symbol, bg: colorByType(t))
        }
    }

    private func titleEN(for item: CalendarItem) -> String {
        if let raw = item.asWorkout?.activityType?.lowercased(),
           let en = enName(for: canonicalType(raw)) {
            return en
        }
        return enName(for: canonicalType(inferType(from: item.asWorkout?.name ?? item.name)))
            ?? (item.asWorkout?.name ?? item.name)
    }

    private func enName(for type: String) -> String? {
        let map: [String: String] = [
            "swim":"Swim","water":"Water","bike":"Cycling",
            "run":"Run","walk":"Walk","run_walk":"Run/Walk",
            "yoga":"Yoga","strength":"Strength","sauna":"Sauna",
            "fasting":"Fasting","triathlon":"Triathlon"
        ]
        return map[type]
    }

    private func iconAssetName(for type: String) -> String? {
        switch type {
        case "yoga": return "ic_workout_yoga"
        case "run": return "ic_workout_run"
        case "walk": return "ic_workout_walk"
        case "run_walk": return "ic_workout_run"
        case "bike": return "ic_workout_bike"
        case "swim": return "ic_workout_swim"
        case "water": return "ic_workout_water"
        case "strength": return "ic_workout_strength"
        case "sauna": return "ic_workout_sauna"
        case "fasting": return "ic_workout_fast"
        default: return nil
        }
    }

    private func glyphSymbolByType(_ type: String) -> String {
        switch type {
        case "yoga": return "figure.mind.and.body"
        case "run":  return "figure.run"
        case "walk": return "figure.walk"
        case "run_walk": return "figure.run"
        case "bike": return "bicycle"
        case "swim", "water": return "drop.fill"
        case "strength":
            if #available(iOS 16.0, *) { return "dumbbell.fill" } else { return "bolt.heart" }
        case "sauna": return "flame.fill"
        case "fasting": return "fork.knife"
        default: return "dumbbell.fill"
        }
    }

    private func colorByType(_ type: String) -> Color {
        switch type {
        case "yoga": return .purple
        case "run": return .pink
        case "walk": return .orange
        case "run_walk": return .pink
        case "bike": return .mint
        case "swim", "water": return .blue
        case "strength": return .green
        case "sauna": return .red
        case "fasting": return .yellow
        default: return .gray
        }
    }

    private func canonicalType(_ raw: String) -> String {
        let s = raw
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if (s.contains("run") || s.contains("running")) &&
           (s.contains("walk") || s.contains("walking")) { return "run_walk" }

        if s.contains("swim")       { return "swim" }
        if s.contains("water")      { return "water" }
        if s.contains("bike") || s.contains("cycl") { return "bike" }
        if s.contains("running") || s == "run"      { return "run" }
        if s.contains("walking") || s == "walk"     { return "walk" }
        if s.contains("yoga")       { return "yoga" }
        if s.contains("strength") || s.contains("gym") { return "strength" }
        if s.contains("sauna")      { return "sauna" }
        if s.contains("fast") || s.contains("fasting") || s.contains("active") { return "fasting" }
        if s.contains("triathlon")  { return "triathlon" }
        return s
    }

    private func inferType(from name: String) -> String {
        let s = name.lowercased()
        if (s.contains("run") || s.contains("бег")) &&
           (s.contains("walk") || s.contains("ходь")) { return "run_walk" }
        if s.contains("yoga") || s.contains("йога") { return "yoga" }
        if s.contains("run") || s.contains("бег") { return "run" }
        if s.contains("walk") || s.contains("ходь") { return "walk" }
        if s.contains("bike") || s.contains("velo") || s.contains("вел") || s.contains("cycl") { return "bike" }
        if s.contains("swim") || s.contains("плав") { return "swim" }
        if s.contains("water") || s.contains("вода") { return "water" }
        if s.contains("sauna") || s.contains("сауна") { return "sauna" }
        if s.contains("fast") || s.contains("пост") || s.contains("active") { return "fasting" }
        if s.contains("strength") || s.contains("силов") || s.contains("gym") { return "strength" }
        if s.contains("triathlon") { return "triathlon" }
        return ""
    }

    // MARK: - Icon circles
    private func circleIcon(system: String, bg: Color) -> some View {
        ZStack {
            Circle().fill(bg.opacity(0.18))
            Circle().stroke(bg.opacity(0.35), lineWidth: 1)
            Image(systemName: system)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(bg)
        }
    }

    private func circleIcon(image: Image, bg: Color) -> some View {
        ZStack {
            Circle().fill(bg.opacity(0.18))
            Circle().stroke(bg.opacity(0.35), lineWidth: 1)
            image.resizable().scaledToFit().padding(8)
        }
    }
}

// === Общий компонент графика с разворотом и метриками ===
private struct ChartSectionView: View {
    let title: String
    let unit: String
    let seriesName: String

    let values: [Double]
    /// секунды от старта (если окажется unix, замените на Date(timeIntervalSince1970:))
    let timeOffsets: [Double]?

    /// Общее время тренировки (минуты)
    let totalMinutes: Int?

    /// слой/подслой (и строка формата 6/7)
    let layer: Int?
    let subLayer: Int?
    let subLayerProgress: String?

    var preferredHeight: CGFloat = 220

    @State private var selectedIndex: Int? = nil
    @State private var showFull = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title)

            metricsHeader

            ZStack(alignment: .topTrailing) {
                chart.frame(height: preferredHeight)

                Button {
                    showFull = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(6)
            }
        }
        .fullScreenCover(isPresented: $showFull) {
            FullScreenChartsView(series: [ChartSeries(name: seriesName, points: makePoints())])
        }
    }

    private var metricsHeader: some View {
        let i = selectedIndex ?? (values.indices.last ?? 0)
        let val = valueString(at: i)

        return HStack(spacing: 16) {
            metric("Время", (totalMinutes != nil ? "\(totalMinutes!)  мин" : "—"), boldLeft: true)
            Divider().frame(height: 16).background(Color.white.opacity(0.2))
            metric("Слой", layer.map(String.init) ?? "—", highlight: true)
            metric("Подслой", subLayerProgress ?? subLayer.map(String.init) ?? "—", subdued: layer == nil)
            Spacer()
            metric(seriesName, val, highlight: true, unitSuffix: unit)
        }
        .font(.footnote)
        .foregroundColor(.white)
        .padding(.vertical, 4)
    }

    private var chart: some View {
        Chart {
            let pts = makePoints()
            ForEach(pts) { p in
                AreaMark(x: .value("t", p.time), y: .value("v", p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(colors: [.green.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("t", p.time), y: .value("v", p.value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.0))
            }
            if let idx = selectedIndex, pts.indices.contains(idx) {
                let sp = pts[idx]
                RuleMark(x: .value("t", sp.time))
                PointMark(x: .value("t", sp.time), y: .value("v", sp.value)).symbolSize(80)
            }
        }
        
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let origin = geo[proxy.plotAreaFrame].origin
                                let x = value.location.x - origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    let pts = makePoints()
                                    if let idx = nearestIndex(in: pts, to: date) {
                                        selectedIndex = idx
                                    }
                                }
                            }
                    )
            }
        }
    }

    // Helpers
    private func metric(_ title: String, _ value: String, boldLeft: Bool = false, highlight: Bool = false, subdued: Bool = false, unitSuffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(boldLeft ? .subheadline.bold() : .subheadline).foregroundColor(.white.opacity(0.75))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.body.weight(.semibold)).foregroundColor(highlight ? .green : (subdued ? .white.opacity(0.6) : .white))
                if let unitSuffix { Text(unitSuffix).font(.caption).foregroundColor(.white.opacity(0.7)) }
            }
        }
    }

    private func makePoints() -> [ChartPoint] {
        let start = Date()
        if let t = timeOffsets, !t.isEmpty {
            let cnt = min(t.count, values.count)
            return (0..<cnt).map { i in ChartPoint(time: start.addingTimeInterval(t[i]), value: values[i]) }
        } else {
            return values.enumerated().map { (i, v) in ChartPoint(time: start.addingTimeInterval(Double(i)), value: v) }
        }
    }

    private func valueString(at index: Int) -> String {
        guard index < values.count else { return "—" }
        let v = values[index]
        if abs(v) >= 1000 { return String(format: "%.0f", v) }
        if abs(v) >= 100  { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }

    private func nearestIndex(in points: [ChartPoint], to t: Date) -> Int? {
        guard !points.isEmpty else { return nil }
        let times = points.map { $0.time.timeIntervalSinceReferenceDate }
        var lo = 0, hi = times.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if times[mid] < t.timeIntervalSinceReferenceDate { lo = mid + 1 } else { hi = mid }
        }
        let i = lo
        if i == 0 { return 0 }
        if i >= times.count { return times.count - 1 }
        let a = times[i - 1], b = times[i]
        return (abs(a - t.timeIntervalSinceReferenceDate) <= abs(b - t.timeIntervalSinceReferenceDate)) ? (i - 1) : i
    }
}

// MARK: - Локальные фото: две плитки
 struct PhotoPickRow: View {
    @Binding var beforeImage: UIImage?
    @Binding var afterImage: UIImage?
    let onPickBefore: () -> Void
    let onPickAfter: () -> Void

    var aspect: CGFloat = 3.0/4.0
    var corner: CGFloat = 18
    var spacing: CGFloat = 12

    var body: some View {
        HStack(spacing: spacing) {
            PhotoPickTileSimple(title: "Фото ДО тренировки",
                                image: beforeImage,
                                action: onPickBefore,
                                aspect: aspect,
                                corner: corner,
                                accent: Color.white.opacity(0.14))
            PhotoPickTileSimple(title: "Фото ПОСЛЕ тренировки",
                                image: afterImage,
                                action: onPickAfter,
                                aspect: aspect,
                                corner: corner,
                                accent: .green)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
        .zIndex(0)
    }
}

private struct PhotoPickTileSimple: View {
    let title: String
    let image: UIImage?
    let action: () -> Void
    var aspect: CGFloat
    var corner: CGFloat
    var accent: Color

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.white.opacity(0.06))

                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 28, weight: .semibold))
                        Text("Выберите фото")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .foregroundColor(.white.opacity(0.6))
                }

                HStack {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(accent)
                        )
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(8)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .zIndex(0)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Удалённые картинки Fallback
private struct FixedRemoteImage: View {
    let url: URL?
    var aspect: CGFloat = 3.0/4.0
    var corner: CGFloat = 12

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url, transaction: .init(animation: .easeInOut)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(.white)
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspect, contentMode: .fill)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.white.opacity(0.06))
            Image(systemName: "photo")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
        }
        .aspectRatio(aspect, contentMode: .fit)
    }
}

// MARK: - DTOs/planned info
private struct PlannedInfo {
    let durationHours: Int
    let durationMinutes: Int
    let layers: Int?
    let swimLayers: [Int]?
    let breakDuration: Int?
    let breaks: Int?

    // ⬇️ Новые поля как во Flutter
    let restDaysAfter: Int?
    let restDays: Int?
    let fastingType: String?
    let type: String?
    let protocolName: String?

    var durationText: String {
        if durationHours == 0 && durationMinutes == 0 { return "—" }
        if durationHours == 0 { return "\(durationMinutes) м" }
        if durationMinutes == 0 { return "\(durationHours) ч" }
        return "\(durationHours) ч \(durationMinutes) м"
    }

    var layersText: String {
        if let arr = swimLayers, !arr.isEmpty {
            return arr.enumerated().map { "\($0.offset+1): \($0.element)" }.joined(separator: "  ")
        }
        if let l = layers { return "\(l)" }
        return "—"
    }

    struct DTO: Decodable {
        let workoutUuid: String?
        let date: String?
        let durationMinutes: Int?
        let durationHours: Int?
        let breakDuration: Int?
        let breaks: Int?
        let layers: Int?
        let swimLayers: [Int]?
        let type: String?
        let `protocol`: String?

        // ⬇️ Новые поля из Flutter-модели
        let restDaysAfter: Int?   // JSON: rest_days_after
        let restDays: Int?        // JSON: rest_days
        let fastingType: String?  // JSON: fasting_type

        enum CodingKeys: String, CodingKey {
            case workoutUuid       = "workout_uuid"
            case date
            case durationMinutes   = "duration_minutes"
            case durationHours     = "duration_hours"
            case breakDuration     = "break_duration"
            case breaks
            case layers
            case swimLayers        = "swim_layers"
            case type
            case `protocol`
            case restDaysAfter     = "rest_days_after"
            case restDays          = "rest_days"
            case fastingType       = "fasting_type"
        }
    }

    init(dto: DTO) {
        self.durationHours = dto.durationHours ?? 0
        self.durationMinutes = dto.durationMinutes ?? 0
        self.breakDuration = dto.breakDuration
        self.breaks = dto.breaks
        self.layers = dto.layers
        self.swimLayers = dto.swimLayers
        self.type = dto.type
        self.protocolName = dto.`protocol`

        // ⬇️ Новые поля
        self.restDaysAfter = dto.restDaysAfter
        self.restDays = dto.restDays
        self.fastingType = dto.fastingType
    }
}

// MARK: - Small view helpers
private func sectionTitle(_ text: String) -> some View {
    Text(text).font(.headline).foregroundColor(.white)
}

