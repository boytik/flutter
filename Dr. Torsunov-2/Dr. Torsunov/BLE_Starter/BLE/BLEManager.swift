import Foundation
import CoreBluetooth
import Combine
import OSLog

private let bleLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "BLE")

enum BLEConnectionStatus: Equatable {
    case idle
    case scanning
    case connecting(String) // device name/id
    case connected(String)  // device name/id
    case disconnected(String?)
    case error(String)
}

struct DiscoveredDevice: Identifiable, Hashable {
    let id: UUID
    var name: String
    let peripheral: CBPeripheral
    var rssi: Int

    // Уникальность только по id
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool { lhs.id == rhs.id }
}


/// Manages CoreBluetooth scanning, connections and characteristic notifications.
final class BLEManager: NSObject, ObservableObject {
    @Published private(set) var status: BLEConnectionStatus = .idle
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var connectedDevice: DiscoveredDevice?
    /// Emits raw *complete* JSON messages (UTF-8) reconstructed from fragments
    let jsonMessage = PassthroughSubject<String, Never>()

    private var central: CBCentralManager!
    private var metricsCharacteristic: CBCharacteristic?
    private var buffer = Data()

    private var scanTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private var targetService: CBUUID? { BLEUUIDs.service }
    private var targetCharacteristic: CBUUID? { BLEUUIDs.metricsCharacteristic }

    override init() {
        super.init()
        self.central = CBCentralManager(delegate: self, queue: .main)
        bleLog.info("BLEManager init; central state=\(self.central.state.rawValue, privacy: .public)")
    }

    func startScan() {
        guard central.state == .poweredOn else {
            status = .error("Bluetooth is not powered on")
            bleLog.error("startScan blocked: state=\(self.central.state.rawValue, privacy: .public)")
            return
        }
        devices = []
        status = .scanning
        let opts: [String: Any] = [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        if let s = targetService {
            central.scanForPeripherals(withServices: [s], options: opts)
            bleLog.info("startScan: filtered by service=\(s.uuidString, privacy: .public)")
        } else {
            central.scanForPeripherals(withServices: nil, options: opts)
            bleLog.info("startScan: no service filter")
        }
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.stopScan()
        }
        bleLog.info("scan timer set to 10s")
    }

    func stopScan() {
        central.stopScan()
        if case .scanning = status { status = .idle }
        bleLog.info("stopScan")
    }

