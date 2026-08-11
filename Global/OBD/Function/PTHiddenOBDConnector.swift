//
//  PTHiddenOBDConnector.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 8/8/2026.
//

import Foundation
import CoreBluetooth
import PooTools
import CryptoKit
import Combine

public extension OBDCommand {
    
    /// 返回该指令在公制标准下对应的物理单位字符串
    var unitString: String {
        switch self {
        case .general(let generalCommand):
            // 特殊处理我们自定义的电压探针
            if generalCommand == .ATRV { return "V" }
            return ""
            
        case .mode1(let mode1Command):
            switch mode1Command {
            // 速度与转速类
            case .rpm: return "RPM"
            case .speed: return "km/h"
            
            // 温度类 (摄氏度)
            case .coolantTemp, .intakeTemp, .ambientAirTemp, .engineOilTemp, .catalystTempB1S1, .catalystTempB2S1, .catalystTempB1S2, .catalystTempB2S2:
                return "℃"
                
            // 压力类 (千帕)
            case .intakePressure, .barometricPressure, .evapVaporPressure, .evapVaporPressureAbs, .evapVaporPressureAlt, .fuelPressure, .fuelRailPressureVac, .fuelRailPressureDirect, .fuelRailPressureAbs:
                return "kPa"
                
            // 百分比类 (负载、节气门、油量、燃油修正等)
            case .engineLoad, .throttlePos, .relativeThrottlePos, .absoluteLoad, .throttleActuator, .throttlePosB, .throttlePosC, .throttlePosD, .throttlePosE, .throttlePosF: return "%"
            case .fuelLevel, .hybridBatteryLife, .relativeAccelPos: return "%"
            case .shortFuelTrim1, .longFuelTrim1, .shortFuelTrim2, .longFuelTrim2, .EGRError, .commandedEGR, .evaporativePurge, .shortO2TrimB1, .longO2TrimB1, .shortO2TrimB2, .longO2TrimB2: return "%"
                
            // 电压与电流类
            case .controlModuleVoltage: return "V"
            case .O2Bank1Sensor1, .O2Bank1Sensor2, .O2Bank1Sensor3, .O2Bank1Sensor4, .O2Bank2Sensor1, .O2Bank2Sensor2, .O2Bank2Sensor3, .O2Bank2Sensor4: return "V"
            case .O2Sensor1WRVolatage, .O2Sensor2WRVolatage, .O2Sensor3WRVolatage, .O2Sensor4WRVolatage, .O2Sensor5WRVolatage, .O2Sensor6WRVolatage, .O2Sensor7WRVolatage, .O2Sensor8WRVolatage: return "V"
            case .O2Sensor1WRCurrent, .O2Sensor2WRCurrent, .O2Sensor3WRCurrent, .O2Sensor4WRCurrent, .O2Sensor5WRCurrent, .O2Sensor6WRCurrent, .O2Sensor7WRCurrent, .O2Sensor8WRCurrent: return "mA"
                
            // 流量与时间类
            case .maf: return "g/s"       // 空气质量流量
            case .fuelRate: return "L/h"  // 燃油消耗率
            case .timingAdvance: return "°" // 点火提前角
            case .runTime, .timeSinceDTCCleared, .runTimeMIL: return "s" // 运行时间 (秒)
            case .distanceWMIL, .distanceSinceDTCCleared: return "km" // 行驶距离
                
            // 计数器类
            case .warmUpsSinceDTCCleared: return "times"
                
            // 其他没有明确数值单位的状态类
            default: return ""
            }
            
        // 如果你需要支持 Mode 6 化验单，由于单位是靠 UASI 动态解析的，此处返回空即可
        case .mode6(_):
            return ""
            
        default:
            return ""
        }
    }
}

// MARK: - 🌟 Mode 6 “化验单”数据模型
public struct PTMode6Data {
    public let mid: String      // 监控部件 ID (如 01)
    public let tid: String      // 测试项目 ID (如 81)
    public let uasi: String     // 🌟 核心：UASI (单位和缩放 ID)，决定了用什么公式计算！
    public let rawValue: Int    // 原始测试值
    public let rawMinValue: Int // 原始及格下限
    public let rawMaxValue: Int // 原始及格上限
    
    // 名称映射：完美复用 SwiftOBD2 的描述！
    public var componentName: String {
        // 拼接 "06" + "01" = "0601"
        let commandString = "06" + mid
        if let obdCommand = OBDCommand.from(command: commandString) {
            return obdCommand.properties.description // 返回如 "O2 Sensor Monitor Bank 1 - Sensor 1"
        }
        return "Unknown Monitor (MID: \(mid))"
    }
    
    // 智能判断该部件是否健康
    public var isPassed: Bool {
        // 在汽车标准中，0000 或 FFFF 通常代表该限制未被使用
        let maxCheck = (rawMaxValue == 0 || rawMaxValue == 65535) ? true : (rawValue <= rawMaxValue)
        let minCheck = (rawMinValue == 0) ? true : (rawValue >= rawMinValue)
        return minCheck && maxCheck
    }
    
    // 智能单位换算：利用 UASI 字节，将原始值转化为人类可读的物理单位
    public var formattedValue: String { return decodeUASI(value: rawValue) }
    public var formattedMin: String   { return decodeUASI(value: rawMinValue) }
    public var formattedMax: String   { return decodeUASI(value: rawMaxValue) }
    
    // MARK: - 内部 UASI 工业标准解码引擎 (部分常用标准 J1979-DA 映射)
    private func decodeUASI(value: Int) -> String {
        // 对于未使用的极限值，显示 N/A
        if value == 0 || value == 65535 { return "N/A" }
        
        let doubleVal = Double(value)
        
        // 解析 UASI 字节
        switch uasi {
        case "01":
            return String(format: "%.0f Counts", doubleVal) // 计数器
        case "04":
            return String(format: "%.0f ms", doubleVal) // 时间 (毫秒)
        case "08", "19", "1B":
            return String(format: "%.3f V", doubleVal * 0.001) // 传感器电压 (1 bit = 1 mV)
        case "0A":
            return String(format: "%.3f A", doubleVal * 0.001) // 电流 (1 bit = 1 mA)
        case "0B", "1E":
            return String(format: "%.0f ℃", doubleVal * 0.1) // 温度 (需结合具体 PID 偏移，这里演示近似)
        case "0F":
            return String(format: "%.1f kPa", doubleVal * 0.1) // 压力 (1 bit = 0.1 kPa)
        case "11":
            return String(format: "%.1f g/s", doubleVal * 0.01) // 质量流量
        case "1D":
            return String(format: "%.2f %%", doubleVal * 0.0015259) // 占空比/百分比
        default:
            // 兜底方案：如果遇到不认识的 UASI，直接显示原始十六进制
            return String(format: "Raw: %04X", value)
        }
    }
}

extension PROTOCOL {
    static func from(string: String) -> PROTOCOL {
        let upper = string.uppercased()
        if upper.contains("15765-4") && upper.contains("11/500") { return .protocol6 }
        if upper.contains("15765-4") && upper.contains("29/500") { return .protocol7 }
        if upper.contains("15765-4") && upper.contains("11/250") { return .protocol8 }
        if upper.contains("15765-4") && upper.contains("29/250") { return .protocol9 }
        if upper.contains("14230-4") && upper.contains("FAST") { return .protocol5 }
        if upper.contains("14230-4") { return .protocol4 }
        if upper.contains("9141-2") { return .protocol3 }
        if upper.contains("J1850 VPW") { return .protocol2 }
        if upper.contains("J1850 PWM") { return .protocol1 }
        if upper.contains("J1939") { return .protocolA }
        return .NONE
    }
}

