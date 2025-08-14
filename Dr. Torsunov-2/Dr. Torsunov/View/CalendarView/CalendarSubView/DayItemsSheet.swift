import SwiftUI

struct DayItemsSheet: View {
    let date: Date
    let items: [CalendarItem]
    let role: PersonalViewModel.Role

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
                        CalendarItemCellView(item: item, role: role)
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
