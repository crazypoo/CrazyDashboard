//
//  PTJieliBLETransport.swift
//  CrazyDashboard
//
//  EN: Discovers the Jieli OTA GATT surface without implementing RCSP packets.
//  ES: Descubre la superficie GATT OTA de Jieli sin implementar paquetes RCSP.
//  中文：发现 Jieli OTA 的 GATT 结构，但不自行实现 RCSP 数据包。
//

@preconcurrency import CoreBluetooth
import Foundation

nonisolated public enum PTJieliCharacteristicMapping: String, Codable, Equatable, Sendable {
    case automatic
    case ae01WriteAE02Notify
    case ae02WriteAE01Notify
}

nonisolated public struct PTJieliCharacteristicDescriptor: Codable, Equatable, Sendable {
    public let uuid: String
    public let supportsWrite: Bool
    public let supportsWriteWithoutResponse: Bool
    public let supportsNotify: Bool
    public let supportsIndicate: Bool

    public init(
        uuid: String,
        supportsWrite: Bool,
        supportsWriteWithoutResponse: Bool,
        supportsNotify: Bool,
        supportsIndicate: Bool
    ) {
        self.uuid = uuid
        self.supportsWrite = supportsWrite
        self.supportsWriteWithoutResponse = supportsWriteWithoutResponse
        self.supportsNotify = supportsNotify
        self.supportsIndicate = supportsIndicate
    }

    public var canWrite: Bool {
        supportsWrite || supportsWriteWithoutResponse
    }

    public var canNotify: Bool {
        supportsNotify || supportsIndicate
    }
}

nonisolated public struct PTJieliCharacteristicSelection: Codable, Equatable, Sendable {
    public let writeUUID: String
    public let notifyUUID: String
    public let mapping: PTJieliCharacteristicMapping

    public init(
        writeUUID: String,
        notifyUUID: String,
        mapping: PTJieliCharacteristicMapping
    ) {
        self.writeUUID = writeUUID
        self.notifyUUID = notifyUUID
        self.mapping = mapping
    }
}

nonisolated public enum PTJieliCharacteristicResolverError: Error, Equatable, LocalizedError, Sendable {
    case missingWriteCharacteristic
    case missingNotifyCharacteristic
    case explicitMappingUnavailable
    case ambiguousMapping

    public var errorDescription: String? {
        switch self {
        case .missingWriteCharacteristic:
            return "Jieli OTA 缺少可写特征"
        case .missingNotifyCharacteristic:
            return "Jieli OTA 缺少通知特征"
        case .explicitMappingUnavailable:
            return "指定的 AE01/AE02 特征映射不可用"
        case .ambiguousMapping:
            return "AE01/AE02 特征映射不明确，需要真实设备确认"
        }
    }
}

// EN: Resolve only from characteristic properties; never guess a write/notify role from a UUID alone.
// ES: Resuelve solo por las propiedades de las características; nunca adivina el rol solo por el UUID.
// 中文：只根据特征属性解析，不会仅凭 UUID 猜测写入或通知角色。
nonisolated public enum PTJieliCharacteristicResolver {
    public static func resolve(
        descriptors: [PTJieliCharacteristicDescriptor],
        mapping: PTJieliCharacteristicMapping = .automatic
    ) throws -> PTJieliCharacteristicSelection {
        let normalized = descriptors.map { descriptor in
            PTJieliCharacteristicDescriptor(
                uuid: normalize(descriptor.uuid),
                supportsWrite: descriptor.supportsWrite,
                supportsWriteWithoutResponse: descriptor.supportsWriteWithoutResponse,
                supportsNotify: descriptor.supportsNotify,
                supportsIndicate: descriptor.supportsIndicate
            )
        }
        let writeCandidates = normalized.filter(\.canWrite)
        let notifyCandidates = normalized.filter(\.canNotify)

        guard !writeCandidates.isEmpty else {
            throw PTJieliCharacteristicResolverError.missingWriteCharacteristic
        }
        guard !notifyCandidates.isEmpty else {
            throw PTJieliCharacteristicResolverError.missingNotifyCharacteristic
        }

        switch mapping {
        case .automatic:
            guard writeCandidates.count == 1, notifyCandidates.count == 1 else {
                throw PTJieliCharacteristicResolverError.ambiguousMapping
            }
            return PTJieliCharacteristicSelection(
                writeUUID: writeCandidates[0].uuid,
                notifyUUID: notifyCandidates[0].uuid,
                mapping: .automatic
            )
        case .ae01WriteAE02Notify:
            guard normalized.contains(where: {
                normalize($0.uuid) == "AE01" && $0.canWrite
            }), normalized.contains(where: {
                normalize($0.uuid) == "AE02" && $0.canNotify
            }) else {
                throw PTJieliCharacteristicResolverError.explicitMappingUnavailable
            }
            return PTJieliCharacteristicSelection(
                writeUUID: "AE01",
                notifyUUID: "AE02",
                mapping: mapping
            )
        case .ae02WriteAE01Notify:
            guard normalized.contains(where: {
                normalize($0.uuid) == "AE02" && $0.canWrite
            }), normalized.contains(where: {
                normalize($0.uuid) == "AE01" && $0.canNotify
            }) else {
                throw PTJieliCharacteristicResolverError.explicitMappingUnavailable
            }
            return PTJieliCharacteristicSelection(
                writeUUID: "AE02",
                notifyUUID: "AE01",
                mapping: mapping
            )
        }
    }

    private static func normalize(_ uuid: String) -> String {
        let compact = uuid.uppercased().replacingOccurrences(of: "-", with: "")
        if compact.count == 4 {
            return compact
        }

        // EN: Bluetooth SIG 16-bit UUIDs are embedded in the first 8 characters of the base UUID.
        // ES: Los UUID de 16 bits de Bluetooth SIG están incrustados en los primeros 8 caracteres del UUID base.
        // 中文：Bluetooth SIG 的 16 位 UUID 嵌入在标准基础 UUID 的前 8 个字符中。
        if compact.hasPrefix("0000"), compact.count >= 8 {
            return String(compact.dropFirst(4).prefix(4))
        }
        return compact
    }
}

