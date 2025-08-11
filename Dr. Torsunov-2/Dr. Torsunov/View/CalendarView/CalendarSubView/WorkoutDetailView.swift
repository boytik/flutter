
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

    private let inspectorRepo = InspectorRepositoryImpl()

    private var workout: Workout? { item.asWorkout }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider().background(Color.gray.opacity(0.3))

            if role == .inspector, workout != nil {
                approveSection
            }

            if let error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.subheadline)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .padding()
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
        .background(Color.black.ignoresSafeArea())
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
            try await inspectorRepo.checkWorkout(id: w.id)
            approved = true
            NotificationCenter.default.post(name: .workoutApproved, object: w.id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
