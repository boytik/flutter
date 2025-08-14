
import Foundation
import Combine

/// Generates a fake BLE JSON array periodically for UI testing (no hardware).
final class BLEMockService {
    let subject = PassthroughSubject<String, Never>()
    private var timer: Timer?

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            let payload = [
                ["timestamp": ISO8601DateFormatter().string(from: .init()),
                 "heartRate": Int.random(in: 60...120),
                 "steps": Int.random(in: 0...5)],
                ["timestamp": ISO8601DateFormatter().string(from: .init().addingTimeInterval(1)),
                 "heartRate": Int.random(in: 60...120),
                 "steps": Int.random(in: 0...5)]
            ]
            if let d = try? JSONSerialization.data(withJSONObject: payload),
               let s = String(data: d, encoding: .utf8) {
                self?.subject.send(s)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
