import Foundation
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app",
                         category: "CalendarMapping")

/// Утилиты для маппинга данных календаря и преобразования моделей
enum CalendarMapping {
    
    /// Универсальный детектор типа активности по ключевым словам
    /// Анализирует массив строк и определяет тип активности на основе содержащихся ключевых слов
    /// - Parameter strings: Массив строк для анализа (названия, описания, типы)
    /// - Returns: Ключ типа активности или nil если не удалось определить
    static func inferTypeKey(from strings: [String?]) -> String? {
        
        let haystack = strings.compactMap { $0?.lowercased() }.joined(separator: " | ")
        
        guard !haystack.isEmpty else {
            return nil
        }
        
        // Проверяем плавание/воду
        if haystack.contains("swim") || haystack.contains("плав") || haystack.contains("water") {
            return "swim"
        }
        
        // Проверяем бег/ходьбу
        if haystack.contains("run") || haystack.contains("бег") || haystack.contains("walk") || haystack.contains("ход") {
            return "run"
        }
        
        // Проверяем велосипед
        if haystack.contains("bike") || haystack.contains("velo") || haystack.contains("вел") || haystack.contains("cycl") {
            return "bike"
        }
        
        // Проверяем йогу/силовые
        if haystack.contains("yoga") || haystack.contains("йога") || haystack.contains("strength") || haystack.contains("сил") {
            return "yoga"
        }
        
        // Проверяем баню/сауну
        if haystack.contains("sauna") || haystack.contains("баня") || haystack.contains("хаммам") {
            return "sauna"
        }
        return nil
    }

    /// Преобразует DTO планировщика в массив тренировок с поддержкой протоколов
    /// Поддерживает специальные протоколы типа "вода → баня → вода"
    /// - Parameter dto: DTO объект от сервера
    /// - Returns: Массив тренировок (может быть несколько для протоколов)
    static func workouts(from dto: PlannerItemDTO) -> [Workout] {
        
        // Определяем дату из различных полей
        let rawDate = dto.date ?? dto.startDate ?? dto.plannedDate ?? dto.workoutDate
        
        guard let parsedDate = DateUtils.parse(rawDate) else {
            log.warning("❌ Не удалось распарсить дату из: '\(rawDate ?? "nil", privacy: .public)'")
            return []
        }

        // Вычисляем длительность
        let minutes = (dto.durationHours ?? 0) * 60 + (dto.durationMinutes ?? 0)
        
        // Определяем ID
        let baseID = dto.workoutUuid ?? dto.workoutKey ?? dto.id ?? UUID().uuidString
        
        // Определяем название
        let visibleName = dto.name ?? dto.type ?? dto.description ?? "Тренировка"

        // Определяем тип активности
        let fromBackend = dto.activityType?.lowercased()
        let inferred = inferTypeKey(from: [dto.activityType, dto.type, dto.name, dto.description])
        let finalType = (fromBackend?.isEmpty == false ? fromBackend : inferred) ?? "other"

        // Проверяем на протокол бани с водой
        let waterArray = dto.swimLayers ?? []
        let saunaLayers = dto.layers ?? 0
        let isSaunaProtocol = finalType.contains("sauna") || finalType.contains("баня")

        // --- ПРОТОКОЛ: баня + вода слева/справа
        if isSaunaProtocol && (saunaLayers > 0 || !waterArray.isEmpty) {
            var result: [Workout] = []

            // Вода слева (до бани)
            if let waterLeft = waterArray.first, waterLeft > 0 {
                result.append(Workout(
                    id: baseID + "|water1",
                    name: visibleName,
                    description: dto.description,
                    duration: minutes,
                    date: parsedDate,
                    activityType: "water",
                    plannedLayers: min(5, waterLeft),
                    swimLayers: nil
                ))
            }

            // Баня в центре
            if saunaLayers > 0 {
                result.append(Workout(
                    id: baseID + "|sauna",
                    name: visibleName,
                    description: dto.description,
                    duration: minutes,
                    date: parsedDate,
                    activityType: "sauna",
                    plannedLayers: min(5, saunaLayers),
                    swimLayers: nil
                ))
            }

            // Вода справа (после бани)
            if waterArray.count > 1, let waterRight = waterArray.dropFirst().first, waterRight > 0 {
                result.append(Workout(
                    id: baseID + "|water2",
                    name: visibleName,
                    description: dto.description,
                    duration: minutes,
                    date: parsedDate,
                    activityType: "water",
                    plannedLayers: min(5, waterRight),
                    swimLayers: nil
                ))
            }

            if !result.isEmpty {
                return result
            }
        }

        // Обычная тренировка (не протокол)
        let singleWorkout = Workout(
            id: baseID,
            name: visibleName,
            description: dto.description,
            duration: minutes,
            date: parsedDate,
            activityType: finalType,
            plannedLayers: dto.layers,
            swimLayers: dto.swimLayers
        )
        return [singleWorkout]
    }

    /// Удаляет дубликаты тренировок по ID или комбинации дата+название
    /// Использует два подхода: по уникальному ID или по составному ключу дата+название
    /// - Parameter plans: Массив тренировок для дедупликации
    /// - Returns: Массив уникальных тренировок
    static func dedup(_ plans: [Workout]) -> [Workout] {
        log.info("🔄 Начинаем дедупликацию \(plans.count) тренировок...")
        
        guard !plans.isEmpty else {
            log.debug("⚠️ Пустой массив для дедупликации")
            return []
        }
        
        var byID: [String: Workout] = [:]
        var seenKeys: Set<String> = []
        var duplicatesCount = 0
        
        for workout in plans {
            if !workout.id.isEmpty {
                // Дедупликация по ID
                if byID[workout.id] != nil {
                    duplicatesCount += 1
                } else {
                    byID[workout.id] = workout
                }
            } else {
                // Дедупликация по составному ключу дата+название
                let dateString = DateUtils.ymd.string(from: workout.date)
                let key = dateString + "|" + workout.name.lowercased()
                
                if seenKeys.contains(key) {
                    duplicatesCount += 1
                } else {
                    seenKeys.insert(key)
                    byID[key] = workout
                }
            }
        }
        
        let result = Array(byID.values)
        log.info("✅ Дедупликация завершена: \(plans.count) → \(result.count) (удалено \(duplicatesCount) дубликатов)")
        
        return result
    }

    /// Преобразует кэшированную тренировку в модель Workout для отображения
    /// Используется при загрузке данных из офлайн кэша
    /// - Parameter c: Кэшированная тренировка
    /// - Returns: Тренировка для UI
    static func workout(from c: CachedWorkout) -> Workout {
//        log.debug("🔄 Преобразуем кэшированную тренировку: '\(c.name, privacy: .public)' (ID: \(c.id, privacy: .public))")
        
        let workout = Workout(
            id: c.id,
            name: c.name,
            description: nil, // В кэше описание не сохраняется
            duration: c.durationSec ?? 0,
            date: c.date,
            activityType: c.type,
            plannedLayers: nil, // В кэше слои не сохраняются
            swimLayers: nil
        )
        
        return workout
    }
}

// MARK: - Расширения для логирования

extension Array where Element == Workout {
    /// Выводит статистику массива тренировок в лог
    func logWorkoutStats(prefix: String = "") {
        let typeGroups = Dictionary(grouping: self) { $0.activityType ?? "unknown" }
        let summary = typeGroups.map { "\($0.key): \($0.value.count)" }.joined(separator: ", ")
    }
}
