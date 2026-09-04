//
//  PTDashboardANCSProvider.swift
//  CrazyDashboard
//
//  EN: Provides an Android-compatible ANCS-shaped channel for PTSpeed-owned alerts.
//  ES: Proporciona un canal con forma ANCS compatible con Android para avisos propios de PTSpeed.
//  中文：为 PTSpeed 自有提醒提供兼容安卓实现的 ANCS 风格通道。
//

import CoreBluetooth
import Foundation
import PooTools

/// EN: Reports whether an app-owned ANCS-shaped message was accepted by the local queue.
/// ES: Indica si el mensaje propio con forma ANCS fue aceptado por la cola local.
/// 中文：表示 App 自有 ANCS 风格消息是否已被本地队列接收。
public enum PTDashboardANCSDeliveryResult: Equatable, Sendable {
    case queued
    case waitingForDashboard
    case unavailable
}

/// EN: Publishes the ANCS-shaped GATT service through the existing peripheral manager.
/// ES: Publica el servicio GATT con forma ANCS mediante el gestor periférico existente.
/// 中文：通过现有外设管理器发布 ANCS 风格的 GATT 服务。
public final class PTDashboardANCSProvider: NSObject {
    public static let shared = PTDashboardANCSProvider()

    public static let serviceUUID = CBUUID(string: "7905F431-B5CE-4E99-A40F-4B1E122D00D0")
    public static let notificationSourceUUID = CBUUID(string: "9FBF120D-6301-42D9-8C58-25E699A21DBD")
    public static let controlPointUUID = CBUUID(string: "69D1D8F3-45E1-49A8-9821-9BBDFDAAD9D9")
    public static let dataSourceUUID = CBUUID(string: "22EAC6E9-24D6-4BB5-BE44-B36ACE7C7BFB")

    private enum Channel {
        case notificationSource
        case dataSource
    }

    private struct OutboundPacket {
        let channel: Channel
        let data: Data
    }

    private struct AttributeRequest {
        let identifier: UInt8
        let maximumLength: Int?
    }

    private var peripheralManager: CBPeripheralManager?
    private var delegateBridge: PTDashboardPeripheralDelegateBridge?
    private var isInstalled = false
    private var serviceAddInFlight = false
    private var servicePublished = false

    private var ancsService: CBMutableService?
    private var notificationSource: CBMutableCharacteristic?
    private var controlPoint: CBMutableCharacteristic?
    private var dataSource: CBMutableCharacteristic?

    private var subscribedCentral: CBCentral?
    private var isNotificationSourceSubscribed = false
    private var isDataSourceSubscribed = false

    private var activeNotifications: [UInt32: PTAncsNotif] = [:]
    private var nextNotificationUID: UInt32 = 1
    private var outboundPackets: [OutboundPacket] = []
    private let maximumPendingPackets = 32

    private override init() {
        super.init()
    }

    /// EN: Install one delegate bridge so the protected BLE manager keeps receiving every existing callback.
    /// ES: Instala un único puente de delegado para que el gestor BLE protegido siga recibiendo todos sus callbacks.
    /// 中文：安装唯一的委托桥接，确保受保护的 BLE 管理器继续收到全部既有回调。
    public func install() {
        guard !isInstalled else { return }

        let manager = PTBluetoothServerManager.shared
        guard let peripheral = manager.peripheralManager else {
            log("无法安装：现有 CBPeripheralManager 尚未创建")
            return
        }
        guard let originalDelegate = peripheral.delegate as? PTBluetoothServerManager else {
            log("无法安装：现有 CBPeripheralManager 委托不是 PTBluetoothServerManager")
            return
        }

        peripheralManager = peripheral
        let bridge = PTDashboardPeripheralDelegateBridge(
            originalDelegate: originalDelegate,
            provider: self
        )
        delegateBridge = bridge
        peripheral.delegate = bridge
        isInstalled = true

        if peripheral.state == .poweredOn {
            scheduleServicePublication()
        }
        log("已安装自有 ANCS 风格通道桥接，系统电话和短信 ANCS 路径保持不变")
    }

    public var isReadyForSending: Bool {
        servicePublished
            && isNotificationSourceSubscribed
            && subscribedCentral != nil
    }