public class PTATVersionModel:NSObject {
    var company:String = ""
    var version:String = ""
    var deviceType:String = ""
    var deviceName:String = ""
    var deviceMac:String = ""
    var interfase:String = ""
    var cust:String = ""
    var crypt:String = ""
}

public class PTOBDInfo:NSObject {
    var atzName:String = ""
    var moudleInfo:PTATVersionModel = PTATVersionModel()
    var aitName:String = ""
    var atdpName:PROTOCOL = .NONE
    var vin:String = ""
    var ecuVersion:String = ""
    var cvn:String = ""
    var supportCommand:[OBDCommand] = []
}

public class PTMultiFrameParser {
    /// 剥离 CAN 报头，提取纯正的 ASCII 字符串
    public static func parseLongString(response: String) -> String {
        let lines = response.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && $0 != ">" }
        
        var hexPayload = ""
        for line in lines {
            let cleanLine = line.filter { "0123456789ABCDEF".contains($0) }
            guard cleanLine.count > 4 else { continue }
            
            // 提取 CAN 帧类型 (如 7E8，第 4 位是帧类型)
            let frameTypeIndex = cleanLine.index(cleanLine.startIndex, offsetBy: 3)
            let frameType = cleanLine[frameTypeIndex]
            
            if frameType == "1" {
                if cleanLine.count > 13 { hexPayload += cleanLine[cleanLine.index(cleanLine.startIndex, offsetBy: 13)...] }
            } else if frameType == "2" {
                if cleanLine.count > 5 { hexPayload += cleanLine[cleanLine.index(cleanLine.startIndex, offsetBy: 5)...] }
            } else if frameType == "0" {
                if cleanLine.count > 11 { hexPayload += cleanLine[cleanLine.index(cleanLine.startIndex, offsetBy: 11)...] }
            }
        }
        
        var asciiStr = ""
        var i = hexPayload.startIndex
        while i < hexPayload.endIndex {
            let nextI = hexPayload.index(i, offsetBy: 2, limitedBy: hexPayload.endIndex) ?? hexPayload.endIndex
            if let byteVal = UInt8(hexPayload[i..<nextI], radix: 16), byteVal >= 32 && byteVal <= 126 {
                asciiStr.append(Character(UnicodeScalar(byteVal)))
            }
            i = nextI
        }
        return asciiStr.trimmingCharacters(in: .whitespaces)
    }
    
    /// 🌟 提取纯净十六进制数据：专门用于剥离 CAN 报头 (如 7E81, 7E82)，提取纯粹的数据载荷。
    public static func extractPureHexPayload(response: String) -> String {
        let lines = response.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && $0 != ">" }
        
        var hexPayload = ""
        for line in lines {
            let cleanLine = line.filter { "0123456789ABCDEF".contains($0) }
            guard cleanLine.count > 4 else { continue }
            
            // 提取 CAN 帧类型
            let frameTypeIndex = cleanLine.index(cleanLine.startIndex, offsetBy: 3)
            let frameType = cleanLine[frameTypeIndex]
            
            if frameType == "1" {
                // 首帧：跳过 7 个字符 (例如 7E8 1 023)
                if cleanLine.count > 7 { hexPayload += cleanLine[cleanLine.index(cleanLine.startIndex, offsetBy: 7)...] }
            } else if frameType == "2" {
                // 连续帧：跳过 5 个字符 (例如 7E8 2 1)
                if cleanLine.count > 5 { hexPayload += cleanLine[cleanLine.index(cleanLine.startIndex, offsetBy: 5)...] }
            } else if frameType == "0" {
                // 单帧：跳过 5 个字符 (例如 7E8 0 4)
                if cleanLine.count > 5 { hexPayload += cleanLine[cleanLine.index(cleanLine.startIndex, offsetBy: 5)...] }
            } else {
                 // 兼容非 CAN 协议的回传，直接拼接 (如直接返回 43 开头的数据)
                 if cleanLine.hasPrefix("43") || cleanLine.hasPrefix("44") {
                     hexPayload += cleanLine
                 }
            }
        }
        return hexPayload
    }

    /// 🌟 DTC 破译器：将 4 位十六进制解析为标准汽车 DTC 故障码 (如 0104 -> P0104)
    public static func decodeSingleDTC(_ hex: String) -> String? {
        guard hex.count == 4 else { return nil }
        let firstChar = hex[hex.startIndex]
        
        // 汽车工业标准 DTC 映射表
        let prefixMap: [Character: String] = [
            "0": "P0", "1": "P1", "2": "P2", "3": "P3", // P = Powertrain 动力系统
            "4": "C0", "5": "C1", "6": "C2", "7": "C3", // C = Chassis 底盘系统
            "8": "B0", "9": "B1", "A": "B2", "B": "B3", // B = Body 车身系统
            "C": "U0", "D": "U1", "E": "U2", "F": "U3"  // U = Network 网络通讯系统
        ]
        
        guard let prefix = prefixMap[firstChar] else { return nil }
        let suffix = String(hex.dropFirst())
        return prefix + suffix
    }
    
    /// 🌟 新增：专门破译 Mode 6 复杂测试结果的方法
    public static func parseMode6TestResults(pureHex: String) -> [PTMode6Data] {
        guard pureHex.hasPrefix("46") else { return [] }
        var results: [PTMode6Data] = []
        let dataStr = String(pureHex.dropFirst(2))
        
        // CAN 总线格式： [MID:2位] [TID:2位] [UASI:2位] [Value:4位] [Min:4位] [Max:4位] = 共 18 字符
        var i = dataStr.startIndex
        while i < dataStr.endIndex {
            let nextI = dataStr.index(i, offsetBy: 18, limitedBy: dataStr.endIndex) ?? dataStr.endIndex
            
            if dataStr.distance(from: i, to: nextI) == 18 {
                let chunk = String(dataStr[i..<nextI])
                
                let midHex  = String(chunk.prefix(2))
                let tidHex  = String(chunk.dropFirst(2).prefix(2))
                let uasiHex = String(chunk.dropFirst(4).prefix(2)) // 🌟 提取出关键的 UASI 字节！
                let valHex  = String(chunk.dropFirst(6).prefix(4))
                let minHex  = String(chunk.dropFirst(10).prefix(4))
                let maxHex  = String(chunk.dropFirst(14).prefix(4))
                
                if let val = Int(valHex, radix: 16),
                   let min = Int(minHex, radix: 16),
                   let max = Int(maxHex, radix: 16) {
                    
                    let testResult = PTMode6Data(
                        mid: midHex,
                        tid: tidHex,
                        uasi: uasiHex, // 注入 UASI
                        rawValue: val,
                        rawMinValue: min,
                        rawMaxValue: max
                    )
                    results.append(testResult)
                    
                    let status = testResult.isPassed ? "✅" : "❌"
                    // 打印看看这炫酷的转换结果！
                    PTOBDLogger.shared.ptLog("🔬 [\(testResult.componentName)] TID:\(tidHex) | 结果:\(testResult.formattedValue) (范围:\(testResult.formattedMin) ~ \(testResult.formattedMax)) | \(status)")
                }
            }
            i = nextI
        }
        return results
    }
}

