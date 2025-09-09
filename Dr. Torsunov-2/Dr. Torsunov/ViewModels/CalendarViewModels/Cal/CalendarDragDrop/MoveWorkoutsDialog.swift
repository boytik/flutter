import SwiftUI
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app",
                         category: "MoveWorkoutsDialog")

/// Диалог для выбора тренировок при перемещении
/// Позволяет пользователю выбрать какие именно тренировки перемещать на новую дату
struct MoveWorkoutsDialog: View {
    let title: String
    let workouts: [Workout]
    var onConfirm: (_ selectedIDs: [String]) -> Void
    var onCancel: () -> Void

    @State private var selected: Set<String> = []

    /// Инициализирует диалог перемещения тренировок
    /// - Parameters:
    ///   - title: Заголовок диалога
    ///   - workouts: Массив тренировок для выбора
    ///   - onConfirm: Колбэк подтверждения с выбранными ID
    ///   - onCancel: Колбэк отмены операции
    init(title: String = "Выберите тренировки",
         workouts: [Workout],
         onConfirm: @escaping (_ selectedIDs: [String]) -> Void,
         onCancel: @escaping () -> Void) {
        
        log.info("🆕 Инициализация MoveWorkoutsDialog...")
        log.debug("📝 Заголовок: '\(title, privacy: .public)'")
        log.debug("💪 Количество тренировок: \(workouts.count)")
        
        self.title = title
        self.workouts = workouts
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        
        // По умолчанию выбираем все тренировки
        let allIDs = Set(workouts.map(\.id))
        self._selected = State(initialValue: allIDs)
        
        log.debug("✅ Предварительно выбраны все тренировки: \(allIDs.count) шт.")
        for (index, workout) in workouts.enumerated() {
            log.debug("💪 [\(index)]: '\(workout.name, privacy: .public)' (ID: \(workout.id, privacy: .public), тип: \(workout.activityType ?? "неизвестно"))")
        }
        
        log.info("✅ MoveWorkoutsDialog инициализирован успешно")
    }

