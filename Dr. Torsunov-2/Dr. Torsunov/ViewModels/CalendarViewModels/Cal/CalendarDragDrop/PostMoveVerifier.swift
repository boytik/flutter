import Foundation
import OSLog

struct MoveVerifyResult {
    let date: Date
    let expectedIDs: [String]               // baseID(local)
    let serverIDs: [String]                 // baseID(server union)
    let matchedByAttrs: [String: String]    // localID -> serverID
    let serverDateForLocal: [String: Date]  // localID -> serverDate (если нашли)
    let serverError: Bool

    var present: [String] { Array(Set(expectedIDs).intersection(serverIDs)) }
    var missing: [String] {
        let byIdMissing = Set(expectedIDs).subtracting(serverIDs)
        let alsoPresent = Set(matchedByAttrs.keys)
        return Array(byIdMissing.subtracting(alsoPresent))
    }
}

final class PostMoveVerifier {
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "MoveVerify")
    private let client: CacheRequesting
    private let mapper = MoveWorkoutsService()

    init(client: CacheRequesting = CacheJSONClient()) {
        self.client = client
    }

    private func fetchServerDayRaw(email: String, date: Date) async throws -> [Workout] {
        let ymd = DateUtils.ymd.string(from: date)
        let url = ApiRoutes.Workouts.calendarDay(email: email, date: ymd)
        log.info("🔎 Verify fetch day \(ymd, privacy: .public) for \(email, privacy: .private) — \(url.absoluteString, privacy: .public)")
        let dtos: [PlannerItemDTO] = try await client.request(url, ttl: 0)
        let ws = dtos.flatMap { CalendarMapping.workouts(from: $0) }
        log.info("📥 Verify server raw \(ymd, privacy: .public): mapped=\(ws.count, privacy: .public)")
        return ws
    }

    private func filterSameDay(_ arr: [Workout], day: Date) -> [Workout] {
        let start = CalendarMath.iso.startOfDay(for: day)
        let res = arr.filter { CalendarMath.iso.isDate($0.date, inSameDayAs: start) }
        log.info("🗂️ Filter to same day \(DateUtils.ymd.string(from: day), privacy: .public): kept=\(res.count, privacy: .public)")
        return res
    }

    private func sameKind(_ a: Workout, _ b: Workout) -> Bool {
        DragDropValidators.normalize(workout: a) == DragDropValidators.normalize(workout: b)
    }

    /// Пытаемся сопоставить localID -> (serverID, serverDate)
    private func matchByAttributes(
        buckets: [(day: Date, workouts: [Workout])],
        moved: [Workout]
    ) -> ([String: String], [String: Date]) {

        var idMap: [String: String] = [:]     // localID -> serverID
        var dateMap: [String: Date] = [:]     // localID -> serverDate
        var usedServer = Set<String>()

        // Приоритет дней: target (offset 0) -> +1 -> -1
        let sortedBuckets = buckets.sorted { lhs, rhs in
            let l = CalendarMath.iso.startOfDay(for: lhs.day)
            let r = CalendarMath.iso.startOfDay(for: rhs.day)
            // 0, +1, -1 приоритет
            let today = CalendarMath.iso.startOfDay(for: buckets.first!.day) // buckets[0] = target
            func rank(_ d: Date) -> Int {
                let diff = CalendarMath.iso.dateComponents([.day], from: today, to: d).day ?? 0
                return (diff == 0) ? 0 : (diff == 1 ? 1 : 2) // 0 -> 1 -> 2
            }
            return rank(l) < rank(r)
        }

        for mw in moved {
            let mKind = DragDropValidators.normalize(workout: mw)
            let mLay  = mw.plannedLayers ?? 0
            let mSw   = mw.swimLayers ?? []

            var matched: (id: String, day: Date)? = nil

            // 1) Жёсткий матч: kind + layers + swim_layers
            outer: for (day, ws) in sortedBuckets {
                if let hit = ws.first(where: { sw in
                    !usedServer.contains(sw.id)
                    && sameKind(sw, mw)
                    && (sw.plannedLayers ?? 0) == mLay
                    && (sw.swimLayers ?? []) == mSw
                }) {
                    matched = (hit.id, day); break outer
                }
            }
            // 2) Мягкий: только kind — берём ПЕРВЫЙ доступный по приоритету дня
            if matched == nil {
                outer2: for (day, ws) in sortedBuckets {
                    if let hit = ws.first(where: { !usedServer.contains($0.id) && sameKind($0, mw) }) {
                        matched = (hit.id, day); break outer2
                    }
                }
            }

            if let m = matched {
                idMap[mw.id] = m.id
                dateMap[mw.id] = m.day
                usedServer.insert(m.id)
                log.info("🔁 matched local \(mw.id, privacy: .public) -> server \(m.id, privacy: .public) at \(DateUtils.ymd.string(from: m.day), privacy: .public)")
            }
        }
        return (idMap, dateMap)
    }

    // MARK: main

    func verify(email: String, targetDate: Date, movedIDs: [String], movedWorkouts: [Workout]) async -> MoveVerifyResult {
        let baseMoved = movedIDs.map(mapper.baseID(from:))
        let cal = CalendarMath.iso
        let dates = [
            targetDate,                                  // 0
            cal.date(byAdding: .day, value:  1, to: targetDate)!, // +1
            cal.date(byAdding: .day, value: -1, to: targetDate)!, // -1
        ]

        var lastErr: Error?
        var buckets: [(day: Date, workouts: [Workout])] = []
        let delays: [UInt64] = [250_000_000, 500_000_000, 1_000_000_000]

        for (i, backoff) in delays.enumerated() {
            do {
                buckets = try await withThrowingTaskGroup(of: (Date, [Workout]).self) { group in
                    for d in dates { group.addTask { (d, try await self.fetchServerDayRaw(email: email, date: d)) } }
                    var tmp: [(Date, [Workout])] = []
                    for try await (d, raw) in group {
                        tmp.append((d, self.filterSameDay(raw, day: d)))
                    }
                    return tmp
                }
                lastErr = nil
                break
            } catch {
                lastErr = error
                if i < delays.count - 1 { try? await Task.sleep(nanoseconds: backoff) }
            }
        }

        if let err = lastErr {
            log.error("❌ Verify failed: \(String(describing: err.localizedDescription), privacy: .public)")
            return MoveVerifyResult(date: targetDate, expectedIDs: baseMoved, serverIDs: [], matchedByAttrs: [:], serverDateForLocal: [:], serverError: true)
        }

        let union = buckets.flatMap { $0.workouts }
        let baseServer = union.map { mapper.baseID(from: $0.id) }

        // атрибутивный матч + серверная дата
        let (idMap, dateMap) = matchByAttributes(buckets: buckets, moved: movedWorkouts)

        let res = MoveVerifyResult(
            date: targetDate,
            expectedIDs: baseMoved,
            serverIDs: baseServer,
            matchedByAttrs: idMap,
            serverDateForLocal: dateMap,
            serverError: false
        )

        if res.missing.isEmpty {
            log.info("✅ Post-move verify OK for \(DateUtils.ymd.string(from: targetDate), privacy: .public).")
        } else {
            log.error("❌ Post-move verify FAILED for \(DateUtils.ymd.string(from: targetDate), privacy: .public). missing=\(res.missing.joined(separator: ","), privacy: .public)")
        }
        return res
    }

    @MainActor
    func verifyAndHeal(viewModel: CalendarViewModel,
                       email: String,
                       targetDate: Date,
                       movedWorkouts: [Workout],
                       autoReload: Bool = true) async {
        let ids = movedWorkouts.map { $0.id }
        let res = await verify(email: email, targetDate: targetDate, movedIDs: ids, movedWorkouts: movedWorkouts)
        guard !res.serverError else { return }

        // 1) Ремап ID (если сервер их сменил)
        if !res.matchedByAttrs.isEmpty {
            viewModel.applyServerIDRemap(res.matchedByAttrs, inMonthOf: targetDate)
        }

        // 2) Коррекция даты (если сервер положил в соседний день)
        //    Преобразуем: newID -> serverDate
        if !res.serverDateForLocal.isEmpty {
            var mapNewIdToDate: [String: Date] = [:]
            for (localID, serverDate) in res.serverDateForLocal {
                let newID = res.matchedByAttrs[localID] ?? localID
                if CalendarMath.iso.startOfDay(for: serverDate) != CalendarMath.iso.startOfDay(for: targetDate) {
                    mapNewIdToDate[newID] = CalendarMath.iso.startOfDay(for: serverDate)
                }
            }
            if !mapNewIdToDate.isEmpty {
                viewModel.applyServerDateCorrection(mapNewIdToDate)
            }
        }

        // 3) Если реально отсутствуют — да, перезагружаем
        if !res.missing.isEmpty, autoReload {
            log.error("🛠️ Healing: server/day mismatch detected — reloading month")
            await viewModel.reload(role: viewModel.role)
        }
    }
}
