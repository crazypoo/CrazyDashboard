//
//  PTBluetoothManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 19/7/2026.
//

import UIKit
import CoreBluetooth
import PooTools

// MARK: - 导航与状态数据模型
// MARK: - 摩托车仪表盘状态模型[cite: 2]

struct PTDashboardControl {
    let vehicleSpeedKmh: Double
    let engineRpm: Int
}

struct PTDashboardData1 {
    let tripKm: Double
    let odoKm: Double
    let fuelLevelPct: Int
    let avgConsumptionLt: Double
}

struct PTDashboardData2 {
    let batteryVolt: Double
    let outsideTempC: Int
    let engineStatus: Int
    let maintenance: Int
}

struct PTDashboardData3 {
    let autonomyKm: Double
    let distToMaintenance: Int
    let colorMeasur: Int
    let language: Int
}

struct PTAbsStatus {
    let absRaw: Int
}

// MARK: - 状态标签转换工具[cite: 2]
struct PTDashboardLabels {
    static func engineStatusLabel(raw: Int) -> String {
        switch raw & 0x03 {
        case 0: return "未启动" // Donmuyor
        case 1: return "启动中" // Basliyor
        case 2: return "运转中" // Calisiyor
        case 3: return "关闭中" // Kapanma
        default: return "-"
        }
    }
    
    static func maintenanceLabel(raw: Int) -> String {
        return (raw & 0xE0) != 0 ? "需要保养" : "无需保养"
    }
    
    static func absLabel(raw: Int) -> String {
        switch raw & 0x03 {
        case 1: return "正常 (OK)"
        case 2: return "故障 (Ariza)"
        default: return "-"
        }
    }
    
    static func unitLabel(c: Int) -> String {
        return (c & 0x08) != 0 ? "英里 (Mil)" : "公里 (Km)"
    }
    
    static func languageLabel(r: Int) -> String {
        let names = ["英语", "法语", "德语", "西班牙语", "意大利语"]
        let code = (r >> 1) & 0x0F
        if code >= 1 && code <= 5 {
            return names[code - 1]
        }
        return "英语"
    }
}

// 复刻 Android 的 NavigationInfo[cite: 2]
struct PTNavigationInfo {
    var nextManeuver: UInt8
    var metersToNextManeuver: UInt32
    var nameNextRoad: String
    var nameCurrentRoad: String
    var currentSpeedLimit: UInt8
    var distanceToDestination: UInt32
    /// 距离到达目的地的预计剩余秒数[cite: 2]
    var estimatedTimeToDestinationSec: Int
}

// 转弯动作常量枚举 (复刻 ManeuverMap)[cite: 2]
enum PTManeuverMap {
    static let undefined: UInt8 = 0
    static let straight: UInt8 = 1
    static let uTurnRight: UInt8 = 2
    static let uTurnLeft: UInt8 = 3
    static let keepRight: UInt8 = 4
    static let lightRight: UInt8 = 5
    static let quiteRight: UInt8 = 6
    static let heavyRight: UInt8 = 7
    static let keepMiddle: UInt8 = 8
    static let keepLeft: UInt8 = 9
    static let lightLeft: UInt8 = 10
    static let quiteLeft: UInt8 = 11
    static let heavyLeft: UInt8 = 12
    static let start: UInt8 = 43
    static let arrive: UInt8 = 44
    static let ferry: UInt8 = 45
    static let calculating: UInt8 = 47
}

// MARK: - 安全认证中心 (完整版)
class PTScooterAuth {
    
    // 核心加密字典表 (2048 长度)[cite: 1]
    private var numbersList: [UInt16] = []
    
    // 当前会话的 Challenge (10 个随机数)
    private var randomNumbers: [UInt16] = Array(repeating: 0, count: 10)
    
    init() {
        // 在类初始化时，自动加载并解析字典表
        loadNumbersList()
    }
    
