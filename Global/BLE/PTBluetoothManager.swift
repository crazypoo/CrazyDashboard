//
//  PTBluetoothManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 19/7/2026.
//

import UIKit
import CoreBluetooth
import PooTools
import UserNotifications

let MotorcycleDashBoardChange = NSNotification.Name("MotorcycleDashBoardChange")

let kmToMilOffset:Double = 0.621371

extension UInt8 {
    /// 将字节转换为 8 位对齐的二进制字符串 (例如: 01010011)
    var binaryString: String {
        let str = String(self, radix: 2)
        // 自动补齐前导 0，确保长度总是 8
        return String(repeating: "0", count: 8 - str.count) + str
    }
}

public enum PTBacklightMode: UInt8 {
    case auto = 0x00 // 二进制 00
    case led1 = 0x01 // 二进制 01
    case led0 = 0x02  // 二进制 10
    case led2 = 0x03  // 二进制 11
    case unknown = 0xFF
    
    public var description: String {
        switch self {
        case .auto: return "Auto"//"自动 (Auto)"
        case .led0: return "Led0"//"亮度档位 0"
        case .led1: return "Led1"//"亮度档位 1"
        case .led2: return "Led2"//"亮度档位 2"
        case .unknown: return "Unknown"//"未知状态"
        }
    }
}

public enum PTTCSMode: UInt8 {
    case mode1 = 0x02 // 相当于二进制 00101110
    case mode2 = 0x04 // 相当于二进制 00010111
    case off   = 0x00 // 相当于二进制 10111000
    case unknown = 0xFF // 用于容错的未知状态
    
    /// 提供给 UI 界面展示的文字描述
    public var description: String {
        switch self {
        case .mode1: return "Mode1"//"模式 1 (运动/标准)"
        case .mode2: return "Mode2"//"模式 2 (雨雪/湿滑)"
        case .off:   return "Off"//"已关闭 (危险)"
        case .unknown: return "Unknown"//"未知状态"
        }
    }
}

/// 专门用于通过 iOS 原生机制向车机推送 ANCS 弹窗消息的工具类
class PTMessagePusher {
    
    /// 1. 必须先向用户申请通知权限 (在 App 启动时调用一次即可)
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
//                PTNSLogConsole("✅ [通知权限] 授权成功！车机弹窗功能已就绪。")
            } else {
//                PTNSLogConsole("❌ [通知权限] 被拒绝，将无法推送到车机。")
            }
        }
    }
    
    /// 2. 推送自定义消息到车机
    /// - Parameters:
    ///   - title: 消息标题 (例如："系统警告" 或 "来自助理")
    ///   - body: 消息正文 (例如："轮胎气压过低，请注意安全！")
    static func pushToDashboard(title: String, body: String) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        PTNotificationCenter.pushCenter(title: title, body: body,trigger: trigger)
    }
}

// MARK: - 主动配置指令模型
/// 车机下发配置的枚举参数 (注意：这里的颜色值与状态回传帧的位掩码值不同)
enum PTConfigColor: UInt8,CaseIterable {
    case red = 1
    case blue = 2
    case gold = 3
    
    func getColor() -> UIColor {
        switch self {
        case .blue:
            return .systemBlue
        case .gold:
            return .GoldColor
        case .red:
            return .systemRed
        }
    }
    
    func getColorName() -> String {
        switch self {
        case .blue:
            return "Blue"
        case .gold:
            return "Gold"
        case .red:
            return "Red"
        }
    }
}

enum PTConfigUnit: UInt8,CaseIterable {
    case metric = 1   // 公制 (Km)
    case imperial = 2 // 英制 (Mil)
    
    func getTypeName() -> String {
        switch self {
        case .metric:
            return "Km"
        case .imperial:
            return "Mil"
        }
    }
}

enum PTConfigLanguage: UInt8,CaseIterable {
    case english = 1
    case french = 2
    case german = 3
    case spanish = 4
    case italian = 5
    
    func getTypeName() -> String {
        switch self {
        case .english: return "English"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .italian: return "Italiano"
        }
    }
}

// MARK: - ANCS 通知数据模型
/// 映射来电、短信等系统通知
struct PTAncsNotif {
    let uid: UInt32
    let title: String
    let message: String
    let category: UInt8 // 例如：1 代表 Call，4 代表 Social
    let appId: String
    
    public init(uid: UInt32, title: String, message: String, category: UInt8, appId: String) {
        self.uid = uid
        self.title = title
        self.message = message
        self.category = category
        self.appId = appId
    }
}

// MARK: - 导航与状态数据模型
struct PTDashboardControl {
    /// 当前车速 (数值取决于仪表盘的单位设置，可能是 km/h 或 mph)
    let vehicleSpeedKmh: Double
    /// 引擎实时转速 (RPM)
    let engineRpm: Int
    
    let tcsMode:PTTCSMode
    
    let isLowBeamOn: Bool
    let isHighBeamOn: Bool
    
    let isLeftTurnOn: Bool
    let isRightTurnOn: Bool
    let isHazardOn: Bool
    
    let isTcsSystemReady:Bool
}

struct PTDashboardData1 {
    /// 单次行程里程 (小计里程 / Trip)
    let tripKm: Double
    /// 车辆总行驶里程 (总里程 / ODO) - 已完美融合安卓的 odo1 和 odo2
    let odoKm: Double
    /// 当前油量百分比 (0% - 100%)
    let fuelLevelPct: Int
    /// 平均油耗 (L/100km)
    let avgConsumptionLt: Double
}

struct PTDashboardData2 {
    /// 电瓶电压 (V)
    let batteryVolt: Double
    /// 车外环境温度 (摄氏度 °C)
    let outsideTempC: Int
    /// 引擎状态枚举原始值 (需通过 PTDashboardLabels.engineStatusLabel 解析)
    /// 0:未启动, 1:启动中, 2:运转中, 3:关闭中
    let engineStatus: Int
    /// 保养状态原始值 (需通过 PTDashboardLabels.maintenanceLabel 解析)
    let maintenance: Int
    /// 仪表盘光
    let backlightMode: PTBacklightMode
    
    let engineTempC: Int
    let isKickstandDown: Bool
    
    let batteryDisplayState: Int
}

struct PTDashboardData3 {
    /// 剩余预估续航里程
    let autonomyKm: Double
    /// 距离下次保养的剩余里程
    let distToMaintenance: Int
    /// 仪表盘颜色与测量单位的混合原始值 (Color & Measure)
    let colorMeasur: Int
    /// 当前系统语言设置原始值
    let language: Int
    /// [新增] 解析出的里程表单位制：true 为公制(公里/Km)，false 为英制(英里/Mil)
    var isMetric: Bool {
        // 如果包含 0x08 标志位，则是英里，否则是公里
        return (colorMeasur & 0x08) == 0
    }
    
    /// [新增] 直接获取用于 UI 展示的单位字符串 ("Km" 或 "Mil")
    var unitString: String {
        return PTDashboardLabels.unitLabel(c: colorMeasur)
    }
    
    var unitType: PTConfigUnit {
        return (colorMeasur & 0x08) != 0 ? .imperial : .metric
    }
    
    var languageType: PTConfigLanguage {
        // 1. 将 Int 转换为 UInt8
        let decodedCode = UInt8((language >> 1) & 0x0F)
        // 2. 尝试用 rawValue 初始化枚举。
        // 如果匹配失败（例如传来一个未知的数字 9），则触发 ?? 后面的安全回退机制，默认返回英语。
        return PTConfigLanguage(rawValue: decodedCode) ?? .english
    }
    
    var dashboardColor: PTConfigColor {
        // 使用 0xC0 掩码提取最高两位
        let colorMask = colorMeasur & 0xC0
        
        switch colorMask {
        case 0x00:
            return .blue
        case 0x40:
            return .gold
        case 0x80:
            return .red
        case 0xC0:
            return .blue // 未定义状态，安全回退为 Blue
        default:
            return .blue // 兜底保护
        }
    }
}

struct PTAbsStatus {
    /// ABS 状态原始值 (1:正常, 2:故障)
    let absRaw: Int
    
    let isAbsLightOn: Bool
    
    let frontWheelSpeedKmh:Double
}

// MARK: - 状态标签转换工具
struct PTDashboardLabels {
    static func engineStatusLabel(raw: Int) -> String {
        switch raw & 0x03 {
        case 0: return PTDashboardConfig.languageFunc(text: "engine_cold")
        case 1: return PTDashboardConfig.languageFunc(text: "engine_start")
        case 2: return PTDashboardConfig.languageFunc(text: "engine_cycling")
        case 3: return PTDashboardConfig.languageFunc(text: "engine_closing")
        default: return "-"
        }
    }
    
    static func maintenanceLabel(raw: Int) -> String {
        return (raw & 0xE0) != 0 ? PTDashboardConfig.languageFunc(text: "maintenance_need") : PTDashboardConfig.languageFunc(text: "maintenance_need_no")
    }
    