    func connect(_ device: DiscoveredDevice) {
        stopScan()
        status = .connecting(device.name)
        central.connect(device.peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: true
        ])
        device.peripheral.delegate = self
        bleLog.info("connect to \(device.name, privacy: .public) id=\(device.id.uuidString, privacy: .public)")
    }

    func disconnect() {
        guard let p = connectedDevice?.peripheral else {
            bleLog.debug("disconnect: no connected peripheral")
            return
        }
        bleLog.info("disconnect requested for \(p.identifier.uuidString, privacy: .public)")
        central.cancelPeripheralConnection(p)
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            break
        case .unauthorized: status = .error("Bluetooth unauthorized")
        case .poweredOff:   status = .error("Bluetooth powered off")
        case .unsupported:  status = .error("Bluetooth unsupported")
        case .resetting:    status = .idle
        case .unknown:      status = .idle
        @unknown default:   status = .idle
        }
        bleLog.info("state=\(central.state.rawValue, privacy: .public)")
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Unknown"
        let newItem = DiscoveredDevice(id: peripheral.identifier, name: name, peripheral: peripheral, rssi: RSSI.intValue)

        if let idx = devices.firstIndex(where: { $0.id == newItem.id }) {
            // обновляем существующую запись (RSSI/имя)
            devices[idx].rssi = RSSI.intValue
            if devices[idx].name != name { devices[idx].name = name }
            bleLog.debug("didDiscover UPDATE name=\(name, privacy: .public) id=\(peripheral.identifier.uuidString, privacy: .public) rssi=\(RSSI.intValue, privacy: .public)")
        } else {
            devices.append(newItem)
            bleLog.info("didDiscover ADD name=\(name, privacy: .public) id=\(peripheral.identifier.uuidString, privacy: .public) rssi=\(RSSI.intValue, privacy: .public)")
        }

        // логи рекламы (оставь как у тебя)
        if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID], !uuids.isEmpty {
            let list = uuids.map { $0.uuidString }.joined(separator: ", ")
            bleLog.debug("adv service UUIDs=[\(list, privacy: .public)]")
        } else {
            bleLog.debug("adv service UUIDs=[]")
        }
        if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            bleLog.debug("manufacturer data len=\(mfg.count, privacy: .public)")
        }
    }



    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let dev = DiscoveredDevice(id: peripheral.identifier, name: peripheral.name ?? "Unknown", peripheral: peripheral, rssi: 0)
        connectedDevice = dev
        status = .connected(dev.name)
        peripheral.delegate = self
        peripheral.discoverServices(targetService != nil ? [targetService!] : nil)
        bleLog.info("didConnect \(peripheral.name ?? "Unknown", privacy: .public)")
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status = .error("Failed to connect: \(error?.localizedDescription ?? "-")")
        bleLog.error("didFailToConnect error=\(error?.localizedDescription ?? "-", privacy: .public)")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        status = .disconnected(peripheral.name)
        connectedDevice = nil
        metricsCharacteristic = nil
        buffer.removeAll()
        bleLog.warning("didDisconnect \(peripheral.name ?? "Unknown", privacy: .public) error=\(error?.localizedDescription ?? "-", privacy: .public)")
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            status = .error("Service discovery error: \(error.localizedDescription)")
            bleLog.error("didDiscoverServices error=\(error.localizedDescription, privacy: .public)")
            return
        }
        guard let services = peripheral.services else { return }
        bleLog.info("didDiscoverServices count=\(services.count, privacy: .public)")
        for s in services {
            bleLog.debug("service uuid=\(s.uuid.uuidString, privacy: .public)")
            peripheral.discoverCharacteristics(targetCharacteristic != nil ? [targetCharacteristic!] : nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            status = .error("Characteristic discovery error: \(error.localizedDescription)")
            bleLog.error("didDiscoverCharacteristics error=\(error.localizedDescription, privacy: .public)")
            return
        }
        guard let chars = service.characteristics else { return }
        bleLog.info("didDiscoverCharacteristics for=\(service.uuid.uuidString, privacy: .public) count=\(chars.count, privacy: .public)")
        for c in chars {
            let hasNotify = c.properties.contains(.notify)
            bleLog.debug("char uuid=\(c.uuid.uuidString, privacy: .public) notify=\(hasNotify, privacy: .public)")
            // auto-pick the targeted notify characteristic, or first notify-capable if none specified
            if let t = targetCharacteristic, c.uuid == t {
                metricsCharacteristic = c
            } else if metricsCharacteristic == nil && hasNotify {
                metricsCharacteristic = c
            }
        }
        if let m = metricsCharacteristic {
            bleLog.info("select characteristic uuid=\(m.uuid.uuidString, privacy: .public)")
            peripheral.setNotifyValue(true, for: m)
            bleLog.info("setNotifyValue(true) for \(m.uuid.uuidString, privacy: .public)")
        } else {
            bleLog.warning("metricsCharacteristic not found on service \(service.uuid.uuidString, privacy: .public)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            status = .error("Notify state error: \(error.localizedDescription)")
            bleLog.error("notify state error for \(characteristic.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        bleLog.info("notify state isEnabled=\(characteristic.isNotifying, privacy: .public) for \(characteristic.uuid.uuidString, privacy: .public)")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            status = .error("Value update error: \(error.localizedDescription)")
            bleLog.error("didUpdateValue error=\(error.localizedDescription, privacy: .public)")
            return
        }
        guard let data = characteristic.value, !data.isEmpty else { return }
        buffer.append(data)
        bleLog.debug("didUpdateValue len=\(data.count, privacy: .public) bufferLen=\(self.buffer.count, privacy: .public) char=\(characteristic.uuid.uuidString, privacy: .public)")

        if let text = String(data: buffer, encoding: .utf8) {
            let preview = String(text.prefix(160))
            bleLog.debug("buffer utf8 prefix160=\(preview, privacy: .public)")
            if let complete = Self.extractCompleteJSONArray(from: text) {
                bleLog.info("complete JSON OK, length=\(complete.utf8.count, privacy: .public)")
                jsonMessage.send(complete)
                buffer.removeAll(keepingCapacity: false)
            } else {
                bleLog.debug("json not complete yet")
            }
        } else {
            bleLog.debug("buffer not valid UTF-8 yet; size=\(self.buffer.count, privacy: .public)")
        }
    }

    // Attempts to detect a complete JSON array message `[...]`. If not complete, returns nil.
    private static func extractCompleteJSONArray(from text: String) -> String? {
        guard text.first == "[", text.last == "]" else { return nil }
        // Quick validation: try JSON parse
        let data = Data(text.utf8)
        if (try? JSONSerialization.jsonObject(with: data)) != nil {
            return text
        }
        return nil
    }
}
