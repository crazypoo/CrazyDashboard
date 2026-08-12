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
import Network

// MARK: - 🌟 0101 车辆健康综合体检模型
public struct PTVehicleStatus0101 {
    // 1. 基础故障灯与故障码状态
    public let isMILOn: Bool          // 发动机故障灯 (Check Engine Light) 是否点亮
    public let dtcCount: Int          // 存储的故障码总数
    
    // 2. 连续监控系统 (时刻都在监测的核心系统)
    public let misfireSupported: Bool // 是否支持失火监控
    public let misfireReady: Bool     // 失火监控是否就绪/完成
    
    public let fuelSystemSupported: Bool // 是否支持燃油系统监控
    public let fuelSystemReady: Bool     // 燃油系统监控是否就绪
    
    public let componentsSupported: Bool // 是否支持综合组件监控
    public let componentsReady: Bool     // 综合组件监控是否就绪
    
    // 3. 非连续监控系统 (部分核心汽油车监控项)
    public let catalystSupported: Bool   // 是否支持三元催化器监控
    public let catalystReady: Bool       // 三元催化器监控是否就绪
    
    public let o2SensorSupported: Bool   // 是否支持氧传感器监控
    public let o2SensorReady: Bool       // 氧传感器监控是否就绪
    
    public let egrSupported: Bool        // 是否支持 EGR (废气再循环) 系统
    public let egrReady: Bool            // EGR 系统是否就绪
    