    static func absLabel(raw: Int) -> String {
        switch raw & 0x03 {
        case 1: return PTDashboardConfig.languageFunc(text: "abs_ok")
        case 2: return PTDashboardConfig.languageFunc(text: "abs_error")
        default: return "-"
        }
    }
    
    static func unitLabel(c: Int) -> String {
        return (c & 0x08) != 0 ? "Mil" : "Km"
    }    
}

// 复刻 Android 的 NavigationInfo
struct PTNavigationInfo {
    var nextManeuver: UInt8
    var metersToNextManeuver: UInt32
    var nameNextRoad: String
    var nameCurrentRoad: String
    var currentSpeedLimit: UInt8
    var distanceToDestination: UInt32
    /// 距离到达目的地的预计剩余秒数
    var estimatedTimeToDestinationSec: Int
}

// 转弯动作常量枚举 (复刻 ManeuverMap)
enum PTManeuverMap {
    static let undefined: UInt8 = 0
    static let straight: UInt8 = 1
    static let uTurnRight: UInt8 = 2
    static let uTurnLeft: UInt8 = 3
    static let keepRight: UInt8 = 4
    static let lightRight: UInt8 = 5
    static let quiteRight: UInt8 = 6
    static let heavyRight: UInt8 = 7   // 急右转
    static let keepMiddle: UInt8 = 8
    static let keepLeft: UInt8 = 9
    static let lightLeft: UInt8 = 10
    static let quiteLeft: UInt8 = 11
    static let heavyLeft: UInt8 = 12   // 急左转
    
    // 🚨 新增：环岛基础动作
    static let roundaboutRightBase: UInt8 = 0x13 // 右侧环岛起始 (13~1E 代表 1~12 出口)
    static let roundaboutLeftBase: UInt8 = 0x1F  // 左侧环岛起始 (1F~2A 代表 1~12 出口)
    
    // 🚨 新增：特殊状态指令
    static let depart: UInt8 = 43       // 0x2B 出发
    static let arrive: UInt8 = 44       // 0x2C 到达
    static let ferry: UInt8 = 45        // 0x2D 轮渡 (推测)
    static let returnToRoute: UInt8 = 46// 0x2E 回到路线
    static let noValidAction: UInt8 = 47// 0x2F 无有效动作
    static let rerouting: UInt8 = 48    // 0x30 ICON_REROUTING (重新算路图标)
    static let noGPS: UInt8 = 49        // 0x31 ICON_NO_GPS (无 GPS 图标)
}

// MARK: - 安全认证中心 (完整版)
class PTScooterAuth {
    
    // 核心加密字典表 (2048 长度)
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
        
        // 1. 将 Base64 解码为原始的 4096 字节 Data
        guard let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else {
            PTProgressHUD.show(text: "❌ 严重错误：Base64 字典表解析失败！")
            self.numbersList = Array(repeating: 0, count: 2048)
            return
        }
        
        // 2. 准备容器，容量为 2048
        var list = [UInt16]()
        list.reserveCapacity(2048)
        
        // 3. 按小端序 (Little-Endian) 读取每两个字节
        data.withUnsafeBytes { buffer in
            for i in 0..<2048 {
                let byteOffset = i * 2
                // 直接从指定偏移量加载 UInt16
                let value = buffer.load(fromByteOffset: byteOffset, as: UInt16.self)
                // 确保无论在哪种架构的 CPU 上，都按照小端序进行解析
                list.append(UInt16(littleEndian: value))
            }
        }
        
        self.numbersList = list
        PTProgressHUD.show(text: "✅ 成功加载加密字典表！容量：\(self.numbersList.count) 个节点。")
    }
    
    // MARK: - 核心验证方法
    
    // 1. 生成 10 个随机数 Challenge
    func createChallenge() -> [UInt16] {
        for i in 0..<10 {
            randomNumbers[i] = UInt16.random(in: 0...UInt16.max)
        }
        return randomNumbers
    }
    
    // 2. 验证摩托车发回来的 20 字节是否正确
    func checkAuthMsg(scooterResponse: Data) -> Bool {
        guard scooterResponse.count >= 10 else { return false }
        let expected = createAuthenticationMessage(r: randomNumbers)
        // 只严格比对前 10 个有效响应字节
        for i in 0..<10 {
            if scooterResponse[i] != expected[i] { return false }
        }
        return true
    }
    
    // 3. 利用字典表生成 20 字节的加密响应
    func createAuthenticationMessage(r: [UInt16]) -> Data {
        var data = Data()
        // 前 10 字节根据表生成
        for k in 0..<5 {
            let c1 = numbersList[Int(r[k] & 0x7FF)]
            let c2 = numbersList[Int(r[k + 5] & 0x7FF)]
            
            // 🚨 核心修复：Swift 防溢出处理！
            // 必须先将 UInt16 提升为 UInt32，相加后再进行掩码，防止程序在这里静默崩溃
            let sum = (UInt32(c1) + UInt32(c2)) & 0xFFFF
            
            // 写入 16-bit Big-Endian (大端序)
            var bigEndianSum = UInt16(sum).bigEndian
            data.append(Data(bytes: &bigEndianSum, count: MemoryLayout<UInt16>.size))
        }
        // 后 10 字节填充随机数防嗅探
        for _ in 0..<10 {
            let randomByte = UInt8.random(in: 0...255)
            data.append(randomByte)
        }
        return data
    }
    
    // 4. 获取 15 字节的设备身份信息 (Key ID)
    func getScooterKeyId() -> Data {
        var data = Data()
        // 固定产品 ID 8758 (大端序)
        var productId = UInt32(8758).bigEndian
        data.append(Data(bytes: &productId, count: 4))
        
        // App 版本 "2.1.37"
        data.append(contentsOf: [2, 0, 8])
        
        // 编译日期 "12/07/2018"
        data.append(contentsOf: [1, 4, 25])
        
        // 固定分隔符
        data.append(1)
        
        // iOS 系统版本 (截取前 4 个段)
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

// MARK: - 2. 协议封装器
class PTFrameBuilder {
    // 封包常量
    static let PREAMBLE: UInt8 = 0x16
    static let END_OF_FRAME: UInt8 = 0x00
    
    static let ID_NAVIGATION: UInt8 = 1
    static let ID_CONFIGURATION: UInt8 = 7
    static let ID_DISCONNECT: UInt8 = 8
    
    // 通用封包方法：[16] + [ID] + [2字节长度] + [Payload] + [00]
    static func wrapTxFrame(idFrame: UInt8, payload: Data) -> Data {
        var frame = Data()
        frame.append(PREAMBLE)
        frame.append(idFrame)
        
        // 写入 2 字节长度 (Big-Endian)
        var length = UInt16(payload.count).bigEndian
        frame.append(Data(bytes: &length, count: MemoryLayout<UInt16>.size))
        
        frame.append(payload)
        frame.append(END_OF_FRAME)
        return frame
    }
    
    // 生成配置指令
    static func buildConfigurationFrame(color: UInt8, unit: UInt8, language: UInt8) -> Data {
        let payload = Data([
                    0x01, color,
                    0x01, unit,
                    0x01, language
        ])
        return wrapTxFrame(idFrame: ID_CONFIGURATION, payload: payload)
    }
    
    // 生成主动断开连接帧
    static func buildDisconnectFrame() -> Data {
        let payload = Data([1, 1])
        return wrapTxFrame(idFrame: ID_DISCONNECT, payload: payload)
    }
    
    /// 生成 TCS 设置指令帧
    /// - Parameter mode: 期望设置的 TCS 模式
    /// - Returns: 封装好的完整二进制蓝牙帧 Data
    static func buildTCSFrame(id:UInt8,mode: PTTCSMode) -> Data {
        // 1. 获取核心控制字节
        let tcsByte = mode.rawValue
        
        // 2. 构建 Payload
        // 注意：如果协议要求类似 configuration 那样的前缀（如 0x01, tcsByte），请在此处修改数组
        let payload = Data([tcsByte])
        
        // 3. 调用你现有的通用封包方法
        return wrapTxFrame(idFrame: id, payload: payload)
    }
    
    /// 生成仪表盘背光设置指令帧
    /// - Parameter mode: 期望设置的背光模式
    /// - Returns: 封装好的完整二进制蓝牙帧 Data
    static func buildBacklightFrame(id:UInt8,mode: PTBacklightMode) -> Data {
        // 1. 获取核心控制字节 (0x00, 0x01, 0x02, 0x03)
        let modeByte = mode.rawValue
        
        // 2. 构建 Payload
        // 如果协议要求带有前缀（例如：0x02 代表设置灯光，后接灯光值），则改为 Data([0x02, modeByte])
        let payload = Data([modeByte])
        
        // 3. 调用你的通用封包方法 (会自动加上包头 0x16，计算大端序长度，并加上包尾 0x00)
        return wrapTxFrame(idFrame: id, payload: payload)
    }
    
    /// 模糊测试专用封包器 (Fuzzer)
    /// - Parameters:
    ///   - idFrame: 你想测试的任意指令 ID (例如 2, 3, 4, 5, 6，或者 9, 10 等未知领域)
    ///   - payload: 任意的十六进制载荷数组 (默认给个 [0x00] 探探路)
    /// - Returns: 自动计算好大端序长度的完整数据帧
    static func buildFuzzFrame(idFrame: UInt8, payload: [UInt8] = [0x00]) -> Data {
        let payloadData = Data(payload)
        
        // 调用你封装得非常完美的底层方法
        return wrapTxFrame(idFrame: idFrame, payload: payloadData)
    }
}

// 补充 PTFrameBuilder 内部方法
extension PTFrameBuilder {
    
    // 生成导航数据帧
    static func buildNavigationFrame(info: PTNavigationInfo) -> Data {
        var payload = Data()
        
        // 1. Maneuver Type (机动动作): [Hdr=1][Maneuver]
        payload.append(1)
        payload.append(info.nextManeuver)
        
        // 2. Maneuver Distance (距下一动作距离): [Hdr=4][4-byte Dist 大端序]
        let roundedNextDist = (info.metersToNextManeuver / 5) * 5
        payload.append(4)
        var dist = roundedNextDist.bigEndian
        payload.append(Data(bytes: &dist, count: MemoryLayout<UInt32>.size))
        
        // 3. Next Road (下一道路): [Size][Text] (最大 50 字节，注意这里没有 Hdr)
        let nextRoadData = encodeString(info.nameNextRoad)
        payload.append(UInt8(nextRoadData.count))
        payload.append(nextRoadData)
        
        // 4. Current Road (当前道路): [Size][Text] (最大 50 字节，注意这里没有 Hdr)
        let curRoadData = encodeString(info.nameCurrentRoad)
        payload.append(UInt8(curRoadData.count))
        payload.append(curRoadData)
        
        // 5. Speed Limit (当前限速): [Hdr=1][Speed]
        payload.append(1)
        payload.append(info.currentSpeedLimit)
        
        // 6. Total Distance (剩余总距离): [Hdr=4][4-byte Dist 大端序]
        payload.append(4)
        var totalDist = info.distanceToDestination.bigEndian
        payload.append(Data(bytes: &totalDist, count: MemoryLayout<UInt32>.size))
        
        // 7. ETA (预计到达时间): [Hdr=7][7-byte Date/Time 大端序]
        payload.append(7)
        
        // 通过当前时间 + 剩余秒数，计算出预计到达的真实时间
        let etaDate = Calendar.current.date(byAdding: .second, value: info.estimatedTimeToDestinationSec, to: Date()) ?? Date()
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: etaDate)
        
        // 写入年份 (Short, 2字节)
        var year = UInt16(comps.year ?? 2026).bigEndian
        payload.append(Data(bytes: &year, count: MemoryLayout<UInt16>.size))
        
        // 写入月、日、时、分、秒 (Byte, 各1字节)
        // Swift 的 month 是 1-12，完美对应自然月，不需要像 Android 的 Calendar 那样 +1
        payload.append(UInt8(comps.month ?? 1))
        payload.append(UInt8(comps.day ?? 1))
        payload.append(UInt8(comps.hour ?? 0))
        payload.append(UInt8(comps.minute ?? 0))
        payload.append(UInt8(comps.second ?? 0))
        
        // 封装成完整的传输帧 (ID = 1)
        return wrapTxFrame(idFrame: ID_NAVIGATION, payload: payload)
    }

    // 字符串截断与编码辅助方法
    private static func encodeString(_ text: String) -> Data {
        let normalizedStr = text.folding(options: .diacriticInsensitive, locale: .current)
        let data = normalizedStr.data(using: .isoLatin1) ?? Data()
        if data.count > 50 {
            return data.prefix(50)
        }
        return data
    }
}

