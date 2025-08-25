
import SwiftUI
import Foundation

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

@MainActor
struct CalendarView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @AppStorage("user_role") private var storedRoleRaw = PersonalViewModel.Role.user.rawValue

    @State private var selectedDay: IdentDate?
    @State private var refreshToken: Int = 0

    private var currentRole: PersonalViewModel.Role {
        PersonalViewModel.Role(rawValue: storedRoleRaw) ?? .user
    }

    private var taskKey: String { "\(storedRoleRaw)_\(refreshToken)" }

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack { contentView }
                    .toolbar(.hidden, for: .navigationBar)
            } else {
                NavigationView {
                    contentView
                        .navigationBarTitle("")
                        .navigationBarHidden(true)
                }
            }
        }
        .task(id: taskKey) {
            await viewModel.reload(role: currentRole)
        }
        .sheet(item: $selectedDay) { day in
            DayItemsSheet(
                date: day.date,
                items: viewModel.items(on: day.date),
                role: viewModel.role,
                thumbProvider: { item in viewModel.thumbFor(item) }
            )
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(24)
            .presentationBackground(.black)
        }
    }

    private var contentView: some View {
        VStack(spacing: 16) {
            HStack {
                Text(currentRole == .user ? "Тренировки" : "Тренировки на проверку")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { refreshToken &+= 1 }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.white)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 8)

            if currentRole == .user {
                modePicker
                    .padding(.vertical)

                if viewModel.pickerMode == .calendar {
                    calendarSection
                    Spacer()
                } else {
                    historyHeader
                    historyGridUser
                }
            } else {
                historyGridInspector
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

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

    private var calendarSection: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { viewModel.previousMonth() }) {
                    Image(systemName: "chevron.left").foregroundColor(.white)
                }
                Spacer()
                Text(viewModel.currentMonth)
                    .foregroundColor(.white)
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.nextMonth() }) {
                    Image(systemName: "chevron.right").foregroundColor(.white)
                }
            }
            .padding(.horizontal)

            CalendarGridView(
                monthDates: viewModel.monthDates,
                displayMonth: viewModel.currentMonthDate,
                onDayTap: { tapped in
                    selectedDay = IdentDate(tapped)
                },
                itemsProvider: { date in
                    viewModel.items(on: date).map { $0 as CalendarGridDayContext }
                }
            )
            .padding(.vertical)
        }
    }




    private var historyHeader: some View {
        HStack {
            Text("История")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Picker("", selection: $viewModel.historyFilter) {
                ForEach(CalendarViewModel.HistoryFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .tint(.green)
            .pickerStyle(.segmented)
            .frame(width: 260)
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private var historyGridUser: some View {
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
                        CalendarItemCellView(
                            item: item,
                            role: viewModel.role,
                            thumbURL: viewModel.thumbFor(item)
                        )
                    }
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
    }

    private var historyGridInspector: some View {
        ScrollView {
            LazyVStack(pinnedViews: [.sectionHeaders]) {
                Section {
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
                                CalendarItemCellView(
                                    item: item,
                                    role: viewModel.role,
                                    thumbURL: viewModel.thumbFor(item)
                                )
                            }
                        }
                    }
                } header: {
                    filterBar
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                FilterChip(
                    text: "Все",
                    selected: viewModel.inspectorTypeFilter == nil,
                    action: { viewModel.setInspectorFilter(nil) }
                )
                ForEach(viewModel.inspectorTypes, id: \.self) { t in
                    FilterChip(
                        text: t,
                        selected: viewModel.inspectorTypeFilter == t,
                        action: { viewModel.setInspectorFilter(t) }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Контрастные «пилюли» фильтра
private struct FilterChip: View {
    let text: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundColor(selected ? .white : .white.opacity(0.92))
            .background(
                ZStack {
                    (selected ? Color.green.opacity(0.28) : Color.white.opacity(0.14))
                        .clipShape(Capsule())
                    Capsule().strokeBorder(selected ? Color.green : Color.white.opacity(0.22), lineWidth: 1)
                }
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct IdentDate: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    init(_ d: Date) { self.date = d }
}