    // MARK: - 字典表加载逻辑
    private func loadNumbersList() {
        // 你提供的 Base64 密文
        let base64String = "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"
        
        // 1. 将 Base64 解码为原始的 4096 字节 Data[cite: 1]
        guard let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else {
            PTProgressHUD.show(text: "❌ 严重错误：Base64 字典表解析失败！")
            self.numbersList = Array(repeating: 0, count: 2048)
            return
        }
        
        // 2. 准备容器，容量为 2048
        var list = [UInt16]()
        list.reserveCapacity(2048)
        
        // 3. 按小端序 (Little-Endian) 读取每两个字节[cite: 1]
        data.withUnsafeBytes { buffer in
            for i in 0..<2048 {
                let byteOffset = i * 2
                // 直接从指定偏移量加载 UInt16
                let value = buffer.load(fromByteOffset: byteOffset, as: UInt16.self)
                // 确保无论在哪种架构的 CPU 上，都按照小端序进行解析[cite: 1]
                list.append(UInt16(littleEndian: value))
            }
        }
        
        self.numbersList = list
        PTProgressHUD.show(text: "✅ 成功加载加密字典表！容量：\(self.numbersList.count) 个节点。")
    }
    
    // MARK: - 核心验证方法
    
    // 1. 生成 10 个随机数 Challenge[cite: 1]
    func createChallenge() -> [UInt16] {
        for i in 0..<10 {
            randomNumbers[i] = UInt16.random(in: 0...UInt16.max)
        }
        return randomNumbers
    }
    
    // 2. 验证摩托车发回来的 20 字节是否正确[cite: 1]
    func checkAuthMsg(scooterResponse: Data) -> Bool {
        guard scooterResponse.count >= 10 else { return false }
        let expected = createAuthenticationMessage(r: randomNumbers)
        // 只严格比对前 10 个有效响应字节[cite: 1]
        for i in 0..<10 {
            if scooterResponse[i] != expected[i] { return false }
        }
        return true
    }
    
    // 3. 利用字典表生成 20 字节的加密响应[cite: 1]
    func createAuthenticationMessage(r: [UInt16]) -> Data {
        var data = Data()
        // 前 10 字节根据表生成[cite: 1]
        for k in 0..<5 {
            let c1 = numbersList[Int(r[k] & 0x7FF)]
            let c2 = numbersList[Int(r[k + 5] & 0x7FF)]
            
            // 🚨 核心修复：Swift 防溢出处理！
            // 必须先将 UInt16 提升为 UInt32，相加后再进行掩码，防止程序在这里静默崩溃
            let sum = (UInt32(c1) + UInt32(c2)) & 0xFFFF
            
            // 写入 16-bit Big-Endian (大端序)[cite: 1]
            var bigEndianSum = UInt16(sum).bigEndian
            data.append(Data(bytes: &bigEndianSum, count: MemoryLayout<UInt16>.size))
        }
        // 后 10 字节填充随机数防嗅探[cite: 1]
        for _ in 0..<10 {
            let randomByte = UInt8.random(in: 0...255)
            data.append(randomByte)
        }
        return data
    }
    
    // 4. 获取 15 字节的设备身份信息 (Key ID)[cite: 1]
    func getScooterKeyId() -> Data {
        var data = Data()
        // 固定产品 ID 8758 (大端序)[cite: 1]
        var productId = UInt32(8758).bigEndian
        data.append(Data(bytes: &productId, count: 4))
        
        // App 版本 "2.1.37"[cite: 1]
        data.append(contentsOf: [2, 0, 8])
        
        // 编译日期 "12/07/2018"[cite: 1]
        data.append(contentsOf: [1, 4, 25])
        
        // 固定分隔符[cite: 1]
        data.append(1)
        
        // iOS 系统版本 (截取前 4 个段)[cite: 1]
        let versionString = UIDevice.current.systemVersion
        let parts = versionString.split(separator: ".")
        var written = 0
        for part in parts {
            if written >= 4 { break }
            let val = UInt8(part) ?? 0
            data.append(val)
            written += 1
        }
        while written < 4 {
            data.append(0)
            written += 1
        }
        return data
    }
}