// MARK: - ANCS 封包扩展 (补充至 PTFrameBuilder)
extension PTFrameBuilder {
    /// 构建 ANCS Notification Source 帧 (通知到达信号)
    static func buildAncsNotifSourceFrame(notif: PTAncsNotif, eventId: UInt8 = 0) -> Data {
        var bb = Data()
        bb.append(eventId) // 0: Added, 1: Modified, 2: Removed
        bb.append(2)       // EventFlags: Important
        bb.append(notif.category)
        bb.append(1)       // CategoryCount
        
        // 🚨 注意：ANCS 协议底层强制使用 Little-Endian (小端序)
        var uidLittleEndian = notif.uid.littleEndian
        bb.append(Data(bytes: &uidLittleEndian, count: MemoryLayout<UInt32>.size))
        return bb
    }
    
    /// 构建 ANCS Data Source 帧 (通知详细内容，如来电人姓名、短信内容)
    static func buildAncsDataSourceFrame(notif: PTAncsNotif, attrId: UInt8) -> Data {
        let text: String
        switch attrId {
        case 0: text = notif.appId
        case 1: text = notif.title
        case 3: text = notif.message
        default: text = ""
        }
        
        // 使用 UTF-8 编码，最大截断 250 字节
        let textData = text.data(using: .utf8)?.prefix(250) ?? Data()
        
        var bb = Data()
        bb.append(0) // CommandID: GetNotificationAttributes
        
        // 写入 UID (小端序)
        var uidLittleEndian = notif.uid.littleEndian
        bb.append(Data(bytes: &uidLittleEndian, count: MemoryLayout<UInt32>.size))
        
        bb.append(attrId)
        
        // 写入字符串长度 (2 字节小端序)
        var lengthLittleEndian = UInt16(textData.count).littleEndian
        bb.append(Data(bytes: &lengthLittleEndian, count: MemoryLayout<UInt16>.size))
        
        // 写入字符串内容
        bb.append(textData)
        return bb
    }
}

// MARK: - 3. 核心蓝牙服务端 (复刻 ScooterGattServer.kt)
enum PTAuthState {
    case waitKeyId      // 等待车机发送 8758
    case waitAuthMsg    // 等待车机返回加密后的验证数据
    case waitRandomNums     // 3. 恢复：等车机发 20 字节挑战码 (即 27b21814...)
    case waitConnectionFrame// 4. 恢复：等车机最终的 0x16 0x01 确认信号
    case success        // 验证完成，数据流通
}

protocol PTBLEDashboardDelegate: AnyObject {
    func dashboardManager(_ manager: PTBluetoothServerManager, didChangeConnectionState isConnected: Bool)
    func dashboardManager(_ manager: PTBluetoothServerManager, dashboardData data: Any?)
    func dashboardManager(_ manager: PTBluetoothServerManager, unknownData data: String)
    func dashboardManager(
        _ manager: PTBluetoothServerManager,
        didUpdateConnectionIdentity identity: PTDashboardConnectionIdentity?
    )
}

extension PTBLEDashboardDelegate {
    func dashboardManager(_ manager: PTBluetoothServerManager, didChangeConnectionState isConnected: Bool) {}
    func dashboardManager(_ manager: PTBluetoothServerManager, dashboardData data: Any?) {}
    func dashboardManager(_ manager: PTBluetoothServerManager, unknownData data: String) {}
    func dashboardManager(
        _ manager: PTBluetoothServerManager,
        didUpdateConnectionIdentity identity: PTDashboardConnectionIdentity?
    ) {}
}

// 只保留外设管理器，做纯粹的服务器
class PTBluetoothServerManager: NSObject, CBPeripheralManagerDelegate {
    
    static let shared = PTBluetoothServerManager()
    
    private class WeakDelegateWrapper {
        weak var delegate: PTBLEDashboardDelegate?
        init(_ delegate: PTBLEDashboardDelegate) { self.delegate = delegate }
    }
    private var delegates: [WeakDelegateWrapper] = []

    // MARK: - 深度 OBD 探针引擎 (Active Diagnostic Prober)
        
    private var diagnosticTimer: Timer?
    private var currentProbeIndex: UInt8 = 0x00

    // 用于控制自动扫描的定时器
    private var fuzzTimer: Timer?
    // 当前正在探测的 ID
    private var currentFuzzID: UInt8 = 0x00
    
    // MARK: - TCS 物理打滑监控系统
    private var currentFrontSpeed: Double = 0.0
    private var currentRearSpeed: Double = 0.0
    /// 允许的最大轮速差安全阈值 (km/h)，可根据测试结果微调
    private let slipThreshold: Double = 5.0
    
    /// 核心逻辑：比对轮速差，复现 TCS 触发条件
    private func checkTCSIntervention() {
        let speedDelta = currentRearSpeed - currentFrontSpeed
        // 当后轮速大于前轮速，且差值超过阈值时，判定为打滑
        if speedDelta > slipThreshold {
            let logMsg = "⚠️ [TCS 预警] 检测到打滑物理条件！后轮: \(currentRearSpeed) | 前轮: \(currentFrontSpeed) | 差值: \(String(format: "%.2f", speedDelta)) km/h"
            PTOBDLogger.moto.ptLog(logMsg)
            // 可在此发送额外的 Notification 让 UI 界面上高亮 TCS 图标
            delegates.forEach( { $0.delegate?.dashboardManager(self, dashboardData: "1") })
        } else {
            delegates.forEach( { $0.delegate?.dashboardManager(self, dashboardData: "0") })
        }
    }

