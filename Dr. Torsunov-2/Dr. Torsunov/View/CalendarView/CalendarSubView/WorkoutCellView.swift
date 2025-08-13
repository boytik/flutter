import SwiftUI

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

private func formatMinutes(_ minutes: Int) -> String {
    let f = MeasurementFormatter()
    f.locale = Locale.current
    f.unitOptions = .providedUnit
    f.unitStyle = .short

    let m = Measurement(value: Double(minutes), unit: UnitDuration.minutes)
    return f.string(from: m)
}


struct CalendarItemCellView: View {
    let item: CalendarItem
    let role: PersonalViewModel.Role

    var body: some View {
        HStack(spacing: 12) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(item.tintColor)
                    .frame(width: 44, height: 44)
                    .background(item.tintColor.opacity(0.2))
                    .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .foregroundColor(.white)

                if let description = item.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                if role == .inspector, let w = item.asWorkout {
                    Text("\(L("duration")): \(formatMinutes(w.duration))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.date.formatted(date: .numeric, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(item.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(12)
    }
}

