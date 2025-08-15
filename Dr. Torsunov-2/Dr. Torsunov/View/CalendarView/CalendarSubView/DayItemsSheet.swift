import SwiftUI

struct DayItemsSheet: View {
    let date: Date
    let items: [CalendarItem]
    let role: PersonalViewModel.Role

    /// Даёт URL мини-превью для элемента истории (активности).
    /// По умолчанию — ничего (чтобы в превью/тестах не требовать VM).
    private let thumbURLProvider: (CalendarItem) -> URL?

    init(
        date: Date,
        items: [CalendarItem],
        role: PersonalViewModel.Role,
        thumbURLProvider: @escaping (CalendarItem) -> URL? = { _ in nil }
    ) {
        self.date = date
        self.items = items
        self.role = role
        self.thumbURLProvider = thumbURLProvider
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        if item.asWorkout != nil {
                            WorkoutDetailView(item: item, role: role)
                        } else if let activity = item.asActivity {
                            ActivityDetailView(activity: activity, role: role)
                        } else {
                            Text("Неизвестный тип").foregroundColor(.gray)
                        }
                    } label: {
                        // ✅ передаём мини-превью
                        CalendarItemCellView(
                            item: item,
                            role: role,
                            thumbURL: thumbURLProvider(item)
                        )
                    }
                }
            }
            .navigationTitle(formattedDate)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f.string(from: date)
    }
}