    public private(set) var latestData1: PTDashboardData1?
    public private(set) var latestData2: PTDashboardData2?
    public private(set) var latestData3: PTDashboardData3?
    public private(set) var latestControl: PTDashboardControl?
    public private(set) var latestAbsStatus: PTAbsStatus?
    // EN: Expose only the current dashboard identity; authentication and transport remain private.
    // ES: Expone solo la identidad actual del tablero; la autenticación y el transporte permanecen privados.
    // 中文：只暴露当前仪表身份，认证和传输逻辑继续保持私有。
    private(set) var dashboardConnectionIdentity: PTDashboardConnectionIdentity?

    // 🚨 核心修复 1：必须使用 16-bit 短标识！否则会撑爆 iOS 的 31 字节广播包，导致摩托车看不见！
    let TIO_SERVICE = CBUUID(string: "FEFB")
    
    let UART_RX = CBUUID(string: "00000001-0000-1000-8000-008025000000")
    let UART_TX = CBUUID(string: "00000002-0000-1000-8000-008025000000")
    let UART_RX_CREDITS = CBUUID(string: "00000003-0000-1000-8000-008025000000")
    let UART_TX_CREDITS = CBUUID(string: "00000004-0000-1000-8000-008025000000")
        
    // 🚨 新增：用于缓存当前活跃的通知，等待车机来主动拉取内容
    private var activeNotifications = [UInt32: PTAncsNotif]()

    var peripheralManager: CBPeripheralManager!
    let auth = PTScooterAuth()
    
    var txChar: CBMutableCharacteristic!
    var txCreditsChar: CBMutableCharacteristic!
    
    private var authState: PTAuthState = .waitKeyId
    private var authenticated = false
    private var isTioSubscribed = false
    private var isCreditsSubscribed = false
    private var localCredits = 0
    private var connectedCentral: CBCentral?
    
    private var sendCredits = 0
    // EN: Keep reassembly at the UART ingress boundary; authentication, credits, sending, and decoding remain unchanged.
    // ES: Mantén el reensamblado en el límite de entrada UART; la autenticación, los créditos, el envío y la decodificación permanecen sin cambios.
    // 中文：仅在 UART 入站边界增加重组；认证、Credits、发送和解码逻辑保持不变。
    private var inboundReassembler = PTXP400BLEInboundReassembler()
        
    struct PTNotifyJob {
        let data: Data
        let characteristic: CBMutableCharacteristic
        let completion: (() -> Void)? // 🚨 新增：该分片成功压入硬件后的回调
    }
    private var sendQueue: [PTNotifyJob] = []
    private var isSending = false
        