// MARK: - 2. 协议封装器 (复刻 ScooterFrames.kt)
class PTFrameBuilder {
    // 封包常量[cite: 2]
    static let PREAMBLE: UInt8 = 0x16
    static let END_OF_FRAME: UInt8 = 0x00
    
    static let ID_NAVIGATION: UInt8 = 1
    static let ID_CONFIGURATION: UInt8 = 7
    static let ID_DISCONNECT: UInt8 = 8
    
    // 通用封包方法：[16] + [ID] + [2字节长度] + [Payload] + [00][cite: 2]
    static func wrapTxFrame(idFrame: UInt8, payload: Data) -> Data {
        var frame = Data()
        frame.append(PREAMBLE)
        frame.append(idFrame)
        
        // 写入 2 字节长度 (Big-Endian)[cite: 2]
        var length = UInt16(payload.count).bigEndian
        frame.append(Data(bytes: &length, count: MemoryLayout<UInt16>.size))
        
        frame.append(payload)
        frame.append(END_OF_FRAME)
        return frame
    }
    
    // 生成配置指令[cite: 2]
    static func buildConfigurationFrame(color: UInt8, unit: UInt8, language: UInt8) -> Data {
        let payload = Data([color, unit, language])
        return wrapTxFrame(idFrame: ID_CONFIGURATION, payload: payload)
    }
}

// 补充 PTFrameBuilder 内部方法
extension PTFrameBuilder {
    
    // 生成导航数据帧[cite: 2]
    static func buildNavigationFrame(info: PTNavigationInfo) -> Data {
        var payload = Data()
        
        // 1. Maneuver Type (机动动作): [Hdr=1][Maneuver][cite: 2]
        payload.append(contentsOf: [1, info.nextManeuver])
        
        // 2. Maneuver Distance (距下一动作距离): [Hdr=4][4-byte Dist 大端序][cite: 2]
        payload.append(4)
        var dist = info.metersToNextManeuver.bigEndian
        payload.append(Data(bytes: &dist, count: 4))
        
        // 3. Next Road (下一道路): [Size][Text] (最大 50 字节)[cite: 2]
        let nextRoadData = encodeString(info.nameNextRoad)
        payload.append(UInt8(nextRoadData.count))
        payload.append(nextRoadData)
        
        // 4. Current Road (当前道路): [Size][Text][cite: 2]
        let curRoadData = encodeString(info.nameCurrentRoad)
        payload.append(UInt8(curRoadData.count))
        payload.append(curRoadData)
        
        // 5. Speed Limit (当前限速): [Hdr=1][Speed][cite: 2]
        payload.append(contentsOf: [1, info.currentSpeedLimit])
        
        // 6. Total Distance (剩余总距离): [Hdr=4][4-byte Dist 大端序][cite: 2]
        payload.append(4)
        var totalDist = info.distanceToDestination.bigEndian
        payload.append(Data(bytes: &totalDist, count: 4))
        
        // 7. ETA (预计到达时间): [Hdr=7][7-byte Date/Time 大端序][cite: 2]
        payload.append(7)
        // 通过当前时间 + 剩余秒数，计算出预计到达的真实时间[cite: 2]
        let etaDate = Calendar.current.date(byAdding: .second, value: info.estimatedTimeToDestinationSec, to: Date()) ?? Date()
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: etaDate)
        
        var year = UInt16(comps.year ?? 2026).bigEndian
        payload.append(Data(bytes: &year, count: 2))
        payload.append(UInt8(comps.month ?? 1))
        payload.append(UInt8(comps.day ?? 1))
        payload.append(UInt8(comps.hour ?? 0))
        payload.append(UInt8(comps.minute ?? 0))
        payload.append(UInt8(comps.second ?? 0))
        