let developerOBDID = "C688934C-8A62-4C35-872F-B07ED5415E94"

// MARK: - 🌟 全局底层 OBD 日志追踪引擎
public class PTOBDLogger {
    public static let shared = PTOBDLogger()
    
    private var logFileHandle: FileHandle?
    public private(set) var currentLogFileURL: URL?
    public private(set) var logHistory: [String] = []
    
    public var onLogUpdated: ((String) -> Void)?
    
    private let ioQueue = DispatchQueue(label: "com.ptools.OBDLogIOQueue", qos: .utility)
    
    private lazy var dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
    
    public func startFileLogging() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "MotoOBDLog_\(formatter.string(from: Date())).txt"
        
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = docsDir.appendingPathComponent(fileName)
        currentLogFileURL = fileURL
        
        FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        
        do {
            logFileHandle = try FileHandle(forWritingTo: fileURL)
            let header = "=== PEUGEOT XP400GT OBD TRACE LOG ===\n=== SESSION START: \(Date()) ===\n\n"
            if let data = header.data(using: .utf8) {
                try logFileHandle?.seekToEnd()
                try logFileHandle?.write(contentsOf: data)
            }
            PTNSLogConsole("📝 [日志系统] 已开启全链路底层写入: \(fileName)")
        } catch {}
    }
    
    public func stopFileLogging() {
        guard logFileHandle != nil else { return }
        let footer = "\n=== SESSION END: \(Date()) ===\n"
        if let data = footer.data(using: .utf8) {
            try? logFileHandle?.seekToEnd()
            try? logFileHandle?.write(contentsOf: data)
        }
        try? logFileHandle?.close()
        logFileHandle = nil
        PTNSLogConsole("💾 [日志系统] 蓝牙会话结束，十六进制日志已安全封装。")
    }
    
    public func ptLog(_ message: String) {
        let timeString = dateFormatter.string(from: Date())
        let formattedLog = "[\(timeString)] \(message)"
        
        PTNSLogConsole(formattedLog)
        
        ioQueue.async { [weak self] in
            guard let self = self, let handle = self.logFileHandle else { return }
            if let data = (formattedLog + "\n").data(using: .utf8) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
        
        DispatchQueue.main.async {
            self.logHistory.append(formattedLog)
            if self.logHistory.count > 1000 { self.logHistory.removeFirst() }
            self.onLogUpdated?(formattedLog)
        }
    }
}

public struct YmobdCrypt {
    public static let defaultKey: Int32 = 0x263D9A7E

    public static func crypt32(input: Int32, key: Int32 = defaultKey) -> Int32 {
        let b0 = input & 0xFF
        let b1 = (input >> 8) & 0xFF
        let b2 = (input >> 16) & 0xFF
        let b3 = (input >> 24) & 0xFF

        let r = (b2 >> (b0 / 50)) | ((b1 << 2) ^ (key << (b3 / 12)))
        let d = (b0 >> (b1 / 63)) | ((key << (b3 / 11)) ^ (b2 >> 1))
        let l = (b0 >> (b1 / 46)) | ((key << (b0 / 34)) ^ b3)
        let m = (b1 << (b3 / 35)) | ((key << (b0 / 49)) & (key >> 18))

        let part1 = (m << 24) & Int32(bitPattern: 0xFF000000)
        let part2 = (l << 16) & 0x00FF0000
        let part3 = (d << 8) & 0x0000FF00
        let part4 = r & 0x000000FF

        return part1 | part2 | part3 | part4
    }

    public static func hex8(value: Int32) -> String {
        let uValue = UInt32(bitPattern: value)
        return String(format: "%08X", uValue)
    }

    public static func newChallenge() -> Int32 {
        return Int32.random(in: 0x12345678...0x7FFFFFFE)
    }
    
    public static func setCryptCommand(cryptFromVersion: String) -> String {
        let safeInput = cryptFromVersion.filter { "0123456789abcdefABCDEF".contains($0) }
        guard let uInput = UInt32(safeInput, radix: 16) else { return "" }
        let input = Int32(bitPattern: uInput)
        let encrypted = crypt32(input: input)
        return "AT+SETCRYPT\(hex8(value: encrypted))\r"
    }
    
    public static func challengeCommand(challenge: Int32) -> String {
        return "AT+CRYPT\(hex8(value: challenge))\r"
    }
}

public class PTHiddenOBDConnector: NSObject {
    public static let shared = PTHiddenOBDConnector()
    
    public var onIceBroken: (() -> Void)?
    public var onStandardDeviceDetected: ((CBPeripheral) -> Void)?
    
    private var centralManager: CBCentralManager!
    public var obdPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    
    private var isUnlocked: Bool = false
    private var pendingConnection: Bool = false
    
    // 严丝合缝的 19 步解锁列队[cite: 4]
    private var initQueue: [String] = [
        "ATZ", "ATE0", "ATL0", "ATH1", "ATSP0", "AT+VERSION", "ATI", "ATRV", "<AUTH>",
        "0100", "020000", "0600", "0900", "ATDP", "0120", "0140", "0902", "0904", "0906"
    ]
    private var currentQueueIndex: Int = 0
    private var activeCommand: String? = nil
    private var rxBuffer: String = ""
    
    public var collectedPIDResponses: [String] = []
    private var debugFlagSent = false
    
    private var responseContinuation: CheckedContinuation<String, any Error>?
    private var timeoutTask: Task<Void, Never>?
    
    private let allowedDeviceNames: Set<String> = [
        "OBDII", "MS310", "B25", "V500", "YM529", "YM329", "YM129",
        "YM819", "BT529", "OBD114", "OBD147", "BROM S10", "BROM S15", "BROM S20"
    ]
    
    private let targetDeviceUUIDString = PTMotoUserDefaultStruct.OBDID.isEmpty ? developerOBDID : PTMotoUserDefaultStruct.OBDID
    
    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    public func startIcebreakerConnection() {
        guard centralManager.state == .poweredOn else {
            pendingConnection = true
            return
        }
        PTOBDLogger.shared.startFileLogging()
        PTOBDLogger.shared.ptLog("🔄 开始启动破冰扫描程序...")
        
        pendingConnection = false
        isUnlocked = false
        collectedPIDResponses.removeAll()
        debugFlagSent = false
        currentQueueIndex = 0
        
        if let authIndex = initQueue.firstIndex(where: { $0.hasPrefix("AT+CRYPT") || $0.hasPrefix("AT+SETCRYPT") }) {
            initQueue[authIndex] = "<AUTH>"
        }
        
        if let deviceUUID = UUID(uuidString: targetDeviceUUIDString) {
            let knownPeripherals = centralManager.retrievePeripherals(withIdentifiers: [deviceUUID])
            if let targetPeripheral = knownPeripherals.first {
                self.obdPeripheral = targetPeripheral
                if targetPeripheral.state == .connected {
                    self.obdPeripheral?.delegate = nil
                    DispatchQueue.main.async { [weak self] in self?.onIceBroken?() }
                    return
                }
                self.obdPeripheral?.delegate = self
                PTOBDLogger.shared.ptLog("🎯 发现已记录设备，发起连接...")
                self.centralManager.connect(targetPeripheral, options: nil)
                return
            }
        }
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }
    