    // UI 快速展示：体检综合评分描述
    public var reportCard: String {
        let milStatus = isMILOn ? "🔴 故障灯亮起" : "🟢 状态正常"
        return "[\(milStatus)] 存在故障码: \(dtcCount) 个 | 氧传感器测试: \(o2SensorReady ? "及格" : "未完成") | 燃油系统: \(fuelSystemReady ? "及格" : "未完成")"
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

// MARK: - 🌟 J1979 标准燃料类型 (PID 0151 返回值)
public enum PTFuelType: Int, Codable {
    case notAvailable = 0
    case gasoline = 1       // 汽油
    case methanol = 2       // 甲醇
    case ethanol = 3        // 乙醇
    case diesel = 4         // 柴油
    case lpg = 5            // 液化石油气
    case cng = 6            // 压缩天然气
    case propane = 7        // 丙烷
    case electric = 8       // 🌟 纯电动
    case bifuelGasoline = 9
    case hybridGasoline = 15 // 🌟 混动汽油
    case hybridElectric = 16
    case hybridMixed = 17
    case hybridDiesel = 18   // 混动柴油
    case unknown = 255
    
    public var stringValue: String {
        switch self {
        case .gasoline: return "汽油"
        case .diesel: return "柴油"
        case .electric: return "纯电动"
        case .hybridGasoline, .hybridElectric, .hybridMixed, .hybridDiesel: return "混合动力"
        default: return "其他/未知"
        }
    }
}

// MARK: - 🌟 动力系统类型
public enum PTEngineType: String, Codable {
    case ice = "燃油车 (ICE)"
    case ev = "纯电动 (EV)"
    case hybrid = "混合动力 (HEV)"
}

public class PTATVersionModel:NSObject {
    public var company:String = ""
    public var version:String = ""
    public var deviceType:String = ""
    public var deviceName:String = ""
    public var deviceMac:String = ""
    public var interfase:String = ""
    public var cust:String = ""
    public var crypt:String = ""
}

public class PTOBDInfo:NSObject {
    public var atzName:String = ""
    public var moudleInfo:PTATVersionModel = PTATVersionModel()
    public var aitName:String = ""
    public var atdpName:PROTOCOL = .NONE
    public var vin:String = ""
    public var ecuVersion:String = ""
    public var cvn:String = ""
    public var supportCommand:[OBDCommand] = []
    public var engineType: PTEngineType = .ice
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
            _ = try? logFileHandle?.seekToEnd()
            _ = try? logFileHandle?.write(contentsOf: data)
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
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
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

public enum PTOBDConnectionType {
    case bluetooth
    case wifi(ip: String, port: UInt16)
}

// MARK: - 🌟 OBD 传输核心协议基类 (负责状态机与碎片组装)
public class PTOBDTransportBase: NSObject {
    
    public var onIceBroken: (() -> Void)?
    public var isUnlocked: Bool = false
    
    // 严丝合缝的 19 步解锁列队
    internal var initQueue: [String] = [
        "ATZ", "ATE0", "ATL0", "ATH1", "ATSP0", "AT+VERSION", "ATI", "ATRV", "<AUTH>",
        "0100", "020000", "0600", "0900", "ATDP", "0120", "0140", "0902", "0904", "0906"
    ]
    internal var currentQueueIndex: Int = 0
    internal var activeCommand: String? = nil
    internal var rxBuffer: String = ""
    public var collectedPIDResponses: [String] = []
    
    internal var responseContinuation: CheckedContinuation<String, any Error>?
    internal var timeoutTask: Task<Void, Never>?
    
    public var isSnifferMode: Bool = false
    // MARK: - ⚠️ 子类必须实现的方法
    
    /// 子类负责将具体的指令通过各自的硬件介质 (BLE/TCP) 发送出去
    internal func writeRawData(_ command: String) {
        fatalError("子类必须重写 writeRawData 方法")
    }
    
    /// 子类负责在发生严重错误或超时时，彻底断开物理连接
    internal func dropPhysicalConnection() {
        fatalError("子类必须重写 dropPhysicalConnection 方法")
    }
    
    // MARK: - 🌟 共享逻辑：重置并启动状态机
    internal func resetAndStartStateMachine() {
        isUnlocked = false
        currentQueueIndex = 0
        rxBuffer = ""
        collectedPIDResponses.removeAll()
        
        // 恢复 <AUTH> 槽位
        if let authIndex = initQueue.firstIndex(where: { $0.hasPrefix("AT+CRYPT") || $0.hasPrefix("AT+SETCRYPT") || $0 == "ATRV" }) {
            initQueue[authIndex] = "<AUTH>"
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.sendNextCommand()
        }
    }
    
    // MARK: - 🌟 共享逻辑：异步发送指令 (API)
    public func sendOBDCommandAsync(_ command: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            guard isUnlocked else {
                continuation.resume(throwing: NSError(domain: "OBDError", code: -1, userInfo: [NSLocalizedDescriptionKey: "底层连接尚未准备好"]))
                return
            }
            
            self.responseContinuation = continuation
            self.activeCommand = command
            self.rxBuffer = ""
            
            PTOBDLogger.shared.ptLog("⬆️ [TX Async] \(command)\\r")
            self.writeRawData(command) // 呼叫子类去执行物理发送
            
            // 20秒超时保护
            self.timeoutTask?.cancel()
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                if !Task.isCancelled {
                    PTOBDLogger.shared.ptLog("⏳ [TX Async] 响应超时: \(command)")
                    self?.responseContinuation?.resume(throwing: NSError(domain: "OBDError", code: -3, userInfo: [NSLocalizedDescriptionKey: "响应超时"]))
                    self?.responseContinuation = nil
                    self?.dropPhysicalConnection() // 超时断开物理连接
                }
            }
        }
    }
    
    // MARK: - 🌟 共享逻辑：接收数据碎片并组装
    internal func handleIncomingChunk(_ chunk: String, sourceName: String) {
        rxBuffer += chunk
        
        // 狙击手/监听模式下的特殊处理 (实时瀑布流输出)
        if isSnifferMode {
            // 在监听模式下，ELM327 会疯狂输出带有 \r 的报文，且没有 ">"
            if rxBuffer.contains("\r") {
                let lines = rxBuffer.components(separatedBy: "\r")
                // 打印除最后一段（可能不完整）之外的所有行
                for i in 0..<(lines.count - 1) {
                    let frame = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !frame.isEmpty {
                        // 💥 这里直接把抓到的原厂私有报文狠狠地砸进日志！
                        PTOBDLogger.shared.ptLog("🕵️‍♂️ [嗅探抓包] 截获报文: \(frame)")
                    }
                }
                // 保留最后一段不完整的碎片
                rxBuffer = lines.last ?? ""
            }
            return // 监听模式下，跳过后面的常规 ">" 判断逻辑
        }

        
        let displayChunk = chunk.replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
        PTOBDLogger.shared.ptLog("⬇️ [RX \(sourceName) Chunk] '\(displayChunk)'")
        
        var isComplete = false
        var endRange: Range<String.Index>? = nil
        
        // 只要遇到 ">"，说明 ECU 这一句话说完了
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
                PTOBDLogger.shared.ptLog("✅ [RX \(sourceName) Async] 抛出上层: \(cleanResponse)")
                responseContinuation?.resume(returning: cleanResponse)
                responseContinuation = nil
            } else {
                PTOBDLogger.shared.ptLog("✅ [RX \(sourceName) Init] 消化: \(cleanResponse)")
                processCompleteResponse(cleanResponse)
            }
        }
    }
    
    // MARK: - 🌟 共享逻辑：自动队列与硬件解密
    internal func sendNextCommand() {
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
        writeRawData(rawCommand)
    }
    
    private func processCompleteResponse(_ response: String) {
        let cleanResponseForCheck = response.replacingOccurrences(of: " ", with: "").uppercased()
        let cmd = activeCommand ?? ""
        
        if cmd == "ATZ" && cleanResponseForCheck.contains("STOPPED") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.sendNextCommand() }
            return
        }
        let okCheckCommands = ["ATE0", "ATL0", "ATH1", "ATS0"]
        if okCheckCommands.contains(cmd) && !cleanResponseForCheck.contains("OK") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.sendNextCommand() }
            return
        }
        
        let purePayload = response.replacingOccurrences(of: cmd, with: "", options: .caseInsensitive) .replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cmd == "ATZ" { PTMotoTelemetryManager.shared.obdInfo.atzName = purePayload }
        if cmd == "ATI" { PTMotoTelemetryManager.shared.obdInfo.aitName = purePayload }
        if cmd == "ATDP" { PTMotoTelemetryManager.shared.obdInfo.atdpName = PROTOCOL.from(string: purePayload) }
        if cmd == "0902" && !cleanResponseForCheck.contains("NODATA") { PTMotoTelemetryManager.shared.obdInfo.vin = PTMultiFrameParser.parseLongString(response: response) }
        if cmd == "0904" && !cleanResponseForCheck.contains("NODATA") { PTMotoTelemetryManager.shared.obdInfo.ecuVersion = PTMultiFrameParser.parseLongString(response: response) }
        if cmd == "0906" && !cleanResponseForCheck.contains("NODATA") { PTMotoTelemetryManager.shared.obdInfo.cvn = PTMultiFrameParser.parseLongString(response: response) }

        if cmd == "AT+VERSION" {
            // 兼容标准设备降级
            if response.contains("?") || response.isEmpty || cleanResponseForCheck.contains("ERROR") {
                PTOBDLogger.shared.ptLog("⚠️ [认证] 发现标准设备，无需 YMOBD 握手，优雅降级！")
                if let authIndex = initQueue.firstIndex(of: "<AUTH>") { initQueue[authIndex] = "ATRV" }
                currentQueueIndex += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.sendNextCommand() }
                return
            }
            
            // 提取信息与加密种子
            let lines = response.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if lines.count > 0 { PTMotoTelemetryManager.shared.obdInfo.moudleInfo.company = lines[0] }
            for line in lines {
                let parts = line.components(separatedBy: ":")
                guard parts.count >= 2 else { continue }
                let key = parts[0].lowercased().trimmingCharacters(in: .whitespaces)
                let value = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
                
                if key == "version" { PTMotoTelemetryManager.shared.obdInfo.moudleInfo.version = value }
                else if key == "device type" { PTMotoTelemetryManager.shared.obdInfo.moudleInfo.deviceType = value }
                else if key == "device name" { PTMotoTelemetryManager.shared.obdInfo.moudleInfo.deviceName = value }
                else if key == "device mac" { PTMotoTelemetryManager.shared.obdInfo.moudleInfo.deviceMac = value.uppercased() }
                else if key == "interface" { PTMotoTelemetryManager.shared.obdInfo.moudleInfo.interfase = value }
                else if key == "cust id" { PTMotoTelemetryManager.shared.obdInfo.moudleInfo.cust = value }
            }

            var cryptSeed = ""
            if let regex = try? NSRegularExpression(pattern: "(?im)^\\s*crypt\\s*:\\s*([0-9a-f]{1,8})") {
                let nsString = response as NSString
                if let match = regex.matches(in: response, range: NSRange(location: 0, length: nsString.length)).first {
                    cryptSeed = String(nsString.substring(with: match.range(at: 1)).filter { "0123456789abcdefABCDEF".contains($0) })
                }
            }
            
            let authCommand = !cryptSeed.isEmpty ? YmobdCrypt.setCryptCommand(cryptFromVersion: cryptSeed) : YmobdCrypt.challengeCommand(challenge: YmobdCrypt.newChallenge())
            if let authIndex = initQueue.firstIndex(of: "<AUTH>") {
                initQueue[authIndex] = authCommand.replacingOccurrences(of: "\r", with: "")
            }
        }
        
        if cmd == "0100" || cmd == "0120" || cmd == "0140" { collectedPIDResponses.append(response) }
                
        currentQueueIndex += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.sendNextCommand() }
    }
}