        // 封装成完整的传输帧 (ID = 1)[cite: 2]
        return wrapTxFrame(idFrame: ID_NAVIGATION, payload: payload)
    }
    
    // 生成主动断开连接帧[cite: 2]
    static func buildDisconnectFrame() -> Data {
        let payload = Data([1, 1])
        return wrapTxFrame(idFrame: ID_DISCONNECT, payload: payload)
    }
    
    // 字符串截断与编码辅助方法[cite: 2]
    private static func encodeString(_ text: String) -> Data {
        // Android 中采用了 ISO_8859_1 或 UTF_8 编码，并限制最大 50 字节[cite: 2]
        let data = text.data(using: .utf8) ?? Data()
        if data.count > 50 {
            return data.prefix(50)
        }
        return data
    }
}

// MARK: - 3. 核心蓝牙服务端 (复刻 ScooterGattServer.kt)
enum PTAuthState {
    case waitKeyId      // 等待车机发送 8758
    case waitAuthMsg    // 等待车机返回加密后的验证数据
    case success        // 验证完成，数据流通
}

class PTBluetoothServerManager: NSObject, CBPeripheralManagerDelegate,CBCentralManagerDelegate {
    
    static let shared = PTBluetoothServerManager()
    
    private let kHasPairedKey = "PT_HasPairedWithScooter"
    var hasRememberedScooter: Bool {
        return UserDefaults.standard.bool(forKey: kHasPairedKey)
    }
    var peripheralManager: CBPeripheralManager!
    var centralManager: CBCentralManager!
    let auth = PTScooterAuth()
    
    // UUID 定义[cite: 3]
    let TIO_SERVICE = CBUUID(string: "0000FEFB-0000-1000-8000-00805F9B34FB")
    let UART_RX = CBUUID(string: "00000001-0000-1000-8000-008025000000")
    let UART_TX = CBUUID(string: "00000002-0000-1000-8000-008025000000")
    let UART_RX_CREDITS = CBUUID(string: "00000003-0000-1000-8000-008025000000")
    let UART_TX_CREDITS = CBUUID(string: "00000004-0000-1000-8000-008025000000")
    
    var txChar: CBMutableCharacteristic!
    var txCreditsChar: CBMutableCharacteristic!
    
    // 状态记录[cite: 3]
    private var authState: PTAuthState = .waitKeyId
    private var authenticated = false
    private var isTioSubscribed = false
    private var isCreditsSubscribed = false
    private var localCredits = 0
    
    // 订阅的中心设备 (摩托车)
    private var connectedCentral: CBCentral?
    private var activeScooter: CBPeripheral? // 记录被我们主动抓取的摩托车
    
