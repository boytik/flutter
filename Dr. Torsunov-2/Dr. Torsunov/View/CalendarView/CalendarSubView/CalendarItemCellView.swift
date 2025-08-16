import SwiftUI

struct CalendarItemCellView: View {
    let item: CalendarItem
    let role: PersonalViewModel.Role
    let thumbURL: URL?

    private var displayName: String {
        if let w = item.asWorkout { return w.name }
        if let a = item.asActivity { return a.name ?? "Activity" }
        return "Activity"
    }
    private var email: String? {
        guard role == .inspector else { return nil }
        // основной источник — из модели Activity
        if let e = item.asActivity?.userEmail, !e.isEmpty { return e }
        // фолбэк: попробуем выдернуть из URL миниатюры, если есть
        if let u = thumbURL {
            let comps = u.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if comps.count >= 3 { return comps[comps.count - 3] }
        }
        return nil
    }
    private var dateText: (String, String) {
        let d = item.date
        let df1 = DateFormatter()
        df1.locale = .current
        df1.setLocalizedDateFormatFromTemplate("dd.MM.yyyy")
        let df2 = DateFormatter()
        df2.locale = .current
        df2.setLocalizedDateFormatFromTemplate("HH:mm")
        return (df1.string(from: d), df2.string(from: d))
    }
    private var glyph: (system: String, color: Color) {
        let name = displayName.lowercased()
        if name.contains("йога") || name.contains("yoga") {
            return ("figure.mind.and.body", .purple)
        }
        if name.contains("вода") || name.contains("water") || name.contains("swim") {
            return ("drop.fill", .blue)
        }
        if name.contains("ход") || name.contains("бег") || name.contains("walk") || name.contains("run") {
            return ("figure.walk", .orange)
        }
        if name.contains("пост") || name.contains("fast") {
            return ("fork.knife", .yellow)
        }
        if name.contains("баня") || name.contains("sauna") {
            return ("flame.fill", .red)
        }
        return ("checkmark.seal.fill", .green)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle().fill(glyph.color.opacity(0.18)).frame(width: 54, height: 54)
                Image(systemName: glyph.system)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(glyph.color)
            }

            // Title + (email for inspector)
            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if let desc = item.asWorkout?.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Date / time
            VStack(alignment: .trailing, spacing: 4) {
                Text(dateText.0)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
                Text(dateText.1)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
