import SwiftUI

struct DayItemsSheet: View {
    let date: Date
    let items: [CalendarItem]
    let role: PersonalViewModel.Role
    var thumbProvider: ((CalendarItem) -> URL?)? = nil

    var body: some View {
        NavigationStack {
            if items.isEmpty {
                ContentUnavailableView("Нет тренировок", systemImage: "calendar")
                    .foregroundStyle(.white)
                    .navigationTitle(formattedDate)
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(items) { item in
                            NavigationLink {
                                if let w = item.asWorkout {
                                    WorkoutDetailView(item: .workout(w), role: role)
                                } else if let a = item.asActivity {
                                    ActivityDetailView(activity: a, role: role)
                                } else {
                                    Text("Неизвестный тип").foregroundColor(.white)
                                }
                            } label: {
                                DayItemRowDark(
                                    item: item,
                                    thumbURL: thumbProvider?(item)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .navigationTitle(formattedDate)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .preferredColorScheme(.dark)
        .tint(.green)
        .background(Color.black.ignoresSafeArea())
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f.string(from: date)
    }
}

// MARK: - Row (тёмная тема)
private struct DayItemRowDark: View {
    let item: CalendarItem
    let thumbURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            thumbOrIcon
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                if let subtitle = item.description, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(dateOnly)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Text(timeOnly)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
            }

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(12)
        .background(Color(.secondarySystemBackground).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var thumbOrIcon: some View {
        if let url = thumbURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.08))
                        ProgressView().tint(.white)
                    }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                case .failure:
                    defaultIcon
                @unknown default:
                    defaultIcon
                }
            }
        } else {
            defaultIcon
        }
    }

    private var defaultIcon: some View {
        ZStack {
            Circle().fill(item.tintColor.opacity(0.22))
            Image(systemName: item.symbolName)
                .foregroundStyle(item.tintColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var dateOnly: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: item.date)
    }

    private var timeOnly: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f.string(from: item.date)
    }
}