    struct PTNotifyJob {
        let data: Data
        let characteristic: CBMutableCharacteristic
    }
    private var sendQueue: [PTNotifyJob] = []
    private var isSending = false

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - 启动双擎
    func startBaseStationAndScan() {
        // 1. 启动基站
        if peripheralManager.state == .poweredOn {
            setupServices()
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [TIO_SERVICE]])
            PTProgressHUD.show(text: "🚀 基站服务已广播...")
        }
        
        // 2. 启动扫描 (贴近连接法)
        if centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: nil, options: nil)
            PTProgressHUD.show(text: "🚀 基站已激活，正在主动雷达扫描摩托车(请贴近)...")
        } else {
            PTProgressHUD.show(text: "❌ 蓝牙未准备好")
        }
    }

    // MARK: - PeripheralManager Delegate
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {}
    
    private func setupServices() {
        // 确保使用无拦截的普通权限，防止配对弹窗卡死物理连接
        let rxChar = CBMutableCharacteristic(
            type: UART_RX,
            properties: [.write,.writeWithoutResponse],
            value: nil,
            permissions: [.writeEncryptionRequired]
        )
        
        txChar = CBMutableCharacteristic(
            type: UART_TX,
            properties: [.notify, .indicate],
            value: nil,
            permissions: [.readEncryptionRequired]
        )
        let rxCreditsChar = CBMutableCharacteristic(
            type: UART_RX_CREDITS,
            properties: [.write,.writeWithoutResponse],
            value: nil,
            permissions: [.writeEncryptionRequired]
        )
        txCreditsChar = CBMutableCharacteristic(
            type: UART_TX_CREDITS,
            properties: [.notify,.indicate],  // 必须是 Indicate，否则摩托车订阅失败并中止握手！
            value: nil,
            permissions: [.readEncryptionRequired]
        )

        let service = CBMutableService(type: TIO_SERVICE, primary: true)
        service.characteristics = [rxChar, txChar, rxCreditsChar, txCreditsChar]
        peripheralManager.add(service)
    }
    
    // 监听通道订阅[cite: 3]
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        connectedCentral = central
        PTProgressHUD.show(text: "⚡️ 发现设备连接！正在订阅通道: \(characteristic.uuid)")
        PTNSLogConsole("⚡️ [雷达响应] 中心设备 \(central.identifier) 订阅了通道: \(characteristic.uuid)")
        if characteristic.uuid == UART_TX { isTioSubscribed = true }
        if characteristic.uuid == UART_TX_CREDITS { isCreditsSubscribed = true }
        
        if isTioSubscribed && isCreditsSubscribed {
            PTProgressHUD.show(text:"🔗 摩托车订阅完毕，开启身份验证握手...")
            authState = .waitKeyId
            authenticated = false
        }
    }
    
    // 监听数据写入请求[cite: 3]
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        if let firstRequest = requests.first, firstRequest.characteristic.properties.contains(.write) {
            peripheralManager.respond(to: firstRequest, withResult: .success)
        }
        for request in requests {
            guard let data = request.value else { continue }
            
            PTProgressHUD.show(text:"⚡️ [雷达响应] 收到设备写入请求，通道: \(request.characteristic.uuid)，数据包: \(data.map { String(format: "%02hhx", $0) }.joined())")
            if request.characteristic.uuid == UART_RX {
                if authenticated && localCredits > 0 {
                    localCredits -= 1
                    if localCredits <= 4 { grantScooterCredits() }
                }
                handleIncoming(data: data)
            }
        }
    }
    
    // MARK: - 身份验证状态机[cite: 3]
    private func handleIncoming(data: Data) {
        if authenticated {
            parseDashboardFrame(data)
            return
        }
        
        switch authState {
        case .waitKeyId:
            let bytes = [UInt8](data)
            if data.count >= 4 {
                let productId = (Int(bytes[0]) << 24) | (Int(bytes[1]) << 16) | (Int(bytes[2]) << 8) | Int(bytes[3])
                if productId == 8758 {
                    PTProgressHUD.show(text:"✅ Step 1: 收到正确 Product ID (8758)")
                    let challenge = auth.createChallenge()
                    var challengeData = Data()
                    for num in challenge {
                        var beNum = num.bigEndian
                        challengeData.append(Data(bytes: &beNum, count: 2))
                    }
                    sendChunkedData(data: challengeData, to: txChar)
                    authState = .waitAuthMsg
                }
            }
            
        case .waitAuthMsg:
            if auth.checkAuthMsg(scooterResponse: data) {
                PTProgressHUD.show(text:"✅ 验证通过！下发 KeyID 并充值额度...")
                
                // 发送 KeyID (App凭证)
                sendChunkedData(data: auth.getScooterKeyId(), to: txChar)
                
                // 步骤 5：验证完成，蓝灯长亮，立即为钱包充值 25 额度！
                grantScooterCredits()
                
                // 彻底打通！状态变为 success
                authState = .success
                authenticated = true
                UserDefaults.standard.set(true, forKey: kHasPairedKey)
                NotificationCenter.default.post(name: NSNotification.Name("MotorcycleAuthSuccess"), object: nil)
            } else {
                PTProgressHUD.show(text:"❌ Step 2: 验证失败，密码本可能有误。")
            }
        case .success:
            break
        }
    }
    
    // MARK: - 数据发送逻辑
    
    // 下发 Credit (解锁摩托车接收端)[cite: 3]
    private func grantScooterCredits() {
        let refill = 25 - localCredits
        if refill <= 0 { return }
        localCredits += refill
        let data = Data([UInt8(refill)])
        sendChunkedData(data: data, to: txCreditsChar)
    }
    
    // 这是苹果特有的回调：当底层通道恢复空闲时，会调用此方法
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // 通道空闲了，恢复发送状态，继续泵送队列
        isSending = false
        pumpQueue()
    }

    // BLE 单次最多发 20 字节，超长数据需分块发送[cite: 3]
    private func sendChunkedData(data: Data, to characteristic: CBMutableCharacteristic) {
        var offset = 0
        let chunkSize = 20
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<end)
            // 将切片加入队列，而不是直接发送
            sendQueue.append(PTNotifyJob(data: chunk, characteristic: characteristic))
            offset = end
        }
        // 触发队列引擎
        pumpQueue()
    }
    
    private func pumpQueue() {
        guard !isSending, !sendQueue.isEmpty else { return }
        let job = sendQueue[0]
        let success = peripheralManager.updateValue(job.data, for: job.characteristic, onSubscribedCentrals: nil)
        
        if success {
            sendQueue.removeFirst()
            DispatchQueue.main.async { self.pumpQueue() }
        } else {
            isSending = true
        }
    }

    // 供外部调用的指令发送入口
    func sendConfiguration(color: UInt8, unit: UInt8, language: UInt8) {
        guard authenticated else {
            PTProgressHUD.show(text:"⚠️ 尚未完成认证，无法发送指令")
            return
        }
        let frame = PTFrameBuilder.buildConfigurationFrame(color: color, unit: unit, language: language)
        sendChunkedData(data: frame, to: txChar)
    }
    
    @objc func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // 保持空即可，我们在 startBaseStationAndScan 中判断
    }

    func autoStartIfRemembered() {
        if hasRememberedScooter {
            PTProgressHUD.show(text:"🔍 发现历史配对记录，自动静默开启蓝牙基站等待摩托车...")
            // 只要调用这个，就会触发 peripheralManagerDidUpdateState 从而开始广播
            _ = self.peripheralManager
        } else {
            PTProgressHUD.show(text:"首次使用，需等待用户手动点击按钮开启连接流程")
        }
    }
    
    // 如果用户想要解绑换车
    func forgetScooter() {
        UserDefaults.standard.set(false, forKey: kHasPairedKey)
        PTProgressHUD.show(text:"🗑️ 已清除记住的摩托车")
        // 这里可以加上断开连接的逻辑
    }
}

