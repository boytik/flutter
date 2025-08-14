import Foundation
import Combine
import OSLog

/// Glue between BLEManager and networking. Keeps last JSON payload ready to upload.
@MainActor
final class BLEViewModel: ObservableObject {
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var status: BLEConnectionStatus = .idle
    @Published var lastJSONString: String? = nil
    @Published var isUploading: Bool = false
    @Published var uploadOK: Bool = false
    @Published var errorMessage: String? = nil

    private let ble: BLEManager
    private let uploader: BLEUploadRepository
    private var cancellables = Set<AnyCancellable>()

    // Logger
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "BLEVM")

    init(ble: BLEManager = BLEManager(), uploader: BLEUploadRepository = BLEUploadRepositoryImpl()) {
        self.ble = ble
        self.uploader = uploader
        log.info("BLEViewModel init")

        ble.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ds in
                self?.devices = ds
                let names = ds.map { $0.name }.joined(separator: ", ")
                self?.log.debug("devices updated count=\(ds.count, privacy: .public) names=\(names, privacy: .public)")
            }
            .store(in: &cancellables)

        ble.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] s in
                self?.status = s
                self?.log.info("status -> \(String(describing: s), privacy: .public)")
            }
            .store(in: &cancellables)

        ble.jsonMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] json in
                self?.lastJSONString = json
                self?.log.info("json received bytes=\(json.utf8.count, privacy: .public)")
                let preview = String(json.prefix(120))   // <- просто создаём String
                self?.log.debug("json preview=\(preview, privacy: .public)")
            }
            .store(in: &cancellables)

    }

    func startScan() {
        log.info("startScan()")
        ble.startScan()
    }

    func stopScan()  {
        log.info("stopScan()")
        ble.stopScan()
    }

    func connect(_ d: DiscoveredDevice) {
        log.info("connect() name=\(d.name, privacy: .public) id=\(d.id.uuidString, privacy: .public)")
        ble.connect(d)
    }

    func disconnect() {
        log.info("disconnect()")
        ble.disconnect()
    }

    func sendToServer() async {
        guard let json = lastJSONString, !json.isEmpty else {
            errorMessage = "Нет данных для отправки"
            log.warning("sendToServer: no data")
            return
        }
        isUploading = true
        uploadOK = false
        errorMessage = nil

        log.info("POST /insert_data bytes=\(json.utf8.count, privacy: .public) url=\(ApiRoutes.Workouts.insertData.absoluteString, privacy: .public)")

        do {
            try await uploader.sendInsertData(rawJSONString: json)
            uploadOK = true
            lastJSONString = nil
            log.info("upload OK")
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = msg
            log.error("upload failed: \(msg, privacy: .public)")
        }

        isUploading = false
    }
}
