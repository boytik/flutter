import SwiftUI

struct InspectorView: View {
    @StateObject private var vm = InspectorViewModel()

    var body: some View {
        List {
            if !vm.toCheck.isEmpty {
                Section("К проверке") {
                    ForEach(vm.toCheck, id: \.id) { a in
                        ToCheckRow(activity: a) {
                            Task { await vm.approve(id: a.id) }
                        }
                    }
                }
            }

            if !vm.fullCheck.isEmpty {
                Section("Полная проверка") {
                    ForEach(vm.fullCheck, id: \.id) { a in
                        FullCheckRow(activity: a)
                    }
                }
            }

            if vm.toCheck.isEmpty && vm.fullCheck.isEmpty && !vm.isLoading {
                ContentUnavailableView("Нет данных для проверки",
                                       systemImage: "checkmark.seal")
            }
        }
        .overlay {
            if vm.isLoading { ProgressView().controlSize(.large) }
        }
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .navigationTitle("Инспектор")
        .alert("Ошибка", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { _ in vm.errorMessage = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }
}

private struct ToCheckRow: View {
    let activity: Activity
    let onApprove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .imageScale(.large)

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.name ?? "Activity")              // ← фикс
                    .font(.headline)
                Text(dateText(activity.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Одобрить", action: onApprove)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct FullCheckRow: View {
    let activity: Activity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .imageScale(.large)

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.name ?? "Activity")              // ← фикс
                    .font(.headline)
                Text(dateText(activity.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

private func dateText(_ date: Date?) -> String {
    guard let date else { return "—" }
    return date.formatted(date: .abbreviated, time: .shortened)
}