extension PTBluetoothServerManager {
    // 发现设备
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let peripheralName = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        guard !peripheralName.isEmpty else { return }
        
        // 2. 将名称转换为大写，精准匹配 "PEUGEOT"
        if peripheralName.uppercased().contains("PEUGEOT") {
            
            // 3. 结合信号强度判断 (>-60 代表大约在 1~3 米范围内)
            // 如果你确信周围只有你这一台车，可以把 `&& RSSI.intValue > -60` 这个条件删掉
            if RSSI.intValue > -60 {
                PTProgressHUD.show(text:"🎯 锁定标致摩托车，正在建立连接...")
                centralManager.stopScan()
                activeScooter = peripheral
                centralManager.connect(peripheral, options: nil)
            }
        }
    }
    
    // 物理连接成功
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        PTProgressHUD.show(text: "✅ 物理连接成功！等待车机订阅基站通道...")
    }
    
    // 意外断开连接
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        PTProgressHUD.show(text: "⚠️ 摩托车物理连接已断开")
        activeScooter = nil
        authenticated = false
    }
}

extension PTBluetoothServerManager {
    
    // MARK: - 发送导航与控制指令
    
    // 发送导航定位信息[cite: 3]
    func sendNavigation(info: PTNavigationInfo) {
        guard authenticated else {
            PTProgressHUD.show(text:"⚠️ 尚未完成认证，无法发送导航数据")
            return
        }
        let frame = PTFrameBuilder.buildNavigationFrame(info: info)
        sendChunkedData(data: frame, to: txChar)
    }
    
