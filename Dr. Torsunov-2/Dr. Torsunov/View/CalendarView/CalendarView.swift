

import SwiftUI
import Combine

struct CalendarView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @AppStorage("user_role") private var storedRoleRaw = PersonalViewModel.Role.user.rawValue

    private var currentRole: PersonalViewModel.Role {
        PersonalViewModel.Role(rawValue: storedRoleRaw) ?? .user
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Заголовок
                HStack {
                    Text(currentRole == .user ? "Тренировки" : "Тренировки на проверку")
                        .font(.title2)
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                if currentRole == .user {
                    modePicker
                        .padding(.vertical)

                    if viewModel.pickerMode == .calendar {
                        calendarSection
                        Spacer()
                    } else {
                        historyGrid
                    }
                } else {
                    historyGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await viewModel.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            await viewModel.applyRole(currentRole)
        }
        .onChange(of: storedRoleRaw) { _, _ in
            Task { await viewModel.applyRole(currentRole) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutApproved)) { _ in
            guard viewModel.role == .inspector else { return }
            Task { await viewModel.refresh() }
        }

    }

    // MARK: - Mode Picker
    private var modePicker: some View {
        Picker("", selection: $viewModel.pickerMode) {
            ForEach(CalendarViewModel.PickersModes.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .tint(.green)
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    // MARK: - Calendar Section
    private var calendarSection: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { viewModel.previousMonth() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                }
                Spacer()
                Text(viewModel.currentMonth)
                    .foregroundColor(.white)
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.nextMonth() }) {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal)

            CalendarGridView(monthDates: viewModel.monthDates)
                .padding(.vertical)
        }
    }

    // MARK: - История (Workouts + Activities / Inspector lists)
    private var historyGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                ForEach(Array(viewModel.filteredItems.enumerated()), id: \.1.id) { _, item in
                    NavigationLink {
                        if item.asWorkout != nil {
                            WorkoutDetailView(item: item, role: viewModel.role)
                        } else if let activity = item.asActivity {
                            ActivityDetailView(activity: activity, role: viewModel.role)
                        } else {
                            Text("Неизвестный тип").foregroundColor(.white)
                        }
                    } label: {
                        CalendarItemCellView(item: item, role: viewModel.role)
                    }
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
    }
}
