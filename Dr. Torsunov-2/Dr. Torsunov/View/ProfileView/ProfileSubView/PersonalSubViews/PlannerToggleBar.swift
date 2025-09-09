import SwiftUI

import SwiftUI

struct PlannerToggleBar: View {
    let hasPlan: Bool
    let isBusy: Bool
    let isChecking: Bool          // <-- новое
    let canToggle: Bool
    let onToggle: () -> Void

    @State private var pressed = false
    @State private var showConfirmDelete = false

    private var currentTitle: String {
        if isChecking { return "Проверяем…" }
        if isBusy { return hasPlan ? "Удаляем…" : "Создаём…" }
        return hasPlan ? "Удалить план" : "Создать план"
    }

    private var currentTint: Color {
        if isChecking { return .gray }
        return hasPlan ? .red : .green
    }

    var body: some View {
        Button(role: hasPlan && !isChecking ? .destructive : .none) {
            guard !isBusy, !isChecking, canToggle else { return }
            if hasPlan {
                showConfirmDelete = true
            } else {
                onToggle()
            }
        } label: {
            HStack(spacing: 10) {
                if isBusy || isChecking {
                    ProgressView().progressViewStyle(.circular)
                } else {
                    Image(systemName: hasPlan ? "trash.fill" : "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                }
                Text(currentTitle)
                    .font(.headline)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(currentTint)
        .disabled(isBusy || isChecking || !canToggle)
        .scaleEffect(pressed ? 0.98 : 1)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: currentTint.opacity(0.35), radius: 14, y: 2)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .confirmationDialog(
            "Удалить план тренировок?",
            isPresented: $showConfirmDelete,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) { onToggle() }
            Button("Отмена", role: .cancel) { }
        }
    }
}


// вспомогательный цвет из hex
fileprivate extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >>  8) & 0xFF) / 255.0,
                  blue:  Double((hex >>  0) & 0xFF) / 255.0,
                  opacity: alpha)
    }
}
