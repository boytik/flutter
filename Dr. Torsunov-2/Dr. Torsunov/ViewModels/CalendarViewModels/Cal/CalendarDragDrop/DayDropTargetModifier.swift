import SwiftUI
import MobileCoreServices
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app",
                         category: "DayDropTarget")

/// SwiftUI модификатор для обработки drag & drop операций на дни календаря
/// Позволяет перетаскивать тренировки между датами с валидацией и подтверждением
struct DayDropTargetModifier: ViewModifier {
    @ObservedObject var viewModel: CalendarViewModel
    let dayDate: Date

    @State private var isTargeted: Bool = false
    @State private var showDialog: Bool = false
    @State private var dialogWorkouts: [Workout] = []

    /// Создаёт UI с drag & drop функциональностью
    /// - Parameter content: Исходный view для модификации
    /// - Returns: View с поддержкой перетаскивания
    func body(content: Content) -> some View {
        log.debug("🎨 Рендерим DayDropTarget для даты: \(DateFormatter().string(from: dayDate), privacy: .public)")
        
        return content
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .onDrop(of: ["public.text"], isTargeted: $isTargeted) { providers in
                log.info("📥 Drop операция начата на дату: \(DateFormatter().string(from: dayDate), privacy: .public)")
                log.debug("📦 Получено providers: \(providers.count)")
                
                guard let itemProvider = providers.first else {
                    log.warning("⚠️ Отсутствует itemProvider в drop операции")
                    return false
                }
                
                log.debug("🔄 Загружаем данные из itemProvider...")
                
                // Асинхронная загрузка данных из provider
                itemProvider.loadItem(forTypeIdentifier: "public.text", options: nil) { (item, error) in
                    if let error = error {
                        log.error("❌ Ошибка загрузки item: \(error.localizedDescription, privacy: .public)")
                        return
                    }
                    
                    log.debug("📄 Обрабатываем загруженный item...")
                    
                    var dataString: String?
                    
                    // Пробуем разные способы извлечения строки
                    if let directString = item as? String {
                        dataString = directString
                        log.debug("✅ Данные получены как String: \(directString.count) символов")
                    } else if let data = item as? Data {
                        dataString = String(data: data, encoding: .utf8)
                        log.debug("✅ Данные получены как Data и конвертированы в String: \(data.count) байт")
                    } else if let url = item as? URL {
                        do {
                            dataString = try String(contentsOf: url)
                            log.debug("✅ Данные получены из URL: \(url.absoluteString, privacy: .public)")
                        } catch {
                            log.error("❌ Ошибка чтения данных из URL: \(error.localizedDescription, privacy: .public)")
                        }
                    } else {
                        log.warning("⚠️ Неизвестный тип данных в item: \(type(of: item))")
                    }
                    
                    guard let finalString = dataString else {
                        log.error("❌ Не удалось извлечь строку из drop данных")
                        return
                    }
                    
                    log.debug("📝 Полученная строка: '\(finalString, privacy: .public)'")
                    
                    // Парсим ID тренировок из строки
                    let workoutIDs = finalString.split(separator: ",")
                        .map { String($0) }
                        .filter { !$0.isEmpty }
                    
                    log.info("🆔 Распарсено ID тренировок: \(workoutIDs.count) шт.")
                    for (index, id) in workoutIDs.enumerated() {
                        log.debug("🆔 [\(index)]: '\(id, privacy: .public)'")
                    }
                    
                    // Обрабатываем drop асинхронно
                    Task {
                        await handleDrop(ids: workoutIDs)
                    }
                }
                
                log.debug("✅ Drop операция принята к обработке")
                return true
            }
            .sheet(isPresented: $showDialog) {
                log.info("📋 Показываем диалог выбора тренировок: \(dialogWorkouts.count) доступных")
                
                return MoveWorkoutsDialog(
                    workouts: dialogWorkouts,
                    onConfirm: { selectedIDs in
                        log.info("✅ Пользователь подтвердил перемещение: \(selectedIDs.count) тренировок")
                        showDialog = false
                        Task {
                            await viewModel.moveWorkouts(withIDs: selectedIDs, to: dayDate)
                        }
                    },
                    onCancel: {
                        log.info("❌ Пользователь отменил перемещение")
                        showDialog = false
                    }
                )
            }
            .onChange(of: isTargeted) { newValue in
                log.debug("🎯 Состояние таргетинга изменено: \(newValue ? "активен" : "неактивен") для \(DateFormatter().string(from: dayDate), privacy: .public)")
            }
    }

