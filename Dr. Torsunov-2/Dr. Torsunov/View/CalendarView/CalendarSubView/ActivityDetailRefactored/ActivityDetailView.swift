import SwiftUI
import UIKit
import Charts

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

    @State private var chartStart = Date()
    private var totalSeconds: Double {
        if let t = vm.timeSeries, let last = t.last { return max(1, last) }
        if let m = vm.preferredDurationMinutes { return Double(max(1, m) * 60) }
        let c = max(vm.heartRateSeries?.count ?? 0, vm.speedSeries?.count ?? 0)
        return max(1, Double(c))
    }

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
                ActivityHeaderView(activity: activity)

                Picker("", selection: $tab) {
                    ForEach(availableTabs, id: \.self) { Text(tabTitle($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .tint(.green)
                .zIndex(3)

                switch tab {
                case .charts:
                    ActivityChartsSectionView(activity: activity, vm: vm, syncEnabled: $syncEnabled, chartStart: chartStart, totalSeconds: totalSeconds)
                case .photos:
                    InspectorPhotosView(activity: activity).background(Color.clear)
                case .review:
                    PhotoPickRow(
                        beforeImage: $beforeImage,
                        afterImage:  $afterImage,
                        onPickBefore: { showBeforePicker = true },
                        onPickAfter:  { showAfterPicker  = true },
                        aspect: 3.0/4.0,
                        corner: 18
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Comment").foregroundColor(.white).font(.subheadline)
                        TextField("Enter a comment...", text: $comment, axis: .vertical)
                            .lineLimit(3...6)
                            .padding()
                            .background(Color(.systemGray6).opacity(0.2))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                    }
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
                        Text("Submit")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background((beforeImage != nil && afterImage != nil) ? Color.green : Color.gray,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundColor(.white)
                    }
                    .disabled(beforeImage == nil || afterImage == nil || isSubmitting)
                }

                if let success = submissionSuccess, role != .inspector {
                    Text(success ? "Submitted!" : "Something went wrong")
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
        .task {
            await vm.load()
            chartStart = Date()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    static func extractWorkoutKey(from activity: Activity) -> String? {
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