    public func sendOBDCommandAsync(_ command: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            guard isUnlocked, let writeChar = self.writeCharacteristic,
                  let data = "\(command)\r".data(using: .ascii),
                  let peripheral = self.obdPeripheral else {
                continuation.resume(throwing: NSError(domain: "OBDError", code: -1, userInfo: [NSLocalizedDescriptionKey: "底层未准备好"]))
                return
            }
            
            self.responseContinuation = continuation
            self.activeCommand = command
            self.rxBuffer = ""
            
            PTOBDLogger.shared.ptLog("⬆️ [TX Async] \(command)\\r")
            
            let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            peripheral.writeValue(data, for: writeChar, type: writeType)
            
            self.timeoutTask?.cancel()
            self.timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                if !Task.isCancelled {
                    PTOBDLogger.shared.ptLog("⏳ [TX Async] 响应超时: \(command)")
                    self.responseContinuation?.resume(throwing: NSError(domain: "OBDError", code: -3, userInfo: [NSLocalizedDescriptionKey: "响应超时"]))
                    self.responseContinuation = nil
                    self.centralManager.cancelPeripheralConnection(peripheral)
                }
            }
        }
    }
}

extension PTHiddenOBDConnector: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        PTOBDLogger.shared.ptLog("📲 蓝牙状态变化: \(central.state.rawValue)")
        if central.state == .poweredOn && pendingConnection { startIcebreakerConnection() }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        if allowedDeviceNames.contains(deviceName) {
            PTOBDLogger.shared.ptLog("🎯 [扫描] 捕获目标设备: \(deviceName) (RSSI: \(RSSI))")
            centralManager.stopScan()
            self.obdPeripheral = peripheral
            self.obdPeripheral?.delegate = self
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        PTOBDLogger.shared.ptLog("🔗 [GATT] 物理连接成功，开始发现服务...")
        let targetServiceUUID = CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB")
        peripheral.discoverServices([targetServiceUUID])
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        PTOBDLogger.shared.ptLog("❌ [GATT] 蓝牙已断开！原因: \(error?.localizedDescription ?? "无")")
        isUnlocked = false
        responseContinuation?.resume(throwing: NSError(domain: "OBDError", code: -2, userInfo: [NSLocalizedDescriptionKey: "蓝牙断开"]))
        responseContinuation = nil
        PTOBDLogger.shared.stopFileLogging()
    }
}

extension PTHiddenOBDConnector: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        PTOBDLogger.shared.ptLog("🔍 [GATT] 发现服务数量: \(services.count)")
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        var targetWrite: CBCharacteristic?
        var targetNotify: CBCharacteristic?
        
        for char in characteristics {
            PTOBDLogger.shared.ptLog("📌 [GATT] 发现通道: \(char.uuid), properties: \(char.properties.rawValue)")
            if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                targetNotify = char
            }
            if char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse) {
                targetWrite = char
            }
        }
        
        if let w = targetWrite { self.writeCharacteristic = w }
        if let n = targetNotify {
            self.notifyCharacteristic = n
            peripheral.setNotifyValue(true, for: n)
            PTOBDLogger.shared.ptLog("✅ [GATT] 锁定写入通道: \(writeCharacteristic?.uuid ?? CBUUID()), 锁定监听通道: \(n.uuid)")
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.isNotifying && characteristic.uuid == self.notifyCharacteristic?.uuid {
            PTOBDLogger.shared.ptLog("🔔 [GATT] 核心通道 Notify 订阅成功，开始发射初始化队列！")
            currentQueueIndex = 0
            rxBuffer = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.sendNextCommand() }
        }
    }
    
    private func sendNextCommand() {
        guard currentQueueIndex < initQueue.count else {
            PTOBDLogger.shared.ptLog("✅ [破冰船] 19 步硬件大满贯解锁完毕！移交控制权！")
            self.isUnlocked = true
            DispatchQueue.main.async { [weak self] in self?.onIceBroken?() }
            return
        }
        
        let rawCommand = initQueue[currentQueueIndex]
        activeCommand = rawCommand
        rxBuffer = ""
        
        PTOBDLogger.shared.ptLog("⬆️ [TX Init \(currentQueueIndex + 1)/\(initQueue.count)] \(rawCommand)\\r")
        
        guard let writeChar = self.writeCharacteristic,
              let data = "\(rawCommand)\r".data(using: .ascii),
              let peripheral = self.obdPeripheral else { return }
        
        let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: writeChar, type: writeType)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        if let chunk = String(data: data, encoding: .ascii) {
            rxBuffer += chunk
            
            let displayChunk = chunk.replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
            PTOBDLogger.shared.ptLog("⬇️ [RX Chunk] '\(displayChunk)'")
            
            var isComplete = false
            var endRange: Range<String.Index>? = nil
            
            if let range = rxBuffer.range(of: ">") {
                isComplete = true
                endRange = range
            }
            
            if isComplete, let range = endRange {
                self.timeoutTask?.cancel()
                self.timeoutTask = nil
                
                let completeResponse = String(rxBuffer[..<range.lowerBound])
                
                if range.upperBound < rxBuffer.endIndex {
                    rxBuffer = String(rxBuffer[range.upperBound...])
                } else {
                    rxBuffer = ""
                }
                
                let cleanResponse = completeResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if isUnlocked {
                    PTOBDLogger.shared.ptLog("✅ [RX Async Complete] 抛出给上层: \(cleanResponse)")
                    responseContinuation?.resume(returning: cleanResponse)
                    responseContinuation = nil
                } else {
                    PTOBDLogger.shared.ptLog("✅ [RX Init Complete] 状态机消化: \(cleanResponse)")
                    processCompleteResponse(cleanResponse)
                }
            }
        }
    }
    
    private func processCompleteResponse(_ response: String) {
        let cleanResponseForCheck = response.replacingOccurrences(of: " ", with: "").uppercased()
        let cmd = activeCommand ?? ""
        
        if cmd == "ATZ" && cleanResponseForCheck.contains("STOPPED") {
            PTOBDLogger.shared.ptLog("⚠️ [状态机] ATZ 被 STOPPED，重试")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.sendNextCommand() }
            return
        }
        
        let okCheckCommands = ["ATE0", "ATL0", "ATH1", "ATS0"]
        if okCheckCommands.contains(cmd) && !cleanResponseForCheck.contains("OK") {
            PTOBDLogger.shared.ptLog("⚠️ [状态机] \(cmd) 未得到 OK，重试")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.sendNextCommand() }
            return
        }
        
        let purePayload = response.replacingOccurrences(of: cmd, with: "", options: .caseInsensitive) .replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if cmd == "ATZ" {
            PTMotoTelemetryManager.shared.obdInfo.atzName = purePayload
        }
        
        if cmd == "ATI" {
            PTMotoTelemetryManager.shared.obdInfo.aitName = purePayload
        }
        
        if cmd == "ATDP" {
            PTMotoTelemetryManager.shared.obdInfo.atdpName = PROTOCOL.from(string: purePayload)
        }
        
        if cmd == "0902" && !cleanResponseForCheck.contains("NODATA") {
            PTMotoTelemetryManager.shared.obdInfo.vin = PTMultiFrameParser.parseLongString(response: response)
        }
        
        if cmd == "0904" && !cleanResponseForCheck.contains("NODATA") {
            let parsedCalID = PTMultiFrameParser.parseLongString(response: response)
            PTMotoTelemetryManager.shared.obdInfo.ecuVersion = parsedCalID
            PTOBDLogger.shared.ptLog("🏍️ [档案] 提取标定识别码: \(parsedCalID)")
        }
        
        if cmd == "0906" && !cleanResponseForCheck.contains("NODATA") {
            PTMotoTelemetryManager.shared.obdInfo.cvn = PTMultiFrameParser.parseLongString(response: response)
        }

        if cmd == "AT+VERSION" {
            if response.contains("?") || response.isEmpty {
                PTOBDLogger.shared.ptLog("⚠️ [认证] 未发现 YMOBD 加密特征，中断隐蔽初始化！")
                self.obdPeripheral?.delegate = nil
                if let p = self.obdPeripheral {
                    DispatchQueue.main.async { [weak self] in self?.onStandardDeviceDetected?(p) }
                }
                return
            }
            
            let lines = response.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if lines.count > 0 {
                PTMotoTelemetryManager.shared.obdInfo.moudleInfo.company = lines[0] // 第一行通常是公司名
            }
            for line in lines {
                // 使用冒号将当前行切分为数组
                let parts = line.components(separatedBy: ":")
                
                // 确保这一行确实包含冒号和有效数据
                guard parts.count >= 2 else { continue }
                
                // 左边是 Key：转小写并去除首尾空格，作为稳固的判断依据
                let key = parts[0].lowercased().trimmingCharacters(in: .whitespaces)
                
                // 右边是 Value：如果数据本身包含冒号(如 MAC 地址)，用 joined 重新拼合，并剔除多余空格
                let value = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
                
                // 极其清爽且绝对安全的赋值
                if key == "version" {
                    PTMotoTelemetryManager.shared.obdInfo.moudleInfo.version = value
                } else if key == "device type" {
                    PTMotoTelemetryManager.shared.obdInfo.moudleInfo.deviceType = value
                } else if key == "device name" {
                    PTMotoTelemetryManager.shared.obdInfo.moudleInfo.deviceName = value
                } else if key == "device mac" {
                    PTMotoTelemetryManager.shared.obdInfo.moudleInfo.deviceMac = value.uppercased()
                } else if key == "interface" {
                    PTMotoTelemetryManager.shared.obdInfo.moudleInfo.interfase = value
                } else if key == "cust id" {
                    PTMotoTelemetryManager.shared.obdInfo.moudleInfo.cust = value
                }
            }

            var cryptSeed = ""
            if let regex = try? NSRegularExpression(pattern: "(?im)^\\s*crypt\\s*:\\s*([0-9a-f]{1,8})") {
                let nsString = response as NSString
                let results = regex.matches(in: response, range: NSRange(location: 0, length: nsString.length))
                if let match = results.first {
                    let seedPart = nsString.substring(with: match.range(at: 1))
                    cryptSeed = String(seedPart.filter { "0123456789abcdefABCDEF".contains($0) })
                    PTOBDLogger.shared.ptLog("🔑 [认证] 从正则中成功提取纯净种子: \(cryptSeed)")
                }
            }
            
            let authCommand = !cryptSeed.isEmpty ? YmobdCrypt.setCryptCommand(cryptFromVersion: cryptSeed) : YmobdCrypt.challengeCommand(challenge: YmobdCrypt.newChallenge())
            let cleanAuthCommand = authCommand.replacingOccurrences(of: "\r", with: "")
            
            if let authIndex = initQueue.firstIndex(of: "<AUTH>") {
                initQueue[authIndex] = cleanAuthCommand
                PTOBDLogger.shared.ptLog("🔐 [认证] 成功向槽位注入密钥: \(cleanAuthCommand)")
            }
        }
        
        // 我们不再重试 0100 的错误情况，保证 19 步行云流水跑通
        if cmd == "0100" || cmd == "0120" || cmd == "0140" {
            collectedPIDResponses.append(response)
        }
                
        currentQueueIndex += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.sendNextCommand() }
    }
}