nonisolated public struct PTJieliBLETransportDiscovery: Codable, Equatable, Sendable {
    public let peripheralIdentifier: UUID
    public let peripheralName: String
    public let serviceUUID: String
    public let characteristics: [PTJieliCharacteristicDescriptor]
    public let selection: PTJieliCharacteristicSelection

    public init(
        peripheralIdentifier: UUID,
        peripheralName: String,
        serviceUUID: String,
        characteristics: [PTJieliCharacteristicDescriptor],
        selection: PTJieliCharacteristicSelection
    ) {
        self.peripheralIdentifier = peripheralIdentifier
        self.peripheralName = peripheralName
        self.serviceUUID = serviceUUID
        self.characteristics = characteristics
        self.selection = selection
    }
}

nonisolated public enum PTJieliBLETransportState: String, Codable, Equatable, Sendable {
    case idle
    case scanning
    case connecting
    case discovering
    case enablingNotifications
    case ready
    case disconnected
    case failed
}

nonisolated public enum PTJieliBLETransportError: Error, Equatable, LocalizedError, Sendable {
    case busy
    case bluetoothUnavailable
    case scanTimeout
    case connectionTimeout
    case connectionFailed
    case serviceNotFound
    case characteristicNotFound
    case notificationFailed
    case writeFailed
    case notConnected
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .busy:
            return "Jieli OTA 传输正在使用中"
        case .bluetoothUnavailable:
            return "蓝牙当前不可用"
        case .scanTimeout:
            return "未发现 Jieli OTA 设备"
        case .connectionTimeout:
            return "Jieli OTA 连接超时"
        case .connectionFailed:
            return "Jieli OTA 连接失败"
        case .serviceNotFound:
            return "未发现 AE00 OTA 服务"
        case .characteristicNotFound:
            return "未发现 AE01/AE02 OTA 特征"
        case .notificationFailed:
            return "Jieli OTA 通知开启失败"
        case .writeFailed:
            return "Jieli OTA 数据写入失败"
        case .notConnected:
            return "Jieli OTA 设备未连接"
        case .cancelled:
            return "Jieli OTA 传输已取消"
        }
    }
}

@MainActor
public final class PTJieliBLETransport: NSObject {
    public static let otaServiceUUID = CBUUID(string: "0000AE00-0000-1000-8000-00805F9B34FB")
    public static let ae01UUID = CBUUID(string: "0000AE01-0000-1000-8000-00805F9B34FB")
    public static let ae02UUID = CBUUID(string: "0000AE02-0000-1000-8000-00805F9B34FB")

    public private(set) var state: PTJieliBLETransportState = .idle
    public private(set) var discovery: PTJieliBLETransportDiscovery?

    public var isReady: Bool {
        state == .ready && peripheral != nil && writeCharacteristic != nil && notifyCharacteristic != nil
    }

