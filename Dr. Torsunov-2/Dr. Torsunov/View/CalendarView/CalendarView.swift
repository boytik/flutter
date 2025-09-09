import SwiftUI
import Foundation

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

@MainActor
struct CalendarView: View {
    // DI: можно передать свою VM, иначе создастся дефолтная
    @StateObject private var vm: CalendarViewModel
    @AppStorage("user_role") private var storedRoleRaw = PersonalViewModel.Role.user.rawValue

    // UI state
    @State private var selectedDay: IdentDate?
    @State private var refreshToken: Int = 0
    @State private var didDebugPrintSamples = false

    // Move mode
    @State private var moveModeEnabled: Bool = false
    @State private var sourceDayForMove: Date?
    @State private var moveTarget: IdentDate?

    init(vm: CalendarViewModel) { _vm = StateObject(wrappedValue: vm) }
    init() { _vm = StateObject(wrappedValue: CalendarViewModel()) }

    private var currentRole: PersonalViewModel.Role {
        PersonalViewModel.Role(rawValue: storedRoleRaw) ?? .user
    }
    private var taskKey: String { "\(storedRoleRaw)_\(refreshToken)" }

    // MARK: - Thumbs
    private func thumbURL(for item: CalendarItem) -> URL? {
        vm.thumbs[item.id]      // берём из @Published словаря VM
    }

    var body: some View {
        ZStack {
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

            if vm.isLoading {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.green)
                        .accessibilityLabel(Text("Загрузка"))
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.isLoading)
        .task(id: taskKey) {
            await vm.reload(role: currentRole)
        }
        // Sheet: список элементов дня
        .sheet(item: $selectedDay) { day in
            DayItemsSheet(
                date: day.date,
                items: vm.items(on: day.date),
                role: vm.role,
                thumbProvider: { item in thumbURL(for: item) }   // <- URL?, без Binding и без vm.thumbFor
            )
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(24)
            .presentationBackground(.black)
        }
        // Sheet: перенос тренировки
        .sheet(item: $moveTarget) { day in
            if let src = sourceDayForMove {
                MoveWorkoutsSheetFixedSource(
                    targetDate: day.date,
                    sourceDate: src,
                    itemsProvider: { d in vm.items(on: d) },
                    onConfirm: { ids in
                        Task {
                            await vm.moveWorkouts(withIDs: ids, to: day.date)
                            moveModeEnabled = false
                            sourceDayForMove = nil
                            moveTarget = nil
                        }
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(24)
                .presentationBackground(.black)
            }
        }
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(spacing: 16) {
            header

            if currentRole == .user {
                modePicker
                    .padding(.vertical)

                if vm.pickerMode == .calendar {
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

    private var header: some View {
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
    }

    private var modePicker: some View {
        Picker("", selection: $vm.pickerMode) {
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
                Button(action: { vm.previousMonth() }) {
                    Image(systemName: "chevron.left").foregroundColor(.white)
                }
                Spacer()
                Text(vm.currentMonth)
                    .foregroundColor(.white)
                    .font(.headline)
                Spacer()
                Button(action: { vm.nextMonth() }) {
                    Image(systemName: "chevron.right").foregroundColor(.white)
                }
            }
            .padding(.horizontal)

            CalendarGridView(
                monthDates: vm.monthDates,
                displayMonth: vm.currentMonthDate,
                onDayTap: { tapped in
                    guard !moveModeEnabled else { return }
                    if !didDebugPrintSamples {
                        let items = vm.items(on: tapped)
                        if let w = items.compactMap({ $0.asWorkout }).first {
                            print("=== SAMPLE WORKOUT ==="); dump(w)
                        } else { print("=== SAMPLE WORKOUT: none on this day ===") }
                        if let a = items.compactMap({ $0.asActivity }).first {
                            print("=== SAMPLE ACTIVITY ==="); dump(a)
                        } else { print("=== SAMPLE ACTIVITY: none on this day ===") }
                        didDebugPrintSamples = true
                    }
                    selectedDay = IdentDate(tapped)
                },
                onDayLongPress: { d in
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    sourceDayForMove = d
                    moveModeEnabled = true
                },
                onSelectMoveTarget: { d in
                    moveTarget = IdentDate(d)
                },
                itemsProvider: { date in vm.items(on: date).map { $0 as CalendarGridDayContext } },
                selectedDate: selectedDay?.date,
                isMoveMode: moveModeEnabled,
                moveHighlightWeekOf: sourceDayForMove,
                moveSourceDate: sourceDayForMove
            )
            .padding(.vertical)
        }
    }

    // MARK: - History (User)

    private var historyHeader: some View {
        HStack {
            Text("История")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Picker("", selection: $vm.historyFilter) {
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
                ForEach(vm.filteredItems, id: \.id) { item in
                    NavigationLink {
                        destination(for: item)
                    } label: {
                        CalendarItemCellView(
                            item: item,
                            role: vm.role,
                            thumbURL: thumbURL(for: item)   // <- URL?
                        )
                    }
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - History (Inspector)

    private var historyGridInspector: some View {
        ScrollView {
            LazyVStack(pinnedViews: [.sectionHeaders]) {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                        ForEach(vm.filteredItems, id: \.id) { item in
                            NavigationLink {
                                destination(for: item)
                            } label: {
                                CalendarItemCellView(
                                    item: item,
                                    role: vm.role,
                                    thumbURL: thumbURL(for: item)   // <- URL?
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

    @ViewBuilder
    private func destination(for item: CalendarItem) -> some View {
        if item.asWorkout != nil {
            WorkoutDetailView(item: item, role: vm.role)
        } else if let activity = item.asActivity {
            ActivityDetailView(activity: activity, role: vm.role)
        } else {
            Text("Неизвестный тип").foregroundColor(.white)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                FilterChip(
                    text: "Все",
                    selected: vm.inspectorTypeFilter == nil,
                    action: { vm.setInspectorFilter(nil) }
                )
                ForEach(vm.inspectorTypes, id: \.self) { t in
                    FilterChip(
                        text: t,
                        selected: vm.inspectorTypeFilter == t,
                        action: { vm.setInspectorFilter(t) }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Reusable bits

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
