import SwiftUI

@MainActor
struct MoveWorkoutsSheetFixedSource: View {
    /// Куда переносим
    let targetDate: Date
    /// Откуда переносим (исходный день — фиксированный)
    let sourceDate: Date
    /// Достаём элементы дня (из VM)
    let itemsProvider: (Date) -> [CalendarItem]
    /// Подтверждение с набором id выбранных тренировок (из sourceDate)
    let onConfirm: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String> = []

    private var workoutsFromSource: [Workout] {
        itemsProvider(sourceDate).compactMap { $0.asWorkout }
    }

    private func titleDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Выберите тренировки, которые хотите перенести на \(titleDate(targetDate))")
                .font(.headline)
                .foregroundColor(.white)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(workoutsFromSource, id: \.id) { w in
                        HStack {
                            Button {
                                if selectedIDs.contains(w.id) { selectedIDs.remove(w.id) } else { selectedIDs.insert(w.id) }
                            } label: {
                                Image(systemName: selectedIDs.contains(w.id) ? "checkmark.circle.fill" : "circle")
                                    .imageScale(.large)
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.name).foregroundColor(.white)
                                Text(titleDate(sourceDate))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if workoutsFromSource.isEmpty {
                        Text("В этот день нет тренировок")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                }
            }

            HStack {
                Button("Отмена") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)

                Button("Переместить") {
                    onConfirm(Array(selectedIDs))
                    dismiss()
                }
                .disabled(selectedIDs.isEmpty)
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .onAppear {
            self.selectedIDs = Set(workoutsFromSource.map { $0.id })
        }
        .padding(20)
        .background(Color.black)
    }
}
