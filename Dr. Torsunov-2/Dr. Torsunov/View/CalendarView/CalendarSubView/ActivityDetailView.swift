import SwiftUI
import UIKit
import Charts

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

struct ActivityDetailView: View {
    let activity: Activity
    let role: PersonalViewModel.Role

    enum Tab: String, CaseIterable { case charts = "Графики", review = "На проверку" }
    @State private var tab: Tab = .charts

    @State private var comment = ""
    @State private var beforeImage: UIImage?
    @State private var afterImage: UIImage?
    @State private var showBeforePicker = false
    @State private var showAfterPicker  = false
    @State private var isSubmitting = false
    @State private var submissionSuccess: Bool?

    @StateObject private var vm: WorkoutDetailViewModel
    @State private var syncEnabled = false

    init(activity: Activity, role: PersonalViewModel.Role) {
        self.activity = activity
        self.role = role
        let key = ActivityDetailView.extractWorkoutKey(from: activity) ?? ""
        _vm = StateObject(wrappedValue: WorkoutDetailViewModel(workoutID: key))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection

                Picker("", selection: $tab) {
                    Text(Tab.charts.rawValue).tag(Tab.charts)
                    if role == .user { Text(Tab.review.rawValue).tag(Tab.review) }
                }
                .pickerStyle(.segmented)
                .tint(.green)

                if tab == .charts {
                    chartsSection
                } else {
                    photosSection
                    commentSection
                    submitButton
                }

                if let success = submissionSuccess {
                    Text(success ? L("submit_success") : L("submit_error"))
                        .foregroundColor(success ? .green : .red)
                        .padding(.top, 6)
                }
            }
            .padding()
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
        HStack {
            Text("✅")
                .font(.title)
                .frame(width: 44, height: 44)
                .background(Color.green.opacity(0.2))
                .clipShape(Circle())

            VStack(alignment: .leading) {
                Text(activity.name ?? "Activity")
                    .font(.headline)
                    .foregroundColor(.white)

                if let description = activity.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                if let date = activity.createdAt {
                    Text(date.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.gray)
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
                                AreaMark(x: .value("t", tx[i]), y: .value("bpm", hr[i]))
                                    .opacity(0.15)
                                LineMark(x: .value("t", tx[i]), y: .value("bpm", hr[i]))
                            }
                        }
                        .frame(height: 220)
                        .chartXAxisLabel("Время", alignment: .trailing)
                        .chartYAxisLabel("bpm")
                    } else {
                        Chart {
                            ForEach(hr.indices, id: \.self) { i in
                                AreaMark(x: .value("i", Double(i)), y: .value("bpm", hr[i]))
                                    .opacity(0.15)
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
                                AreaMark(x: .value("t", tx[i]), y: .value("°C", wt[i]))
                                    .opacity(0.15)
                                LineMark(x: .value("t", tx[i]), y: .value("°C", wt[i]))
                            }
                        }
                        .frame(height: 220)
                        .chartXAxisLabel("Время", alignment: .trailing)
                        .chartYAxisLabel("°C")
                    } else {
                        Chart {
                            ForEach(wt.indices, id: \.self) { i in
                                AreaMark(x: .value("i", Double(i)), y: .value("°C", wt[i]))
                                    .opacity(0.15)
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

    // MARK: Photos + Comment + Submit
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
                        .frame(height: 150)
                    if let img = image.wrappedValue {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(height: 150)
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
