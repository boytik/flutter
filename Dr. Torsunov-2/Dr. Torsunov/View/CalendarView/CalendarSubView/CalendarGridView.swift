
import SwiftUI

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

// MARK: - Grid
struct CalendarGridView: View {
    let monthDates: [WorkoutDay]
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            // Заголовки дней недели по локали + первый день недели из системы
            HStack {
                ForEach(localizedWeekdays(), id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(monthDates) { day in
                    VStack(spacing: 4) {
                        Text("\(Calendar.current.component(.day, from: day.date))")
                            .foregroundColor(.white)
                            .font(.headline)

                        HStack(spacing: 3) {
                            ForEach(day.dots.indices, id: \.self) { idx in
                                Circle()
                                    .fill(day.dots[idx])
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6).opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal)
    }
}

private func localizedWeekdays() -> [String] {
    let cal = Calendar.current
    var df = DateFormatter()
    df.locale = Locale.current
    df.calendar = cal

    let symbols: [String]
    if let s = df.shortStandaloneWeekdaySymbols, !s.isEmpty {
        symbols = s
    } else {
        symbols = df.shortWeekdaySymbols
    }

    let firstIndex = max(0, min(symbols.count - 1, cal.firstWeekday - 1))
    let head = Array(symbols[firstIndex..<symbols.count])
    let tail = Array(symbols[0..<firstIndex])
    let reordered = head + tail
    return reordered.map { $0.capitalized }
}


// MARK: - Screen (демо)
struct CalendarScreen: View {
    @State private var selectedTab = 0

    var sampleData: [WorkoutDay] {
        let startOfMonth = Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!
        return (0..<31).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: startOfMonth)!
            let workoutColors: [Color] = (0..<(Int.random(in: 0...4))).map { _ in
                [Color.purple, Color.orange, Color.blue].randomElement()!
            }
            return WorkoutDay(date: date, dots: workoutColors)
        }
    }

    var body: some View {
        VStack {
            Picker("", selection: $selectedTab) {
                Text(L("calendar")).tag(0)
                Text(L("history")).tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()

            CalendarGridView(monthDates: sampleData)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