    override init() {
        super.init()
        PTOBDLogger.moto.ptLog("🛠️ [DEBUG] 初始化基站 (移除所有多余扫描干扰)")
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
        
    // MARK: - 启动基站
    func startBaseStationAndScan() {
        if peripheralManager.state == .poweredOn {
            if peripheralManager.isAdvertising {
                PTOBDLogger.moto.ptLog("⚠️ [状态] 基站已经在广播中了")
                return
            }
            setupServices()
            
            // 🚨 核心修复 1 延续：只广播服务，不带名字，保证 FEFB 绝对暴露给摩托车！
            peripheralManager.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [TIO_SERVICE]
            ])
            PTOBDLogger.moto.ptLog("📡 [状态] 信号发射！车机可以直接发现我们了...")
        } else {
            PTOBDLogger.moto.ptLog("❌ [错误] 蓝牙未开启，状态: \(peripheralManager.state.rawValue)")
        }
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        PTOBDLogger.moto.ptLog("🛠️ [DEBUG] 硬件状态: \(peripheral.state.rawValue)")
    }
    
    private func setupServices() {
        let rxChar = CBMutableCharacteristic(
            type: UART_RX,
            properties: [.writeWithoutResponse],
            value: nil,
            permissions: [.writeEncryptionRequired]
        )
        
        // 🚨 核心修复 2：使用 notifyEncryptionRequired！
        // 强迫车机在订阅这一刻就弹出系统配对框，否则后续的 8758 会被 iOS 丢弃！
        txChar = CBMutableCharacteristic(
            type: UART_TX,
            properties: [.notifyEncryptionRequired], // 👈 最关键的一步
            value: nil,
            permissions: [.readEncryptionRequired]
        )
        
        let rxCreditsChar = CBMutableCharacteristic(
            type: UART_RX_CREDITS,
            properties: [.write],
            value: nil,
            permissions: [.writeEncryptionRequired]
        )
        
        // 🚨 核心修复 2 延续：使用 indicateEncryptionRequired
        txCreditsChar = CBMutableCharacteristic(
            type: UART_TX_CREDITS,
            properties: [.indicateEncryptionRequired], // 👈 最关键的一步
            value: nil,
            permissions: [.readEncryptionRequired]
        )

        let service = CBMutableService(type: TIO_SERVICE, primary: true)
        service.characteristics = [rxChar, txChar, rxCreditsChar, txCreditsChar]
        peripheralManager.add(service)
                
        PTOBDLogger.moto.ptLog("🛠️ [DEBUG] 通道搭建完毕 (iOS 强制加密挂载完成)")
    }
    
    // MARK: - 监听订阅
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        let identityChanged = connectedCentral?.identifier != central.identifier
        connectedCentral = central
        dashboardConnectionIdentity = PTDashboardConnectionIdentity(centralIdentifier: central.identifier)
        PTOBDLogger.moto.ptLog("⚡️ [雷达] 摩托车订阅成功: \(characteristic.uuid.uuidString)")

        if identityChanged {
            inboundReassembler.reset()
            delegates.forEach {
                $0.delegate?.dashboardManager(self, didUpdateConnectionIdentity: dashboardConnectionIdentity)
            }
        }
        
        if characteristic.uuid == UART_TX { isTioSubscribed = true }
        if characteristic.uuid == UART_TX_CREDITS { isCreditsSubscribed = true }

        if isTioSubscribed && isCreditsSubscribed {
            PTOBDLogger.moto.ptLog("🔗 [状态] 通道订阅完毕！等待车机写入 8758...")
            authState = .waitKeyId
            authenticated = false
            inboundReassembler.reset()
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        PTOBDLogger.moto.ptLog("⚠️ [状态] 摩托车断开了通道")
        PTOBDLogger.moto.stopFileLogging()
        authenticated = false
        isTioSubscribed = false
        isCreditsSubscribed = false
        authState = .waitKeyId
        inboundReassembler.reset()
        if PTDashboardConfig.shared.blueConnected {
            self.cleanupDelegates()
            self.delegates.forEach( { $0.delegate?.dashboardManager(self, didChangeConnectionState: false) })
        }
        dashboardConnectionIdentity = nil
        connectedCentral = nil
        delegates.forEach {
            $0.delegate?.dashboardManager(self, didUpdateConnectionIdentity: nil)
        }
    }
    
    // MARK: - 监听写入
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        if let first = requests.first, first.characteristic.properties.contains(.write) {
            peripheralManager.respond(to: first, withResult: .success)
        }
        
        for request in requests {
            guard let data = request.value else { continue }
            
            if request.characteristic.uuid == UART_RX {
                if authenticated && localCredits > 0 {
                    localCredits -= 1
                    if localCredits <= 4 { grantScooterCredits() }
                }
                receiveUARTData(data)
            } else if request.characteristic.uuid == UART_RX_CREDITS {
                // 🚨 核心修复 1：接收摩托车发放的发送令牌 (Credits)！
                let addedCredits = Int(data[0])
                self.sendCredits += addedCredits
                PTOBDLogger.moto.ptLog("🎟️ [流控通道] 摩托车发放了 \(addedCredits) 个发送令牌，当前总余额: \(self.sendCredits)")
                
                // 拿到令牌后，立刻启动发送泵，把积压的导航数据发出去
                self.pumpQueue()
            }
        }
    }

    // EN: Map the established authentication state to the packet shape expected by the ingress assembler.
    // ES: Mapea el estado de autenticación establecido a la forma de paquete esperada por el ensamblador de entrada.
    // 中文：把既有认证状态映射为入站重组器所期待的数据包类型。
    private var currentInboundPhase: PTXP400BLEInboundPhase {
        if authenticated {
            return .vehicleStatus
        }

        switch authState {
        case .waitKeyId:
            return .keyConfiguration
        case .waitAuthMsg:
            return .authenticationResponse
        case .waitRandomNums:
            return .randomChallenge
        case .waitConnectionFrame:
            return .connectionFrame
        case .success:
            return .vehicleStatus
        }
    }

    // EN: Drain all complete logical packets from one or more BLE writes before waiting for more bytes.
    // ES: Vacía todos los paquetes lógicos completos de una o más escrituras BLE antes de esperar más bytes.
    // 中文：在等待更多字节前，排空一次或多次 BLE 写入中所有完整的逻辑数据包。
    private func receiveUARTData(_ data: Data) {
        inboundReassembler.append(data)

        while true {
            switch inboundReassembler.nextFrame(for: currentInboundPhase) {
            case .frame(let frame):
                handleIncoming(data: frame)
            case .dropped:
                PTOBDLogger.moto.ptLog("⚠️ [上行重组] 丢弃当前认证阶段无法匹配的数据，剩余缓存: \(inboundReassembler.bufferedByteCount) 字节")
            case .waiting:
                return
            }
        }
    }
    
    // MARK: - 身份验证状态机
    private func handleIncoming(data: Data) {
        if authenticated {
            PTOBDLogger.moto.ptLog("🔄 [DEBUG] 解析仪表盘数据包...")
            parseDashboardFrame(data)
            return
        }
        
        switch authState {
        case .waitKeyId:
            let bytes = [UInt8](data)
            guard data.count == PTXP400BLEProtocol.authenticationKeyConfigurationFrameLength, bytes.count >= 4 else {
                PTOBDLogger.moto.ptLog("⚠️ [握手干扰] Key/Configuration 帧长度无效: \(data.count)")
                return
            }

            let productId = (Int(bytes[0]) << 24) | (Int(bytes[1]) << 16) | (Int(bytes[2]) << 8) | Int(bytes[3])
            guard productId == Int(PTXP400BLEProtocol.authenticationKeyID) else {
                PTOBDLogger.moto.ptLog("⚠️ [握手干扰] 收到未知产品 Key ID")
                return
            }

            PTOBDLogger.moto.ptLog("✅ [握手 1/4] 收到 8758！下发挑战码...")
            let challenge = auth.createChallenge()
            var challengeData = Data()
            for num in challenge {
                var beNum = num.bigEndian
                challengeData.append(Data(bytes: &beNum, count: 2))
            }
            sendChunkedData(data: challengeData, to: txChar)
            authState = .waitAuthMsg
            
        case .waitAuthMsg:
            guard data.count == PTXP400BLEProtocol.authenticationChallengeLength else {
                PTOBDLogger.moto.ptLog("⚠️ [握手干扰] 认证响应长度无效: \(data.count)")
                return
            }

            if auth.checkAuthMsg(scooterResponse: data) {
                PTOBDLogger.moto.ptLog("✅ [握手 2/4] 车机答题正确！发送 KeyID，等待车机出题...")
                sendChunkedData(data: auth.getScooterKeyId(), to: txChar)
                
                // 🚨 核心修复：握手还没完，进入下半场！
                authState = .waitRandomNums
            } else {
                PTOBDLogger.moto.ptLog("❌ [错误] 密码本校验失败")
            }
            
        case .waitRandomNums:
            // 🚨 核心修复：这就是你抓到的 27b21814... (车机的考题)
            guard data.count == PTXP400BLEProtocol.authenticationChallengeLength else {
                PTOBDLogger.moto.ptLog("⚠️ [握手干扰] 期待 20 字节挑战码，实际收到: \(data.count) 字节")
                return
            }

            PTOBDLogger.moto.ptLog("✅ [握手 3/4] 收到车机挑战码！正在计算答案并回复...")
            var r = [UInt16](repeating: 0, count: 10)
            for i in 0..<10 {
                let start = i * 2
                let byte0 = UInt16(data[start])
                let byte1 = UInt16(data[start + 1])
                r[i] = (byte0 << 8) | byte1
            }

            // EN: Calculate the response without changing the established authentication algorithm.
            // ES: Calcula la respuesta sin cambiar el algoritmo de autenticación establecido.
            // 中文：在不改变既有认证算法的前提下计算响应。
            let authMsg = auth.createAuthenticationMessage(r: r)
            sendChunkedData(data: authMsg, to: txChar)

            // 答完题，等待车机的 0x16 确认信
            authState = .waitConnectionFrame
            
        case .waitConnectionFrame:
            // EN: Accept authentication only after the exact 15-byte connection identity frame is validated.
            // ES: Acepta la autenticación solo después de validar la trama de identidad de conexión exacta de 15 bytes.
            // 中文：只有严格校验 15 字节连接身份帧后，才接受认证完成。
            if PTXP400BLEProtocol.connectionSerial(in: data) != nil {
                PTOBDLogger.moto.ptLog("🎉 [握手 4/4] 互信认证全部打通！蓝灯长亮！解锁数据通道！")
                
                authState = .success
                authenticated = true
                PTMotoUserDefaultStruct.MotoLinkedAPP = true
                PTOBDLogger.moto.startFileLogging(prefix: "MotoHexLog", headerTitle: "PEUGEOT XP400GT RAW HEX LOG")
                // 必须在互信彻底完成后，再发钱解锁仪表盘！
                grantScooterCredits()
                
                delegates.forEach( { $0.delegate?.dashboardManager(self, didChangeConnectionState: true) })
                
                // 别浪费这第一包数据，立刻丢给仪表盘解析器
                parseDashboardFrame(data)
            } else {
                PTOBDLogger.moto.ptLog("⚠️ [握手干扰] 期待 0x16 确认帧，收到了其他数据")
            }
        case .success:
            break
        }

    }
    
    // MARK: - 发送逻辑 (队列保持不变)
    private func grantScooterCredits() {
        let refill = 25 - localCredits
        if refill <= 0 { return }
        localCredits += refill
        let data = Data([UInt8(refill)])
        sendChunkedData(data: data, to: txCreditsChar)
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        isSending = false
        pumpQueue()
    }

    private func sendChunkedData(data: Data, to characteristic: CBMutableCharacteristic, completion: (() -> Void)? = nil) {
        var offset = 0
        let hexString = data.map { String(format: "%02hhx", $0) }.joined()
        PTOBDLogger.moto.ptLog("⬆️ [发送包] 正在发射指令: \(hexString)")
        // 🚨 优化：向订阅了该特征的中心设备查询它所支持的最大长度，如果没有则安全降级回默认值 20
        // 对于 WriteWithoutResponse 或 Notify，使用 .withoutResponse 类型的 MTU
        let maxChunkSize = 20
                
        let totalChunks = Int(ceil(Double(data.count) / Double(maxChunkSize)))
        var currentChunk = 0

        while offset < data.count {
            let end = min(offset + maxChunkSize, data.count)
            currentChunk += 1
            let isLastChunk = (currentChunk == totalChunks)
            
            sendQueue.append(PTNotifyJob(
                data: data.subdata(in: offset..<end),
                characteristic: characteristic,
                completion: isLastChunk ? completion : nil
            ))
            offset = end
        }
        pumpQueue()
    }
    
    private func pumpQueue() {
        guard !isSending, !sendQueue.isEmpty else { return }
        let job = sendQueue[0]
        
        // 🚨 终极死锁破除器：如果当前没有车机订阅此通道，强制丢弃以防永久卡死
        if job.characteristic.uuid == UART_TX {
            // 如果余额不足，绝对不能发！挂起队列，等待车机通过 RX_CREDITS 补充令牌
            guard self.sendCredits > 0 else {
                return
            }
        }

        if !self.isTioSubscribed {
            let completedJob = sendQueue.removeFirst()
            if let callback = completedJob.completion {
                DispatchQueue.main.async { callback() }
            }
            DispatchQueue.main.async { self.pumpQueue() }
            return
        }
        
        // 下方代码保持你原来的逻辑不变
        let success = peripheralManager.updateValue(job.data, for: job.characteristic, onSubscribedCentrals: nil)
        
        if success {
            let completedJob = sendQueue.removeFirst()
            if completedJob.characteristic.uuid == UART_TX {
                self.sendCredits -= 1
            }

            if let callback = completedJob.completion {
                DispatchQueue.main.async { callback() }
            }
            DispatchQueue.main.async { self.pumpQueue() }
        } else {
            isSending = true
        }
    }
}

extension PTBluetoothServerManager {
    
    // MARK: - 发送导航与控制指令
    func sendCustomAlertToDashboard(title: String, message: String) {
        // 1. 创建一个唯一的 UID
        let alertUid = UInt32(Date().timeIntervalSince1970) % 100000
        
        let notif = PTAncsNotif(uid: alertUid, title: title, message: message, category: 1, appId: "com.ptools.moto")
        
        // 2. 生成“通知到达”帧
        let _ = PTFrameBuilder.buildAncsNotifSourceFrame(notif: notif)
        
        // 3. 将数据压入蓝牙发送队列 (假设你有一个特征值专门处理 ANCS 数据)
        // sendChunkedData(data: sourceFrame, to: ancsCharacteristic)
    }
    
    // 发送导航定位信息
    func sendNavigation(info: PTNavigationInfo) {
        guard authenticated else {
            PTOBDLogger.moto.ptLog( "⚠️ 尚未完成认证，无法发送导航数据")
            return
        }
        let frame = PTFrameBuilder.buildNavigationFrame(info: info)
        sendChunkedData(data: frame, to: txChar)
    }
    
