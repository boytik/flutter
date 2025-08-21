import SwiftUI
import Charts

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
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

    private var isFuture: Bool { item.date > Date() }
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

                if isFuture {
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
                    .zIndex(2) // ⬅️ всегда над фотоблоком

                    if tab == .charts { chartsSection } else { reviewSection }
                }
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if isFuture {
                await loadPlannedInfo()
            } else {
                await vm.load()
            }
        }
        .sheet(isPresented: $showBeforePicker) { ImagePicker(image: $beforeImage) }
        .sheet(isPresented: $showAfterPicker) { ImagePicker(image: $afterImage) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            headerIcon(name: workout?.name ?? item.name)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(workout?.name ?? item.name)
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
                .padding(.top, 4)

            // ЧСС
            VStack(alignment: .leading, spacing: 10) {
                Text("Диаграмма частоты сердцебиения")
                    .font(.headline).foregroundColor(.white)

                if let hr = vm.heartRateSeries {
                    if let tx = vm.timeSeries, !tx.isEmpty {
                        let count = min(tx.count, hr.count)
                        Chart {
                            ForEach(0..<count, id: \.self) { i in
                                LineMark(x: .value("t", tx[i]), y: .value("bpm", hr[i]))
                            }
                        }
                        .frame(height: 220)
                    } else {
                        Chart {
                            ForEach(hr.indices, id: \.self) { i in
                                LineMark(x: .value("i", Double(i)), y: .value("bpm", hr[i]))
                            }
                        }
                        .frame(height: 220)
                    }
                } else if let url = vm.diagramImageURLs.first(where: {
                    $0.absoluteString.localizedCaseInsensitiveContains("heart")
                    || $0.lastPathComponent.localizedCaseInsensitiveContains("pulse")
                }) {
                    FixedRemoteImage(url: url, aspect: 3/4, corner: 12)
                } else {
                    Text("Нет данных для отображения.")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                }
            }

            // Температура воды
            VStack(alignment: .leading, spacing: 10) {
                Text("Диаграмма температуры воды")
                    .font(.headline).foregroundColor(.white)

                if let wt = vm.waterTempSeries {
                    if let tx = vm.timeSeries, !tx.isEmpty {
                        let count = min(tx.count, wt.count)
                        Chart {
                            ForEach(0..<count, id: \.self) { i in
                                LineMark(x: .value("t", tx[i]), y: .value("°C", wt[i]))
                            }
                        }
                        .frame(height: 220)
                    } else {
                        Chart {
                            ForEach(wt.indices, id: \.self) { i in
                                LineMark(x: .value("i", Double(i)), y: .value("°C", wt[i]))
                            }
                        }
                        .frame(height: 220)
                    }
                } else if let url = vm.diagramImageURLs.first(where: {
                    $0.absoluteString.localizedCaseInsensitiveContains("temp")
                    || $0.absoluteString.localizedCaseInsensitiveContains("water")
                }) {
                    FixedRemoteImage(url: url, aspect: 3/4, corner: 12)
                } else {
                    Text("Нет данных для отображения.")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                }
            }

            // Скорость
            if let spd = vm.speedSeries {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Скорость, км/ч")
                        .font(.headline).foregroundColor(.white)

                    if let tx = vm.timeSeries, !tx.isEmpty {
                        let count = min(tx.count, spd.count)
                        Chart {
                            ForEach(0..<count, id: \.self) { i in
                                LineMark(x: .value("t", tx[i]), y: .value("km/h", spd[i]))
                            }
                        }
                        .frame(height: 180)
                    } else {
                        Chart {
                            ForEach(spd.indices, id: \.self) { i in
                                LineMark(x: .value("i", Double(i)), y: .value("km/h", spd[i]))
                            }
                        }
                        .frame(height: 180)
                    }
                }
            }
        }
    }

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

    private var plannedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(workout?.name ?? item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                Spacer()
            }

            VStack(alignment: .leading, spacing: 16) {
                plannedRow(icon: "calendar",
                           title: "Запланированная дата тренировки:",
                           value: formattedPlannedDate(item.date))

                plannedRow(icon: "timer",
                           title: "Длительность:",
                           value: planned?.durationText ?? "—")

                plannedRow(icon: "square.grid.3x3",
                           title: "Количество слоёв:",
                           value: planned?.layersText ?? "—")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
            )
        }
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

    private func headerIcon(name: String) -> some View {
        let lower = name.lowercased()
        if lower.contains("water") || lower.contains("вода") {
            return AnyView(circleIcon(system: "drop.fill", bg: .blue))
        } else if lower.contains("walk") || lower.contains("run")
                    || lower.contains("ходь") || lower.contains("бег") {
            return AnyView(circleIcon(system: "figure.walk", bg: .orange))
        } else if lower.contains("sauna") || lower.contains("сауна") {
            return AnyView(circleIcon(system: "flame.fill", bg: .red))
        } else if lower.contains("swim") || lower.contains("плав") {
            return AnyView(circleIcon(system: "figure.swim", bg: .cyan))
        } else {
            return AnyView(circleIcon(system: "dumbbell.fill", bg: .gray))
        }
    }

    private func circleIcon(system: String, bg: Color) -> some View {
        ZStack {
            Circle().fill(bg.opacity(0.18))
            Circle().stroke(bg.opacity(0.35), lineWidth: 1)
            Image(systemName: system)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(bg)
        }
    }
}

// MARK: - Локальные фото: две плитки без GeometryReader
private struct PhotoPickRow: View {
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
            .aspectRatio(aspect, contentMode: .fit) // высота → от ширины
            .frame(maxWidth: .infinity)
            .zIndex(0)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Удалённые картинки для диаграмм
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

private struct PlannedInfo {
    let durationHours: Int
    let durationMinutes: Int
    let layers: Int?
    let swimLayers: [Int]?
    let breakDuration: Int?
    let breaks: Int?
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
    }
}