public class PTWifiOBDConnector: PTOBDTransportBase {
    public static let shared = PTWifiOBDConnector()
    
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.ptools.wifiOBDQueue")
    
    public var targetIP: String = "192.168.0.10"
    public var targetPort: UInt16 = 35000
    
    // 🌟 1. 重写物理发送方法
    override func writeRawData(_ command: String) {
        guard let data = "\(command)\r".data(using: .ascii) else { return }
        connection?.send(content: data, completion: .contentProcessed({ error in
            if let err = error { PTOBDLogger.shared.ptLog("❌ [TX WIFI] 发送失败: \(err)") }
        }))
    }
    
    // 🌟 2. 重写强制断开方法
    override func dropPhysicalConnection() {
        self.disconnect()
    }
    
    public func startConnection() {
        PTOBDLogger.shared.startFileLogging()
        PTOBDLogger.shared.ptLog("🔄 [WIFI] 开始连接: \(targetIP):\(targetPort)")
        
        let host = NWEndpoint.Host(targetIP)
        let port = NWEndpoint.Port(rawValue: targetPort)!
        connection = NWConnection(host: host, port: port, using: .tcp)
        
        connection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                PTOBDLogger.shared.ptLog("✅ [WIFI] 通道建立成功！启动接收流与状态机...")
                self.startReceiveLoop()
                self.resetAndStartStateMachine() // 呼叫基类干活！
            case .failed(let error):
                self.disconnect(error: error)
            case .cancelled:
                self.disconnect(error: nil)
            default: break
            }
        }
        connection?.start(queue: queue)
    }
    
    public func disconnect(error: Error? = nil) {
        connection?.cancel()
        connection = nil
        isUnlocked = false
        if let err = error { responseContinuation?.resume(throwing: err) }
        else { responseContinuation?.resume(throwing: NSError(domain: "WIFIError", code: -2, userInfo: [NSLocalizedDescriptionKey: "WIFI 断开"])) }
        responseContinuation = nil
        PTOBDLogger.shared.stopFileLogging()
        NotificationCenter.default.post(name: NSNotification.Name("PTMotoOBDDisconnected"), object: nil)
    }
    
    private func startReceiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            if let err = error { self.disconnect(error: err); return }
            
            if let data = data, let chunk = String(data: data, encoding: .ascii) {
                self.handleIncomingChunk(chunk, sourceName: "WIFI") // 把碎片直接扔给基类组装！
            }
            if isComplete { self.disconnect(); return }
            self.startReceiveLoop()
        }
    }
}

public class PTHiddenOBDConnector: PTOBDTransportBase {
    public static let shared = PTHiddenOBDConnector()
    
    private var centralManager: CBCentralManager!
    public var obdPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    
    private var pendingConnection: Bool = false
    private let allowedDeviceNames: Set<String> = [ "OBDII", "MS310", "B25", "V500", "YM529", "YM329", "YM129", "YM819", "BT529" ]
    
    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    // 重写物理发送方法
    override func writeRawData(_ command: String) {
        guard let writeChar = self.writeCharacteristic,
              let data = "\(command)\r".data(using: .ascii),
              let peripheral = self.obdPeripheral else { return }
        
        let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: writeChar, type: writeType)
    }
    
    // 重写强制断开方法
    override func dropPhysicalConnection() {
        if let p = self.obdPeripheral { centralManager.cancelPeripheralConnection(p) }
    }
    
    public func startIcebreakerConnection() {
        guard centralManager.state == .poweredOn else {
            pendingConnection = true; return
        }
        PTOBDLogger.shared.startFileLogging()
        PTOBDLogger.shared.ptLog("🔄 [BLE] 开始扫描...")
        pendingConnection = false
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }
}

extension PTHiddenOBDConnector: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && pendingConnection { startIcebreakerConnection() }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        if allowedDeviceNames.contains(deviceName) {
            centralManager.stopScan()
            self.obdPeripheral = peripheral
            self.obdPeripheral?.delegate = self
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB")])
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isUnlocked = false
        responseContinuation?.resume(throwing: NSError(domain: "BLEError", code: -2, userInfo: [NSLocalizedDescriptionKey: "蓝牙断开"]))
        responseContinuation = nil
        PTOBDLogger.shared.stopFileLogging()
        NotificationCenter.default.post(name: NSNotification.Name("PTMotoOBDDisconnected"), object: nil)
    }
}