    public func sendWelcomeMessage(next:String = "",title:String,nextManeuver:UInt8 = PTManeuverMap.depart) {
        guard authenticated else { return }

        // 伪造一个导航对象
        let welcomeInfo = PTNavigationInfo(
            nextManeuver: nextManeuver, // 使用“出发”图标
            metersToNextManeuver: 999,
            nameNextRoad: next, // 下一条路留空
            nameCurrentRoad: title, // 🚨 你的专属欢迎语，建议用全大写英文
            currentSpeedLimit: 99,
            distanceToDestination: 0,
            estimatedTimeToDestinationSec: 0
        )
        
        PTOBDLogger.moto.ptLog("🎉 [视觉交互] 正在向仪表盘推送欢迎信息: \(welcomeInfo.nameCurrentRoad)")
        // 复用你已有的导航发送方法
        self.sendNavigation(info: welcomeInfo)
    }

    // MARK: - 逆向工程：模糊测试 (Fuzzing) 通道
    
    /// 向机车发送任意 ID 和 Payload 的探测报文
    /// - Parameters:
    ///   - targetID: 目标指令 ID
    ///   - payloadBytes: 十六进制载荷数组
    public func sendFuzzTest(targetID: UInt8, payloadBytes: [UInt8] = [0x00]) {
        guard authenticated else {
            PTOBDLogger.moto.ptLog( "⚠️ 尚未完成认证，无法发送导航数据")
            return
        }
        let dataToWrite = PTFrameBuilder.buildFuzzFrame(idFrame: targetID, payload: payloadBytes)
        sendChunkedData(data: dataToWrite, to: txChar)
    }

    // 发送断开连接指令
    func sendDisconnect() {
        guard authenticated else { return }
        let frame = PTFrameBuilder.buildDisconnectFrame()
        sendChunkedData(data: frame, to: txChar)
    }
    
    func sendTCSMode(id:UInt8,mode: PTTCSMode) {
        guard authenticated else { return }
        let frame = PTFrameBuilder.buildTCSFrame(id: id, mode: mode)
        sendChunkedData(data: frame, to: txChar)
    }
    
    func sendLightMode(id:UInt8,mode: PTBacklightMode) {
        guard authenticated else { return }
        let frame = PTFrameBuilder.buildBacklightFrame(id: id, mode: mode)
        sendChunkedData(data: frame, to: txChar)
    }
    
    func sendConfiguration(color: PTConfigColor, unit: PTConfigUnit, language: PTConfigLanguage, completion: @escaping (Bool) -> Void) {
        // 🚨 安全解包：彻底根除在此处点击导致的强制解包闪退
        guard authenticated, let targetChar = txChar else {
            PTOBDLogger.moto.ptLog("⚠️ 尚未完成认证或 TX 通道未建立，拦截配置下发")
            completion(false)
            return
        }
        
        let frame = PTFrameBuilder.buildConfigurationFrame(
            color: color.rawValue,
            unit: unit.rawValue,
            language: language.rawValue
        )
        
        sendChunkedData(data: frame, to: targetChar) {
            PTOBDLogger.moto.ptLog("🎨 [配置下发] 指令已成功发射！")
            completion(true)
        }
    }
    
