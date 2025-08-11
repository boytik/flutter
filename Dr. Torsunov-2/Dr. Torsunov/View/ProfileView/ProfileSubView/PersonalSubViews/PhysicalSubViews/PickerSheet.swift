
import SwiftUI

struct PickerSheet: View {
    @ObservedObject var viewModel: PhysicalDataViewModel
    var pickerType: PickerType
    
    var body: some View {
        VStack {
            Spacer()
            Group {
                switch pickerType {
                case .date:
                    DatePicker("", selection: $viewModel.startDate, displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                case .age:
                    Picker("", selection: $viewModel.age) {
                        ForEach(10...100, id: \.self) { Text("\($0)") }
                    }
                    .pickerStyle(.wheel)
                case .gender:
                    Picker("", selection: $viewModel.gender) {
                        Text("Male").tag("Male")
                        Text("Female").tag("Female")
                    }
                    .pickerStyle(.wheel)
                case .height:
                    Picker("", selection: $viewModel.height) {
                        ForEach(100...220, id: \.self) { Text("\($0) cm") }
                    }
                    .pickerStyle(.wheel)
                case .weight:
                    Picker("", selection: $viewModel.weight) {
                        ForEach(40...150, id: \.self) { Text("\($0) kg") }
                    }
                    .pickerStyle(.wheel)
                }
            }
            .colorScheme(.dark)
            .background(Color.black)
            
            Button("Готово") {
                viewModel.activePicker = nil
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.green)
            .foregroundColor(.white)
        }
        .presentationDetents([.fraction(0.3)])
        .presentationDragIndicator(.visible)
        .background(Color.black)
    }
}
