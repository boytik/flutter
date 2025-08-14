
import CoreBluetooth

enum BLEUUIDs {
//    static let service: CBUUID? = CBUUID(string: "00001234-0000-1000-8000-00805F9B34FB")
    static let metricsCharacteristic: CBUUID? = CBUUID(string: "00001235-0000-1000-8000-00805F9B34FB")
    static let batteryService: CBUUID = CBUUID(string: "180F") // опционально
    static let service: CBUUID? = nil
}
