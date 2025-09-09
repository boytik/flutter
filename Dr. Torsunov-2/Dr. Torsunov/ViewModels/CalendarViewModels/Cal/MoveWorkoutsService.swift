import Foundation
import OSLog

private let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app",
    category: "MoveWorkoutsService"
)

/// Сервис для перемещения тренировок между датами
/// Обрабатывает API-запросы и синхронизацию офлайн-кэша
struct MoveWorkoutsService {

    // MARK: - Network (минимальный payload)

    /// Минимальный запрос перемещения (как запасной вариант).
    /// Отправляет массив `{ workout_uuid, date }`, где:
    ///  - `workout_uuid` — БАЗОВЫЙ UUID (без суффиксов протокола)
    ///  - `date` — строка `"yyyy-MM-dd HH:mm:ss"` на полночь целевого дня
    func sendMoveRequest(email: String, targetDate: Date, selectedIDs: [String]) async throws {
        log.info("📤 Начинаем отправку запроса на перемещение тренировок…")
        log.debug("👤 Email: \(email, privacy: .private)")

        // Локальная полуночь -> "yyyy-MM-dd HH:mm:ss"
        let midnight = CalendarMath.iso.startOfDay(for: targetDate)
        let targetDateString = DateUtils.ymdhmsSp.string(from: midnight)

        log.debug("📅 Целевая дата (полночь): \(targetDateString, privacy: .public)")
        log.debug("🆔 Количество тренировок: \(selectedIDs.count)")

        struct MoveItem: Codable {
            let workout_uuid: String
            let date: String  // "yyyy-MM-dd HH:mm:ss"
        }

        // ⚠️ На всякий случай сами обрезаем до baseID
        let bodyItems: [MoveItem] = selectedIDs.map { id in
            let bid = baseID(from: id)
            log.debug("📦 Добавляем в запрос ID: \(bid, privacy: .public) → \(targetDateString, privacy: .public)")
            return MoveItem(workout_uuid: bid, date: targetDateString)
        }

        let apiURL = APIEnv.baseURL.appendingPathComponent("/workout_calendar/\(email)")
        log.debug("🌐 URL для запроса: \(apiURL.absoluteString, privacy: .public)")

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")     // ← добавили

        do {
            let body = try JSONEncoder().encode(bodyItems)
            request.httpBody = body
            let preview = String(data: body.prefix(2048), encoding: .utf8) ?? ""
            log.info("➡️ MOVE MIN POST \(apiURL.absoluteString, privacy: .public) items=\(bodyItems.count, privacy: .public) bytes=\(body.count, privacy: .public) preview=\(preview, privacy: .public)")
        } catch {
            log.error("❌ Ошибка кодирования тела запроса: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        if let authToken = UserDefaults.standard.string(forKey: "auth_token"), !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            log.debug("🔐 Добавлен токен авторизации")
        } else {
            log.warning("⚠️ Токен авторизации отсутствует")
        }

        log.info("🚀 Отправляем HTTP запрос…")
        let (responseData, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse {
            log.debug("📥 HTTP код: \(http.statusCode)")
            guard (200...299).contains(http.statusCode) else {
                let msg = String(data: responseData, encoding: .utf8) ?? "Неизвестная ошибка"
                log.error("❌ Сервер вернул ошибку \(http.statusCode): \(msg, privacy: .public)")
                throw NSError(domain: "MoveAPI", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(msg)"])
            }
            log.info("✅ Сервер успешно обработал запрос")
            if let txt = String(data: responseData, encoding: .utf8) {
                log.debug("📄 Ответ сервера: \(txt, privacy: .public)")
            }
        } else {
            log.warning("⚠️ Получен нестандартный тип ответа")
        }
    }

    // MARK: - Offline cache sync

    /// Синхронизирует офлайн-кэш после перемещения:
    /// удаляет записи из месяцев-источников и добавляет их в месяц назначения.
    func updateOfflineCache(
        prevPlanned: [Workout],
        updatedMonthPlanned: [Workout],
        movedIDs: [String],
        newDate: Date,
        offlineStore: WorkoutCacheStore
    ) {
        log.info("💾 Начинаем синхронизацию офлайн кэша после перемещения…")
        log.debug("🔢 Перемещено тренировок: \(movedIDs.count)")
        log.debug("📅 Новая дата: \(DateUtils.ymd.string(from: newDate), privacy: .public)")

        // Месяцы-источники (по старым датам)
        let sourceMonthKeys = Set(
            prevPlanned
                .filter { movedIDs.contains($0.id) }
                .map { MonthKey.from(date: $0.date) }
        )

        log.debug("📂 Найдено месяцев-источников: \(sourceMonthKeys.count)")
        sourceMonthKeys.forEach {
            log.debug("📂 Месяц-источник: \($0.description, privacy: .public)")
        }

        // Месяц назначения
        let destinationMonthKey = MonthKey.from(date: newDate)
        log.debug("📂 Месяц назначения: \(destinationMonthKey.description, privacy: .public)")

        // 1) Удаляем из месяцев-источников
        log.info("🗑️ Удаляем тренировки из месяцев-источников…")
        var sourceUpdatesCount = 0

        for monthKey in sourceMonthKeys {
            do {
                if var env = try offlineStore.loadMonth(monthKey) {
                    let before = env.workouts.count
                    env.workouts.removeAll { movedIDs.contains($0.id) }
                    let removed = before - env.workouts.count

                    env.fetchedAt = Date()
                    env.etag = nil // инвалидируем etag, чтобы не держаться за старую версию

                    try offlineStore.saveMonth(env)
                    sourceUpdatesCount += 1

                    log.debug("✅ Из месяца \(monthKey.description, privacy: .public) удалено \(removed) тренировок")
                } else {
                    log.debug("⚠️ Месяц-источник \(monthKey.description, privacy: .public) не найден в кэше")
                }
            } catch {
                log.error("❌ Ошибка обновления месяца-источника \(monthKey.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        log.info("✅ Обновлено месяцев-источников: \(sourceUpdatesCount)")

        // 2) Добавляем в месяц назначения (без дублей по ID)
        log.info("📥 Добавляем тренировки в месяц назначения…")

        let movedCached: [CachedWorkout] = updatedMonthPlanned
            .filter { movedIDs.contains($0.id) }
            .map { w in
                log.debug("🔄 Конвертируем тренировку для кэша: '\(w.name, privacy: .public)' (ID: \(w.id, privacy: .public))")
                return CachedWorkout(
                    id: w.id,
                    name: w.name,
                    date: newDate,
                    durationSec: w.duration,
                    type: w.activityType,
                    updatedAt: Date()
                )
            }

        log.debug("🔄 Подготовлено кэшированных тренировок: \(movedCached.count)")

        do {
            if var dest = try offlineStore.loadMonth(destinationMonthKey) {
                log.debug("📂 Обновляем существующий месяц назначения…")

                let existing = Set(dest.workouts.map(\.id))
                let toAppend = movedCached.filter { !existing.contains($0.id) }

                dest.workouts.append(contentsOf: toAppend)
                dest.fetchedAt = Date()
                dest.etag = nil // тоже сбросить etag

                try offlineStore.saveMonth(dest)
                log.info("✅ В существующий месяц добавлено \(toAppend.count) новых тренировок")
            } else {
                log.debug("📂 Создаём новый месяц назначения…")
                let newEnv = CachedMonthEnvelope(
                    monthKey: destinationMonthKey,
                    fetchedAt: Date(),
                    etag: nil,
                    workouts: movedCached,
                    softDeletedIDs: []
                )
                try offlineStore.saveMonth(newEnv)
                log.info("✅ Создан новый месяц с \(movedCached.count) тренировками")
            }
        } catch {
            log.error("❌ Ошибка обновления месяца назначения: \(error.localizedDescription, privacy: .public)")
        }

        log.info("✅ Синхронизация офлайн кэша завершена")
    }

    // MARK: - Helpers

    /// Извлекает базовый UUID без суффиксов протокола (например, "abc|water1" → "abc")
    func baseID(from fullID: String) -> String {
        fullID.split(separator: "|", maxSplits: 1).first.map(String.init) ?? fullID
    }
}

// MARK: - Debug helpers

extension Array where Element == String {
    /// Логирует статистику массива ID (обычные/протокольные)
    func logIDStats(prefix: String = "") {
        let protocolIDs = filter { $0.contains("|") }
        let regularIDs  = filter { !$0.contains("|") }
        log.debug("\(prefix, privacy: .public)🆔 ID статистика: всего \(count), обычных \(regularIDs.count), протокольных \(protocolIDs.count)")
    }
}