    /// EN: Queue an app-owned notification after the dashboard subscribes to Notification Source.
    /// ES: Encola un aviso propio después de que el tablero se suscriba a Notification Source.
    /// 中文：仪表盘订阅 Notification Source 后，加入 App 自有通知。
    @discardableResult
    public func sendNotification(
        title: String,
        message: String,
        category: UInt8 = 4,
        appIdentifier: String? = nil
    ) -> PTDashboardANCSDeliveryResult {
        guard isInstalled, servicePublished else {
            log("拒绝发送：ANCS 服务尚未发布")
            return .unavailable
        }
        guard isReadyForSending else {
            log("等待发送：仪表盘尚未订阅 ANCS Notification Source")
            return .waitingForDashboard
        }
        guard outboundPackets.count < maximumPendingPackets else {
            log("拒绝发送：ANCS 队列已达到 \(maximumPendingPackets) 个分片上限")
            return .unavailable
        }

        let uid = allocateNotificationUID()
        let notification = PTAncsNotif(
            uid: uid,
            title: title,
            message: message,
            category: category,
            appId: appIdentifier ?? Bundle.main.bundleIdentifier ?? "com.yd.PTSpeed"
        )
        activeNotifications[uid] = notification

        let categoryCount = activeNotifications.values.reduce(into: 0) { count, item in
            if item.category == category { count += 1 }
        }
        outboundPackets.append(
            OutboundPacket(
                channel: .notificationSource,
                data: Self.makeNotificationSourcePacket(
                    notification,
                    categoryCount: UInt8(min(categoryCount, Int(UInt8.max)))
                )
            )
        )
        pumpQueue()
        log("已加入 ANCS 通知：UID \(uid)")
        return .queued
    }

    /// EN: Send a deterministic English payload for real-dashboard interoperability testing.
    /// ES: Envía un contenido inglés determinista para probar la interoperabilidad con el tablero real.
    /// 中文：发送固定英文内容，用于真实仪表盘互操作测试。
    @discardableResult
    public func sendTestNotification() -> PTDashboardANCSDeliveryResult {
        sendNotification(
            title: "PTSpeed Test",
            message: "Custom dashboard notification"
        )
    }

    // MARK: - Peripheral lifecycle

    private func scheduleServicePublication() {
        guard isInstalled else { return }
        DispatchQueue.main.async { [weak self] in
            self?.publishServiceIfPossible()
        }
    }

    private func publishServiceIfPossible() {
        guard isInstalled,
              let peripheralManager,
              peripheralManager.state == .poweredOn,
              !servicePublished,
              !serviceAddInFlight else {
            return
        }

        let source = CBMutableCharacteristic(
            type: Self.notificationSourceUUID,
            properties: [.notify],
            value: nil,
            permissions: [.readEncryptionRequired]
        )
        let cp = CBMutableCharacteristic(
            type: Self.controlPointUUID,
            properties: [.write],
            value: nil,
            permissions: [.writeEncryptionRequired]
        )
        let data = CBMutableCharacteristic(
            type: Self.dataSourceUUID,
            properties: [.notify],
            value: nil,
            permissions: [.readEncryptionRequired]
        )
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [source, cp, data]

        notificationSource = source
        controlPoint = cp
        dataSource = data
        ancsService = service
        serviceAddInFlight = true
        peripheralManager.add(service)
        log("已提交 ANCS 风格 GATT 服务注册")
    }

    fileprivate func handlePeripheralStateUpdate(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {
            servicePublished = false
            serviceAddInFlight = false
            clearSession()
            return
        }
        scheduleServicePublication()
    }

    fileprivate func handleServiceAdded(_ service: CBService, error: Error?) {
        guard service.uuid == Self.serviceUUID else { return }
        serviceAddInFlight = false
        if let error {
            servicePublished = false
            log("ANCS 风格 GATT 服务注册失败：\(error.localizedDescription)")
            return
        }
        servicePublished = true
        log("ANCS 风格 GATT 服务注册完成")
    }

    fileprivate func handleSubscribe(_ central: CBCentral, characteristic: CBCharacteristic) {
        guard characteristic.uuid == Self.notificationSourceUUID
                || characteristic.uuid == Self.dataSourceUUID else { return }

        if subscribedCentral?.identifier != central.identifier {
            clearSession()
            subscribedCentral = central
        }
        if characteristic.uuid == Self.notificationSourceUUID {
            isNotificationSourceSubscribed = true
        } else {
            isDataSourceSubscribed = true
        }
        log("仪表盘订阅 ANCS 特征：\(characteristic.uuid.uuidString)")
        pumpQueue()
    }

    fileprivate func handleUnsubscribe(_ central: CBCentral, characteristic: CBCharacteristic) {
        guard subscribedCentral?.identifier == central.identifier else { return }
        guard characteristic.uuid == Self.notificationSourceUUID
                || characteristic.uuid == Self.dataSourceUUID else { return }

        clearSession()
        log("仪表盘取消订阅 ANCS 特征：\(characteristic.uuid.uuidString)")
    }

