import Foundation
import Combine

// Единый протокол источника сырых BLE-строк JSON.
// Его реализуют и реальный адаптер, и (при необходимости) мок.
public protocol BLEDataProvider {
    var rawJSONStringPublisher: AnyPublisher<String, Never> { get }
}

/// Преобразует поток сырых Data из BluetoothManager в строки JSON,
/// совместимые с HTTPClient.postRawJSON (как во Flutter: шлём "как есть").
final class BluetoothManagerJSONAdapter: BLEDataProvider {
    private let subject = PassthroughSubject<String, Never>()
    private var cancellables = Set<AnyCancellable>()

    var rawJSONStringPublisher: AnyPublisher<String, Never> {
        subject.eraseToAnyPublisher()
    }

    init(manager: BluetoothManager = .shared) {
        manager.metricsDataPublisher
            .sink { [weak self] data in
                guard let self else { return }

                // 1) Если пришёл готовый JSON (UTF-8, начинается с [ или {) — прокидываем как есть.
                if let s = String(data: data, encoding: .utf8),
                   let first = s.trimmingCharacters(in: .whitespacesAndNewlines).first,
                   first == "[" || first == "{" {
                    self.subject.send(s)
                    return
                }

                // 2) Иначе заворачиваем "сырьё" в минимальный массив с timestamp + base64(raw)
                let payload: [[String: Any]] = [[
                    "timestamp": ISO8601DateFormatter().string(from: Date()),
                    "raw": data.base64EncodedString()
                ]]

                if let json = try? JSONSerialization.data(withJSONObject: payload),
                   let s = String(data: json, encoding: .utf8) {
                    self.subject.send(s)
                }
            }
            .store(in: &cancellables)
    }
}