    /// Создаёт UI диалога с элементами выбора тренировок
    var body: some View {
        log.debug("🎨 Рендерим MoveWorkoutsDialog...")
        
        return VStack(spacing: 16) {
            // Заголовок диалога
            Text(title)
                .font(.headline)
                .onAppear {
                    log.debug("📝 Отображен заголовок: '\(title, privacy: .public)'")
                }
            
            // Список тренировок для выбора
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(workouts, id: \.id) { workout in
                        Toggle(isOn: Binding(
                            get: {
                                let isSelected = selected.contains(workout.id)
                                log.debug("🔍 Проверка состояния тренировки '\(workout.name, privacy: .public)': \(isSelected ? "выбрана" : "не выбрана")")
                                return isSelected
                            },
                            set: { newValue in
                                log.info("🔄 Изменение выбора тренировки '\(workout.name, privacy: .public)': \(newValue ? "выбрать" : "снять")")
                                
                                if newValue {
                                    selected.insert(workout.id)
                                    log.debug("✅ Тренировка добавлена в выбор: \(workout.id, privacy: .public)")
                                } else {
                                    selected.remove(workout.id)
                                    log.debug("❌ Тренировка удалена из выбора: \(workout.id, privacy: .public)")
                                }
                                
                                log.debug("📊 Текущий выбор: \(selected.count) из \(workouts.count) тренировок")
                            })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    // Название тренировки
                                    Text(workout.name)
                                        .font(.body)
                                    
                                    // Тип активности (если есть)
                                    if let activityType = workout.activityType {
                                        Text("Тип: \(activityType)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    // Дата тренировки
                                    Text(DateUtils.ymd.string(from: workout.date))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(CheckboxToggleStyle())
                            .padding(.vertical, 6)
                            .onAppear {
                                log.debug("🎯 Отображена тренировка: '\(workout.name, privacy: .public)' на \(DateUtils.ymd.string(from: workout.date), privacy: .public)")
                            }
                    }
                }
                .padding(.horizontal, 2)
            }
            .onAppear {
                log.debug("📜 ScrollView с тренировками отображён")
            }
            
            // Кнопки действий
            HStack {
                Button("Отмена") {
                    log.info("❌ Пользователь нажал кнопку 'Отмена'")
                    log.debug("🚫 Отменяем операцию перемещения тренировок")
                    onCancel()
                }
                .onAppear {
                    log.debug("🔘 Кнопка 'Отмена' отображена")
                }
                
                Spacer()
                
                Button("Переместить") {
                    let selectedArray = Array(selected)
                    log.info("✅ Пользователь подтвердил перемещение: \(selectedArray.count) тренировок")
                    
                    for (index, id) in selectedArray.enumerated() {
                        log.debug("🚀 [\(index)]: ID для перемещения: \(id, privacy: .public)")
                    }
                    
                    if selectedArray.isEmpty {
                        log.warning("⚠️ Попытка подтверждения с пустым выбором (кнопка должна быть недоступна)")
                    }
                    
                    onConfirm(selectedArray)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
                .onAppear {
                    log.debug("🔘 Кнопка 'Переместить' отображена, активна: \(!selected.isEmpty)")
                }
                .onChange(of: selected.isEmpty) { isEmpty in
                    log.debug("🔄 Состояние кнопки 'Переместить' изменено: \(isEmpty ? "недоступна" : "доступна")")
                }
            }
            .onAppear {
                log.debug("🔘 Панель кнопок действий отображена")
            }
        }
        .padding(16)
        .frame(maxWidth: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
        .padding()
        .onAppear {
            log.info("🎨 MoveWorkoutsDialog полностью отображён")
            logCurrentSelectionState()
        }
        .onDisappear {
            log.info("👋 MoveWorkoutsDialog скрыт")
        }
    }
    
    /// Логирует текущее состояние выбора тренировок
    private func logCurrentSelectionState() {
        log.debug("📊 === Состояние выбора тренировок ===")
        log.debug("📊 Всего тренировок: \(workouts.count)")
        log.debug("📊 Выбрано: \(selected.count)")
        log.debug("📊 Не выбрано: \(workouts.count - selected.count)")
        
        if selected.isEmpty {
            log.debug("📊 ❌ Ни одна тренировка не выбрана")
        } else if selected.count == workouts.count {
            log.debug("📊 ✅ Выбраны все тренировки")
        } else {
            log.debug("📊 🔘 Частичный выбор тренировок")
        }
        
        // Группировка по типам активности
        let selectedWorkouts = workouts.filter { selected.contains($0.id) }
        let typeGroups = Dictionary(grouping: selectedWorkouts) { $0.activityType ?? "unknown" }
        let typeSummary = typeGroups.map { "\($0.key): \($0.value.count)" }.joined(separator: ", ")
        
        if !typeSummary.isEmpty {
            log.debug("📊 Выбранные типы: \(typeSummary, privacy: .public)")
        }
    }
}

/// Кастомный стиль чекбокса для выбора тренировок
/// Отображает квадратный чекбокс с галочкой вместо стандартного переключателя
struct CheckboxToggleStyle: ToggleStyle {
    
    /// Создаёт внешний вид чекбокса
    /// - Parameter configuration: Конфигурация toggle элемента
    /// - Returns: View с кастомным оформлением чекбокса
    func makeBody(configuration: Configuration) -> some View {
        log.debug("🎨 Рендерим CheckboxToggleStyle, состояние: \(configuration.isOn ? "включён" : "выключен")")
        
        return Button(action: {
            log.debug("🔄 Переключение чекбокса: \(configuration.isOn ? "выключаем" : "включаем")")
            configuration.isOn.toggle()
        }) {
            HStack {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundColor(configuration.isOn ? .accentColor : .secondary)
                    .onAppear {
                        let iconName = configuration.isOn ? "checkmark.square.fill" : "square"
                        log.debug("🎯 Отображена иконка чекбокса: \(iconName)")
                    }
                
                configuration.label
                    .onAppear {
                        log.debug("📝 Отображен label чекбокса")
                    }
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            log.debug("✅ CheckboxToggleStyle полностью отображён")
        }
    }
}

// MARK: - Расширения для логирования

extension Array where Element == Workout {
    /// Логирует детальную статистику тренировок в диалоге
    func logDialogWorkoutStats(prefix: String = "") {
        let typeGroups = Dictionary(grouping: self) { $0.activityType ?? "unknown" }
        let durationTotal = self.reduce(0) { $0 + $1.duration }
        let avgDuration = self.isEmpty ? 0 : durationTotal / self.count
        
        for (type, workouts) in typeGroups {
            let typeTotal = workouts.reduce(0) { $0 + $1.duration }
            log.debug("  🏷️ \(type): \(workouts.count) шт., \(typeTotal) мин")
        }
        
        // Группировка по датам
        let dateGroups = Dictionary(grouping: self) {
            DateUtils.ymd.string(from: $0.date)
        }
        
        if dateGroups.count <= 5 {
            for (date, workouts) in dateGroups.sorted(by: { $0.key < $1.key }) {
                log.debug("  📅 \(date): \(workouts.count) тренировок")
            }
        } else {
            log.debug("  📅 Диапазон дат: \(dateGroups.count) различных дней")
        }
    }
}

extension Set where Element == String {
    /// Логирует статистику выбранных ID
    func logSelectionStats(prefix: String = "") {
        let protocolIDs = self.filter { $0.contains("|") }
        let regularIDs = self.filter { !$0.contains("|") }
        
        if !protocolIDs.isEmpty {
            log.debug("  🔗 Протокольные ID: \(protocolIDs.joined(separator: ", "), privacy: .public)")
        }
    }
}
