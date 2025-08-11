import SwiftUI

struct InspectorView: View {
    @StateObject var vm = InspectorViewModel()

    var body: some View {
        List {
            if !vm.toCheck.isEmpty {
                Section("К проверке") {
                    ForEach(vm.toCheck, id: \.id) { w in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(w.name).font(.headline)
                                Text(w.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Одобрить") {
                                Task { await vm.approve(id: w.id) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            if !vm.fullCheck.isEmpty {
                Section("Полная проверка") {
                    ForEach(vm.fullCheck, id: \.id) { w in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(w.name).font(.headline)
                            Text(w.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if vm.toCheck.isEmpty && vm.fullCheck.isEmpty && !vm.isLoading {
                ContentUnavailableView("Нет данных для проверки", systemImage: "checkmark.seal")
            }
        }
        .overlay { if vm.isLoading { ProgressView() } }
        .task { await vm.load() }
        .navigationTitle("Инспектор")
    }
}