    /// 启动全频段主动查询扫描
    /// 向配置通道 (ID: 7) 发送轮询请求，试图触发车机回传隐藏的物理数据
    public func startActiveDiagnosticScan() {
        guard authenticated else {
            PTOBDLogger.moto.ptLog("⚠️ [查询拦截] 尚未完成认证，无法发送诊断探针。")
            return
        }
        
        PTOBDLogger.moto.ptLog("🚀 [深度探测] 开始发送 ISO-TP 增强版主动查询指令 (OBD/UDS 模式)...")
        currentProbeIndex = 0x00
        
        // 每 1.2 秒发送一次探针，给车机留出处理和回传的时间
        diagnosticTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 🚨 升级点：遵守 ISO-TP 传输层单帧格式 (Single Frame)
            // UDS 规范中，PID 通常是两字节的 (例如 0xF1 0x90)
            // 格式：[有效载荷长度, 服务ID, PID高位, PID低位]
            
            let udsLength: UInt8 = 0x03
            let serviceID: UInt8 = 0x22 // 读取数据服务 (Read Data By Identifier)
            let pidHighByte: UInt8 = 0x00 // 大多车辆标准 PID 从 0x0000 到 0xFFFF
            let pidLowByte: UInt8 = self.currentProbeIndex
            
            // 组合成标准 UDS 载荷
            let payload: [UInt8] = [udsLength, serviceID, pidHighByte, pidLowByte]
            let payloadData = Data(payload)
            
            // 复用你已有的常量 ID_CONFIGURATION (0x07) 作为诊断通道
            let targetID = PTFrameBuilder.ID_CONFIGURATION
            let frame = PTFrameBuilder.wrapTxFrame(idFrame: targetID, payload: payloadData)
            
            // 使用现有的分包发送方法将探针压入蓝牙通道
            self.sendChunkedData(data: frame, to: self.txChar) {
                let hexStr = payload.map { String(format: "%02X", $0) }.joined(separator: " ")
                PTOBDLogger.moto.ptLog("📡 [ISO-TP 探针发射] 通道 ID: 0x\(String(format: "%02X", targetID)), 载荷: [ \(hexStr) ]")
            }
            
            // 扫描结束条件
            if self.currentProbeIndex == 0xFF {
                self.stopActiveDiagnosticScan()
            } else {
                // 使用溢出运算符，防止边界崩溃
                self.currentProbeIndex &+= 1
            }
        }
    }
    
    /// 停止主动诊断扫描
    public func stopActiveDiagnosticScan() {
        diagnosticTimer?.invalidate()
        diagnosticTimer = nil
        PTOBDLogger.moto.ptLog("🛑 [深度探测] 主动查询扫描已手动结束或完成全频段覆盖。")
    }

    public func requestStaticConfiguration() {
        guard authenticated else {
            PTOBDLogger.moto.ptLog("⚠️ [查询拦截] 尚未完成认证，无法发送查询请求。")
            return
        }
        
        // 策略 1：针对已知的配置通道 (ID: 7)，发送 0x00 载荷，触发底层 Read 逻辑
        let readPayload = Data([0x00])
        
        // 利用你封装好的通用封包器
        let requestFrame = PTFrameBuilder.wrapTxFrame(idFrame: 7, payload: readPayload)
        
        sendChunkedData(data: requestFrame, to: txChar) {
            PTOBDLogger.moto.ptLog("📡 [主动查询] 已向配置通道发射探针，请紧盯回传日志...")
        }
    }

    // MARK: - 解析摩托车回传状态
    /// 解析摩托车仪表盘的实时状态帧
    func parseDashboardFrame(_ value: Data) {
        let hexString = value.map { String(format: "%02hhx", $0) }.joined()
        PTOBDLogger.moto.ptLog("📦 [原始包] 收到帧数据: \(hexString)")
        
        // 1. 校验最基本长度 (包头1字节 + ID 1字节 + 包尾1字节 = 至少3字节)
        guard value.count >= 3, value[0] == 0x16 else {
            PTOBDLogger.moto.ptLog("⚠️ [解析拦截] 包头不匹配或长度不足")
            return
        }
        
        // 2. 校验包尾 (安卓协议定义最后 1 字节必须是 0x00)
        guard value.last == 0x00 else {
            PTOBDLogger.moto.ptLog("⚠️ [解析拦截] 结尾不是 0x00")
            return
        }
        
        let id = value[1]
        
        // 3. 🚨 核心修复：摩托车的上行状态帧没有长度字段！
        // Payload 直接从索引 2 开始，到倒数第二个字节结束
        let payload = value.subdata(in: 2..<(value.count - 1))
        let bytes = [UInt8](payload)
        
        switch id {
        case 1:
            if let asciiString = String(bytes: bytes, encoding: .ascii) {
                dashboardConnectionIdentity = PTDashboardConnectionIdentity(
                    centralIdentifier: connectedCentral?.identifier,
                    reportedSerialNumber: asciiString
                )
                delegates.forEach {
                    $0.delegate?.dashboardManager(
                        self,
                        didUpdateConnectionIdentity: dashboardConnectionIdentity
                    )
                }
            }
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "[已知] ID:1 (心跳/连接) -> \(hexString)") })
            if let asciiString = String(bytes: bytes, encoding: .ascii) {
                PTOBDLogger.moto.ptLog("🔗 [状态] 车机报告连接正常 (CONNECTION) | 设备序列号: \(asciiString)")
            } else {
                PTOBDLogger.moto.ptLog("🔗 [状态] 车机报告连接正常 (CONNECTION)")
            }
        case 2: // DATA1
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "[已知] ID:2 (DATA1) -> \(hexString)") })
            guard bytes.count >= 8 else { return }
            
            let hiddenBits = "b[1]:\(bytes[1].binaryString)"
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "🔬 [未知] DATA1 隐藏位: \(hiddenBits)") })
            
            let fuelRaw = Double(bytes[0])
            let fuel = min(max(Int(round(fuelRaw * 0.3937)), 0), 100)
            let avg = Double(bytes[2]) * 0.1
            let tripRaw = (Int(bytes[3]) << 8) | Int(bytes[4])
            let odoRaw = (Int(bytes[5]) << 16) | (Int(bytes[6]) << 8) | Int(bytes[7])
            let data1 = PTDashboardData1(tripKm: Double(tripRaw) * 0.1, odoKm: Double(odoRaw) * 0.1, fuelLevelPct: fuel, avgConsumptionLt: avg)
            self.latestData1 = data1
            delegates.forEach( { $0.delegate?.dashboardManager(self, dashboardData: data1) })
            PTOBDLogger.moto.ptLog("📊 [DATA1] 油量: \(fuel)%, 消耗: \(avg)L, 总里程: \(Double(odoRaw) * 0.1)km")
            
        case 3: // DATA2
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "[已知] ID:3 (DATA2) -> \(hexString)") })
            guard bytes.count >= 6 else { return }
            
            // 🚨 深度嗅探：提取被忽略的 bytes[0], bytes[2]，以及如果存在的更靠后的字节
            var hiddenBits = "b[2]:\(bytes[2].binaryString)"
            if bytes.count >= 9 { // 根据你提供的数据，DATA2 实际有 9 个 payload 字节
                hiddenBits += " | b[6]:\(bytes[6].binaryString) | b[7]:\(bytes[7].binaryString) | b[8]:\(bytes[8].binaryString)"
            }
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "🔬 [未知] DATA2 隐藏位: \(hiddenBits)") })

            let engineRaw = Int(bytes[1])
            // 通过 rawValue 安全地转换为枚举对象，如果匹配失败则回退到 .unknown
            let backlightModeRaw = UInt8((engineRaw & 0xC0) >> 6)
            let currentBacklightMode = PTBacklightMode(rawValue: backlightModeRaw) ?? .unknown

            let batteryDisplayState = (engineRaw & 0x0C) >> 2
            // 提取最低 2 位获取引擎状态 (0:未启动, 1:启动中, 2:运转中, 3:关闭中)
            let engineStatus = engineRaw & 0x03

            let isKickstandDown = (engineRaw & 0x30) != 0
            
            let engineTempC = 0

            let engine = Int(bytes[1])
            let maint = Int(bytes[3])
            let temp = Int(bytes[4]) - 50
            let batt = Double(bytes[5]) * 0.1
            let data2 = PTDashboardData2(batteryVolt: batt, outsideTempC: temp, engineStatus: engineStatus, maintenance: maint,backlightMode: currentBacklightMode,engineTempC: engineTempC,isKickstandDown: isKickstandDown,batteryDisplayState:batteryDisplayState)
            self.latestData2 = data2
            delegates.forEach( { $0.delegate?.dashboardManager(self, dashboardData: data2) })
            PTOBDLogger.moto.ptLog("🔋 [DATA2] 引擎: \(PTDashboardLabels.engineStatusLabel(raw: engine)), 电压: \(batt)V")
            
        case 4: // DATA3
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "[已知] ID:4 (DATA3) -> \(hexString)") })
            guard bytes.count >= 6 else { return }
            if bytes.count >= 8 {
                let hiddenBits = "b[6]:\(bytes[6].binaryString) | b[7]:\(bytes[7].binaryString)"
                delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "🔬 [未知] DATA3 隐藏位: \(hiddenBits)") })
            }

            let autoRaw = (Int(bytes[0]) << 8) | Int(bytes[1])
            let col = Int(bytes[2])
            let dist = (Int(bytes[3]) << 8) | Int(bytes[4])
            let lang = Int(bytes[5])
            let data3 = PTDashboardData3(autonomyKm: Double(autoRaw) * 0.1, distToMaintenance: dist, colorMeasur: col, language: lang)
            self.latestData3 = data3
            delegates.forEach( { $0.delegate?.dashboardManager(self, dashboardData: data3) })
            PTOBDLogger.moto.ptLog("🛣️ [DATA3] 剩余续航: \(Double(autoRaw) * 0.1)km")
            
        case 5: // CONTROL
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "[已知] ID:5 (CONTROL) -> \(hexString)") })
            guard bytes.count >= 8 else { return }
                        
            let tcsRaw = bytes[3] & 0x0F // 提取低 4 位
            let isTcsSystemReady = (tcsRaw & 0b10000000) != 0 // 提取最高位作为系统就绪标志
            let currentTCS: PTTCSMode
            switch tcsRaw {
            case 0x02: currentTCS = .mode1
            case 0x04: currentTCS = .mode2
            case 0x00: currentTCS = .off
            default: currentTCS = .unknown
            }

            let byte1 = bytes[1]
            let isLeftTurnOn = (byte1 & 0b00010000) != 0
            let isRightTurnOn = (byte1 & 0b01000000) != 0

            let byte2 = bytes[2]
                        
            // 提取近光灯 (Bit 6)
            let isLowBeamOn = (byte2 & 0b01000000) != 0
            
            // 提取远光灯 (Bit 4)
            let isHighBeamOn = (byte2 & 0b00010000) != 0
            
            let isHazardAuxBitOn = (byte2 & 0b00000001) != 0
            let isHazardOn = isLeftTurnOn && isRightTurnOn && isHazardAuxBitOn

            let vehicleRaw = (Int(bytes[6]) << 8) | Int(bytes[7])
            let rearSpeed = Double(vehicleRaw) * 0.01

            self.currentRearSpeed = rearSpeed
            self.checkTCSIntervention()

            let engineRaw = (Int(bytes[4]) << 8) | Int(bytes[5])
            let control = PTDashboardControl(vehicleSpeedKmh: Double(vehicleRaw) * 0.01, engineRpm: Int(Double(engineRaw) * 0.25),tcsMode: currentTCS,isLowBeamOn: isLowBeamOn,isHighBeamOn: isHighBeamOn,isLeftTurnOn: isLeftTurnOn,isRightTurnOn: isRightTurnOn,isHazardOn: isHazardOn,isTcsSystemReady: isTcsSystemReady)
            self.latestControl = control
            delegates.forEach( { $0.delegate?.dashboardManager(self, dashboardData: control) })
            PTOBDLogger.moto.ptLog("🏍️ [CONTROL] 车速: \(Double(vehicleRaw) * 0.01) km/h, 转速: \(Int(Double(engineRaw) * 0.25)) rpm")
            
        case 6: // ABS
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "[已知] ID:6 (ABS) -> \(hexString)") })
            guard bytes.count >= 3 else { return }
            
            // 🚨 新挖掘：提取前轮独立车速 (Byte 0 和 Byte 1)
            let frontSpeedRaw = (Int(bytes[0]) << 8) | Int(bytes[1])
            let frontSpeed = Double(frontSpeedRaw) * 0.01
            
            // 更新本实例的前轮车速，并触发 TCS 打滑检测
            self.currentFrontSpeed = frontSpeed
            self.checkTCSIntervention()
                        
            let byte1 = bytes[1]
            // 如果结果为 0 (即 00000000)，说明灯是亮起的
            let isAbsLightOn = (byte1 & 0b00010000) == 0

            let absStatus = PTAbsStatus(absRaw: Int(bytes[2]),isAbsLightOn: isAbsLightOn,frontWheelSpeedKmh: frontSpeed)
            self.latestAbsStatus = absStatus
            delegates.forEach( { $0.delegate?.dashboardManager(self, dashboardData: absStatus) })
            PTOBDLogger.moto.ptLog("🛑 [ABS] 状态: \(PTDashboardLabels.absLabel(raw: Int(bytes[2])))")
            
        default:
            let binaryMatrix = bytes.map { $0.binaryString }.joined(separator: " | ")
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "⚠️ [深挖] 捕获未知 ID 0x\(String(format: "%02X", id)) -> 二进制: [ \(binaryMatrix) ]") })
            PTOBDLogger.moto.ptLog("❓ [未知数据] ID: 0x\(String(format: "%02X", id)) -> \(binaryMatrix)")
        }
    }
}

extension PTBluetoothServerManager {
    // MARK: - 深度逆向：自动化 Fuzz 扫描器
        