    fileprivate func handleWriteRequests(
        _ requests: [CBATTRequest],
        peripheral: CBPeripheralManager
    ) {
        for request in requests where request.characteristic.uuid == Self.controlPointUUID {
            guard request.offset == 0,
                  let value = request.value,
                  let parsed = Self.parseAttributeRequest(value),
                  let notification = activeNotifications[parsed.uid] else {
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
                log("拒绝非法 ANCS Control Point 请求")
                continue
            }

            let response = Self.makeDataSourcePacket(
                notification: notification,
                attributes: parsed.attributes
            )
            guard enqueueDataSourceResponse(response) else {
                peripheral.respond(to: request, withResult: .unlikelyError)
                log("拒绝 ANCS Data Source 请求：响应超过当前队列容量")
                continue
            }
            peripheral.respond(to: request, withResult: .success)
            pumpQueue()
        }
    }

    fileprivate func handlePeripheralReady() {
        pumpQueue()
    }

    // MARK: - Session and queue

    private func allocateNotificationUID() -> UInt32 {
        let allocated = nextNotificationUID == 0 ? 1 : nextNotificationUID
        nextNotificationUID = allocated == UInt32.max ? 1 : allocated + 1
        return allocated
    }

    private func clearSession() {
        subscribedCentral = nil
        isNotificationSourceSubscribed = false
        isDataSourceSubscribed = false
        activeNotifications.removeAll(keepingCapacity: false)
        outboundPackets.removeAll(keepingCapacity: false)
        nextNotificationUID = 1
    }

    @discardableResult
    private func enqueueDataSourceResponse(_ data: Data) -> Bool {
        let chunkSize = 20
        let requiredPackets = (data.count + chunkSize - 1) / chunkSize
        guard requiredPackets > 0,
              outboundPackets.count + requiredPackets <= maximumPendingPackets else {
            log("拒绝 ANCS Data Source 响应：队列已满")
            return false
        }

        // EN: Enqueue the complete response or none of it, so the dashboard never receives a truncated tuple list.
        // ES: Encola la respuesta completa o ninguna parte, para no entregar una lista de tuplas truncada.
        // 中文：要么完整加入响应，要么一片都不加入，避免仪表收到截断的属性元组列表。
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            outboundPackets.append(
                OutboundPacket(
                    channel: .dataSource,
                    data: data.subdata(in: offset..<end)
                )
            )
            offset = end
        }
        return true
    }

    private func pumpQueue() {
        guard let peripheralManager,
              let central = subscribedCentral,
              !outboundPackets.isEmpty else { return }

        while let packet = outboundPackets.first {
            let subscribed: Bool
            let characteristic: CBMutableCharacteristic?
            switch packet.channel {
            case .notificationSource:
                subscribed = isNotificationSourceSubscribed
                characteristic = notificationSource
            case .dataSource:
                subscribed = isDataSourceSubscribed
                characteristic = dataSource
            }

            guard subscribed, let characteristic else { return }
            guard peripheralManager.updateValue(
                packet.data,
                for: characteristic,
                onSubscribedCentrals: [central]
            ) else {
                return
            }
            outboundPackets.removeFirst()
        }
    }

    // MARK: - ANCS codec

    private static func makeNotificationSourcePacket(
        _ notification: PTAncsNotif,
        categoryCount: UInt8
    ) -> Data {
        var packet = Data([
            0, // EN: Added; ES: añadido; 中文：新增
            2, // EN: Important; ES: importante; 中文：重要
            notification.category,
            categoryCount
        ])
        appendLittleEndian(notification.uid, to: &packet)
        return packet
    }

    private static func makeDataSourcePacket(
        notification: PTAncsNotif,
        attributes: [AttributeRequest]
    ) -> Data {
        var packet = Data([0])
        appendLittleEndian(notification.uid, to: &packet)

        for attribute in attributes {
            packet.append(attribute.identifier)
            let text = textForAttribute(attribute.identifier, notification: notification)
            let maxLength = min(attribute.maximumLength ?? 250, 250)
            let bytes = utf8Prefix(text, maximumByteCount: maxLength)
            appendLittleEndian(UInt16(bytes.count), to: &packet)
            packet.append(bytes)
        }
        return packet
    }

    private static func parseAttributeRequest(
        _ data: Data
    ) -> (uid: UInt32, attributes: [AttributeRequest])? {
        let bytes = [UInt8](data)
        guard bytes.count >= 6, bytes[0] == 0 else { return nil }

        let uid = UInt32(bytes[1])
            | UInt32(bytes[2]) << 8
            | UInt32(bytes[3]) << 16
            | UInt32(bytes[4]) << 24
        var index = 5
        var attributes: [AttributeRequest] = []

        while index < bytes.count {
            let identifier = bytes[index]
            index += 1
            guard (0...6).contains(Int(identifier)) else { return nil }

            // EN: Accept both the standard request shape and the one-attribute Android variant.
            // ES: Acepta tanto la forma estándar como la variante Android de un solo atributo.
            // 中文：同时兼容标准请求格式和安卓单属性请求格式。
            if index == bytes.count {
                attributes.append(AttributeRequest(identifier: identifier, maximumLength: nil))
            } else if identifier != 0 {
                guard index + 1 < bytes.count else { return nil }
                let maximumLength = Int(bytes[index]) | Int(bytes[index + 1]) << 8
                attributes.append(AttributeRequest(identifier: identifier, maximumLength: maximumLength))
                index += 2
            } else {
                attributes.append(AttributeRequest(identifier: identifier, maximumLength: nil))
            }
        }

        return attributes.isEmpty ? nil : (uid, attributes)
    }

    private static func textForAttribute(_ identifier: UInt8, notification: PTAncsNotif) -> String {
        switch identifier {
        case 0:
            return notification.appId
        case 1:
            return notification.title
        case 3:
            return notification.message
        default:
            return ""
        }
    }

    private static func utf8Prefix(_ text: String, maximumByteCount: Int) -> Data {
        guard maximumByteCount > 0 else { return Data() }
        var result = Data()
        for scalar in text.unicodeScalars {
            let scalarData = String(scalar).data(using: .utf8) ?? Data()
            guard result.count + scalarData.count <= maximumByteCount else { break }
            result.append(scalarData)
        }
        return result
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { data.append(contentsOf: $0) }
    }

    private func log(_ message: String) {
        PTNSLogConsole("📬 [自有 ANCS] \(message)")
    }
}

