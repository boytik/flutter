
import SwiftUI

public struct BLEScanView: View {
    @StateObject var vm = BLEViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            header
            list
            if let json = vm.lastJSONString {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Получен пакет данных")
                        .font(.headline)
                    Text("Длина: \(json.count) байт")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(action: { Task { await vm.sendToServer() } }) {
                            if vm.isUploading {
                                ProgressView()
                            } else {
                                Text(vm.uploadOK ? "Отправлено ✓" : "Отправить на сервер")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isUploading)

                        Button("Очистить") {
                            vm.lastJSONString = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                .padding(.horizontal)
            }

            if let err = vm.errorMessage {
                Text(err).foregroundStyle(.red)
            }

            Spacer()
        }
        .navigationTitle("Bluetooth")
        .onAppear { vm.startScan() }
        .onDisappear { vm.stopScan() }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 12) {
            statusBadge
            Spacer()
            Button(action: { vm.startScan() }) {
                Label("Сканировать", systemImage: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch vm.status {
        case .idle:
            Label("Готово", systemImage: "bolt.horizontal").foregroundStyle(.secondary)
        case .scanning:
            HStack {
                ProgressView()
                Text("Поиск устройств...")
            }
        case .connecting(let name):
            HStack {
                ProgressView()
                Text("Подключение к \(name)")
            }
        case .connected(let name):
            Label("Подключено: \(name)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .disconnected(let name):
            Label("Отключено: \(name ?? "")", systemImage: "xmark.circle").foregroundStyle(.secondary)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var list: some View {
        List(vm.devices) { d in
            HStack {
                VStack(alignment: .leading) {
                    Text(d.name).font(.headline)
                    Text(d.id.uuidString).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(d.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                Button("Подключить") { vm.connect(d) }
                    .buttonStyle(.bordered)
            }
        }
    }
}

#Preview {
    NavigationStack {
        BLEScanView()
    }
}
