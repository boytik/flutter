import SwiftUI

@MainActor
final class ActivityViewModel: ObservableObject {
    @Published var activities: [Activity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repository: ActivityRepository
    private let ns = "activities"                 // namespace для KVStore
    private let kvKeyAll = "all"                  // ключ списка
    private let kvTTL: TimeInterval = 60 * 10     // 10 минут для оффлайна

    init(repository: ActivityRepository = ActivityRepositoryImpl()) {
        self.repository = repository
        Task { await load() }
    }

    /// Загружает список активностей:
    /// 1) пробует оффлайн из KVStore (если есть) — мгновенно обновляет UI
    /// 2) параллельно тянет из сети (репозиторий внутри использует CachedHTTPClient)
    /// 3) по приходу сети — сохраняет в KVStore и обновляет UI
    func load() async {
        isLoading = true
        errorMessage = nil

        // 1) оффлайн (если есть) — показываем сразу
        if let cached: [Activity] = try? KVStore.shared.get([Activity].self, namespace: ns, key: kvKeyAll) {
            print("📦 KVStore HIT \(ns)/\(kvKeyAll) (\(cached.count) записей)")
            self.activities = cached
        }

        // 2) сеть
        do {
            print("🌐 fetch activities из сети…")
            let fresh = try await repository.fetchAll()
            self.activities = fresh

            // 3) сохранить в оффлайн
            try? KVStore.shared.put(fresh, namespace: ns, key: kvKeyAll, ttl: kvTTL)
            print("💾 KVStore SAVE \(ns)/\(kvKeyAll) (\(fresh.count) записей, ttl \(Int(kvTTL))s)")
        } catch {
            // если сети нет и оффлайна не было — покажем ошибку
            if activities.isEmpty {
                self.errorMessage = error.localizedDescription
                print("❌ activities fetch error: \(error.localizedDescription)")
            } else {
                print("⚠️ activities fetch error (показан оффлайн): \(error.localizedDescription)")
            }
        }

        isLoading = false
    }

    func upload(activity: Activity) async {
        errorMessage = nil
        do {
            try await repository.upload(activity: activity)
            // после успешной загрузки — обновим список, чтобы инвалидировать кэш/оффлайн
            await load()
        } catch {
            errorMessage = error.localizedDescription
            print("❌ upload error: \(error.localizedDescription)")
        }
    }

    func submit(activityId: String,
                comment: String?,
                beforeImage: UIImage?,
                afterImage: UIImage?) async {
        errorMessage = nil
        do {
            try await repository.submit(activityId: activityId,
                                        comment: comment,
                                        beforeImage: beforeImage,
                                        afterImage: afterImage)
            // после успешной отправки — обновим список
            await load()
        } catch {
            errorMessage = error.localizedDescription
            print("❌ submit error: \(error.localizedDescription)")
        }
    }

    // MARK: - Debug helpers (по желанию можно вызвать из UI)
    func clearOffline() {
        try? KVStore.shared.delete(namespace: ns, key: kvKeyAll)
        print("🧹 KVStore DELETE \(ns)/\(kvKeyAll)")
    }
}
