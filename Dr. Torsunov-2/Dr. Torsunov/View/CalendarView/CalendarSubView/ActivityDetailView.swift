import SwiftUI
import UIKit
import Charts

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

struct ActivityDetailView: View {
    let activity: Activity
    let role: PersonalViewModel.Role

    enum Tab: String, Hashable { case charts, photos, review }
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
        let key = ActivityDetailView.extractWorkoutKey(from: activity) ?? activity.id
        _vm = StateObject(wrappedValue: WorkoutDetailViewModel(workoutID: key))
    }

    private var availableTabs: [Tab] { role == .inspector ? [.charts, .photos] : [.charts, .review] }
    private func tabTitle(_ t: Tab) -> String { t == .charts ? "Графики" : (t == .photos ? "Фото" : "На проверку") }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection

                // Сегмент-контрол всегда над контентом
                Picker("", selection: $tab) {
                    ForEach(availableTabs, id: \.self) { Text(tabTitle($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .tint(.green)
                .zIndex(3)

                switch tab {
                case .charts:
                    chartsSection

                case .photos:
                    // ВАЖНО: чистая вью без safeAreaInset/материалов
                    InspectorPhotosView(activity: activity)
                        .background(Color.clear)

                case .review:
                    PhotoPickRow(
                        beforeImage: $beforeImage,
                        afterImage:  $afterImage,
                        onPickBefore: { showBeforePicker = true },
                        onPickAfter:  { showAfterPicker  = true },
                        aspect: 3.0/4.0,
                        corner: 18
                    )
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
            .padding(.bottom, 24)
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
                    } else {
                        Chart {
                            ForEach(hr.indices, id: \.self) { i in
                                AreaMark(x: .value("i", Double(i)), y: .value("bpm", hr[i])).opacity(0.15)
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
                        .foregroundColor(.gray).font(.subheadline)
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
                                AreaMark(x: .value("t", tx[i]), y: .value("°C", wt[i])).opacity(0.15)
                                LineMark(x: .value("t", tx[i]), y: .value("°C", wt[i]))
                            }
                        }
                        .frame(height: 220)
                    } else {
                        Chart {
                            ForEach(wt.indices, id: \.self) { i in
                                AreaMark(x: .value("i", Double(i)), y: .value("°C", wt[i])).opacity(0.15)
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
                        .foregroundColor(.gray).font(.subheadline)
                }
            }
        }
    }

    // MARK: User review (если роль не инспектор)
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
        Button {
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
        } label: {
            Text(L("submit"))
                .frame(maxWidth: .infinity)
                .padding()
                .background((beforeImage != nil && afterImage != nil) ? Color.green : Color.gray,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(.white)
        }
        .disabled(beforeImage == nil || afterImage == nil || isSubmitting)
    }

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

// === Локальные хелперы для выбора фото (user) ===
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
            PhotoPickTileSimple(title: L("photo_before"), image: beforeImage, action: onPickBefore, aspect: aspect, corner: corner, accent: Color.white.opacity(0.14))
            PhotoPickTileSimple(title: L("photo_after"),  image: afterImage,  action: onPickAfter,  aspect: aspect, corner: corner, accent: .green)
        }
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
                    Image(uiImage: img).resizable().scaledToFill().clipped().compositingGroup()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 28, weight: .semibold))
                        Text("Выберите фото").font(.footnote).foregroundColor(.white.opacity(0.7))
                    }.foregroundColor(.white.opacity(0.6))
                }
                HStack {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accent))
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(8)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// === Безопасная удалённая картинка для fallback-графиков ===
private struct FixedRemoteImage: View {
    let url: URL?
    var aspect: CGFloat = 3.0/4.0
    var corner: CGFloat = 12

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url, transaction: .init(animation: .easeInOut)) { phase in
                    switch phase {
                    case .empty: ProgressView().tint(.white)
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: placeholder
                    @unknown default: placeholder
                    }
                }
            } else { placeholder }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspect, contentMode: .fill)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.white.opacity(0.06))
            Image(systemName: "photo").font(.system(size: 22, weight: .semibold)).foregroundColor(.white.opacity(0.6))
        }
        .aspectRatio(aspect, contentMode: .fit)
    }
}