    public var writeUsesResponse: Bool {
        writeCharacteristic?.properties.contains(.write) == true
    }

    private let centralManager: CBCentralManager
    private var peripheral: CBPeripheral?
    private var otaService: CBService?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var targetIdentifier: UUID?
    private var targetName: String?
    private var mapping: PTJieliCharacteristicMapping = .automatic
    private var pendingDiscovery: PTJieliBLETransportDiscovery?
    private var connectionContinuation: CheckedContinuation<PTJieliBLETransportDiscovery, any Error>?
    private var writeContinuation: CheckedContinuation<Void, any Error>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var writeTimeoutTask: Task<Void, Never>?
    private var notificationContinuation: AsyncStream<Data>.Continuation?

    public override init() {
        centralManager = CBCentralManager(delegate: nil, queue: .main)
        super.init()
        centralManager.delegate = self
    }

    public func connect(
        identifier: UUID? = nil,
        name: String? = nil,
        mapping: PTJieliCharacteristicMapping = .automatic,
        timeout: TimeInterval = 20
    ) async throws -> PTJieliBLETransportDiscovery {
        guard connectionContinuation == nil else {
            throw PTJieliBLETransportError.busy
        }
        try Task.checkCancellation()

        targetIdentifier = identifier
        targetName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mapping = mapping
        discovery = nil
        pendingDiscovery = nil
        state = .connecting

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PTJieliBLETransportDiscovery, any Error>) in
                connectionContinuation = continuation
                startConnection(timeout: timeout)
            }
        }, onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelPendingConnection()
            }
        })
    }

    public func reconnect(timeout: TimeInterval = 20) async throws -> PTJieliBLETransportDiscovery {
        let identifier = targetIdentifier ?? peripheral?.identifier
        let name = targetName ?? peripheral?.name
        let selectedMapping = mapping

        if let peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        self.peripheral = nil
        otaService = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        pendingDiscovery = nil
        state = .idle

        return try await connect(
            identifier: identifier,
            name: name,
            mapping: selectedMapping,
            timeout: timeout
        )
    }

    public func makeNotificationStream() -> AsyncStream<Data> {
        notificationContinuation?.finish()
        return AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            notificationContinuation = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.notificationContinuation = nil
                }
            }
        }
    }

    public func write(_ data: Data, timeout: TimeInterval = 5) async throws {
        guard !data.isEmpty,
              let peripheral,
              let characteristic = writeCharacteristic,
              state == .ready else {
            throw PTJieliBLETransportError.notConnected
        }

        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write)
            ? .withResponse
            : .withoutResponse

        guard writeType == .withResponse else {
            peripheral.writeValue(data, for: characteristic, type: writeType)
            return
        }

        guard writeContinuation == nil else {
            throw PTJieliBLETransportError.busy
        }

        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                writeContinuation = continuation
                writeTimeoutTask?.cancel()
                writeTimeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(max(timeout, 0.001) * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        self?.finishWrite(.failure(PTJieliBLETransportError.writeFailed))
                    } catch {
                        // EN: A cancelled write watchdog is expected after a response or transport teardown.
                        // ES: La cancelación del vigilante de escritura es normal después de una respuesta o cierre.
                        // 中文：收到响应或传输关闭后，写入看门狗被取消是正常情况。
                    }
                }
                peripheral.writeValue(data, for: characteristic, type: writeType)
            }
        }, onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishWrite(.failure(PTJieliBLETransportError.cancelled))
            }
        })
    }

    /// EN: The SDK delegate is synchronous, so this method submits one already-framed packet immediately.
    /// ES: El delegado del SDK es síncrono; este método envía inmediatamente un paquete ya enmarcado.
    /// 中文：SDK delegate 是同步回调，因此这里立即提交一个已经分帧的包。
    public func writeImmediately(_ data: Data) throws {
        guard !data.isEmpty,
              let peripheral,
              let characteristic = writeCharacteristic,
              state == .ready else {
            throw PTJieliBLETransportError.notConnected
        }

        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write)
            ? .withResponse
            : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
    }

    public func disconnect() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        writeTimeoutTask?.cancel()
        writeTimeoutTask = nil
        centralManager.stopScan()

        if let peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }

        connectionContinuation?.resume(throwing: PTJieliBLETransportError.cancelled)
        connectionContinuation = nil
        finishWrite(.failure(PTJieliBLETransportError.cancelled))
        notificationContinuation?.finish()
        notificationContinuation = nil

        peripheral = nil
        otaService = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        pendingDiscovery = nil
        discovery = nil
        state = .idle
    }
}