public protocol PTMotoTelemetryDelegate: AnyObject {
    func telemetryManager(_ manager: PTMotoTelemetryManager, didChangeConnectionState isConnected: Bool)
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateMeasurements measurements: [String: Any])
    func telemetryManager(_ manager: PTMotoTelemetryManager, didDiscoverSupportedCommands commands: [String])
}

public extension PTMotoTelemetryDelegate {
    func telemetryManager(_ manager: PTMotoTelemetryManager, didChangeConnectionState isConnected: Bool) {}
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateMeasurements measurements: [String: Any]) {}
    func telemetryManager(_ manager: PTMotoTelemetryManager, didDiscoverSupportedCommands commands: [String]) {}
}

public class PTMotoTelemetryManager {
    public static let shared = PTMotoTelemetryManager()
    
    public private(set) var obdInfo = PTOBDInfo()
    
    private class WeakDelegateWrapper {
        weak var delegate: PTMotoTelemetryDelegate?
        init(_ delegate: PTMotoTelemetryDelegate) { self.delegate = delegate }
    }
    private var delegates: [WeakDelegateWrapper] = []
    
    public private(set) var isConnected: Bool = false
    public private(set) var currentRPM: Double = 0.0
    public private(set) var currentSpeed: Double = 0.0
    
    private var telemetryPollingTask: Task<Void, Never>?
    private var obdService = OBDService(connectionType: .bluetooth)
    private var cancellables = Set<AnyCancellable>()
    public private(set) var isUsingSwiftOBD2: Bool = false
    
    private init() {}
    
    public func addDelegate(_ delegate: PTMotoTelemetryDelegate) {
        cleanupDelegates()
        let isAlreadyAdded = delegates.contains { $0.delegate === delegate }
        if !isAlreadyAdded {
            delegates.append(WeakDelegateWrapper(delegate))
            if isConnected && !obdInfo.supportCommand.isEmpty {
                let commands = obdInfo.supportCommand.map { value in
                    value.properties.command
                }
                delegate.telemetryManager(self, didDiscoverSupportedCommands: commands)
            }
        }
    }
    
    public func connectToMotorcycle() {
        PTOBDLogger.shared.ptLog("📡 [OBD2] 开始连接入口调用...")
        isUsingSwiftOBD2 = false
        
        PTHiddenOBDConnector.shared.onStandardDeviceDetected = { [weak self] peripheral in
            guard let self = self else { return }
            self.isUsingSwiftOBD2 = true
            self.setupConnectionListener()
            self.startOBDServiceHandshake()
        }

        PTHiddenOBDConnector.shared.onIceBroken = { [weak self] in
            guard let self = self else { return }
            self.isConnected = true
            PTOBDLogger.shared.ptLog("✅ [Manager] 底层通知破冰完毕，移交轮询控制权！")
            self.startLightweightPolling(rawPIDs: PTHiddenOBDConnector.shared.collectedPIDResponses)
        }
        
        PTHiddenOBDConnector.shared.startIcebreakerConnection()
    }
    
