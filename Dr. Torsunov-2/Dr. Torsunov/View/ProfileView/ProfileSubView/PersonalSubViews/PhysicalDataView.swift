
import SwiftUI


struct PhysicalDataView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PhysicalDataViewModel  // 🔹 теперь получаем из PersonalViewModel

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    DataSectionView(viewModel: viewModel)
                    ToggleSectionView(viewModel: viewModel)

                    Button(role: .destructive) {
                        // TODO: Удалить план
                    } label: {
                        Text("Удалить план тренировок")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Личные данные")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.pink)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.hasChanges {
                        Button("Сохранить") {
                            Task {
                                await viewModel.saveChanges()
                                dismiss() // 🔹 Закрытие после сохранения
                            }
                        }
                        .foregroundColor(.pink)
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .sheet(isPresented: $viewModel.showChronicAlert) {
                ChronicAlertSheet(viewModel: viewModel)
            }
            .sheet(item: $viewModel.activePicker) { pickerType in
                PickerSheet(viewModel: viewModel, pickerType: pickerType)
            }
        }
        .onAppear {
            UITextView.appearance().backgroundColor = .clear
        }
    }
}