    /// 启动全频段自动化指令探测
    public func startAutomatedFuzzing() {
        guard authenticated else {
            PTOBDLogger.moto.ptLog("⚠️ 尚未完成认证，无法进行 Fuzz 扫描")
            return
        }
        let startString = "🚀 [自动化 Fuzz] 扫描任务已启动！请密切观察机车仪表盘反应..."
        PTOBDLogger.moto.ptLog(startString)
        delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: startString) })
        fuzzTimer?.invalidate()
        currentFuzzID = 0x00
        
        // 每 1.5 秒发送一次探测帧，给车机留出反应和回传数据的时间
        fuzzTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 🚨 跳过已知的指令 ID，防止干扰正常的仪表盘运作或导致重复断连
            let knownIDs: [UInt8] = [0x01,0x07,0x08]
            while knownIDs.contains(self.currentFuzzID) {
                // 使用溢出运算符 &+ 防止越界崩溃
                self.currentFuzzID = self.currentFuzzID &+ 1
            }
            
            // 扫描结束条件
            if self.currentFuzzID == 0xFF {
                let finishString = "🏁 [自动化 Fuzz] 全频段扫描完成！"
                PTOBDLogger.moto.ptLog(finishString)
                delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: finishString) })
                self.fuzzTimer?.invalidate()
                return
            }
            
            // 构造探测 Payload：
            // 很多工厂指令使用 0x00(查询), 0x01(开启), 或 0xFF(出厂重置) 作为标识
            let testPayload: [UInt8] = [0x02, 0x10, 0x03]
            let searchingString = "📡 [自动化 Fuzz] 正在探测 ID: 0x\(String(format: "%02X", self.currentFuzzID)) ..."
            PTOBDLogger.moto.ptLog(searchingString)
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: searchingString) })
            self.sendFuzzTest(targetID: self.currentFuzzID, payloadBytes: testPayload)
            
            self.currentFuzzID = self.currentFuzzID &+ 1
        }
    }
    
    /// 停止自动化探测
    public func stopAutomatedFuzzing() {
        fuzzTimer?.invalidate()
        fuzzTimer = nil
        let stopString = "🛑 [自动化 Fuzz] 扫描已手动终止。"
        PTOBDLogger.moto.ptLog(stopString)
        delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: stopString) })
    }
}

//MARK: Delegate
extension PTBluetoothServerManager {
    public func addDelegate(_ delegate: PTBLEDashboardDelegate) {
        cleanupDelegates()
        let isAlreadyAdded = delegates.contains { $0.delegate === delegate }
        if !isAlreadyAdded {
            delegates.append(WeakDelegateWrapper(delegate))
        }
    }
    
    private func cleanupDelegates() {
        delegates.removeAll { $0.delegate == nil }
    }
    
    public func removeDelegate(_ delegate: PTBLEDashboardDelegate) {
        delegates.removeAll { $0.delegate === delegate || $0.delegate == nil }
    }
}

extension PTBluetoothServerManager {
    
    // MARK: - 🎮 离线沙盒：仪表盘数据引擎 (Mock Dashboard Data Pump)
    
    /// 模拟机车的物理状态缓存
    private struct PTMockPhysicsState {
        static var timer: Timer?
        static var mockSpeed: Double = 0.0      // 模拟车速 (km/h)
        static var mockRPM: Double = 1200.0     // 模拟转速 (RPM)，默认怠速
        static var mockFuel: Double = 254.0     // 模拟油量原始值 (约等于 100%)
        static var isAccelerating = true        // 物理状态机：是否正在加速
    }
    
    /// 启动本地模拟数据泵 (完全脱离机车进行 UI 联调)
    func startMockDashboardData() {
        guard !authenticated else {
            PTOBDLogger.moto.ptLog("⚠️ 已连接真实设备，无法开启模拟器")
            return
        }
        
        PTOBDLogger.moto.ptLog("🎮 [模拟器] 正在启动仪表盘沙盒数据泵...")
        
        // 1. 强制击穿安全锁，伪造连接成功状态
        self.authenticated = true
        PTMotoUserDefaultStruct.MotoLinkedAPP = true
        self.delegates.forEach({ $0.delegate?.dashboardManager(self, didChangeConnectionState: true) })
        
        // 2. 启动 10Hz (0.1秒) 的高频数据泵，实现 UI 丝滑刷新
        PTMockPhysicsState.timer?.invalidate()
        PTMockPhysicsState.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // --- 动态物理状态更新 ---
            if PTMockPhysicsState.isAccelerating {
                PTMockPhysicsState.mockSpeed += 1.2
                PTMockPhysicsState.mockRPM += 120.0
                if PTMockPhysicsState.mockSpeed > 135.0 { PTMockPhysicsState.isAccelerating = false } // 极速 135km/h
            } else {
                PTMockPhysicsState.mockSpeed -= 1.8
                PTMockPhysicsState.mockRPM -= 180.0
                if PTMockPhysicsState.mockSpeed <= 0 {
                    PTMockPhysicsState.mockSpeed = 0
                    PTMockPhysicsState.mockRPM = 1200.0 // 恢复怠速
                    PTMockPhysicsState.isAccelerating = true
                }
            }
            // 油量缓慢减少
            PTMockPhysicsState.mockFuel = max(0, PTMockPhysicsState.mockFuel - 0.05)
            
            // --- 组装并投递全套报文 ---
            self.parseDashboardFrame(self.buildMockFrame(id: 2, payload: self.mockData1()))
            self.parseDashboardFrame(self.buildMockFrame(id: 3, payload: self.mockData2()))
            self.parseDashboardFrame(self.buildMockFrame(id: 4, payload: self.mockData3()))
            self.parseDashboardFrame(self.buildMockFrame(id: 5, payload: self.mockControl()))
            self.parseDashboardFrame(self.buildMockFrame(id: 6, payload: self.mockABS()))
        }
    }
    
    /// 停止模拟并恢复未连接状态
    func stopMockDashboardData() {
        PTMockPhysicsState.timer?.invalidate()
        PTMockPhysicsState.timer = nil
        self.authenticated = false
        self.delegates.forEach({ $0.delegate?.dashboardManager(self, didChangeConnectionState: false) })
        PTOBDLogger.moto.ptLog("🛑 [模拟器] 已停止沙盒引擎。")
    }
    
    // MARK: - 逆向组包工具
    
    /// 将十六进制数组封装为仪表盘期望的 [0x16, ID, Payload, 0x00] 格式
    private func buildMockFrame(id: UInt8, payload: [UInt8]) -> Data {
        var frame = Data()
        frame.append(0x16) // Preamble (包头)
        frame.append(id)   // ID
        frame.append(contentsOf: payload) // 载荷
        frame.append(0x00) // EOF (包尾)
        return frame
    }
    
    /// 伪造 DATA1 (油量、平均油耗、小计里程、总里程)
    private func mockData1() -> [UInt8] {
        let fuel = UInt8(PTMockPhysicsState.mockFuel) // 逆向公式: (254 * 0.3937) ≈ 100%
        let avg: UInt8 = 45 // 4.5 L/100km
        let trip: UInt16 = 1250 // 125.0 km
        let odo: UInt32 = 10 // 1.0 km
        
        return [
            fuel, 0x00, avg,
            UInt8((trip >> 8) & 0xFF), UInt8(trip & 0xFF),
            UInt8((odo >> 16) & 0xFF), UInt8((odo >> 8) & 0xFF), UInt8(odo & 0xFF)
        ]
    }
    
    /// 伪造 DATA2 (引擎状态、水温、电瓶电压)
    private func mockData2() -> [UInt8] {
        let engineStatus: UInt8 = 0x02 // 运转中 (0x02)
        let temp: UInt8 = 35 + 50 // 35°C (逆向公式: byte - 50)
        let batt: UInt8 = 142 // 14.2V (逆向公式: byte * 0.1)
        
        // 此帧要求至少 9 个字节以规避解析拦截
        return [0x00, engineStatus, 0x00, 0x00, temp, batt, 0x00, 0x00, 0x00]
    }
    
    /// 伪造 DATA3 (续航里程、仪表盘颜色/单位、保养距离、语言)
    private func mockData3() -> [UInt8] {
        let auto: UInt16 = 2500 // 250.0 km 剩余续航
        let col: UInt8 = 0x80 // Red (0x80) + 公制
        let dist: UInt16 = 1100 // 1100 km 距离保养
        let lang: UInt8 = 0x02 // 英文
        
        return [
            UInt8((auto >> 8) & 0xFF), UInt8(auto & 0xFF),
            col,
            UInt8((dist >> 8) & 0xFF), UInt8(dist & 0xFF),
            lang, 0x00, 0x00
        ]
    }
    
    /// 伪造 CONTROL (车速、转速、灯光、TCS状态)
    private func mockControl() -> [UInt8] {
        let speedRaw = UInt16(PTMockPhysicsState.mockSpeed / 0.01)
        let rpmRaw = UInt16(PTMockPhysicsState.mockRPM / 0.25)
        let tcsByte: UInt8 = 0x82 // mode1 (0x02) | ready (0x80)
        let lightByte: UInt8 = 0x40 // 近光灯开启 (0x40)
        
        return [
            0x00, 0x00, lightByte, tcsByte,
            UInt8((rpmRaw >> 8) & 0xFF), UInt8(rpmRaw & 0xFF),
            UInt8((speedRaw >> 8) & 0xFF), UInt8(speedRaw & 0xFF)
        ]
    }
    
    /// 伪造 ABS (前轮轮速、ABS灯光)
    private func mockABS() -> [UInt8] {
        let frontSpeedRaw = UInt16(PTMockPhysicsState.mockSpeed / 0.01)
        let absByte: UInt8 = 0x01 // ABS 状态正常
        
        return [
            UInt8((frontSpeedRaw >> 8) & 0xFF), UInt8(frontSpeedRaw & 0xFF),
            absByte
        ]
    }
}
