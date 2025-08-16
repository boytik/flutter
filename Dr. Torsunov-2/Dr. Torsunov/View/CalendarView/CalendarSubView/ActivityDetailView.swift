import SwiftUI
import UIKit
import Charts

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

struct ActivityDetailView: View {
    let activity: Activity
    let role: PersonalViewModel.Role

    enum Tab: String, Hashable { case charts, photos, review }
    @State private var tab: Tab = .charts

    // USER: загрузка фото/коммента
    @State private var comment = ""
    @State private var beforeImage: UIImage?
    @State private var afterImage: UIImage?
    @State private var showBeforePicker = false
    @State private var showAfterPicker  = false
    @State private var isSubmitting = false
    @State private var submissionSuccess: Bool?

    // Графики
    @StateObject private var vm: WorkoutDetailViewModel
    @State private var syncEnabled = false

    init(activity: Activity, role: PersonalViewModel.Role) {
        self.activity = activity
        self.role = role
        let key = ActivityDetailView.extractWorkoutKey(from: activity) ?? activity.id
        _vm = StateObject(wrappedValue: WorkoutDetailViewModel(workoutID: key))
    }

    private var availableTabs: [Tab] { role == .inspector ? [.charts, .photos] : [.charts, .review] }
    private func tabTitle(_ t: Tab) -> String { t == .charts ? "Графики" : (t == .photos ? "Фото" : "На проверку") }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection

                Picker("", selection: $tab) {
                    ForEach(availableTabs, id: \.self) { Text(tabTitle($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .tint(.green)

                switch tab {
                case .charts:
                    chartsSection
                case .photos:
                    InspectorPhotosTab(activity: activity) // переработанная вкладка
                case .review:
                    photosSection
                    commentSection
                    submitButton
                }

                if let success = submissionSuccess, role != .inspector {
                    Text(success ? L("submit_success") : L("submit_error"))
                        .foregroundColor(success ? .green : .red)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 24) // запас снизу для прокрутки
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showBeforePicker) { ImagePicker(image: $beforeImage) }
        .sheet(isPresented: $showAfterPicker)  { ImagePicker(image: $afterImage) }
        .onAppear { comment = activity.description ?? "" }
        .task { await vm.load() }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header
    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.green.opacity(0.2))
                Text("✅").font(.title2)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.name ?? "Activity")
                    .font(.headline)
                    .foregroundColor(.white)

                if let date = activity.createdAt {
                    Text(date.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            Spacer()
        }
    }

    // MARK: Charts
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

            // Пульс
            VStack(alignment: .leading, spacing: 10) {
                Text("Диаграмма частоты сердцебиения")
                    .font(.headline).foregroundColor(.white)

                if let hr = vm.heartRateSeries {
                    if let tx = vm.timeSeries, !tx.isEmpty {
                        let count = min(tx.count, hr.count)
                        Chart {
                            ForEach(0..<count, id: \.self) { i in
                                AreaMark(x: .value("t", tx[i]), y: .value("bpm", hr[i])).opacity(0.15)
                                LineMark(x: .value("t", tx[i]), y: .value("bpm", hr[i]))
                            }
                        }
                        .frame(height: 220)
                        .chartXAxisLabel("Время", alignment: .trailing)
                        .chartYAxisLabel("bpm")
                    } else {
                        Chart {
                            ForEach(hr.indices, id: \.self) { i in
                                AreaMark(x: .value("i", Double(i)), y: .value("bpm", hr[i])).opacity(0.15)
                                LineMark(x: .value("i", Double(i)), y: .value("bpm", hr[i]))
                            }
                        }
                        .frame(height: 220)
                        .chartXAxisLabel("Индекс", alignment: .trailing)
                        .chartYAxisLabel("bpm")
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
                        .foregroundColor(.gray).font(.subheadline)
                }
            }

            // Температура воды (если есть)
            VStack(alignment: .leading, spacing: 10) {
                Text("Диаграмма температуры воды")
                    .font(.headline).foregroundColor(.white)

                if let wt = vm.waterTempSeries {
                    if let tx = vm.timeSeries, !tx.isEmpty {
                        let count = min(tx.count, wt.count)
                        Chart {
                            ForEach(0..<count, id: \.self) { i in
                                AreaMark(x: .value("t", tx[i]), y: .value("°C", wt[i])).opacity(0.15)
                                LineMark(x: .value("t", tx[i]), y: .value("°C", wt[i]))
                            }
                        }
                        .frame(height: 220)
                        .chartXAxisLabel("Время", alignment: .trailing)
                        .chartYAxisLabel("°C")
                    } else {
                        Chart {
                            ForEach(wt.indices, id: \.self) { i in
                                AreaMark(x: .value("i", Double(i)), y: .value("°C", wt[i])).opacity(0.15)
                                LineMark(x: .value("i", Double(i)), y: .value("°C", wt[i]))
                            }
                        }
                        .frame(height: 220)
                        .chartXAxisLabel("Индекс", alignment: .trailing)
                        .chartYAxisLabel("°C")
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
                        .foregroundColor(.gray).font(.subheadline)
                }
            }
        }
    }

    // MARK: USER (как и раньше)
    private var photosSection: some View {
        VStack(spacing: 14) {
            uploadSection(title: L("photo_before"), image: $beforeImage, showPicker: $showBeforePicker)
            uploadSection(title: L("photo_after"),  image: $afterImage,  showPicker: $showAfterPicker)
        }
    }

    private func uploadSection(title: String, image: Binding<UIImage?>, showPicker: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).foregroundColor(.white).font(.subheadline)
            Button(action: { showPicker.wrappedValue = true }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6).opacity(0.2))
                        .frame(height: 160)
                    if let img = image.wrappedValue {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("comment_label"))
                .foregroundColor(.white)
                .font(.subheadline)

