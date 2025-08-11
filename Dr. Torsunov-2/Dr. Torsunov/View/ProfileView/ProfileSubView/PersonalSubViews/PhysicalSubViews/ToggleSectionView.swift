

import SwiftUI
struct ToggleSectionView: View {
    @ObservedObject var viewModel: PhysicalDataViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            toggleRow(title: "Соблюдение распорядка дня", isOn: $viewModel.dailyRoutine)
            toggleRow(title: "Вредные привычки", isOn: $viewModel.badHabits)
            
            VStack(spacing: 10) {
                Toggle(isOn: Binding(
                    get: { viewModel.chronicDiseases },
                    set: { newValue in
                        viewModel.chronicDiseases = newValue
                        if newValue {
                            viewModel.showChronicAlert = true
                        } else {
                            viewModel.showChronicTextField = false
                            viewModel.chronicDescription = ""
                        }
                    }
                )) {
                    Text("Хронические заболевания")
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color(red: 28/255, green: 28/255, blue: 30/255))
                .cornerRadius(12)
                
                if viewModel.showChronicTextField {
                    TextEditor(text: $viewModel.chronicDescription)
                        .scrollContentBackground(.hidden)
                        .frame(height: 100)
                        .padding(8)
                        .background(Color(red: 28/255, green: 28/255, blue: 30/255))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Готово") {
                                    hideKeyboard()
                                }
                            }
                        }
                }
            }
        }
    }
    
    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).foregroundColor(.white)
        }
        .padding()
        .background(Color(red: 28/255, green: 28/255, blue: 30/255))
        .cornerRadius(12)
    }
}

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
#endif
