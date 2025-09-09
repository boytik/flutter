import SwiftUI
import UIKit

struct PhysicalDataView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PhysicalDataViewModel

    // биндинг для алерта ошибок
    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        DataSectionView(viewModel: viewModel)
                        ToggleSectionView(viewModel: viewModel)
                    }
                    .padding()
                    .padding(.bottom, 120) // место под нижний бар
                }
                .refreshable { await viewModel.refreshPlanState() }

                // затемнение при сетевых операциях
                if viewModel.isBusy {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
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
                                dismiss()
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
            // Нижняя панель действий планировщика (одна кнопка как во Flutter)
            .safeAreaInset(edge: .bottom) {
                PlannerToggleBar(
                      hasPlan: viewModel.hasPlan,
                      isBusy: viewModel.isBusy,
                      isChecking: viewModel.isCheckingPlan,     // <-- новое
                      canToggle: !viewModel.email.isEmpty,
                      onToggle: { viewModel.togglePlan() }
                  )            }
            // алерт ошибок
            .alert("Ошибка", isPresented: isErrorPresented) {
                Button("Ок", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "Неизвестная ошибка")
            }
            // автообновление состояния плана при смене даты
            .onChange(of: viewModel.startDate) { _ in
                Task { await viewModel.refreshPlanState() }
            }
        }
        .onAppear {
            UITextView.appearance().backgroundColor = .clear
        }
    }
}