extension PTHiddenOBDConnector: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: service) }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for char in service.characteristics ?? [] {
            if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                self.notifyCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            }
            if char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse) {
                self.writeCharacteristic = char
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.isNotifying {
            PTOBDLogger.shared.ptLog("🔔 [BLE] 通道就绪，启动状态机！")
            self.resetAndStartStateMachine() // 呼叫基类干活！
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let data = characteristic.value, let chunk = String(data: data, encoding: .ascii) {
            self.handleIncomingChunk(chunk, sourceName: "BLE") // 把碎片直接扔给基类组装！
        }
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
    
    private var activeConnectionType: PTOBDConnectionType = .bluetooth
    
    public private(set) var obdInfo = PTOBDInfo()
    
    internal func sendRawCommandAsync(_ command: String) async throws -> String {
        switch activeConnectionType {
        case .bluetooth:
            return try await PTHiddenOBDConnector.shared.sendOBDCommandAsync(command)
        case .wifi:
            return try await PTWifiOBDConnector.shared.sendOBDCommandAsync(command)
        }
    }

    private class WeakDelegateWrapper {
        weak var delegate: PTMotoTelemetryDelegate?
        init(_ delegate: PTMotoTelemetryDelegate) { self.delegate = delegate }
    }
    private var delegates: [WeakDelegateWrapper] = []
    
    public private(set) var isConnected: Bool = false
    public private(set) var currentRPM: Double = 0.0
    public private(set) var currentSpeed: Double = 0.0
    
    private var telemetryPollingTask: Task<Void, Never>?
    
    private var customParsers: [String: (_ pureResponse: String) -> Any?] = [:]
    // 🌟 热插拔 API：向系统注册你自己的私有探针！
    public func registerCustomPollingCommand(commandHex: String, parser: @escaping (_ pureResponse: String) -> Any?) {
        let cleanCommand = commandHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        customParsers[cleanCommand] = parser
        PTOBDLogger.shared.ptLog("🔌 [热插拔] 成功注册自定义实时轮询指令: \(cleanCommand)")
    }
    
    // 如果你想取消注册
    public func removeCustomPollingCommand(commandHex: String) {
        let cleanCommand = commandHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        customParsers.removeValue(forKey: cleanCommand)
    }

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
    
    public func connectToMotorcycle(via type: PTOBDConnectionType = .bluetooth, engineType: PTEngineType = .ice) {
        PTOBDLogger.shared.ptLog("📡 [OBD2 纯血引擎] 开始连接，模式: \(type)")
        self.obdInfo.engineType = engineType // 保存动力配置
        self.activeConnectionType = type
        
        switch type {
        case .bluetooth:
            PTHiddenOBDConnector.shared.onIceBroken = { [weak self] in
                self?.handleIceBroken(rawPIDs: PTHiddenOBDConnector.shared.collectedPIDResponses)
            }
            PTHiddenOBDConnector.shared.startIcebreakerConnection()
            
        case .wifi(let ip, let port):
            PTWifiOBDConnector.shared.targetIP = ip
            PTWifiOBDConnector.shared.targetPort = port
            PTWifiOBDConnector.shared.onIceBroken = { [weak self] in
                self?.handleIceBroken(rawPIDs: PTWifiOBDConnector.shared.collectedPIDResponses)
            }
            PTWifiOBDConnector.shared.startConnection()
        }
    }
    
    private func handleIceBroken(rawPIDs: [String]) {
        self.isConnected = true
        PTOBDLogger.shared.ptLog("✅ [Manager] 底层通知破冰完毕，移交轮询控制权！")
        self.startLightweightPolling(rawPIDs: rawPIDs)
    }

    // MARK: - 极简轮询引擎 (全频段动态提取 + 核心加权狂闪版)
    private func startLightweightPolling(rawPIDs: [String]) {
        telemetryPollingTask?.cancel()
        
        telemetryPollingTask = Task { [weak self] in
            guard let self = self else { return }
            
            // 动态解析所有车辆支持的 PID
            let parsedPIDs = self.parseAllPIDs(rawResponses: rawPIDs)
            guard !parsedPIDs.isEmpty else {
                PTOBDLogger.shared.ptLog("❌ [轮询引擎] 探针解析全 0，主动断开！")
                await MainActor.run { self.disconnect() }
                return
            }
            
            await self.autoDetectEngineType(supportedHexPIDs: parsedPIDs)
            
            // 2. 构建包含基础电压的动态总表
            var allDynamicCommands = parsedPIDs
            if self.obdInfo.engineType == .ev {
                PTOBDLogger.shared.ptLog("🔋 [EV 模式] 识别为纯电动车，启动总线带宽净化机制...")
                // 剔除纯电车绝对没有的燃油属性探针：
                // 0105(水温), 010A(燃油压力), 010E(点火提前角), 0110(MAF空气流量), 0114-011B(氧传感器) 等
                let iceOnlyPIDs = [
                    "0105", "0106", "0107", "0108", "0109", "010A", "010B", "010E", "0110",
                    "0114", "0115", "0116", "0117", "0118", "0119", "011A", "011B", "013C",
                    "013D", "013E", "013F", "015E","0151"
                ]
                allDynamicCommands.removeAll { iceOnlyPIDs.contains($0) }
                PTOBDLogger.shared.ptLog("🔋 [EV 模式] 净化完毕！剔除了无用探针，将 100% 算力集中于电控系统。")
            }

            if !allDynamicCommands.contains("ATRV") {
                allDynamicCommands.append("ATRV")
            }
            
            allDynamicCommands.append(contentsOf: self.customParsers.keys)
            
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
                        let response = try await self.sendRawCommandAsync(commandString)
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
    private func parseSingleResponse(command: String, response: String) -> Any? {
        // 只保留 0-9 和 A-F，彻底粉碎所有的空格、回车、甚至是不可见的 \0 (Null Byte)！
        let hexValid = "0123456789ABCDEF"
        let pureResponse = response.uppercased().filter { hexValid.contains($0) }
        let pureCommand = command.uppercased().filter { hexValid.contains($0) }
        
        // 为 ATRV 开辟专属“绿色通道”
        if pureCommand == "ATRV" || command.uppercased().contains("ATRV") {
            // 电压含有小数点，单独提纯
            let voltStr = response.uppercased().replacingOccurrences(of: "V", with: "").filter { "0123456789.".contains($0) }
            return Double(voltStr)
        }
        
        // 如果这个指令是你手动注册的，直接把纯净回传丢给你的闭包处理，然后潇洒返回！
        if let customParser = customParsers[pureCommand] {
            return customParser(pureResponse)
        }

        // 确保指令前缀合法且长度足够
        guard (pureCommand.hasPrefix("01") || pureCommand.hasPrefix("02")) && pureCommand.count >= 4 else {
            PTOBDLogger.shared.ptLog("❌ 拦截：指令格式不合法 -> [\(pureCommand)]")
            return nil
        }
        
        // 3. 提取预期报头，例如 "010C" -> "410C"
        let modeAndPID = String(pureCommand.prefix(4))
        let modeStr = String(modeAndPID.prefix(2))     // 提取出 "01"
        let pidHex = String(modeAndPID.suffix(2))      // 提取出 "0C"

        // 拼接预期前缀 (41 + 0C = 410C)
        let expectedMode = modeStr == "01" ? "41" : "42"
        let expectedPrefix = expectedMode + pidHex
        
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
        let C = getByte(at: 2)
        let D = getByte(at: 3)

        // 使用纯净的 4 位指令进行 Switch，彻底打通数据通路！
        var parsedValue: Any? = nil
                
        //
        switch modeAndPID {
        case "0101":
            if let a = A, let b = B, let c = C, let d = D {
                // 将 Double 转回 Int 以进行位运算
                let aInt = Int(a)
                let bInt = Int(b)
                let cInt = Int(c)
                let dInt = Int(d)
                
                // 【Byte A】：Bit 7 是 MIL，Bit 0-6 是故障码数量
                let milOn = (aInt & 0x80) != 0       // 1000 0000 掩码提取第 7 位
                let count = (aInt & 0x7F)            // 0111 1111 掩码提取低 7 位
                
                // 【Byte B】：连续监控系统
                // 支持位 (Supported): Bit 0, 1, 2
                let misfireSup = (bInt & 0x01) != 0
                let fuelSup    = (bInt & 0x02) != 0
                let compSup    = (bInt & 0x04) != 0
                // 就绪位 (Ready): Bit 4, 5, 6 (在 OBD 标准中，0 代表就绪，1 代表未就绪)
                let misfireRdy = (bInt & 0x10) == 0
                let fuelRdy    = (bInt & 0x20) == 0
                let compRdy    = (bInt & 0x40) == 0
                
                // 【Byte C & D】：非连续监控系统 (以汽油机标准为例)
                // 支持位 (Byte C 的 Bit 0, Bit 5, Bit 7)
                let catSup = (cInt & 0x01) != 0 // 催化器
                let o2Sup  = (cInt & 0x20) != 0 // 氧传感器
                let egrSup = (cInt & 0x80) != 0 // EGR
                // 就绪位 (Byte D 的 Bit 0, Bit 5, Bit 7)
                let catRdy = (dInt & 0x01) == 0
                let o2Rdy  = (dInt & 0x20) == 0
                let egrRdy = (dInt & 0x80) == 0
                
                let status = PTVehicleStatus0101(
                    isMILOn: milOn, dtcCount: count,
                    misfireSupported: misfireSup, misfireReady: misfireRdy,
                    fuelSystemSupported: fuelSup, fuelSystemReady: fuelRdy,
                    componentsSupported: compSup, componentsReady: compRdy,
                    catalystSupported: catSup, catalystReady: catRdy,
                    o2SensorSupported: o2Sup, o2SensorReady: o2Rdy,
                    egrSupported: egrSup, egrReady: egrRdy
                )
                parsedValue = status
            }
        case "010C": // RPM 转速
            if let a = A, let b = B { parsedValue = (a * 256.0 + b) / 4.0 }
        case "010D": // Vehicle Speed 车速
            if let a = A { parsedValue = a }
        case "0151": // 🌟 新增：燃料类型解析
            if let a = A {
                let fuelTypeInt = Int(a)
                parsedValue = PTFuelType(rawValue: fuelTypeInt) ?? .unknown
            }
        case "0104", "0111", "0145", "014C", "0152", "015A", "015B": // 各种百分比 (节气门, 引擎负载等)
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
        case "0103", "0113", "011C", "0141": // 状态/协议/掩码类数据
            if let a = A { parsedValue = a }
        case "0100", "0120", "0140", "0160": // PID 支持探针 (本身不是 Double 测量值，给个占位符防止报错)
            parsedValue = 1.0
        default:
            PTOBDLogger.shared.ptLog("⚠️ 未适配计算公式: \(modeAndPID)")
        }
        
        if let val = parsedValue {
//            PTOBDLogger.shared.ptLog("🏎️ [解析成功] \(modeAndPID) -> \(val)")
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
        telemetryPollingTask?.cancel()
        isConnected = false
        obdInfo.supportCommand = []
        delegates.forEach { $0.delegate?.telemetryManager(self, didChangeConnectionState: false) }
        PTOBDLogger.shared.stopFileLogging()
    }
    
    public func clearDiagnosticTroubleCodes() async -> Bool {
        guard isConnected else { return false }
        do {
            let response = try await self.sendRawCommandAsync("04")
            let cleanResponse = self.clearString(response: response)
            if cleanResponse.hasPrefix("44") || cleanResponse.contains("OK") { return true }
            else { return false }
        } catch { return false }
    }
}

extension PTMotoTelemetryManager {
    
    // MARK: - 🚀 Mode 3: 获取车辆故障码 (DTCs)
    public func getConfirmedDTCs() async -> [PTTroubleCode] {
        return await fetchDTCs(command: "03", expectedHeader: "43")
    }
    
    /// 2. 获取待定/偶发故障码 (潜伏期，尚未亮灯) - Mode 7
    public func getPendingDTCs() async -> [PTTroubleCode] {
        return await fetchDTCs(command: "07", expectedHeader: "47")
    }
    
    /// 3. 获取永久故障码 (无法手动清除，必须修复硬件) - Mode A (0A)
    public func getPermanentDTCs() async -> [PTTroubleCode] {
        return await fetchDTCs(command: "0A", expectedHeader: "4A")
    }

    private func fetchDTCs(command: String, expectedHeader: String) async -> [PTTroubleCode] {
        guard isConnected else { return [] }
        do {
            let response = try await self.sendRawCommandAsync(command)
            let purePayload = PTMultiFrameParser.extractPureHexPayload(response: response)
            
            // 找到对应的成功响应头
            guard let range = purePayload.range(of: expectedHeader) else { return [] }
            let dtcData = String(purePayload[range.upperBound...])
            
            var dtcs: [PTTroubleCode] = []
            var i = dtcData.startIndex
            
            while i < dtcData.endIndex {
                let nextI = dtcData.index(i, offsetBy: 4, limitedBy: dtcData.endIndex) ?? dtcData.endIndex
                if dtcData.distance(from: i, to: nextI) == 4 {
                    let dtcHex = String(dtcData[i..<nextI])
                    if dtcHex != "0000" { // 0000 是 ECU 凑数用的空码
                        if let parsedCode = PTMultiFrameParser.decodeSingleDTC(dtcHex) {
                            let detailedDTC = PTDTCManager.getTroubleCodeDetails(for: parsedCode)
                            dtcs.append(detailedDTC)
                            PTOBDLogger.shared.ptLog("⚠️ [Mode \(command) 异常] 发现故障码: \(parsedCode)")
                        }
                    }
                }
                i = nextI
            }
            return dtcs
        } catch { return [] }
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
                let response = try await self.sendRawCommandAsync(currentMid)
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
                let response = try await self.sendRawCommandAsync(hexCommand)
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
    
    // MARK: - 📸 高阶诊断：抓取冻结帧数据 (Mode 2)
    /// 传入想要查询的 PID (例如 "0C" 查转速)，获取故障发生那一刻的数据
    public func getFreezeFrameData(forPID pidHex: String, frameNumber: String = "00") async -> Double? {
        guard isConnected else { return nil }
        
        // 拼接指令：例如 02 0C 00
        let safePid = pidHex.uppercased().filter { "0123456789ABCDEF".contains($0) }
        guard safePid.count == 2 else { return nil }
        
        let command = "02" + safePid + frameNumber
        
        do {
            let response = try await self.sendRawCommandAsync(command)
            let cleanResponse = self.clearString(response: response)
            
            if cleanResponse.contains("NODATA") || cleanResponse.contains("ERROR") {
                return nil // 说明没有故障，或者这个 PID 没有被冻结记录
            }
            
            // 丢给双模无敌装甲解析器
            let val = self.parseSingleResponse(command: command, response: response)
            if let v = val as? Double {
                PTOBDLogger.shared.ptLog("📸 [冻结帧快照] 捕获 PID:\(safePid) 故障时数据 -> \(v)")
                return v
            } else {
                return nil
            }
        } catch { return nil }
    }
}

extension PTMotoTelemetryManager {
    
    // MARK: - 🎛️ Mode 8: 双向控制与执行器测试 (Bi-Directional Control)
    
    /// 执行车辆硬件系统测试
    /// - Parameter command: Mode 8 的执行指令
    /// - Returns: Bool 表示 ECU 是否接受并成功执行了该指令
    public func executeSystemTest(command: OBDCommand.Mode8) async -> Bool {
        guard isConnected else { return false }
        
        let hexCommand = command.properties.command // 例如 "0801"
        PTOBDLogger.shared.ptLog("⚠️ [Mode 8] 准备执行双向控制硬件测试: \(command.properties.description) (\(hexCommand))")
        
        // 🌟 1. 挂起当前的轮询引擎！绝对不能让 10ms 的数据流打断硬件测试！
        let wasPolling = (self.telemetryPollingTask != nil)
        if wasPolling {
            PTOBDLogger.shared.ptLog("⏸️ [Mode 8] 正在挂起高频轮询引擎...")
            self.telemetryPollingTask?.cancel()
            self.telemetryPollingTask = nil
            // 稍作休眠，等待总线上最后一条常规指令处理完毕
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        var isTestSuccessful = false
        
        do {
            // 🌟 2. 发送 Mode 8 执行指令
            let response = try await self.sendRawCommandAsync(hexCommand)
            let purePayload = PTMultiFrameParser.extractPureHexPayload(response: response)
            
            // 🌟 3. 验证执行结果
            // Mode 8 的成功响应头必定是 "48" 加上 PID (例如请求 0801，成功返回 4801)
            let expectedHeader = "48" + hexCommand.dropFirst(2)
            
            if purePayload.contains(expectedHeader) {
                PTOBDLogger.shared.ptLog("✅ [Mode 8] 测试命令已被 ECU 接受并成功执行！")
                isTestSuccessful = true
            } else if purePayload.contains("7F") {
                // 7F 是 OBD2 的否定响应 (Negative Response)
                PTOBDLogger.shared.ptLog("❌ [Mode 8] 被 ECU 拒绝。可能原因：引擎未熄火、车速不为零或该模块不支持被外部唤醒。原始回传: \(purePayload)")
                isTestSuccessful = false
            } else {
                PTOBDLogger.shared.ptLog("❌ [Mode 8] 执行失败或设备不支持。回传: \(purePayload)")
                isTestSuccessful = false
            }
        } catch {
            PTOBDLogger.shared.ptLog("❌ [Mode 8] 指令发送发生异常: \(error)")
            isTestSuccessful = false
        }
        
        // 🌟 4. 无论测试成功还是失败，都必须恢复被挂起的轮询引擎
        if wasPolling {
            PTOBDLogger.shared.ptLog("▶️ [Mode 8] 测试结束，恢复高频轮询引擎...")
            // 取出之前缓存的支持的 PID，重新启动轻量级轮询
            let rawPIDsToResume = PTHiddenOBDConnector.shared.collectedPIDResponses.isEmpty ? PTWifiOBDConnector.shared.collectedPIDResponses : PTHiddenOBDConnector.shared.collectedPIDResponses
            self.startLightweightPolling(rawPIDs: rawPIDsToResume)
        }
        
        return isTestSuccessful
    }
}

extension PTMotoTelemetryManager {
    
    // MARK: - 🥷 UDS 统一诊断服务 / 原生指令注入通道
    
    /// 发送任意原生的十六进制指令 (如 UDS 的 Service $22, $27, $2E，或 AT 嗅探指令)
    /// - Parameters:
    ///   - rawHex: 原生十六进制字符串 (例如 "22F190" 读取车辆特定 VIN，或 "ATMA" 启动总线监听)
    ///   - requiresPause: 发送该指令时是否需要挂起后台的高频轮询引擎 (通常 UDS 或刷写指令必须独占总线)
    /// - Returns: 未经业务层过滤的绝对原始底层回传字符串
    public func injectRawHexCommand(_ rawHex: String, requiresPause: Bool = true) async -> String {
        guard isConnected else { return "ERROR: NO_CONNECTION" }
        
        let cleanHex = rawHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        PTOBDLogger.shared.ptLog("🥷 [原生注入] 准备向总线发射深度指令: \(cleanHex)")
        
        let wasPolling = (self.telemetryPollingTask != nil)
        
        //  如果需要独占总线，挂起轮询引擎
        if requiresPause && wasPolling {
            PTOBDLogger.shared.ptLog("⏸️ [原生注入] 正在挂起轮询引擎以保障总线带宽...")
            self.telemetryPollingTask?.cancel()
            self.telemetryPollingTask = nil
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        var rawResponse = ""
        
        // 直接透过我们封装好的多模网络层发向底层硬件
        do {
            let response = try await self.sendRawCommandAsync(cleanHex)
            // 拿到绝对纯粹的底层返回，保留所有可能包含私有协议格式的字符
            rawResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
            PTOBDLogger.shared.ptLog("✅ [原生注入] 收到底层原始响应: \(rawResponse)")
            
        } catch {
            rawResponse = "ERROR: \(error.localizedDescription)"
            PTOBDLogger.shared.ptLog("❌ [原生注入] 发送发生异常: \(error)")
        }
        
        // 释放总线，恢复日常生命体征监测
        if requiresPause && wasPolling {
            PTOBDLogger.shared.ptLog("▶️ [原生注入] 注入完毕，恢复轮询引擎...")
            let rawPIDsToResume = PTHiddenOBDConnector.shared.collectedPIDResponses.isEmpty ? PTWifiOBDConnector.shared.collectedPIDResponses : PTHiddenOBDConnector.shared.collectedPIDResponses
            self.startLightweightPolling(rawPIDs: rawPIDsToResume)
        }
        
        return rawResponse
    }
    
    // MARK: - 🥷 UDS 私有协议探针 (特定 ECU 数据窃取)
    
    /// 向特定的 ECU 节点发送私有指令并捕获返回值
    /// - Parameters:
    ///   - header: 目标 ECU 的发送报头 (例如: "7E0" 代表发动机, "7A0" 代表某些仪表)
    ///   - receiveAddress: 期望接收响应的 ECU 报头 (例如: "7E8")
    ///   - udsCommand: 原生 UDS 指令 (例如 "22F190" 读取私有 VIN)
    /// - Returns: 目标 ECU 返回的绝对原始底层字符串
    public func fetchProprietaryData(header: String, receiveAddress: String, udsCommand: String) async -> String {
        guard isConnected else { return "ERROR: NO_CONNECTION" }
        
        let cleanHeader = header.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanCRA = receiveAddress.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanCommand = udsCommand.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        PTOBDLogger.shared.ptLog("🥷 [私有探针] 目标: \(cleanHeader) | 监听: \(cleanCRA) | 指令: \(cleanCommand)")
        
        // 1. 统一挂起常规轮询，霸占总线绝对控制权
        let wasPolling = (self.telemetryPollingTask != nil)
        if wasPolling {
            PTOBDLogger.shared.ptLog("⏸️ [私有探针] 霸占总线，挂起常规轮询...")
            self.telemetryPollingTask?.cancel()
            self.telemetryPollingTask = nil
            // 确保总线安静下来
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        var finalResult = ""
        
        do {
            // 2. 更改 ELM327 发送地址 (Set Header)
            _ = try await self.sendRawCommandAsync("ATSH\(cleanHeader)")
            
            // 3. 设置严格的接收过滤器 (CAN Receive Address)，防止收到总线垃圾信息
            _ = try await self.sendRawCommandAsync("ATCRA\(cleanCRA)")
            
            // 4. 发射真正的 UDS 探针，并捕获回传
            let response = try await self.sendRawCommandAsync(cleanCommand)
            finalResult = response.trimmingCharacters(in: .whitespacesAndNewlines)
            PTOBDLogger.shared.ptLog("✅ [私有探针] 截获目标返回: \(finalResult)")
            
        } catch {
            finalResult = "ERROR: \(error.localizedDescription)"
            PTOBDLogger.shared.ptLog("❌ [私有探针] 渗透失败: \(error)")
        }
        
        // 5. 🧹 打扫战场 (极其关键！)
        PTOBDLogger.shared.ptLog("🧹 [私有探针] 清洗配置，恢复标准 OBD2 通道...")
        // ATD: 恢复 ELM327 所有出厂设置 (寻址变回标准的 7DF)
        _ = try? await self.sendRawCommandAsync("ATD")
        // 由于 ATD 会打开回显等功能，我们需要重新补发破冰船中的环境配置
        _ = try? await self.sendRawCommandAsync("ATE0") // 关闭回显
        _ = try? await self.sendRawCommandAsync("ATL0") // 关闭换行符
        _ = try? await self.sendRawCommandAsync("ATH1") // 开启报头 (无敌解析器依赖 410C 这样的报头)
        
        // 6. 归还总线，恢复日常生命体征监测
        if wasPolling {
            PTOBDLogger.shared.ptLog("▶️ [私有探针] 总线归还，重新启动日常监测。")
            let rawPIDsToResume = PTHiddenOBDConnector.shared.collectedPIDResponses.isEmpty ? PTWifiOBDConnector.shared.collectedPIDResponses : PTHiddenOBDConnector.shared.collectedPIDResponses
            self.startLightweightPolling(rawPIDs: rawPIDsToResume)
        }
        
        return finalResult
    }
}

extension PTMotoTelemetryManager {
    
    // MARK: - 🕵️‍♂️ 黑客工具：CAN 总线全域嗅探 (Sniffer Mode)
    
    /// 启动 CAN 总线抓包模式 (需要配合 Y 型分线器和原厂诊断仪使用)
    /// - Parameter filterHeader: 可选。如果只关心某个 ECU (例如仪表盘 "7A0")，传入该报头可防止 ELM327 缓冲区溢出。传 nil 则监听全车。
    public func startCANSniperMode(filterHeader: String? = nil) async {
        guard isConnected else { return }
        
        PTOBDLogger.shared.ptLog("🕵️‍♂️ [嗅探系统] 警告：正在进入总线监听模式！")
        
        // 1. 彻底挂起后台轮询，防止我们的指令污染抓包现场
        if telemetryPollingTask != nil {
            self.telemetryPollingTask?.cancel()
            self.telemetryPollingTask = nil
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        
        do {
            // 2. 配置 ELM327 为黑客窃听状态
            _ = try await self.sendRawCommandAsync("ATZ")   // 复位
            _ = try await self.sendRawCommandAsync("ATE0")  // 关闭回显
            _ = try await self.sendRawCommandAsync("ATL1")  // 开启换行符 (瀑布流必须)
            _ = try await self.sendRawCommandAsync("ATH1")  // 🌟 开启报头显示 (抓包最核心：必须知道是谁发的！)
            _ = try await self.sendRawCommandAsync("ATS1")  // 🌟 开启空格显示 (让字节之间有空格，极大地提高人类阅读体验)
            _ = try await self.sendRawCommandAsync("ATAL")  // 允许长度超过 7 字节的长报文
            
            // 3. (可选) 设置监听过滤器
            if let target = filterHeader {
                let cleanTarget = target.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await self.sendRawCommandAsync("ATCRA" + cleanTarget)
                PTOBDLogger.shared.ptLog("🎯 [嗅探系统] 过滤器已激活，仅监听地址: \(cleanTarget)")
            }
            
            // 4. 拨下开关，进入瀑布流模式！
            // 注意：底层的 isSnifferMode 必须在发 ATMA 之前设置为 true
            switch activeConnectionType {
            case .bluetooth:
                PTHiddenOBDConnector.shared.isSnifferMode = true
            default:
                PTWifiOBDConnector.shared.isSnifferMode = true
            }
            
            PTOBDLogger.shared.ptLog("🚀 [嗅探系统] 启动指令已发送，正在录制通讯流量，请操作原厂诊断仪...")
            
            // 发送 ATMA (Monitor All)。注意：ELM327 收到这个后就不会返回 ">" 了，直到我们打断它
            // 所以我们不等待它的 await 结果，直接使用底层对象的 writeRawData
            switch activeConnectionType {
            case .bluetooth:
                PTHiddenOBDConnector.shared.writeRawData("ATMA")
            default:
                PTWifiOBDConnector.shared.writeRawData("ATMA")
            }
        } catch {
            PTOBDLogger.shared.ptLog("❌ [嗅探系统] 启动监听失败: \(error)")
        }
    }
    
    /// 停止抓包并恢复日常监控
    public func stopCANSniperMode() async {
        guard isConnected else { return }
        
        PTOBDLogger.shared.ptLog("🛑 [嗅探系统] 正在停止抓包...")
        
        // 发送任意字符 (如空回车) 可打断 ELM327 的 ATMA 监听状态
        switch activeConnectionType {
        case .bluetooth:
            PTHiddenOBDConnector.shared.writeRawData("")
        default:
            PTWifiOBDConnector.shared.writeRawData("")
        }
        
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        // 关闭底层的瀑布流开关
        switch activeConnectionType {
        case .bluetooth:
            PTHiddenOBDConnector.shared.isSnifferMode = false
        default:
            PTWifiOBDConnector.shared.isSnifferMode = false
        }
        
        // 恢复 ELM327 出厂设置，清洗掉我们刚才的黑客配置
        _ = try? await self.sendRawCommandAsync("ATD")
        _ = try? await self.sendRawCommandAsync("ATE0")
        _ = try? await self.sendRawCommandAsync("ATL0")
        _ = try? await self.sendRawCommandAsync("ATH1")
        
        PTOBDLogger.shared.ptLog("▶️ [嗅探系统] 抓包结束，正在恢复常规轮询引擎。")
        
        let rawPIDsToResume = PTHiddenOBDConnector.shared.collectedPIDResponses.isEmpty ? PTWifiOBDConnector.shared.collectedPIDResponses : PTHiddenOBDConnector.shared.collectedPIDResponses
        self.startLightweightPolling(rawPIDs: rawPIDsToResume)
    }
}

extension PTMotoTelemetryManager {
    
    // MARK: - 🧠 智能动力类型指纹推断
    internal func autoDetectEngineType(supportedHexPIDs: [String]) async {
        PTOBDLogger.shared.ptLog("🧠 [智能推断] 开始对车辆进行动力系统侧写 (Profiling)...")
        
        // 1. 标准探针询问：如果车辆支持 0151，直接问它！
        if supportedHexPIDs.contains("0151") {
            if let response = try? await self.sendRawCommandAsync("0151"),
               let fuelObj = self.parseSingleResponse(command: "0151", response: response) as? PTFuelType {
                
                PTOBDLogger.shared.ptLog("🧠 [智能推断] 车辆通过 0151 主动坦白燃料类型: \(fuelObj.stringValue)")
                
                switch fuelObj {
                case .electric: self.obdInfo.engineType = .ev
                case .hybridGasoline, .hybridDiesel, .hybridMixed, .hybridElectric: self.obdInfo.engineType = .hybrid
                default: self.obdInfo.engineType = .ice
                }
                return // 成功拿到，直接结束推断
            }
        }
        
        // 2. 侧写指纹推断：根据支持的 PID 列表来猜
        let supportsBatteryLife = supportedHexPIDs.contains("015B")
        let supportsO2Sensors = supportedHexPIDs.contains(where: { $0.hasPrefix("0114") || $0.hasPrefix("0115") || $0 == "0113" })
        let supportsFuelPressure = supportedHexPIDs.contains("010A") || supportedHexPIDs.contains("0122")
        let supportsRPM = supportedHexPIDs.contains("010C")
        
        if supportsBatteryLife && !supportsO2Sensors && !supportsFuelPressure {
            PTOBDLogger.shared.ptLog("🧠 [智能推断] 无氧传感器 + 支持电池寿命 = 纯电动 (EV)！")
            self.obdInfo.engineType = .ev
        }
        else if supportsBatteryLife && supportsO2Sensors {
            PTOBDLogger.shared.ptLog("🧠 [智能推断] 有氧传感器 + 支持电池寿命 = 混合动力 (HEV)！")
            self.obdInfo.engineType = .hybrid
        }
        else if supportsRPM && supportsO2Sensors {
            PTOBDLogger.shared.ptLog("🧠 [智能推断] 标准油车指纹 = 燃油车 (ICE)！")
            self.obdInfo.engineType = .ice
        }
        else if supportedHexPIDs.isEmpty {
            // 3. 极端情况：硬件连上了，但全频段不支持 Mode 1，大概率是全私有协议电车
            PTOBDLogger.shared.ptLog("🧠 [智能推断] Mode 1 全盲，推测为使用私有协议的纯电车 (EV)。")
            self.obdInfo.engineType = .ev
        } else {
            PTOBDLogger.shared.ptLog("🧠 [智能推断] 无法精准定性，默认降级为 燃油车 (ICE)。")
            self.obdInfo.engineType = .ice
        }
    }
}
