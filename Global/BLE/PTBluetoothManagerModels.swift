//
//  PTBluetoothManagerModels.swift
//  CrazyDashboard
//
//  EN: Keeps the shared XP400 protocol models and frame builders outside the compatibility facade.
//  ES: Mantiene los modelos compartidos y constructores de tramas del protocolo XP400 fuera de la fachada de compatibilidad.
//  中文：将 XP400 共享协议模型和帧构造器移出兼容门面。
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
// EN: Preserve the raw dashboard payload while making decoded-value validity explicit.
// ES: Conserva la carga útil sin procesar del tablero y hace explícita la validez del valor decodificado.
// 中文：保留仪表原始 Payload，同时明确标记解码值是否有效。
public enum PTDashboardValueAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable

    public var isAvailable: Bool {
        self == .available
    }
}

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

    // EN: Keep the complete payload and the availability of the two numeric control fields.
    // ES: Conserva la carga útil completa y la disponibilidad de los dos campos numéricos de control.
    // 中文：保留完整 Payload，并记录两个控制数值字段的可用性。
    let rawPayload: Data
    let vehicleSpeedAvailability: PTDashboardValueAvailability
    let engineRpmAvailability: PTDashboardValueAvailability

    init(
        vehicleSpeedKmh: Double,
        engineRpm: Int,
        tcsMode: PTTCSMode,
        isLowBeamOn: Bool,
        isHighBeamOn: Bool,
        isLeftTurnOn: Bool,
        isRightTurnOn: Bool,
        isHazardOn: Bool,
        isTcsSystemReady: Bool,
        rawPayload: Data = Data(),
        vehicleSpeedAvailability: PTDashboardValueAvailability = .available,
        engineRpmAvailability: PTDashboardValueAvailability = .available
    ) {
        self.vehicleSpeedKmh = vehicleSpeedKmh
        self.engineRpm = engineRpm
        self.tcsMode = tcsMode
        self.isLowBeamOn = isLowBeamOn
        self.isHighBeamOn = isHighBeamOn
        self.isLeftTurnOn = isLeftTurnOn
        self.isRightTurnOn = isRightTurnOn
        self.isHazardOn = isHazardOn
        self.isTcsSystemReady = isTcsSystemReady
        self.rawPayload = rawPayload
        self.vehicleSpeedAvailability = vehicleSpeedAvailability
        self.engineRpmAvailability = engineRpmAvailability
    }
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

    // EN: Keep the original eight-byte payload and field-level availability flags.
    // ES: Conserva la carga útil original de ocho bytes y las banderas de disponibilidad por campo.
    // 中文：保留原始八字节 Payload，并记录每个字段的可用性。
    let rawPayload: Data
    let fuelLevelAvailability: PTDashboardValueAvailability
    let averageConsumptionAvailability: PTDashboardValueAvailability
    let tripAvailability: PTDashboardValueAvailability
    let odometerAvailability: PTDashboardValueAvailability

    init(
        tripKm: Double,
        odoKm: Double,
        fuelLevelPct: Int,
        avgConsumptionLt: Double,
        rawPayload: Data = Data(),
        fuelLevelAvailability: PTDashboardValueAvailability = .available,
        averageConsumptionAvailability: PTDashboardValueAvailability = .available,
        tripAvailability: PTDashboardValueAvailability = .available,
        odometerAvailability: PTDashboardValueAvailability = .available
    ) {
        self.tripKm = tripKm
        self.odoKm = odoKm
        self.fuelLevelPct = fuelLevelPct
        self.avgConsumptionLt = avgConsumptionLt
        self.rawPayload = rawPayload
        self.fuelLevelAvailability = fuelLevelAvailability
        self.averageConsumptionAvailability = averageConsumptionAvailability
        self.tripAvailability = tripAvailability
        self.odometerAvailability = odometerAvailability
    }
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

    // EN: Keep source bytes and distinguish unavailable engine, maintenance, temperature, and battery values.
    // ES: Conserva los bytes de origen y distingue los valores no disponibles del motor, mantenimiento, temperatura y batería.
    // 中文：保留源字节，并区分发动机、保养、温度和电瓶字段的不可用状态。
    let rawPayload: Data
    let engineAvailability: PTDashboardValueAvailability
    let maintenanceAvailability: PTDashboardValueAvailability
    let outsideTemperatureAvailability: PTDashboardValueAvailability
    let batteryAvailability: PTDashboardValueAvailability

    init(
        batteryVolt: Double,
        outsideTempC: Int,
        engineStatus: Int,
        maintenance: Int,
        backlightMode: PTBacklightMode,
        engineTempC: Int,
        isKickstandDown: Bool,
        batteryDisplayState: Int,
        rawPayload: Data = Data(),
        engineAvailability: PTDashboardValueAvailability = .available,
        maintenanceAvailability: PTDashboardValueAvailability = .available,
        outsideTemperatureAvailability: PTDashboardValueAvailability = .available,
        batteryAvailability: PTDashboardValueAvailability = .available
    ) {
        self.batteryVolt = batteryVolt
        self.outsideTempC = outsideTempC
        self.engineStatus = engineStatus
        self.maintenance = maintenance
        self.backlightMode = backlightMode
        self.engineTempC = engineTempC
        self.isKickstandDown = isKickstandDown
        self.batteryDisplayState = batteryDisplayState
        self.rawPayload = rawPayload
        self.engineAvailability = engineAvailability
        self.maintenanceAvailability = maintenanceAvailability
        self.outsideTemperatureAvailability = outsideTemperatureAvailability
        self.batteryAvailability = batteryAvailability
    }
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

    // EN: Preserve Data3 bytes and expose validity for range, maintenance, configuration, and language.
    // ES: Conserva los bytes de Data3 y expone la validez de autonomía, mantenimiento, configuración e idioma.
    // 中文：保留 Data3 原始字节，并公开续航、保养、配置和语言的有效性。
    let rawPayload: Data
    let autonomyAvailability: PTDashboardValueAvailability
    let maintenanceDistanceAvailability: PTDashboardValueAvailability
    let configurationAvailability: PTDashboardValueAvailability
    let languageAvailability: PTDashboardValueAvailability

    init(
        autonomyKm: Double,
        distToMaintenance: Int,
        colorMeasur: Int,
        language: Int,
        rawPayload: Data = Data(),
        autonomyAvailability: PTDashboardValueAvailability = .available,
        maintenanceDistanceAvailability: PTDashboardValueAvailability = .available,
        configurationAvailability: PTDashboardValueAvailability = .available,
        languageAvailability: PTDashboardValueAvailability = .available
    ) {
        self.autonomyKm = autonomyKm
        self.distToMaintenance = distToMaintenance
        self.colorMeasur = colorMeasur
        self.language = language
        self.rawPayload = rawPayload
        self.autonomyAvailability = autonomyAvailability
        self.maintenanceDistanceAvailability = maintenanceDistanceAvailability
        self.configurationAvailability = configurationAvailability
        self.languageAvailability = languageAvailability
    }

    /// [新增] 解析出的里程表单位制：true 为公制(公里/Km)，false 为英制(英里/Mil)
    var isMetric: Bool {
        guard configurationAvailability.isAvailable else { return true }
        // 如果包含 0x08 标志位，则是英里，否则是公里
        return (colorMeasur & 0x08) == 0
    }
    
    /// [新增] 直接获取用于 UI 展示的单位字符串 ("Km" 或 "Mil")
    var unitString: String {
        guard configurationAvailability.isAvailable else { return "-" }
        return PTDashboardLabels.unitLabel(c: colorMeasur)
    }
    
    var unitType: PTConfigUnit {
        // EN: An unavailable configuration must fall back to the documented metric default.
        // ES: Una configuración no disponible debe volver al valor métrico predeterminado documentado.
        // 中文：配置不可用时必须回退到协议约定的公制默认值。
        guard configurationAvailability.isAvailable else { return .metric }
        return (colorMeasur & 0x08) != 0 ? .imperial : .metric
    }
    
    var languageType: PTConfigLanguage {
        // EN: Do not decode an unavailable language byte as English by accident.
        // ES: No decodifiques por accidente un byte de idioma no disponible como inglés.
        // 中文：语言字节不可用时，不要误解码成英语。
        guard languageAvailability.isAvailable else { return .english }
        // 1. 将 Int 转换为 UInt8
        let decodedCode = UInt8((language >> 1) & 0x0F)
        // 2. 尝试用 rawValue 初始化枚举。
        // 如果匹配失败（例如传来一个未知的数字 9），则触发 ?? 后面的安全回退机制，默认返回英语。
        return PTConfigLanguage(rawValue: decodedCode) ?? .english
    }
    
    var dashboardColor: PTConfigColor {
        // EN: An unavailable color/configuration byte must not select a color from sentinel bits.
        // ES: Un byte de color/configuración no disponible no debe seleccionar un color desde bits centinela.
        // 中文：颜色/配置字节不可用时，不能从哨兵位中推导颜色。
        guard configurationAvailability.isAvailable else { return .blue }
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

    // EN: Keep the ABS payload and distinguish unavailable wheel speed from a real zero speed.
    // ES: Conserva la carga útil ABS y distingue la velocidad de rueda no disponible de una velocidad real de cero.
    // 中文：保留 ABS Payload，并区分轮速不可用与真实零速。
    let rawPayload: Data
    let frontWheelSpeedAvailability: PTDashboardValueAvailability
    let statusAvailability: PTDashboardValueAvailability

    init(
        absRaw: Int,
        isAbsLightOn: Bool,
        frontWheelSpeedKmh: Double,
        rawPayload: Data = Data(),
        frontWheelSpeedAvailability: PTDashboardValueAvailability = .available,
        statusAvailability: PTDashboardValueAvailability = .available
    ) {
        self.absRaw = absRaw
        self.isAbsLightOn = isAbsLightOn
        self.frontWheelSpeedKmh = frontWheelSpeedKmh
        self.rawPayload = rawPayload
        self.frontWheelSpeedAvailability = frontWheelSpeedAvailability
        self.statusAvailability = statusAvailability
    }
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
        // EN: Validate the complete 20-byte envelope before comparing the ten authenticated bytes.
        // ES: Valida la envoltura completa de 20 bytes antes de comparar los diez bytes autenticados.
        // 中文：先校验完整 20 字节包络，再比较参与认证的十个字节。
        guard PTXP400BLEProtocol.isValidAuthenticationChallenge(scooterResponse) else { return false }
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
    // EN: Keep frame constants tied to the tested XP400 protocol contract.
    // ES: Mantén las constantes de trama vinculadas al contrato de protocolo probado del XP400.
    // 中文：让帧常量统一绑定到已经测试的 XP400 协议契约。
    static let PREAMBLE: UInt8 = PTXP400BLEProtocol.preamble
    static let END_OF_FRAME: UInt8 = PTXP400BLEProtocol.terminator

    static let ID_NAVIGATION: UInt8 = PTXP400BLEProtocol.navigationFrameID
    static let ID_CONFIGURATION: UInt8 = PTXP400BLEProtocol.configurationFrameID
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
    // EN: Report observed CoreBluetooth lifecycle facts without owning the reducer here.
    // ES: Informa hechos observados de CoreBluetooth sin poseer aquí el reductor.
    // 中文：上报 CoreBluetooth 实际观察到的生命周期事实，但不在此处持有状态归约器。
    func dashboardManager(_ manager: PTBluetoothServerManager, didObserveLifecycleEvent event: PTXP400BLELifecycleEvent)
    func dashboardManager(
        _ manager: PTBluetoothServerManager,
        didUpdateConnectionIdentity identity: PTDashboardConnectionIdentity?
    )
}

extension PTBLEDashboardDelegate {
    func dashboardManager(_ manager: PTBluetoothServerManager, didChangeConnectionState isConnected: Bool) {}
    func dashboardManager(_ manager: PTBluetoothServerManager, dashboardData data: Any?) {}
    func dashboardManager(_ manager: PTBluetoothServerManager, unknownData data: String) {}
    func dashboardManager(_ manager: PTBluetoothServerManager, didObserveLifecycleEvent event: PTXP400BLELifecycleEvent) {}
    func dashboardManager(
        _ manager: PTBluetoothServerManager,
        didUpdateConnectionIdentity identity: PTDashboardConnectionIdentity?
    ) {}
}