    /// Обрабатывает drop операцию с валидацией и выбором действия
    /// - Parameter ids: Массив ID перетаскиваемых тренировок
    private func handleDrop(ids: [String]) async {
        log.info("🔄 Начинаем обработку drop операции с \(ids.count) ID")
        
        guard !ids.isEmpty else {
            log.warning("⚠️ Пустой массив ID для drop операции")
            return
        }
        
        // Валидируем перетаскиваемые тренировки
        log.debug("🔍 Валидируем перетаскивание на дату: \(DateFormatter().string(from: dayDate), privacy: .public)")
        let validationResult = viewModel.validateDraggedIDs(ids, to: dayDate)
        let allowedIDs = validationResult.allowedIDs
        
        log.info("✅ Валидация завершена: разрешено \(allowedIDs.count) из \(ids.count) тренировок")
        
        if let firstError = validationResult.firstError {
            log.warning("⚠️ Ошибка валидации: \(firstError.localizedDescription, privacy: .public)")
        }
        
        // Если нет разрешённых тренировок - прекращаем
        guard !allowedIDs.isEmpty else {
            log.warning("🚫 Нет разрешённых тренировок для перемещения")
            return
        }

        // Определяем стратегию действия
        if allowedIDs.count == 1 {
            // Одна тренировка - перемещаем сразу
            log.info("🚀 Перемещаем одну тренировку напрямую: \(allowedIDs.first!, privacy: .public)")
            await viewModel.moveWorkouts(withIDs: allowedIDs, to: dayDate)
            
        } else {
            // Несколько тренировок - показываем диалог выбора
            log.info("📋 Показываем диалог для выбора из \(allowedIDs.count) тренировок")
            
            await MainActor.run {
                log.debug("🔄 Получаем данные тренировок для диалога...")
                self.dialogWorkouts = viewModel.workoutsByIDs(allowedIDs)
                
                log.debug("📋 Подготовлены тренировки для диалога: \(self.dialogWorkouts.count)")
                for (index, workout) in self.dialogWorkouts.enumerated() {
                    log.debug("📋 [\(index)]: '\(workout.name, privacy: .public)' (ID: \(workout.id, privacy: .public))")
                }
                
                self.showDialog = true
                log.info("✅ Диалог выбора тренировок активирован")
            }
        }
    }
}

/// Расширение View для удобного применения drag & drop функциональности
extension View {
    /// Добавляет поддержку drag & drop для дня календаря
    /// - Parameters:
    ///   - viewModel: ViewModel календаря для обработки операций
    ///   - date: Дата дня календаря
    /// - Returns: View с поддержкой перетаскивания тренировок
    func asCalendarDayDropTarget(_ viewModel: CalendarViewModel, date: Date) -> some View {
        log.debug("🎯 Применяем DayDropTarget к view для даты: \(DateFormatter().string(from: date), privacy: .public)")
        return self.modifier(DayDropTargetModifier(viewModel: viewModel, dayDate: date))
    }
}

// MARK: - Расширения для логирования

extension Array where Element == String {
    /// Логирует подробную статистику массива ID тренировок
    func logDropStats(prefix: String = "") {
        let protocolIDs = self.filter { $0.contains("|") }
        let regularIDs = self.filter { !$0.contains("|") }
        let uniqueIDs = Set(self)
        
        log.debug("\(prefix, privacy: .public)📊 Drop статистика:")
        log.debug("  📦 Всего ID: \(self.count)")
        log.debug("  🆔 Уникальных: \(uniqueIDs.count)")
        log.debug("  💪 Обычных тренировок: \(regularIDs.count)")
        log.debug("  🔗 Протокольных (с |): \(protocolIDs.count)")
        
        if self.count != uniqueIDs.count {
            log.warning("  ⚠️ Обнаружены дубликаты ID в drop операции")
        }
    }
}

extension Array where Element == Workout {
    /// Логирует статистику тренировок для диалога
    func logDialogStats(prefix: String = "") {
        let typeGroups = Dictionary(grouping: self) { $0.activityType ?? "unknown" }
        let typesSummary = typeGroups.map { "\($0.key): \($0.value.count)" }.joined(separator: ", ")
        
        log.debug("\(prefix, privacy: .public)📋 Диалог тренировок:")
        log.debug("  💪 Всего: \(self.count)")
        log.debug("  🏷️ По типам: \(typesSummary, privacy: .public)")
    }
}
