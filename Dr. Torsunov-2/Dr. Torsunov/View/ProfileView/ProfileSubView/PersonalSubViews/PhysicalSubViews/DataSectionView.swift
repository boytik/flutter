

import SwiftUI

struct DataSectionView: View {
    @ObservedObject var viewModel: PhysicalDataViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            dataRow(title: "Начало тренировок*", value: formattedDate(viewModel.startDate), picker: .date)
            Divider().background(Color.gray.opacity(0.5))
            dataRow(title: "Возраст*", value: "\(viewModel.age)", picker: .age)
            Divider().background(Color.gray.opacity(0.5))
            dataRow(title: "Пол", value: viewModel.gender, picker: .gender)
            Divider().background(Color.gray.opacity(0.5))
            dataRow(title: "Рост", value: "\(viewModel.height) cm", picker: .height)
            Divider().background(Color.gray.opacity(0.5))
            dataRow(title: "Вес", value: "\(viewModel.weight) kg", picker: .weight)
        }
        .padding()
        .background(Color(red: 28/255, green: 28/255, blue: 30/255))
        .cornerRadius(12)
    }
    
    private func dataRow(title: String, value: String, picker: PickerType) -> some View {
        HStack {
            Text(title).foregroundColor(.white)
            Spacer()
            Text(value).foregroundColor(.gray)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.activePicker = picker
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