    // MARK: - 极简轮询引擎 (全频段动态提取 + 核心加权狂闪版)
    private func startLightweightPolling(rawPIDs: [String]) {
        telemetryPollingTask?.cancel()
        
        telemetryPollingTask = Task { [weak self] in
            guard let self = self else { return }
            
            // 1. 动态解析所有车辆支持的 PID
            let parsedPIDs = self.parseAllPIDs(rawResponses: rawPIDs)
            guard !parsedPIDs.isEmpty else {
                PTOBDLogger.shared.ptLog("❌ [轮询引擎] 探针解析全 0，主动断开！")
                await MainActor.run { self.disconnect() }
                return
            }
            
            // 2. 构建包含基础电压的动态总表
            var allDynamicCommands = parsedPIDs
            if !allDynamicCommands.contains("ATRV") {
                allDynamicCommands.append("ATRV")
            }
            let typedCommands = allDynamicCommands.compactMap { OBDCommand.from(command: $0) }
            self.obdInfo.supportCommand = typedCommands
            
            await MainActor.run {
                self.delegates.forEach { wrapper in
                    wrapper.delegate?.telemetryManager(self, didChangeConnectionState: true)
                    wrapper.delegate?.telemetryManager(self, didDiscoverSupportedCommands: allDynamicCommands)
                }
            }
            
            PTOBDLogger.shared.ptLog("⚡️ [轮询引擎] 成功提取 \(allDynamicCommands.count) 条支持指令，开始构建加权火力网！")
            
            // 为了防止全频段扫描导致转速表(RPM)刷新率下降，我们将高优指令交替插入列队
            var pollingQueue: [String] = []
            let rpmCmd = "010C"
            let speedCmd = "010D"
            
            let otherCommands = allDynamicCommands.filter { $0 != rpmCmd && $0 != speedCmd }
            
            if otherCommands.isEmpty {
                pollingQueue = allDynamicCommands
            } else {
                // 生成交替队列：[转速, 车速, 其它1, 转速, 车速, 其它2...]
                for other in otherCommands {
                    if allDynamicCommands.contains(rpmCmd) { pollingQueue.append(rpmCmd) }
                    if allDynamicCommands.contains(speedCmd) { pollingQueue.append(speedCmd) }
                    pollingQueue.append(other)
                }
            }
            
            // 4. 建立持续保存数据的字典
            var persistentMeasurements: [String: Any] = [:]
            for command in allDynamicCommands { persistentMeasurements[command] = 0.0 }
            
            while !Task.isCancelled && self.isConnected {
                
                for commandString in pollingQueue {
                    if Task.isCancelled { break }
                    
                    do {
                        let response = try await PTHiddenOBDConnector.shared.sendOBDCommandAsync(commandString)
                        let cleanResponse = self.clearString(response: response)
                        
                        // 过滤掉偶尔的 NO DATA 或杂音，绝不打断轮询
                        if !cleanResponse.isEmpty && !cleanResponse.contains("NODATA") && !cleanResponse.contains("ERROR") && !cleanResponse.contains("NO DATA") {
                            
                            // 交给无敌装甲解析器
                            if let val = self.parseSingleResponse(command: commandString, response: response) {
                                persistentMeasurements[commandString] = val
                                
                                // 为了防止日志爆炸，可以考虑只打印部分核心数据的解析结果
                                // PTOBDLogger.shared.ptLog("🏎️ [解析成功] 完美提取 \(commandString) 数据 = \(val)")
                                
                                // 0 延迟派发机制，让 UI 极速响应
                                let mapToDispatch = persistentMeasurements
                                await MainActor.run {
                                    self.dispatchMeasurementsToDelegates(measurements: mapToDispatch)
                                }
                            } else {
                                // 如果是支持的 PID 但我们还没在 parseSingleResponse 里写公式，暂存原始 Hex
                                if cleanResponse.contains("41") {
                                    persistentMeasurements[commandString] = cleanResponse
                                    let mapToDispatch = persistentMeasurements
                                    await MainActor.run {
                                        self.dispatchMeasurementsToDelegates(measurements: mapToDispatch)
                                    }
                                }
                            }
                        }
                    } catch {}
                    
                    // 维持 10 毫秒极限微延迟，压榨硬件通讯极速
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
                
                // 周期底噪
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    func clearString(response:String) ->String {
        let cleanStr = response.replacingOccurrences(of: " ", with: "")
                                       .replacingOccurrences(of: ">", with: "")
                                       .replacingOccurrences(of: "\r", with: "")
                                       .replacingOccurrences(of: "\n", with: "")
                                       .uppercased()
        return cleanStr
    }
    
    private func parseAllPIDs(rawResponses: [String]) -> [String] {
        var allSupported: [String] = []
        for res in rawResponses {
            let clean = clearString(response: res)
            var base = 0x00
            if clean.contains("4120") { base = 0x20 }
            else if clean.contains("4140") { base = 0x40 }
            allSupported.append(contentsOf: parseSupportedPIDs(response: res, baseCommand: base))
        }
        return allSupported
    }
    
    private func parseSupportedPIDs(response: String, baseCommand: Int) -> [String] {
        let clean = clearString(response: response)
        let prefix = String(format: "41%02X", baseCommand)
        let pattern = "\(prefix)([0-9A-F]{8})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        
        let matches = regex.matches(in: clean, options: [], range: NSRange(location: 0, length: clean.count))
        var combinedMask: UInt32 = 0
        
        for match in matches {
            if let range = Range(match.range(at: 1), in: clean) {
                let hexString = String(clean[range])
                if let maskValue = UInt32(hexString, radix: 16) {
                    combinedMask |= maskValue
                }
            }
        }
        
        guard combinedMask > 0 else { return [] }
        var supported: [String] = []
        
        for i in 0..<32 {
            let bit = (combinedMask >> (31 - i)) & 1
            if bit == 1 {
                let pid = baseCommand + i + 1
                supported.append(String(format: "01%02X", pid))
            }
        }
        return supported
    }

    // MARK: 使用硬编码字符串完美脱离 SwiftOBD2 评估依赖
    private func parseSingleResponse(command: String, response: String) -> Double? {
        // 1. 终极净化：只保留 0-9 和 A-F，彻底粉碎所有的空格、回车、甚至是不可见的 \0 (Null Byte)！
        let hexValid = "0123456789ABCDEF"
        let pureResponse = response.uppercased().filter { hexValid.contains($0) }
        let pureCommand = command.uppercased().filter { hexValid.contains($0) }
        
        // 为 ATRV 开辟专属“绿色通道”
        if pureCommand == "ATRV" || command.uppercased().contains("ATRV") {
            // 电压含有小数点，单独提纯
            let voltStr = response.uppercased().replacingOccurrences(of: "V", with: "").filter { "0123456789.".contains($0) }
            return Double(voltStr)
        }
        
        // 2. 确保指令前缀合法且长度足够
        guard pureCommand.hasPrefix("01") && pureCommand.count >= 4 else {
            PTOBDLogger.shared.ptLog("❌ 拦截：指令格式不合法 -> [\(pureCommand)]")
            return nil
        }
        
        // 3. 提取预期报头，例如 "010C" -> "410C"
        let modeAndPID = String(pureCommand.prefix(4))
        let pidHex = String(modeAndPID.suffix(2))
        
        // 拼接预期前缀 (41 + 0C = 410C)
        let expectedPrefix = "41" + pidHex
        
        // 4. 在绝对纯净的响应中寻找报头
        // 此时 "7E804410C196C".range(of: "410C") 绝对能完美匹配！
        guard let range = pureResponse.range(of: expectedPrefix) else {
            PTOBDLogger.shared.ptLog("❌ 拦截：纯净响应中找不到报头 | 纯净指令:[\(pureCommand)] 预期报头:[\(expectedPrefix)] 纯净响应:[\(pureResponse)]")
            return nil
        }
        
        let rawDataPart = String(pureResponse[range.upperBound...])
        
        func getByte(at index: Int) -> Double? {
            let startOffset = index * 2
            guard rawDataPart.count >= startOffset + 2 else { return nil }
            let startIndex = rawDataPart.index(rawDataPart.startIndex, offsetBy: startOffset)
            let endIndex = rawDataPart.index(startIndex, offsetBy: 2)
            if let intVal = Int(rawDataPart[startIndex..<endIndex], radix: 16) { return Double(intVal) }
            return nil
        }
        
        let A = getByte(at: 0)
        let B = getByte(at: 1)
        
        // 5. 使用纯净的 4 位指令进行 Switch，彻底打通数据通路！
        var parsedValue: Double? = nil
                
        // 4. SwiftOBD2 公式！
        switch modeAndPID {
        case "010C": // RPM 转速
            if let a = A, let b = B { parsedValue = (a * 256.0 + b) / 4.0 }
        case "010D": // Vehicle Speed 车速
            if let a = A { parsedValue = a }
        case "0104", "0111", "0145", "014C", "0152", "015A": // 各种百分比 (节气门, 引擎负载等)
            if let a = A { parsedValue = a * 100.0 / 255.0 }
        case "0105", "010F", "0146", "015C": // 各种温度 (水温, 进气温, 机油温度)
            if let a = A { parsedValue = a - 40.0 }
        case "0106", "0107", "0108", "0109", "0155", "0156", "0157", "0158": // 长短期燃油修正 (百分比居中)
            if let a = A { parsedValue = (a - 128.0) * 100.0 / 128.0 }
        case "010B", "0133": // 进气压力 & 绝对大气压
            if let a = A { parsedValue = a }
        case "010E": // 点火提前角
            if let a = A { parsedValue = a / 2.0 - 64.0 }
        case "0110": // MAF 空气流量
            if let a = A, let b = B { parsedValue = (a * 256.0 + b) / 100.0 }
        case "0114", "0115", "0116", "0117", "0118", "0119", "011A", "011B": // O2 氧传感器电压
            if let a = A { parsedValue = a / 200.0 }
        case "011F", "0121", "0131", "014D", "014E": // 运行时间 & 行驶距离
            if let a = A, let b = B { parsedValue = a * 256.0 + b }
        case "0142": // 控制模块电压
            if let a = A, let b = B { parsedValue = (a * 256.0 + b) / 1000.0 }
        case "015E": // 发动机燃油率
            if let a = A, let b = B { parsedValue = (a * 256.0 + b) / 20.0 }
        case "0101", "0103", "0113", "011C", "0141", "0151": // 状态/协议/掩码类数据
            if let a = A { parsedValue = a }
        case "0100", "0120", "0140", "0160": // PID 支持探针 (本身不是 Double 测量值，给个占位符防止报错)
            parsedValue = 1.0
        default:
            PTOBDLogger.shared.ptLog("⚠️ 未适配计算公式: \(modeAndPID)")
        }
        
        if let val = parsedValue {
            PTOBDLogger.shared.ptLog("🏎️ [解析成功] \(modeAndPID) -> \(val)")
            return val
        }
        
        return nil
    }
    
    @MainActor
    private func dispatchMeasurementsToDelegates(measurements: [String: Any]) {
        self.cleanupDelegates()
        
        // UI 回调，UI 需要监听 "010C" 等字符串
        if let rpm = measurements["010C"] as? Double { self.currentRPM = rpm }
        if let speed = measurements["010D"] as? Double { self.currentSpeed = speed }
        
        self.delegates.forEach { wrapper in
            wrapper.delegate?.telemetryManager(self, didUpdateMeasurements: measurements)
        }
    }
    
    private func cleanupDelegates() {
        delegates.removeAll { $0.delegate == nil }
    }
    
    public func removeDelegate(_ delegate: PTMotoTelemetryDelegate) {
        delegates.removeAll { $0.delegate === delegate || $0.delegate == nil }
    }
}

extension PTMotoTelemetryManager {
    public func disconnect() {
        if isUsingSwiftOBD2 {
            obdService.stopConnection()
        } else {
            telemetryPollingTask?.cancel()
            isConnected = false
            obdInfo.supportCommand = []
            delegates.forEach { $0.delegate?.telemetryManager(self, didChangeConnectionState: false) }
        }
        PTOBDLogger.shared.stopFileLogging()
    }

    private func setupConnectionListener() {
        obdService.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                
                self.cleanupDelegates()
                switch state {
                case .connectedToVehicle:
                    self.isConnected = true
                    PTNSLogConsole("✅ [OBD2] 成功连接 ECU，开始数据抓取！")
                    self.delegates.forEach { wrapper in
                        guard let delegate = wrapper.delegate else { return }
                        delegate.telemetryManager(self, didChangeConnectionState: true)
                    }
                case .disconnected:
                    self.telemetryPollingTask?.cancel()
                    self.isConnected = false
                    PTNSLogConsole("❌ [OBD2] 连接断开。")
                    self.delegates.forEach { wrapper in
                        guard let delegate = wrapper.delegate else { return }
                        delegate.telemetryManager(self, didChangeConnectionState: false)
                    }
                    NotificationCenter.default.post(name: NSNotification.Name("PTMotoOBDDisconnected"), object: nil)
                    
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    public func startOBDServiceHandshake() {
        Task {
            do {
                let swiftOBD2Info = try await obdService.startConnection()
                let supportedPIDs = await obdService.getSupportedPIDs()
                let map = supportedPIDs.map { $0.properties.command }

                obdInfo.supportCommand = swiftOBD2Info.supportedPIDs ?? []
                obdInfo.vin = swiftOBD2Info.vin ?? ""
                obdInfo.atdpName = swiftOBD2Info.obdProtocol ?? .NONE
                
                self.isConnected = true
                await MainActor.run {
                    self.cleanupDelegates()
                    self.delegates.forEach { wrapper in
                        wrapper.delegate?.telemetryManager(self, didChangeConnectionState: true)
                        wrapper.delegate?.telemetryManager(self, didDiscoverSupportedCommands: map)
                    }
                }
                
                telemetryPollingTask?.cancel()
                let safeSwiftCommands: [OBDCommand] = [.mode1(.rpm), .mode1(.speed), .mode1(.coolantTemp)]
                telemetryPollingTask = Task { [weak self = self] in
                    guard let self = self else { return }
                    while !Task.isCancelled && self.isConnected {
                        var currentMeasurements: [OBDCommand: Any] = [:]
                        for command in safeSwiftCommands { currentMeasurements[command] = 0.0 }
                        
                        for command in safeSwiftCommands {
                            if Task.isCancelled { break }
                            do {
                                let response = try await self.obdService.sendCommand(command)
                                switch response {
                                case .success(let result):
                                    if let val = result.measurementResult?.value {
                                        currentMeasurements[command] = val
                                    }
                                case .failure: break
                                }
                            } catch {}
                            try? await Task.sleep(nanoseconds: 10_000_000)
                        }
                        
                        await MainActor.run {
                            var map:[String:Any] = [:]
                            currentMeasurements.forEach { value in map[value.key.properties.command] = value.value }
                            self.dispatchMeasurementsToDelegates(measurements: map)
                        }
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                }
            } catch {}
        }
    }
    
    public func clearDiagnosticTroubleCodes() async -> Bool {
        guard isConnected else { return false }
        
        if isUsingSwiftOBD2 {
            do {
                let response = try await obdService.sendCommand(.mode4(.CLEAR_DTC))
                switch response {
                case .success: return true
                case .failure: return false
                }
            } catch { return false }
        } else {
            do {
                let response = try await PTHiddenOBDConnector.shared.sendOBDCommandAsync("04")
                let cleanResponse = self.clearString(response: response)
                if cleanResponse.hasPrefix("44") || cleanResponse.contains("OK") { return true }
                else { return false }
            } catch { return false }
        }
    }
}

extension PTMotoTelemetryManager {
    
    // MARK: - 🚀 Mode 3: 获取车辆故障码 (DTCs)
    public func getDiagnosticTroubleCodes() async -> [String] {
        guard isConnected else { return [] }
        
        if isUsingSwiftOBD2 {
            do {
                // 方案 A：使用 SwiftOBD2 标准库调用
                let response = try await obdService.sendCommand(.mode3(.GET_DTC))
                switch response {
                case .success(let result):
                    if let dtcs = result.troubleCode {
                        return dtcs.map { $0.code }
                    }
                    return []
                case .failure:
                    return []
                }
            } catch { return [] }
            
        } else {
            // 方案 B：使用我们的底层隐藏连接调用
            do {
                // 发送 Mode 3 指令请求故障码
                let response = try await PTHiddenOBDConnector.shared.sendOBDCommandAsync("03")
                
                // 1. 剥离所有 CAN 包头，拿到纯净的数据体
                let purePayload = PTMultiFrameParser.extractPureHexPayload(response: response)
                
                // 2. 找到 03 指令的成功响应头 (43)
                guard let range = purePayload.range(of: "43") else { return [] }
                
                // 3. 截取 43 之后真正的故障码数据部分
                let dtcData = String(purePayload[range.upperBound...])
                var dtcs: [String] = []
                
                // 4. 每 4 个字符破译为一个故障码
                var i = dtcData.startIndex
                while i < dtcData.endIndex {
                    let nextI = dtcData.index(i, offsetBy: 4, limitedBy: dtcData.endIndex) ?? dtcData.endIndex
                    if dtcData.distance(from: i, to: nextI) == 4 {
                        let dtcHex = String(dtcData[i..<nextI])
                        
                        // "0000" 代表数据补齐，后面没有更多故障码了
                        if dtcHex != "0000" {
                            if let parsedCode = PTMultiFrameParser.decodeSingleDTC(dtcHex) {
                                dtcs.append(parsedCode)
                                PTOBDLogger.shared.ptLog("⚠️ [Mode 3] 扫描到车辆异常故障码: \(parsedCode)")
                            }
                        }
                    }
                    i = nextI
                }
                return dtcs
            } catch { return [] }
        }
    }    
}

extension PTMotoTelemetryManager {
    
    // MARK: - 🚀 步骤 1：深度扫描车辆支持的 Mode 6 指令 (强制全扫版)
    /// 主动遍历 MIDS_A 到 MIDS_F 目录，找出所有支持的化验单项目
    public func scanSupportedMode6Commands() async -> [OBDCommand.Mode6] {
        guard isConnected else { return [] }
        
        var supportedHexCommands: [String] = []
        
        // 🌟 核心改进：不再依赖 ECU 的不靠谱翻页标志，直接强制列出所有目录清单
        let directoryMIDs: [OBDCommand.Mode6] = [
            .MIDS_A, // 0600
            .MIDS_B, // 0620
            .MIDS_C, // 0640
            .MIDS_D, // 0660
            .MIDS_E, // 0680
            .MIDS_F  // 06A0
        ]
        
        for directory in directoryMIDs {
            let currentMid = directory.properties.command
            
            do {
                let response = try await PTHiddenOBDConnector.shared.sendOBDCommandAsync(currentMid)
                let cleanResponse = self.clearString(response: response)
                
                // 如果 ECU 明确表示不支持该页目录，直接跳过查下一页
                if cleanResponse.contains("NODATA") || cleanResponse.isEmpty {
                    continue
                }
                
                let purePayload = PTMultiFrameParser.extractPureHexPayload(response: response)
                
                // 预期报头，例如 "0600" -> "4600"
                let expectedPrefix = "46" + currentMid.dropFirst(2)
                guard let range = purePayload.range(of: expectedPrefix) else { continue }
                
                // 截取后面的 8 个字符 (32 位掩码)
                let maskHex = String(purePayload[range.upperBound...].prefix(8))
                guard maskHex.count == 8, let maskValue = UInt32(maskHex, radix: 16) else { continue }
                
                // 获取当前目录的基础值，例如 "0600" 提取出 0x00，"0620" 提取出 0x20
                let baseHex = currentMid.dropFirst(2)
                guard let baseInt = Int(baseHex, radix: 16) else { continue }
                
                // 解析 32 位掩码
                for i in 0..<32 {
                    let bit = (maskValue >> (31 - i)) & 1
                    if bit == 1 {
                        let supportedPidInt = baseInt + i + 1
                        let supportedPidHex = String(format: "06%02X", supportedPidInt)
                        supportedHexCommands.append(supportedPidHex)
                    }
                }
                
                // 保护 ECU 缓冲区的微小休眠
                try? await Task.sleep(nanoseconds: 50_000_000)
                
            } catch {
                PTOBDLogger.shared.ptLog("❌ [Mode 6] 扫描目录 \(currentMid) 失败")
            }
        }
        
        // 🌟 将我们算出来的 Hex 字符串，统一映射为 SwiftOBD2 的原生对象！
        var supportedMode6Enums: [OBDCommand.Mode6] = []
        for hexCmd in supportedHexCommands {
            // 过滤掉目录指针本身 (如 0620, 0640 代表翻页标志，并非真实测试项)
            if hexCmd.hasSuffix("0") { continue }
            
            if let commandEnum = OBDCommand.from(command: hexCmd),
               case .mode6(let mode6Cmd) = commandEnum {
                supportedMode6Enums.append(mode6Cmd)
            } else {
                PTOBDLogger.shared.ptLog("⚠️ [Mode 6] 发现车厂私有监控项，SwiftOBD2 暂未收录: \(hexCmd)")
            }
        }
        
        PTOBDLogger.shared.ptLog("🔬 [Mode 6] 扫描完毕，支持 \(supportedMode6Enums.count) 项化验单")
        return supportedMode6Enums
    }
    
    // MARK: - 🚀 步骤 2：批量获取支持的化验单详情
    /// 传入上一步扫描出的支持指令，真正去抽取车辆的化验单数据
    public func fetchMode6TestReports(for commands: [OBDCommand.Mode6]) async -> [PTMode6Data] {
        guard isConnected else { return [] }
        var allReports: [PTMode6Data] = []
        
        for cmdEnum in commands {
            let hexCommand = cmdEnum.properties.command // 提取如 "0601"
            do {
                let response = try await PTHiddenOBDConnector.shared.sendOBDCommandAsync(hexCommand)
                let purePayload = PTMultiFrameParser.extractPureHexPayload(response: response)
                
                // 将纯净十六进制丢给我们的解析器，解析出数值、上限、下限
                let reports = PTMultiFrameParser.parseMode6TestResults(pureHex: purePayload)
                allReports.append(contentsOf: reports)
                
                // 稍微休眠，防止 ECU 拥堵
                try? await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                continue
            }
        }
        return allReports
    }
}
