import Foundation
import CoreBluetooth
import Combine
import UIKit

enum BLEUUIDs {
    static let service: CBUUID? = nil
    static let metricsCharacteristic: CBUUID? = CBUUID(string: "00001235-0000-1000-8000-00805F9B34FB")
    static let batteryService: CBUUID = CBUUID(string: "180F")
}

final class BluetoothManager: NSObject, ObservableObject {
    static let shared = BluetoothManager()

    enum BluetoothError: LocalizedError, Equatable {
        case poweredOff
        case unauthorized
        case unsupported
        case unknown
        case connectFailed(Error)
        case discoverFailed

        var errorDescription: String? {
            switch self {
            case .poweredOff: return "Bluetooth выключен"
            case .unauthorized: return "Нет разрешения на использование Bluetooth"
            case .unsupported: return "Bluetooth не поддерживается на этом устройстве"
            case .unknown: return "Неизвестная ошибка Bluetooth"
            case .connectFailed(let err): return "Не удалось подключиться: \(err.localizedDescription)"
            case .discoverFailed: return "Не удалось обнаружить нужные сервисы/характеристики"
            }
        }

        static func == (lhs: BluetoothError, rhs: BluetoothError) -> Bool {
            switch (lhs, rhs) {
            case (.poweredOff, .poweredOff),
                 (.unauthorized, .unauthorized),
                 (.unsupported, .unsupported),
                 (.unknown, .unknown),
                 (.discoverFailed, .discoverFailed):
                return true
            case (.connectFailed(let e1), .connectFailed(let e2)):
                let n1 = e1 as NSError, n2 = e2 as NSError
                return n1.domain == n2.domain && n1.code == n2.code
            default: return false
            }
        }
    }

    // MARK: Public state
    @Published private(set) var isReady: Bool = false
    @Published private(set) var isScanning: Bool = false
    @Published var lastError: BluetoothError?
    @Published private(set) var discoveredPeripherals: [CBPeripheral] = []
    @Published private(set) var connectedPeripheral: CBPeripheral?
    @Published private(set) var metricsCharacteristic: CBCharacteristic?

    // Поток сырых данных метрик (то, что дальше улетит «как есть»)
    let metricsDataSubject = PassthroughSubject<Data, Never>()
    var metricsDataPublisher: AnyPublisher<Data, Never> { metricsDataSubject.eraseToAnyPublisher() }

    // MARK: Private
    private var central: CBCentralManager!
    private let queue = DispatchQueue(label: "com.revive.bt.central")

    private override init() { super.init() }

    func activateIfNeeded() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: queue, options: [
                CBCentralManagerOptionShowPowerAlertKey: true
            ])
        } else {
            evaluateStateAndMaybeScan()
        }
    }

    func startScanning() {
        guard central != nil else { activateIfNeeded(); return }
        guard central.state == .poweredOn else {
            handleStateProblem(central.state)
            return
        }
        guard !isScanning else { return }

        let servicesFilter: [CBUUID]? = BLEUUIDs.service.map { [$0] }
        central.scanForPeripherals(withServices: servicesFilter,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.async { self.isScanning = true }
    }

    func stopScanning() {
        guard isScanning else { return }
        central.stopScan()
        DispatchQueue.main.async { self.isScanning = false }
    }

    func openBluetoothSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    private func evaluateStateAndMaybeScan() {
        switch central.state {
        case .poweredOn:
            DispatchQueue.main.async {
                self.isReady = true
                self.lastError = nil
            }
            startScanning()
        default:
            handleStateProblem(central.state)
        }
    }

    private func handleStateProblem(_ state: CBManagerState) {
        let error: BluetoothError
        switch state {
        case .unauthorized: error = .unauthorized
        case .unsupported:  error = .unsupported
        case .poweredOff:   error = .poweredOff
        default:            error = .unknown
        }
        DispatchQueue.main.async {
            self.isReady = false
            self.lastError = error
            self.isScanning = false
        }
    }

    private func appendDiscovered(_ peripheral: CBPeripheral) {
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            DispatchQueue.main.async { self.discoveredPeripherals.append(peripheral) }
        }
    }

    private func tryAutoConnect(_ peripheral: CBPeripheral) {
        central.connect(peripheral, options: nil)
    }

    private func discoverNeeded(on peripheral: CBPeripheral) {
        peripheral.delegate = self
        if let service = BLEUUIDs.service {
            peripheral.discoverServices([service, BLEUUIDs.batteryService])
        } else {
            peripheral.discoverServices(nil)
        }
    }

    private func discoverCharacteristics(on peripheral: CBPeripheral, for service: CBService) {
        if let metricUUID = BLEUUIDs.metricsCharacteristic,
           BLEUUIDs.service == nil || service.uuid == (BLEUUIDs.service ?? service.uuid) {
            peripheral.discoverCharacteristics([metricUUID], for: service)
        } else if service.uuid == BLEUUIDs.batteryService {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
}

// MARK: CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        evaluateStateAndMaybeScan()
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        appendDiscovered(peripheral)
        // Как во Flutter: сразу коннектимся к подходящим; без фильтра — ко всем (можно добавить эвристику по имени)
        if BLEUUIDs.service != nil {
            tryAutoConnect(peripheral)
        } else {
            tryAutoConnect(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        DispatchQueue.main.async { self.connectedPeripheral = peripheral }
        discoverNeeded(on: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async { self.lastError = .connectFailed(error ?? NSError(domain: "BLE", code: -1)) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async {
            if self.connectedPeripheral?.identifier == peripheral.identifier {
                self.connectedPeripheral = nil
                self.metricsCharacteristic = nil
            }
        }
    }
}

// MARK: CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            DispatchQueue.main.async { self.lastError = .connectFailed(error) }
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            DispatchQueue.main.async { self.lastError = .discoverFailed }
            return
        }
        for service in services {
            if let root = BLEUUIDs.service {
                if service.uuid == root || service.uuid == BLEUUIDs.batteryService {
                    discoverCharacteristics(on: peripheral, for: service)
                }
            } else {
                discoverCharacteristics(on: peripheral, for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error {
            DispatchQueue.main.async { self.lastError = .connectFailed(error) }
            return
        }
        guard let chars = service.characteristics else { return }

        if let metricUUID = BLEUUIDs.metricsCharacteristic,
           let metric = chars.first(where: { $0.uuid == metricUUID }) {
            DispatchQueue.main.async { self.metricsCharacteristic = metric }
            peripheral.setNotifyValue(true, for: metric)
            peripheral.readValue(for: metric)
        }

        if service.uuid == BLEUUIDs.batteryService {
            if let batteryChar = chars.first(where: { $0.properties.contains(.read) }) {
                peripheral.readValue(for: batteryChar)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            DispatchQueue.main.async { self.lastError = .connectFailed(error) }
            return
        }
        guard let data = characteristic.value else { return }

        // Ключевой момент: отдаём «сырьё» наверх, дальше оно уходит POST'ом как есть.
        metricsDataSubject.send(data)
    }
}