/// EN: Multiplex only the existing peripheral delegate callbacks needed by the new service.
/// ES: Multiplexa solo los callbacks del delegado periférico existente que necesita el nuevo servicio.
/// 中文：只复用新服务需要的现有外设委托回调。
private final class PTDashboardPeripheralDelegateBridge: NSObject, CBPeripheralManagerDelegate {
    private let originalDelegate: PTBluetoothServerManager
    private weak var provider: PTDashboardANCSProvider?

    init(
        originalDelegate: PTBluetoothServerManager,
        provider: PTDashboardANCSProvider
    ) {
        self.originalDelegate = originalDelegate
        self.provider = provider
        super.init()
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        originalDelegate.peripheralManagerDidUpdateState(peripheral)
        provider?.handlePeripheralStateUpdate(peripheral)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?
    ) {
        guard service.uuid != PTDashboardANCSProvider.serviceUUID else {
            provider?.handleServiceAdded(service, error: error)
            return
        }
        originalDelegate.peripheralManager(peripheral, didAdd: service, error: error)
        provider?.handleServiceAdded(service, error: error)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        guard characteristic.uuid != PTDashboardANCSProvider.notificationSourceUUID,
              characteristic.uuid != PTDashboardANCSProvider.dataSourceUUID else {
            provider?.handleSubscribe(central, characteristic: characteristic)
            return
        }
        originalDelegate.peripheralManager(peripheral, central: central, didSubscribeTo: characteristic)
        provider?.handleSubscribe(central, characteristic: characteristic)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        guard characteristic.uuid != PTDashboardANCSProvider.notificationSourceUUID,
              characteristic.uuid != PTDashboardANCSProvider.dataSourceUUID else {
            provider?.handleUnsubscribe(central, characteristic: characteristic)
            return
        }
        originalDelegate.peripheralManager(peripheral, central: central, didUnsubscribeFrom: characteristic)
        provider?.handleUnsubscribe(central, characteristic: characteristic)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        let dashboardRequests = requests.filter {
            $0.characteristic.uuid != PTDashboardANCSProvider.controlPointUUID
        }
        if !dashboardRequests.isEmpty {
            originalDelegate.peripheralManager(peripheral, didReceiveWrite: dashboardRequests)
        }
        provider?.handleWriteRequests(requests, peripheral: peripheral)
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        originalDelegate.peripheralManagerIsReady(toUpdateSubscribers: peripheral)
        provider?.handlePeripheralReady()
    }
}
