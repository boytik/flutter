import SwiftUI

struct DayItemsSheet: View {
    let date: Date
    let items: [CalendarItem]
    let role: PersonalViewModel.Role
    let thumbProvider: (CalendarItem) -> URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 44, height: 5)
                    .padding(.top, 8)

                HStack {
                    Text(dateFormatted(date))
                        .font(.headline).foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 16)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(items, id: \.id) { item in
                            NavigationLink {
                                destination(for: item)
                                    .background(Color.black.ignoresSafeArea())
                            } label: {
                                row(for: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .background(Color.black.ignoresSafeArea())
        }
        .tint(.green)
    }

    @ViewBuilder
    private func destination(for item: CalendarItem) -> some View {
        if item.asWorkout != nil {
            WorkoutDetailView(item: item, role: role)
        } else if let activity = item.asActivity {
            ActivityDetailView(activity: activity, role: role)
        } else {
            Text("Неизвестный тип").foregroundColor(.white)
        }
    }

    private func row(for item: CalendarItem) -> some View {
        HStack(spacing: 12) {
            iconView(for: item)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.date, style: .date)
                    .font(.caption).foregroundColor(.white.opacity(0.7))
                Text(item.date, style: .time)
                    .font(.caption2).foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func iconView(for item: CalendarItem) -> some View {
        if let url = thumbProvider(item) {
            AsyncImage(url: url) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                ZStack { placeholderCircle(); ProgressView().tint(.white) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            let lower = item.name.lowercased()
            if lower.contains("water") || lower.contains("вода") {
                circleIcon(system: "drop.fill", bg: .blue)
            } else if lower.contains("walk") || lower.contains("run")
                        || lower.contains("ходь") || lower.contains("бег") {
                circleIcon(system: "figure.walk", bg: .orange)
            } else if lower.contains("sauna") || lower.contains("сауна") {
                circleIcon(system: "flame.fill", bg: .red)
            } else if lower.contains("swim") || lower.contains("плав") {
                circleIcon(system: "figure.swim", bg: .cyan)
            } else {
                circleIcon(system: "dumbbell.fill", bg: .gray)
            }
        }
    }

    private func circleIcon(system: String, bg: Color) -> some View {
        ZStack {
            Circle().fill(bg.opacity(0.18))
            Circle().stroke(bg.opacity(0.35), lineWidth: 1)
            Image(systemName: system)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(bg)
        }
    }

    private func placeholderCircle() -> some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.08))
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func dateFormatted(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "d MMMM"
        return df.string(from: d)
    }
}