@MainActor
extension PTJieliBLETransport: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === centralManager else { return }

        switch central.state {
        case .poweredOn:
            guard connectionContinuation != nil else { return }
            startDiscovery()
        case .poweredOff, .unauthorized, .unsupported:
            if connectionContinuation != nil {
                finishConnection(.failure(PTJieliBLETransportError.bluetoothUnavailable))
            } else if state == .ready {
                state = .disconnected
                notificationContinuation?.finish()
                notificationContinuation = nil
            }
        case .resetting:
            if connectionContinuation != nil {
                finishConnection(.failure(PTJieliBLETransportError.bluetoothUnavailable))
            }
        case .unknown:
            break
        @unknown default:
            if connectionContinuation != nil {
                finishConnection(.failure(PTJieliBLETransportError.bluetoothUnavailable))
            }
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard central === centralManager,
              connectionContinuation != nil,
              matches(peripheral) else { return }

        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central === centralManager,
              peripheral.identifier == self.peripheral?.identifier,
              connectionContinuation != nil else { return }

        state = .discovering
        peripheral.delegate = self
        peripheral.discoverServices([Self.otaServiceUUID])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard central === centralManager,
              peripheral.identifier == self.peripheral?.identifier else { return }
        finishConnection(.failure(PTJieliBLETransportError.connectionFailed))
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard central === centralManager,
              peripheral.identifier == self.peripheral?.identifier else { return }

        self.peripheral = nil
        otaService = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        finishWrite(.failure(PTJieliBLETransportError.notConnected))
        if connectionContinuation != nil {
            finishConnection(.failure(PTJieliBLETransportError.connectionFailed))
        } else {
            state = .disconnected
            notificationContinuation?.finish()
            notificationContinuation = nil
        }
    }
}

@MainActor
extension PTJieliBLETransport: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier,
              error == nil else {
            finishConnection(.failure(PTJieliBLETransportError.serviceNotFound))
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == Self.otaServiceUUID }) else {
            finishConnection(.failure(PTJieliBLETransportError.serviceNotFound))
            return
        }
        otaService = service
        state = .discovering
        peripheral.discoverCharacteristics(nil, for: service)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard peripheral.identifier == self.peripheral?.identifier,
              service.uuid == Self.otaServiceUUID,
              error == nil else {
            finishConnection(.failure(PTJieliBLETransportError.characteristicNotFound))
            return
        }

        let descriptors = (service.characteristics ?? []).compactMap(Self.makeDescriptor)
        guard !descriptors.isEmpty else {
            finishConnection(.failure(PTJieliBLETransportError.characteristicNotFound))
            return
        }

        do {
            let selection = try PTJieliCharacteristicResolver.resolve(
                descriptors: descriptors,
                mapping: mapping
            )
            guard let write = service.characteristics?.first(where: {
                Self.normalizedUUID($0.uuid) == Self.normalizedUUID(selection.writeUUID)
            }), let notify = service.characteristics?.first(where: {
                Self.normalizedUUID($0.uuid) == Self.normalizedUUID(selection.notifyUUID)
            }) else {
                throw PTJieliBLETransportError.characteristicNotFound
            }

            writeCharacteristic = write
            notifyCharacteristic = notify
            let result = PTJieliBLETransportDiscovery(
                peripheralIdentifier: peripheral.identifier,
                peripheralName: peripheral.name ?? "",
                serviceUUID: Self.otaServiceUUID.uuidString,
                characteristics: descriptors,
                selection: selection
            )
            pendingDiscovery = result
            state = .enablingNotifications
            peripheral.setNotifyValue(true, for: notify)
        } catch let error as PTJieliBLETransportError {
            finishConnection(.failure(error))
        } catch {
            finishConnection(.failure(PTJieliBLETransportError.characteristicNotFound))
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral.identifier == self.peripheral?.identifier,
              characteristic.uuid == notifyCharacteristic?.uuid else { return }

        guard error == nil, characteristic.isNotifying else {
            finishConnection(.failure(PTJieliBLETransportError.notificationFailed))
            return
        }

        guard let pendingDiscovery else {
            finishConnection(.failure(PTJieliBLETransportError.characteristicNotFound))
            return
        }
        discovery = pendingDiscovery
        finishConnection(.success(pendingDiscovery))
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral.identifier == self.peripheral?.identifier,
              characteristic.uuid == notifyCharacteristic?.uuid,
              error == nil,
              let value = characteristic.value else { return }
        notificationContinuation?.yield(value)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral.identifier == self.peripheral?.identifier,
              characteristic.uuid == writeCharacteristic?.uuid else { return }
        finishWrite(error == nil ? .success(()) : .failure(PTJieliBLETransportError.writeFailed))
    }
}