            TextField(L("enter_comment_placeholder"), text: $comment, axis: .vertical)
                .lineLimit(3...6)
                .padding()
                .background(Color(.systemGray6).opacity(0.2))
                .cornerRadius(8)
                .foregroundColor(.white)
        }
    }

    private var submitButton: some View {
        Button(action: submitData) {
            if isSubmitting {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Text(L("submit"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background((beforeImage != nil && afterImage != nil) ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .disabled(beforeImage == nil || afterImage == nil || isSubmitting)
    }

    private func submitData() {
        guard !isSubmitting else { return }
        isSubmitting = true
        submissionSuccess = nil
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                isSubmitting = false
                submissionSuccess = true
            }
        }
    }

    // Достаём workoutKey из Activity
    private static func extractWorkoutKey(from activity: Activity) -> String? {
        let mirror = Mirror(reflecting: activity)
        for child in mirror.children {
            guard let label = child.label?.lowercased() else { continue }
            let isCandidate =
                (label.contains("workout") && (label.contains("key") || label.contains("uuid") || label.hasSuffix("id")))
                || label == "id" || label == "uuid"
            if isCandidate, let s = child.value as? String, !s.isEmpty { return s }
        }
        return nil
    }
}

// MARK: - Вкладка «Фото» для инспектора
private struct InspectorPhotosTab: View {
    let activity: Activity
    var mediaRepo: WorkoutMediaRepository = WorkoutMediaRepositoryImpl()
    var inspectorRepo: InspectorRepository = InspectorRepositoryImpl()

    @State private var beforeURL: URL?
    @State private var afterURL: URL?
    @State private var existingLayer: Int?
    @State private var existingSub: Int?
    @State private var textComment: String = ""
    @State private var level: Int = 0
    @State private var sublevel: Int = 0
    @State private var isSending = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 18) {
            // Фото
            HStack(spacing: 16) {
                photoBox(title: "Фото ДО тренировки", url: beforeURL)
                photoBox(title: "Фото ПОСЛЕ тренировки", url: afterURL)
            }
            .frame(height: 220)

            // Слои/подслои
            if let l = existingLayer, let s = existingSub {
                HStack {
                    Text("Слой: \(l)")
                    Spacer(minLength: 12)
                    Text("Подслой: \(s)")
                    Spacer()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Выберите слой")
                        .foregroundColor(.white.opacity(0.9))
                        .fontWeight(.semibold)
                    HStack(spacing: 12) {
                        picker(title: "Слой", range: 0...10, selection: $level)
                        picker(title: "Подслой", range: 0...6, selection: $sublevel)
                        Spacer(minLength: 0)
                    }
                }
            }

            // Комментарий
            VStack(alignment: .leading, spacing: 8) {
                Text("Введите комментарий")
                    .foregroundColor(.white.opacity(0.8))
                TextEditor(text: $textComment)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 160)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(.white)
            }

            if let err = loadError {
                Text(err).foregroundColor(.red).font(.footnote)
            }

            // запас места под «плавающую» кнопку
            Spacer(minLength: 80)
        }
        .onAppear { Task { await loadMedia() } }
        .safeAreaInset(edge: .bottom) { sendBar } // фиксированная кнопка над таббаром
    }

    // Нижняя панель с кнопкой
    private var sendBar: some View {
        HStack {
            Button(action: send) {
                HStack {
                    if isSending { ProgressView().tint(.black) }
                    Text("Отправить").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.green)
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isSending || (existingLayer != nil))
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial) // лёгкая подложка над таббаром
    }

    // MARK: Data
    private func loadMedia() async {
        let email = activity.userEmail ?? ""
        do {
            let m = try await mediaRepo.fetch(workoutId: activity.id, email: email)
            await MainActor.run {
                beforeURL = m.before
                afterURL  = m.after
                existingLayer = m.currentLayerChecked
                existingSub   = m.currentSubLayerChecked
                textComment   = m.comment ?? ""
            }
        } catch {
            await MainActor.run { loadError = "Ошибка загрузки фото: \(error.localizedDescription)" }
        }
    }

    private func send() {
        Task {
            guard !isSending else { return }
            await MainActor.run { isSending = true }
            let email = activity.userEmail ?? ""
            do {
                try await inspectorRepo.sendLayers(
                    workoutId: activity.id,
                    email: email,
                    level: level,
                    sublevel: sublevel,
                    comment: textComment
                )
                await MainActor.run {
                    existingLayer = level
                    existingSub   = sublevel
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    loadError = "Не удалось отправить данные: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: UI helpers
    @ViewBuilder
    private func photoBox(title: String, url: URL?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline).foregroundColor(.white.opacity(0.9))
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)

                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty: ProgressView().tint(.white)
                        case .success(let img): img.resizable().scaledToFill()
                        case .failure: Image(systemName: "photo").resizable().scaledToFit().padding(24)
                        @unknown default: EmptyView()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    Image(systemName: "photo")
                        .resizable().scaledToFit().padding(24)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func picker(title: String, range: ClosedRange<Int>, selection: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundColor(.white.opacity(0.9))
            Picker(title, selection: selection) {
                ForEach(Array(range), id: \.self) { v in
                    Text("\(v)").tag(v)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .frame(width: 120)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
