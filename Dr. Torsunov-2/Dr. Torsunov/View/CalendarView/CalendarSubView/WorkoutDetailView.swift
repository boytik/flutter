
import SwiftUI

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

extension Notification.Name {
    static let workoutApproved = Notification.Name("workoutApproved")
}

struct WorkoutDetailView: View {
    let item: CalendarItem
    let role: PersonalViewModel.Role

    @Environment(\.dismiss) private var dismiss
    @State private var isApproving = false
    @State private var approved = false
    @State private var error: String?

    // MARK: - VM для metadata/metrics
    @StateObject private var vm: WorkoutDetailViewModel

    private var workout: Workout? { item.asWorkout }

    // Инициализация StateObject из параметров
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
                Divider().background(Color.gray.opacity(0.3))

                // Инспекторская кнопка
                if role == .inspector, workout != nil {
                    approveSection
                }

                if let error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.subheadline)
                }

                // MARK: Metadata
                Group {
                    HStack {
                        Text(L("metadata"))
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        if vm.isLoading {
                            ProgressView().tint(.white)
                        }
                    }

                    if !vm.metadataLines.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(vm.metadataLines, id: \.0) { k, v in
                                KVRow(key: k, value: v)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.12))
                        .cornerRadius(12)
                    } else if !vm.isLoading {
                        Text(L("no_metadata"))
                            .foregroundColor(.gray)
                            .font(.subheadline)
                    }
                }

                // MARK: Metrics (raw)
                Group {
                    Text(L("diagrams"))
                        .font(.headline)
                        .foregroundColor(.white)

                    if !vm.metricsLines.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(vm.metricsLines, id: \.0) { k, v in
                                KVRow(key: k, value: v)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.12))
                        .cornerRadius(12)
                    } else if !vm.isLoading {
                        Text(L("no_diagram_data"))
                            .foregroundColor(.gray)
                            .font(.subheadline)
                    }
                }
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(L("workout"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if role == .inspector, workout != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await approve() }
                    } label: {
                        if isApproving {
                            ProgressView()
                        } else {
                            Text(approved ? L("approved") : L("approve"))
                        }
                    }
                    .disabled(isApproving || approved)
                }
            }
        }
        .task {
            await vm.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(workout?.name ?? L("workout"))
                .font(.title3.bold())
                .foregroundColor(.white)

            Text(item.date.formatted(date: .long, time: .shortened))
                .foregroundColor(.gray)
                .font(.subheadline)
        }
    }

    private var approveSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await approve() }
            } label: {
                HStack {
                    Image(systemName: approved ? "checkmark.seal.fill" : "checkmark.seal")
                    Text(approved ? L("approved") : L("approve_workout"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(approved ? Color.green.opacity(0.3) : Color.green)
                .foregroundColor(.black)
                .cornerRadius(12)
            }
            .disabled(isApproving || approved)
        }
    }

    @MainActor
    private func approve() async {
        guard let w = workout else { return }
        guard TokenStorage.shared.accessToken != nil else {
            error = L("need_auth_to_approve")
            return
        }
        error = nil
        isApproving = true
        defer { isApproving = false }

        do {
            let inspectorRepo = InspectorRepositoryImpl()
            try await inspectorRepo.checkWorkout(id: w.id)
            approved = true
            NotificationCenter.default.post(name: .workoutApproved, object: w.id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// Простой key-value ряд
private struct KVRow: View {
    let key: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.leading)
            Spacer()
        }
    }
}