private extension PTJieliBLETransport {
    func startConnection(timeout: TimeInterval) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(max(timeout, 0.001) * 1_000_000_000))
                guard !Task.isCancelled, self?.connectionContinuation != nil else { return }
                self?.finishConnection(.failure(PTJieliBLETransportError.connectionTimeout))
            } catch {
                // EN: A cancelled connection watchdog is expected after discovery or teardown completes.
                // ES: La cancelación del vigilante de conexión es normal tras completar el descubrimiento o cierre.
                // 中文：发现完成或传输关闭后，连接看门狗被取消是正常情况。
            }
        }

        switch centralManager.state {
        case .poweredOn:
            startDiscovery()
        case .poweredOff, .unauthorized, .unsupported, .resetting:
            finishConnection(.failure(PTJieliBLETransportError.bluetoothUnavailable))
        case .unknown:
            break
        @unknown default:
            finishConnection(.failure(PTJieliBLETransportError.bluetoothUnavailable))
        }
    }

    func startDiscovery() {
        guard connectionContinuation != nil, centralManager.state == .poweredOn else { return }

        if let targetIdentifier,
           let retrieved = centralManager.retrievePeripherals(withIdentifiers: [targetIdentifier]).first {
            peripheral = retrieved
            retrieved.delegate = self
            state = .connecting
            centralManager.connect(retrieved, options: nil)
            return
        }

        state = .scanning
        centralManager.scanForPeripherals(
            withServices: [Self.otaServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func matches(_ candidate: CBPeripheral) -> Bool {
        if let targetIdentifier, candidate.identifier != targetIdentifier {
            return false
        }
        guard let targetName, !targetName.isEmpty else { return true }
        return candidate.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(targetName) == .orderedSame
    }

    func cancelPendingConnection() {
        guard connectionContinuation != nil else { return }
        finishConnection(.failure(PTJieliBLETransportError.cancelled))
    }

    func finishConnection(_ result: Result<PTJieliBLETransportDiscovery, Error>) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        centralManager.stopScan()

        guard let continuation = connectionContinuation else { return }
        connectionContinuation = nil

        switch result {
        case .success(let discovery):
            self.discovery = discovery
            state = .ready
            continuation.resume(returning: discovery)
        case .failure(let error):
            state = error is PTJieliBLETransportError && (error as? PTJieliBLETransportError) == .cancelled
                ? .idle
                : .failed
            if let peripheral {
                centralManager.cancelPeripheralConnection(peripheral)
            }
            continuation.resume(throwing: error)
        }
    }

    func finishWrite(_ result: Result<Void, Error>) {
        writeTimeoutTask?.cancel()
        writeTimeoutTask = nil
        guard let continuation = writeContinuation else { return }
        writeContinuation = nil
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    static func makeDescriptor(_ characteristic: CBCharacteristic) -> PTJieliCharacteristicDescriptor? {
        let uuid = normalizedUUID(characteristic.uuid)
        guard uuid == "AE01" || uuid == "AE02" else { return nil }
        return PTJieliCharacteristicDescriptor(
            uuid: uuid,
            supportsWrite: characteristic.properties.contains(.write),
            supportsWriteWithoutResponse: characteristic.properties.contains(.writeWithoutResponse),
            supportsNotify: characteristic.properties.contains(.notify),
            supportsIndicate: characteristic.properties.contains(.indicate)
        )
    }

    static func normalizedUUID(_ uuid: CBUUID) -> String {
        let compact = uuid.uuidString.uppercased().replacingOccurrences(of: "-", with: "")
        if compact.count == 4 {
            return compact
        }
        if compact.hasPrefix("0000"), compact.count >= 8 {
            return String(compact.dropFirst(4).prefix(4))
        }
        return compact
    }

    static func normalizedUUID(_ uuid: String) -> String {
        let compact = uuid.uppercased().replacingOccurrences(of: "-", with: "")
        if compact.count == 4 {
            return compact
        }
        if compact.hasPrefix("0000"), compact.count >= 8 {
            return String(compact.dropFirst(4).prefix(4))
        }
        return compact
    }
}

private extension PTJieliBLETransport {
    func normalizedUUID(_ uuid: CBUUID) -> String {
        Self.normalizedUUID(uuid)
    }
}
