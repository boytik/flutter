import SwiftUI
import Charts

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
extension Notification.Name { static let workoutApproved = Notification.Name("workoutApproved") }

struct WorkoutDetailView: View {
    let item: CalendarItem
    let role: PersonalViewModel.Role

    @Environment(\.dismiss) private var dismiss

    // MARK: Tabs
    enum Tab: String, CaseIterable { case charts = "Графики", review = "На проверку" }
    @State private var tab: Tab = .charts

    // MARK: Review state
    @State private var comment = ""
    @State private var beforeImage: UIImage?
    @State private var afterImage: UIImage?
    @State private var showBeforePicker = false
    @State private var showAfterPicker = false
    @State private var isSubmitting = false
    @State private var submissionSuccess: Bool?

    // MARK: VM (метаданные/метрики)
    @StateObject private var vm: WorkoutDetailViewModel

    // MARK: Planned (для будущих тренировок)
    private var isFuture: Bool { item.date > Date() }
    @State private var planned: PlannedInfo?
    @State private var plannedIsLoading = false

    // MARK: Init
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
                    // ---- БУДУЩАЯ ТРЕНИРОВКА ----
                    if plannedIsLoading {
                        ProgressView().tint(.white)
                    } else {
                        plannedCard
                    }
                } else {
                    // ---- ПРОШЕДШАЯ (ИСТОРИЯ) ----
                    Picker("", selection: $tab) {
                        Text(Tab.charts.rawValue).tag(Tab.charts)
                        if role == .user { Text(Tab.review.rawValue).tag(Tab.review) }
                    }
                    .pickerStyle(.segmented)
                    .tint(.green)

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
                await vm.load() // тянет /metadata и /get_diagram_data (с фолбэком)
            }
        }
        .sheet(isPresented: $showBeforePicker) { ImagePicker(image: $beforeImage) }
        .sheet(isPresented: $showAfterPicker) { ImagePicker(image: $afterImage) }
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 12) {
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

    // MARK: Charts
    @State private var syncEnabled = false

    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if vm.isLoading { ProgressView().tint(.white) }

            // краткая ошибка, если была (например, Server error (500) для /metadata)
            if let err = vm.errorMessage, !err.isEmpty {
                Text(err).font(.footnote).foregroundColor(.gray)
            }

            Toggle("Синхронизация", isOn: $syncEnabled)
                .toggleStyle(.switch)
                .tint(.green)
                .foregroundColor(.white)
                .padding(.top, 4)

            // 1) Пульс
            VStack(alignment: .leading, spacing: 10) {
                Text("Диаграмма частоты сердцебиения")
                    .font(.headline).foregroundColor(.white)

                if let hr = vm.heartRateSeries {
                    if let tx = vm.timeSeries, !tx.isEmpty {
                        let count = min(tx.count, hr.count)
                        Chart {
                            ForEach(0..<count, id: \.self) { i in
                                LineMark(
                                    x: .value("t", tx[i]),
                                    y: .value("bpm", hr[i])
                                )
                            }
                        }
                        .frame(height: 220)
                    } else {
                        // фолбэк: ось X — индекс
                        Chart {
                            ForEach(hr.indices, id: \.self) { i in
                                LineMark(
                                    x: .value("i", Double(i)),
                                    y: .value("bpm", hr[i])
                                )
                            }
                        }
                        .frame(height: 220)
                    }
                } else if let url = vm.diagramImageURLs.first(where: {
                    $0.absoluteString.localizedCaseInsensitiveContains("heart")
                    || $0.lastPathComponent.localizedCaseInsensitiveContains("pulse")
                }) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: { ProgressView().tint(.white) }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("Нет данных для отображения.")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                }
            }

            // 2) Температура воды
            VStack(alignment: .leading, spacing: 10) {
                Text("Диаграмма температуры воды")
                    .font(.headline).foregroundColor(.white)

                if let wt = vm.waterTempSeries {
                    if let tx = vm.timeSeries, !tx.isEmpty {
                        let count = min(tx.count, wt.count)
                        Chart {
                            ForEach(0..<count, id: \.self) { i in
                                LineMark(
                                    x: .value("t", tx[i]),
                                    y: .value("°C", wt[i])
                                )
                            }
                        }
                        .frame(height: 220)
                    } else {
                        Chart {
                            ForEach(wt.indices, id: \.self) { i in
                                LineMark(
                                    x: .value("i", Double(i)),
                                    y: .value("°C", wt[i])
                                )
                            }
                        }
                        .frame(height: 220)
                    }
                } else if let url = vm.diagramImageURLs.first(where: {
                    $0.absoluteString.localizedCaseInsensitiveContains("temp")
                    || $0.absoluteString.localizedCaseInsensitiveContains("water")
                }) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: { ProgressView().tint(.white) }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("Нет данных для отображения.")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                }
            }

            // 3) Скорость (если есть)
            if let spd = vm.speedSeries {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Скорость, км/ч")
                        .font(.headline).foregroundColor(.white)

                    if let tx = vm.timeSeries, !tx.isEmpty {
                        let count = min(tx.count, spd.count)
                        Chart {
                            ForEach(0..<count, id: \.self) { i in
                                LineMark(
                                    x: .value("t", tx[i]),
                                    y: .value("km/h", spd[i])
                                )
                            }
                        }
                        .frame(height: 180)
                    } else {
                        Chart {
                            ForEach(spd.indices, id: \.self) { i in
                                LineMark(
                                    x: .value("i", Double(i)),
                                    y: .value("km/h", spd[i])
                                )
                            }
                        }
                        .frame(height: 180)
                    }
                }
            }
        }
    }

    // MARK: Review
    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 14) {
                uploadBlock(title: "Загрузите фото ДО тренировки", image: $beforeImage, showPicker: $showBeforePicker)
                uploadBlock(title: "Загрузите фото ПОСЛЕ тренировки", image: $afterImage, showPicker: $showAfterPicker)
            }

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

    private func uploadBlock(title: String, image: Binding<UIImage?>, showPicker: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).foregroundColor(.white).font(.subheadline)
            Button { showPicker.wrappedValue = true } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6).opacity(0.2))
                        .frame(height: 150)
                    if let img = image.wrappedValue {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40)).foregroundColor(.gray)
                    }
                }
            }
        }
    }

    // MARK: – Отправка на проверку (пока заглушка)
    private func submitReview() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        submissionSuccess = nil
        defer { isSubmitting = false }
        try? await Task.sleep(nanoseconds: 300_000_000)
        submissionSuccess = true
    }

    // MARK: - FUTURE: загрузка запланированной информации
    private func loadPlannedInfo() async {
        plannedIsLoading = true
        defer { plannedIsLoading = false }

        guard let email = TokenStorage.shared.currentEmail(), !email.isEmpty else { return }

        let ymd = Self.ymd(item.date)
        let url = ApiRoutes.Workouts.calendarDay(email: email, date: ymd)
        do {
            // локальный DTO, чтобы не конфликтовать с другими типами
            let arr = try await HTTPClient.shared.request([PlannedInfo.DTO].self, url: url)
            // сначала пробуем сопоставить по workout_uuid
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

    // Представление карточки запланированной тренировки
    private var plannedCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Запланированная тренировка").font(.headline).foregroundColor(.white)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 10) {
                Tag(text: workout?.name ?? item.name)

                KVRow(key: "Запланированная дата тренировки:",
                      value: item.date.formatted(date: .long, time: .standard))

                KVRow(key: "Длительность:", value: planned?.durationText ?? "—")
                KVRow(key: "Количество слоёв:", value: planned?.layersText ?? "—")

                if let bd = planned?.breakDuration { KVRow(key: "Продолжительность перерыва:", value: "\(bd)") }
                if let br = planned?.breaks { KVRow(key: "Перерывы:", value: "\(br)") }
                if let t = planned?.type, !t.isEmpty { KVRow(key: "Тип:", value: t) }
                if let p = planned?.protocolName, !p.isEmpty { KVRow(key: "Протокол:", value: p) }
            }
            .padding()
            .background(Color(.systemGray6).opacity(0.12))
            .cornerRadius(12)
        }
    }
}

// MARK: - Вспомогательные UI
private struct KVRow: View {
    let key: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key).font(.subheadline.bold()).foregroundColor(.white)
                .frame(width: 180, alignment: .leading)
            Text(value).font(.subheadline).foregroundColor(.gray)
                .multilineTextAlignment(.leading)
            Spacer()
        }
    }
}

private struct Tag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .foregroundColor(.white)
            .clipShape(Capsule())
    }
}

// MARK: - Локальные модели для Planned
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

    // Вложенный DTO, чтобы не конфликтовать с другими типами проекта
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
        self.layers = dto.layers
        self.swimLayers = dto.swimLayers
        self.breakDuration = dto.breakDuration
        self.breaks = dto.breaks
        self.type = dto.type
        self.protocolName = dto.protocol
    }
}
