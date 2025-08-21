import Foundation
import Combine

final class BLEUploadPump {
    private let repo: BLEUploadRepository
    private var cancellables = Set<AnyCancellable>()
    private let queue = DispatchQueue(label: "com.revive.ble.upload")

    private let flushInterval: TimeInterval = 0.8
    private let maxBatch: Int = 10

    init(repo: BLEUploadRepository = BLEUploadRepositoryImpl()) {
        self.repo = repo
    }

    func start(with provider: BLEDataProvider) {
        stop()
        provider.rawJSONStringPublisher
            .receive(on: queue)
            .buffer(size: maxBatch, prefetch: .keepFull, whenFull: .dropOldest)
            .collect(.byTimeOrCount(queue, .seconds(flushInterval), maxBatch))
            .filter { !$0.isEmpty }
            .sink { [weak self] batch in
                Task.detached { [weak self] in
                    guard let self else { return }
                    for raw in batch {
                        await self.sendWithRetry(raw: raw)
                    }
                }
            }
            .store(in: &cancellables)
    }

    func stop() { cancellables.removeAll() }

    private func sendWithRetry(raw: String) async {
        let delays: [UInt64] = [0, 500, 1500, 3000]
        for (i, delay) in delays.enumerated() {
            do {
                try await repo.sendInsertData(rawJSONString: raw)
                return
            } catch {
                if i == delays.count - 1 {
                    #if DEBUG
                    print("BLE upload failed:", error)
                    #endif
                } else {
                    try? await Task.sleep(nanoseconds: delay * 1_000_000)
                }
            }
        }
    }
}