    // 发送断开连接指令[cite: 3]
    func sendDisconnect() {
        guard authenticated else { return }
        let frame = PTFrameBuilder.buildDisconnectFrame()
        sendChunkedData(data: frame, to: txChar)
    }
    
    // MARK: - 解析摩托车回传状态
    /// 解析摩托车仪表盘的实时状态帧[cite: 2]
    func parseDashboardFrame(_ value: Data) {
        // 校验包头 0x16 并且长度至少足够提取 ID 和 Payload[cite: 2]
        guard value.count >= 4, value[0] == 0x16 else { return }
        
        let id = value[1]
        let payload = value.subdata(in: 2..<(value.count - 1))
        let bytes = [UInt8](payload)
        
        switch id {
        case 1:
            PTProgressHUD.show(text:"🔗 收到连接状态包 (CONNECTION)")
        case 2:
            let fuelRaw = Double(bytes[0])
            let fuel = min(max(Int(round(fuelRaw * 0.3937)), 0), 100)
            let avg = Double(bytes[2]) * 0.1
            let tripRaw = (Int(bytes[3]) << 8) | Int(bytes[4])
            let odoRaw = (Int(bytes[5]) << 16) | (Int(bytes[6]) << 8) | Int(bytes[7])
            let data1 = PTDashboardData1(tripKm: Double(tripRaw) * 0.1, odoKm: Double(odoRaw) * 0.1, fuelLevelPct: fuel, avgConsumptionLt: avg)
            NotificationCenter.default.post(name: NSNotification.Name("MotorcycleDATA1"), object: data1)
        case 3:
            guard bytes.count >= 6 else { return }
            let engine = Int(bytes[1])
            let maint = Int(bytes[3])
            let temp = Int(bytes[4]) - 50
            let batt = Double(bytes[5]) * 0.1
            let data2 = PTDashboardData2(batteryVolt: batt, outsideTempC: temp, engineStatus: engine, maintenance: maint)
            NotificationCenter.default.post(name: NSNotification.Name("MotorcycleDATA2"), object: data2)
        case 4:
            guard bytes.count >= 6 else { return }
            let autoRaw = (Int(bytes[0]) << 8) | Int(bytes[1])
            let col = Int(bytes[2])
            let dist = (Int(bytes[3]) << 8) | Int(bytes[4])
            let lang = Int(bytes[5])
            let data3 = PTDashboardData3(autonomyKm: Double(autoRaw) * 0.1, distToMaintenance: dist, colorMeasur: col, language: lang)
            NotificationCenter.default.post(name: NSNotification.Name("MotorcycleDATA3"), object: data3)
        case 5:
            guard bytes.count >= 8 else { return }
            let engineRaw = (Int(bytes[4]) << 8) | Int(bytes[5])
            let vehicleRaw = (Int(bytes[6]) << 8) | Int(bytes[7])
            let control = PTDashboardControl(vehicleSpeedKmh: Double(vehicleRaw) * 0.01, engineRpm: Int(Double(engineRaw) * 0.25))
            NotificationCenter.default.post(name: NSNotification.Name("MotorcycleCONTROL"), object: control)
        case 6: // RxId.ABS[cite: 2]
            guard bytes.count >= 3 else { return }
            let absStatus = PTAbsStatus(absRaw: Int(bytes[2]))
            NotificationCenter.default.post(name: NSNotification.Name("MotorcycleABS"), object: absStatus)
        default:
            break
        }
    }
}
