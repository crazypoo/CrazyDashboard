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

// MARK: - ✂️ OBD 字符串专属公共扩展
public extension String {
    /// 提取纯净的 OBD 报文 (去除空格、换行符、>符号，并转为大写)
    var obdCleaned: String {
        return self.replacingOccurrences(of: " ", with: "")
                   .replacingOccurrences(of: ">", with: "")
                   .replacingOccurrences(of: "\r", with: "")
                   .replacingOccurrences(of: "\n", with: "")
                   .uppercased()
    }
    
    /// 仅保留十六进制有效字符 (0-9, A-F)
    var hexOnly: String {
        return self.uppercased().filter { "0123456789ABCDEF".contains($0) }
    }
}

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

// MARK: - 🌟 车辆详细档案 (VIN 解析结果)
public struct PTVINDetails {
    public let rawVIN: String       // 原始 17 位代码
    public let region: String       // 产地 (如: "法国", "中国")
    public let manufacturer: String // 厂商名称 (如: "标致 (Peugeot)")
    public let modelYear: String    // 第 10 位: 生产年份 (如: "2026")
    public let isStandardLength: Bool // 是否是标准的 17 位车架号
    
    // UI 快速展示格式
    public var summary: String {
        guard isStandardLength else { return "非标准 VIN 码 (\(rawVIN))" }
        return "[\(modelYear) 款] \(region)产 \(manufacturer)"
    }
}

// MARK: - 🌟 固件标定信息 (CAL ID 解析结果)
public struct PTCALDetails {
    public let rawString: String       // 原始字符串
    public let detectedModel: String   // 自动推断的车型 (如: "Peugeot XP400")
    public let softwareVersion: String // 提取出的软件版号 (如: "E540")
    public let isSupportedModel: Bool  // 是否是我们的 App 完美支持的车型
    
    // UI 快速展示格式
    public var summary: String {
        return "车型: \(detectedModel) | 固件版号: \(softwareVersion)"
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
    public var vin: String = "" {
        didSet {
            let cleanVIN = vin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            // 只要非空且发生改变，就立刻解析
            if !cleanVIN.isEmpty {
                self.vinDetails = self.decodeVIN(cleanVIN)
            }
        }
    }
    public var ecuVersion:String = "" {
        didSet {
            let cleanString = ecuVersion.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !cleanString.isEmpty {
                self.calDetails = self.decodeCALID(cleanString)
            }
        }
    }
    public var cvn:String = ""
    public var supportCommand:[OBDCommand] = []
    public var engineType: PTEngineType = .ice
    public var vinDetails: PTVINDetails?
    
    // MARK: - 🧠 VIN 工业标准解码引擎
    private func decodeVIN(_ raw: String) -> PTVINDetails {
        let isStandard = raw.count == 17
        
        var regionStr = "未知产地"
        var brandStr = "未知厂商"
        var yearStr = "未知年份"
        
        if isStandard {
            // 1. 提取区域 (第 1 位)
            let regionChar = raw[raw.startIndex]
            regionStr = getRegion(from: regionChar)
            
            // 2. 提取制造商 WMI (前 3 位)
            let wmiIndex = raw.index(raw.startIndex, offsetBy: 3)
            let wmi = String(raw[..<wmiIndex])
            brandStr = getManufacturer(from: wmi)
            
            // 3. 提取年份 (第 10 位，索引为 9)
            let yearCharIndex = raw.index(raw.startIndex, offsetBy: 9)
            let yearChar = raw[yearCharIndex]
            yearStr = getYear(from: yearChar)
        }
        
        return PTVINDetails(
            rawVIN: raw,
            region: regionStr,
            manufacturer: brandStr,
            modelYear: yearStr,
            isStandardLength: isStandard
        )
    }
    
    // MARK: - 私有字典与映射方法
    
    private func getRegion(from char: Character) -> String {
        let regionMap: [Character: String] = [
            "1": "美国", "2": "加拿大", "3": "墨西哥", "4": "美国", "5": "美国",
            "J": "日本", "K": "韩国", "L": "中国", "M": "印度",
            "S": "英国", "T": "瑞士", "V": "法国", "W": "德国", "Z": "意大利"
        ]
        return regionMap[char] ?? "其他区域"
    }
    
    private func getManufacturer(from wmi: String) -> String {
        // 汽车工业 WMI 常见映射 (这里仅做部分常用演示，你可以随时扩充)
        if wmi.hasPrefix("VF3") { return "标致 (Peugeot)" }
        if wmi.hasPrefix("WBA") { return "宝马 (BMW)" }
        if wmi.hasPrefix("WDC") { return "戴姆勒-奔驰 (Mercedes-Benz)" }
        if wmi.hasPrefix("WP0") { return "保时捷 (Porsche)" }
        if wmi.hasPrefix("JT")  { return "丰田 (Toyota)" }
        if wmi.hasPrefix("JH")  { return "本田 (Honda)" }
        if wmi.hasPrefix("LSV") { return "上汽大众" }
        if wmi.hasPrefix("LSG") { return "上汽通用" }
        if wmi.hasPrefix("LRW") { return "特斯拉中国 (Tesla)" }
        
        return "代码: \(wmi)"
    }
    
    private func getYear(from char: Character) -> String {
        // ISO 3779 标准的第 10 位年份映射表 (2010 年之后)
        // 标准中不使用字母 I, O, Q, U, Z 以及数字 0
        let yearMap: [Character: String] = [
            "A": "2010", "B": "2011", "C": "2012", "D": "2013", "E": "2014",
            "F": "2015", "G": "2016", "H": "2017", "J": "2018", "K": "2019",
            "L": "2020", "M": "2021", "N": "2022", "P": "2023", "R": "2024",
            "S": "2025", "T": "2026", "V": "2027", "W": "2028", "X": "2029"
        ]
        return yearMap[char] ?? "2009或更早/未知"
    }
    
    public var calDetails: PTCALDetails?
    // MARK: - 🧠 固件标定信息解码大脑
    private func decodeCALID(_ raw: String) -> PTCALDetails {
        var model = "未知车型"
        var isSupported = false
        var swVersion = "未知版本"
        
        // 1. 自动嗅探 Peugeot XP40 系列
        if raw.contains("XP40") {
            model = "Peugeot XP400 GT"
            isSupported = true
            
            // 2. 提取核心软件版本号 (通常紧跟在车型代号后面)
            if let range = raw.range(of: "XP40") {
                let suffix = String(raw[range.upperBound...])
                // 提取开头的 4 个字符作为版本号 (例如 "E540")
                if suffix.count >= 4 {
                    swVersion = String(suffix.prefix(4))
                } else {
                    swVersion = suffix
                }
            }
        }        
        return PTCALDetails(
            rawString: raw,
            detectedModel: model,
            softwareVersion: swVersion,
            isSupportedModel: isSupported
        )
    }
}

public class PTMultiFrameParser {
    /// 🌟 提取纯净十六进制数据：专门用于剥离 CAN 报头 (支持 11-bit 和 29-bit CAN)
    public static func extractPureHexPayload(response: String) -> String {
        let lines = response.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && $0 != ">" }
        
        var hexPayload = ""
        for line in lines {
            // 提取纯大写的 Hex 字符
            let cleanLine = line.uppercased().filter { "0123456789ABCDEF".contains($0) }
            guard cleanLine.count > 4 else { continue }
            
            // 🛡️ 自动嗅探 CAN 报头长度 (7E8 等 11-bit 通常为 3，18DAF110 等 29-bit 通常为 8)
            var headerLength = 3
            if cleanLine.hasPrefix("18D") || cleanLine.hasPrefix("18C") {
                headerLength = 8
            } else if cleanLine.hasPrefix("7E") || cleanLine.hasPrefix("7F") {
                headerLength = 3
            } else {
                headerLength = 0 // 未知报头，默认不截断
            }
            
            if headerLength > 0 && cleanLine.count > headerLength {
                let pciIndex = cleanLine.index(cleanLine.startIndex, offsetBy: headerLength)
                let pciChar = cleanLine[pciIndex]
                
                if pciChar == "1" {
                    // 首帧 (First Frame): 报头 + PCI(1) + 长度(3) = headerLength + 4
                    let dropCount = headerLength + 4
                    if cleanLine.count > dropCount { hexPayload += cleanLine.dropFirst(dropCount) }
                } else if pciChar == "2" || pciChar == "0" {
                    // 连续帧/单帧 (Consecutive/Single): 报头 + PCI(1) + 序列号/长度(1) = headerLength + 2
                    let dropCount = headerLength + 2
                    if cleanLine.count > dropCount { hexPayload += cleanLine.dropFirst(dropCount) }
                } else {
                    hexPayload += cleanLine // PCI 不匹配，保留原样
                }
            } else {
                hexPayload += cleanLine
            }
        }
        return hexPayload
    }

    /// 🌟 剥离所有底层协议头，提取纯正的 ASCII 字符串
    public static func parseLongString(response: String) -> String {
        let hexPayload = extractPureHexPayload(response: response)
        
        // 1. 将 Hex 转为 Byte 数组
        var bytes = [UInt8]()
        var i = hexPayload.startIndex
        while i < hexPayload.endIndex {
            let nextI = hexPayload.index(i, offsetBy: 2, limitedBy: hexPayload.endIndex) ?? hexPayload.endIndex
            if let byteVal = UInt8(hexPayload[i..<nextI], radix: 16) {
                bytes.append(byteVal)
            }
            i = nextI
        }
        
        // 2. 🛡️ 核心修复：智能剔除 OBD 业务层响应头！
        // 防止 49 或 62 等控制指令被错误解析为字母
        if bytes.count >= 3 {
            if bytes[0] == 0x49 {
                // 剔除 Mode 09 的头：例如 49 04 02 -> 剩下纯文本
                bytes = Array(bytes.dropFirst(3))
            } else if bytes[0] == 0x62 {
                // 剔除 Mode 22 的头：例如 62 F1 90 -> 剩下纯文本
                bytes = Array(bytes.dropFirst(3))
            }
        }
        
        // 3. 转成 ASCII 文本
        var asciiStr = ""
        for byte in bytes {
            // 仅保留标准可见的 ASCII 字符 (32-126)，自动过滤掉所有的 \0 和奇葩乱码
            if byte >= 32 && byte <= 126 {
                asciiStr.append(Character(UnicodeScalar(byte)))
            }
        }
        
        return asciiStr.trimmingCharacters(in: .whitespaces)
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
                    PTOBDLogger.obd.ptLog("🔬 [\(testResult.componentName)] TID:\(tidHex) | 结果:\(testResult.formattedValue) (范围:\(testResult.formattedMin) ~ \(testResult.formattedMax)) | \(status)")
                }
            }
            i = nextI
        }
        return results
    }
    
    // MARK: - 🧩 ISO-TP 多行日志流自动拼装与解码引擎
    
    /// 直接传入从日志中复制或捕获的多行原始文本块，自动完成 ISO-TP 拼包并转为可读字符串
    /// - Parameter rawLogChunk: 包含多帧响应的完整文本 (支持换行分隔)
    /// - Returns: 解密并拼接完成的纯净文本
    public static func assembleAndDecodeMultiFrameLog(_ rawLogChunk: String) -> String {
        parseLongString(response: rawLogChunk)
    }
    
    // MARK: - ⚡️ 实时 ECU 电压解析器
        
    /// 从 CAN 总线原始流中精准提取 0142 的控制模块电压
    /// - Parameter hexChunk: 包含 4142 标识的十六进制字符串 (例如: "7E804414238D7")
    /// - Returns: 解析后的双精度电压值 (例如: 14.55)
    public static func parseControlModuleVoltage(hexChunk: String) -> Double? {
        // 清洗掉可能的空格并统一大写
        let cleanStr = hexChunk.replacingOccurrences(of: " ", with: "").uppercased()
        
        // 确保包含 0142 的成功响应头 "4142"
        guard cleanStr.contains("4142") else { return nil }
        
        if let range = cleanStr.range(of: "4142") {
            // 截取 4142 后面的有效载荷
            let payload = String(cleanStr[range.upperBound...])
            
            // 0142 的载荷必须至少有 4 个字符 (2个字节 A 和 B)
            if payload.count >= 4 {
                let aHex = String(payload.prefix(2))
                let bHex = String(payload.dropFirst(2).prefix(2))
                
                // 将十六进制转换为整型后代入标准公式
                if let aInt = Int(aHex, radix: 16), let bInt = Int(bHex, radix: 16) {
                    let voltage = (Double(aInt) * 256.0 + Double(bInt)) / 1000.0
                    return voltage
                }
            }
        }
        
        return nil
    }
}

let developerOBDID = "C688934C-8A62-4C35-872F-B07ED5415E94"

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
    case mock
}

// MARK: - 🌟 OBD 传输核心协议基类 (负责状态机与碎片组装)
public class PTOBDTransportBase: NSObject {
    
    public var onIceBroken: (() -> Void)?
    public var onDisconnected: ((Error?) -> Void)?
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
            
            PTOBDLogger.obd.ptLog("⬆️ [TX Async] \(command)\\r")
            self.writeRawData(command) // 呼叫子类去执行物理发送
            
            // 20秒超时保护
            self.timeoutTask?.cancel()
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                if !Task.isCancelled {
                    PTOBDLogger.obd.ptLog("⏳ [TX Async] 响应超时: \(command)")
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
                        PTOBDLogger.obd.ptLog("🕵️‍♂️ [嗅探抓包] 截获报文: \(frame)")
                    }
                }
                // 保留最后一段不完整的碎片
                rxBuffer = lines.last ?? ""
            }
            return // 监听模式下，跳过后面的常规 ">" 判断逻辑
        }

        
        let displayChunk = chunk.replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
        PTOBDLogger.obd.ptLog("⬇️ [RX \(sourceName) Chunk] '\(displayChunk)'")
        
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
                PTOBDLogger.obd.ptLog("✅ [RX \(sourceName) Async] 抛出上层: \(cleanResponse)")
                responseContinuation?.resume(returning: cleanResponse)
                responseContinuation = nil
            } else {
                PTOBDLogger.obd.ptLog("✅ [RX \(sourceName) Init] 消化: \(cleanResponse)")
                processCompleteResponse(cleanResponse)
            }
        }
    }
    
    // MARK: - 🌟 共享逻辑：自动队列与硬件解密
    internal func sendNextCommand() {
        guard currentQueueIndex < initQueue.count else {
            PTOBDLogger.obd.ptLog("✅ [破冰船] 19 步硬件大满贯解锁完毕！移交控制权！")
            self.isUnlocked = true
            DispatchQueue.main.async { [weak self] in self?.onIceBroken?() }
            return
        }
        let rawCommand = initQueue[currentQueueIndex]
        activeCommand = rawCommand
        rxBuffer = ""
        PTOBDLogger.obd.ptLog("⬆️ [TX Init \(currentQueueIndex + 1)/\(initQueue.count)] \(rawCommand)\\r")
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
                PTOBDLogger.obd.ptLog("⚠️ [认证] 发现标准设备，无需 YMOBD 握手，优雅降级！")
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
                    PTMotoTelemetryManager.shared.obdInfo.moudleInfo.crypt = cryptSeed
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

public enum PTMockVehicleConfig {
    case singleECU // 单 ECU (例如常规踏板车)
    case dualECU   // 双 ECU (例如多缸复杂机车)
}

// MARK: 离线 OBD 沙盒虚拟引擎 (用于无车环境下的 UI 开发与测试)
public class PTMockOBDConnector: PTOBDTransportBase {
    public static let shared = PTMockOBDConnector()
    
    private let mockQueue = DispatchQueue(label: "com.ptools.mockOBDQueue")
    public var vehicleConfig: PTMockVehicleConfig = .dualECU
    
    private override init() { super.init() }
    
    // 重写物理发送方法，将指令发给我们的“虚拟 ECU”
    override func writeRawData(_ command: String) {
        let cleanCommand = command.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        // 模拟网络和蓝牙的物理延迟 (50 毫秒)
        mockQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            let simulatedResponse = self.generateMockResponse(for: cleanCommand)
            // 把虚拟的回传数据丢给基类去组装
            self.handleIncomingChunk(simulatedResponse, sourceName: "MOCK")
        }
    }
    
    // 重写断开连接
    override func dropPhysicalConnection() {
        self.isUnlocked = false
        if let cont = responseContinuation {
            cont.resume(throwing: NSError(domain: "MockError", code: -2, userInfo: [NSLocalizedDescriptionKey: "模拟器断开"]))
            self.responseContinuation = nil
        }
        onDisconnected?(nil)
    }
    
    // 启动模拟连接
    public func startMockConnection() {
        PTOBDLogger.obd.startFileLogging()
        PTOBDLogger.obd.ptLog("🎮 [模拟器] 正在启动离线沙盒引擎...")
        
        // 模拟 1 秒的连接耗时
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            PTOBDLogger.obd.ptLog("✅ [模拟器] 虚拟物理通道建立成功，启动状态机！")
            self?.resetAndStartStateMachine() // 呼叫基类，开始 19 步破冰！
        }
    }
    
    // MARK: - 🧠 核心：虚拟 ECU 响应大脑 (完美还原实车工况)
    private func generateMockResponse(for command: String) -> String {
        switch command {
        // 基础握手与配置
        case "ATZ", "ATD", "ATI": return "ELM327 v1.5\r\n>"
        case "ATE0", "ATL0", "ATH1", "ATS1", "ATAL", "ATSP0", "AT+SETCRYPT": return "OK\r\n>"
        case "ATDP": return "AUTO, ISO 15765-4 (CAN 11/500)\r\n>"
        case "AT+VERSION": return "Company: PTools Mock Engine\r\nVersion: V1.0.0\r\n>"
            
        // 🔋 电池电压 (ATRV) -> 图中显示 14.6V
        case "ATRV": return "14.6V\r\n>"
            
        // 🌟 动态生成支持目录 (宣告支持的 PID)
        case "0100": return "7E8 06 41 00 1E 3E 10 01\r\n>" // 支持 01-20 中的关键 PID
        case "0120": return "7E8 06 41 20 80 00 00 01\r\n>" // 支持 21-40
        case "0140": return "7E8 06 41 40 48 08 00 01\r\n>" // 支持 41-60
            
        // 🌟 实况物理数据注入 (严格遵循图片数值逆向生成的报文)
        case "0101": return "7E8 06 41 01 01 00 00 00\r\n>" // Status since DTCs cleared: 1
        case "0103": return "7E8 04 41 03 02 00\r\n>"       // Fuel System Status: 2
        case "0104": return "7E8 03 41 04 59\r\n>"          // Calculated Engine Load: 35%
        case "0105": return "7E8 03 41 05 65\r\n>"          // Coolant temperature: 61°C
        case "0106": return "7E8 03 41 06 73\r\n>"          // Short Term Fuel Trim: -10%
        case "0107": return "7E8 03 41 07 80\r\n>"          // Long Term Fuel Trim: 0%
        case "010B": return "7E8 03 41 0B 23\r\n>"          // Intake Manifold Pressure: 35 kPa
        case "010E": return "7E8 03 41 0E 89\r\n>"          // Timing Advance: 4.4°
        case "010F": return "7E8 03 41 0F 59\r\n>"          // Intake Air Temp: 49°C
        case "0111": return "7E8 03 41 11 17\r\n>"          // Throttle Position: 9%
        case "0113": return "7E8 03 41 13 01\r\n>"          // O2 Sensors Present: 1
        case "0114": return "7E8 04 41 14 18 00\r\n>"       // O2: Bank 1 Sensor 1 Voltage: 0.12V
        case "011C": return "7E8 03 41 1C 06\r\n>"          // OBD Standards Compliance: 6
        case "011F": return "7E8 04 41 1F 00 32\r\n>"       // Engine Run Time: 50s
        case "0121": return "7E8 04 41 21 00 00\r\n>"       // Distance Traveled with MIL on: 0
        case "0141": return "7E8 06 41 41 00 00 00 00\r\n>" // Monitor status this drive cycle: 0
        case "0142": return "7E8 04 41 42 39 6C\r\n>"       // Control module voltage: 14.7V
        case "0145": return "7E8 03 41 45 00\r\n>"          // Relative throttle position: 0%
        case "014D": return "7E8 04 41 4D 00 00\r\n>"       // Time run with MIL on: 0
        case "0151": return "7E8 03 41 51 01\r\n>"          // 燃料类型 (1 = 汽油)
            
        case "0902":
            return "7E8 14 49 02 01 00 00 00 31 57 42 41 31 32 33 34 35 36 37 38 39 30 31 32 33\r\n>"
        case "0904": // 模拟读取 Calibration ID (固件标定号，包含 XP40 等特征)
            let chunk1 = "7E8 10 23 49 04 02 31 31 37"
            let chunk2 = "7E8 21 39 37 31 33 39 30 30"
            let chunk3 = "7E8 22 30 30 31 39 35 33 58"
            let chunk4 = "7E8 23 50 34 30 45 35 34 30"
            let chunk5 = "7E8 24 30 30 33 37 30 30 30"
            let chunk6 = "7E8 25 30 00 00 00 00 00 00"
            // 按照 ELM327 的真实换行格式进行无缝拼接
            return "\(chunk1)\r\(chunk2)\r\(chunk3)\r\(chunk4)\r\(chunk5)\r\(chunk6)\r\r>"
        // 🚀 高频动态数据 (转速与车速)
        case "010C": // Engine RPM: 1651
            let ecu1Resp = "7E8 04 41 0C 19 CC"
            if vehicleConfig == .dualECU {
                return "\(ecu1Resp)\r7E9 04 41 0C 19 68\r\n>" // 模拟辅 ECU
            }
            return "\(ecu1Resp)\r\n>"
            
        case "010D": // Vehicle Speed: 0
            return "7E8 03 41 0D 00\r\n>"
            
        default:
            if command.hasPrefix("AT") { return "OK\r\n>" }
            return "NO DATA\r\n>"
        }
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
            if let err = error { PTOBDLogger.obd.ptLog("❌ [TX WIFI] 发送失败: \(err)") }
        }))
    }
    
    // 🌟 2. 重写强制断开方法
    override func dropPhysicalConnection() {
        self.disconnect()
    }
    
    public func startConnection() {
        PTOBDLogger.obd.startFileLogging()
        PTOBDLogger.obd.ptLog("🔄 [WIFI] 开始连接: \(targetIP):\(targetPort)")
        
        let host = NWEndpoint.Host(targetIP)
        let port = NWEndpoint.Port(rawValue: targetPort)!
        connection = NWConnection(host: host, port: port, using: .tcp)
        
        connection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                PTOBDLogger.obd.ptLog("✅ [WIFI] 通道建立成功！启动接收流与状态机...")
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
        PTOBDLogger.obd.stopFileLogging()
        onDisconnected?(error)
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
        PTOBDLogger.obd.startFileLogging()
        PTOBDLogger.obd.ptLog("🔄 [BLE] 开始扫描...")
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
        PTOBDLogger.obd.stopFileLogging()
        onDisconnected?(error)
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
            PTOBDLogger.obd.ptLog("🔔 [BLE] 通道就绪，启动状态机！")
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
        case .mock:
            return try await PTMockOBDConnector.shared.sendOBDCommandAsync(command)
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
    
    public var telemetryPollingTask: Task<Void, Never>?
    
    private var customParsers: [String: (_ pureResponse: String) -> Any?] = [:]
    // 🌟 热插拔 API：向系统注册你自己的私有探针！
    public func registerCustomPollingCommand(commandHex: String, parser: @escaping (_ pureResponse: String) -> Any?) {
        let cleanCommand = commandHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        customParsers[cleanCommand] = parser
        PTOBDLogger.obd.ptLog("🔌 [热插拔] 成功注册自定义实时轮询指令: \(cleanCommand)")
    }
    
    // 如果你想取消注册
    public func removeCustomPollingCommand(commandHex: String) {
        let cleanCommand = commandHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        customParsers.removeValue(forKey: cleanCommand)
    }

    // 连接超时的回调闭包 (UI 层使用)
    public var onConnectionTimeout: (() -> Void)?
    // 超时倒计时任务句柄
    private var connectionTimeoutTask: Task<Void, Never>?

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
        PTOBDLogger.obd.ptLog("📡 [OBD2 纯血引擎] 开始连接，模式: \(type)")
        self.obdInfo.engineType = engineType // 保存动力配置
        self.activeConnectionType = type
        
        self.startConnectionTimeoutTimer()
        
        switch type {
        case .bluetooth:
            PTHiddenOBDConnector.shared.onIceBroken = { [weak self] in
                self?.handleIceBroken(rawPIDs: PTHiddenOBDConnector.shared.collectedPIDResponses)
            }
            PTHiddenOBDConnector.shared.onDisconnected = { [weak self] error in
                self?.handlePhysicalDisconnect(error: error)
            }
            PTHiddenOBDConnector.shared.startIcebreakerConnection()
            
        case .wifi(let ip, let port):
            PTWifiOBDConnector.shared.targetIP = ip
            PTWifiOBDConnector.shared.targetPort = port
            PTWifiOBDConnector.shared.onIceBroken = { [weak self] in
                self?.handleIceBroken(rawPIDs: PTWifiOBDConnector.shared.collectedPIDResponses)
            }
            PTWifiOBDConnector.shared.onDisconnected = { [weak self] error in
                self?.handlePhysicalDisconnect(error: error)
            }
            PTWifiOBDConnector.shared.startConnection()
        case .mock:
            PTMockOBDConnector.shared.onIceBroken = { [weak self] in
                // 模拟器破冰成功，将模拟器的 PID 转交上去
                self?.handleIceBroken(rawPIDs: PTMockOBDConnector.shared.collectedPIDResponses)
            }
            PTMockOBDConnector.shared.onDisconnected = { [weak self] error in
                self?.handlePhysicalDisconnect(error: error)
            }
            PTMockOBDConnector.shared.startMockConnection()
        }
    }
    
    private func handlePhysicalDisconnect(error: Error?) {
        if let err = error {
            PTOBDLogger.obd.ptLog("⚠️ [物理连接断开] 检测到硬件脱机: \(err.localizedDescription)")
        } else {
            PTOBDLogger.obd.ptLog("⚠️ [物理连接断开] 检测到硬件脱机")
        }
        
        // 保证在主线程安全地更新所有挂载了的 Delegate UI
        DispatchQueue.main.async { [weak self] in
            // 这会调用你现有的 disconnect()，里面包含了中止轮询和触发 Delegate 的完美逻辑！
            self?.disconnect()
        }
    }

    private func handleIceBroken(rawPIDs: [String]) {
        self.isConnected = true
        self.connectionTimeoutTask?.cancel()
        self.connectionTimeoutTask = nil
        PTOBDLogger.obd.ptLog("✅ [Manager] 底层通知破冰完毕，移交轮询控制权！")
        self.startLightweightPolling(rawPIDs: rawPIDs)
    }

    // MARK: - 极简轮询引擎 (全频段动态提取 + 核心加权狂闪版)
    func startLightweightPolling(rawPIDs: [String]) {
        telemetryPollingTask?.cancel()
        
        telemetryPollingTask = Task { [weak self] in
            guard let self = self else { return }
            
            // 动态解析所有车辆支持的 PID
            let parsedPIDs = self.parseAllPIDs(rawResponses: rawPIDs)
            guard !parsedPIDs.isEmpty else {
                PTOBDLogger.obd.ptLog("❌ [轮询引擎] 探针解析全 0，主动断开！")
                await MainActor.run { self.disconnect() }
                return
            }
            
            await self.autoDetectEngineType(supportedHexPIDs: parsedPIDs)
            
            // 2. 构建包含基础电压的动态总表
            var allDynamicCommands = parsedPIDs
            if self.obdInfo.engineType == .ev {
                PTOBDLogger.obd.ptLog("🔋 [EV 模式] 识别为纯电动车，启动总线带宽净化机制...")
                // 剔除纯电车绝对没有的燃油属性探针：
                // 0105(水温), 010A(燃油压力), 010E(点火提前角), 0110(MAF空气流量), 0114-011B(氧传感器) 等
                let iceOnlyPIDs = [
                    "0105", "0106", "0107", "0108", "0109", "010A", "010B", "010E", "0110",
                    "0114", "0115", "0116", "0117", "0118", "0119", "011A", "011B", "013C",
                    "013D", "013E", "013F", "015E","0151"
                ]
                allDynamicCommands.removeAll { iceOnlyPIDs.contains($0) }
                PTOBDLogger.obd.ptLog("🔋 [EV 模式] 净化完毕！剔除了无用探针，将 100% 算力集中于电控系统。")
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
            
            PTOBDLogger.obd.ptLog("⚡️ [轮询引擎] 成功提取 \(allDynamicCommands.count) 条支持指令，开始构建加权火力网！")
            
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
                        let cleanResponse = response.obdCleaned
                        
                        // 过滤掉偶尔的 NO DATA 或杂音，绝不打断轮询
                        if !cleanResponse.isEmpty && !cleanResponse.contains("NODATA") && !cleanResponse.contains("ERROR") && !cleanResponse.contains("NO DATA") {
                            
                            // 交给无敌装甲解析器
                            if let val = self.parseSingleResponse(command: commandString, response: response) {
                                persistentMeasurements[commandString] = val
                                
                                // 为了防止日志爆炸，可以考虑只打印部分核心数据的解析结果
                                // PTOBDLogger.obd.ptLog("🏎️ [解析成功] 完美提取 \(commandString) 数据 = \(val)")
                                
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
    
    private func parseAllPIDs(rawResponses: [String]) -> [String] {
        var allSupported: [String] = []
        for res in rawResponses {
            let clean = res.obdCleaned
            var base = 0x00
            if clean.contains("4120") { base = 0x20 }
            else if clean.contains("4140") { base = 0x40 }
            allSupported.append(contentsOf: parseSupportedPIDs(response: res, baseCommand: base))
        }
        return allSupported
    }
    
    private func parseSupportedPIDs(response: String, baseCommand: Int) -> [String] {
        let clean = response.obdCleaned
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
        let hexValid = "0123456789ABCDEF"
        let pureCommand = command.uppercased().filter { hexValid.contains($0) }
        
        // 1. 为 ATRV 开辟专属“绿色通道”
        if pureCommand == "ATRV" || command.uppercased().contains("ATRV") {
            let voltStr = response.uppercased().replacingOccurrences(of: "V", with: "").filter { "0123456789.".contains($0) }
            return Double(voltStr)
        }
        
        // 2. 为你注册的“私有黑客指令”开辟绿色通道
        let globalPureResponse = response.uppercased().filter { hexValid.contains($0) }
        if let customParser = customParsers[pureCommand] {
            return customParser(globalPureResponse)
        }

        // 3. 校验报文格式
        guard (pureCommand.hasPrefix("01") || pureCommand.hasPrefix("02")) && pureCommand.count >= 4 else {
            PTOBDLogger.obd.ptLog("❌ 拦截：指令格式不合法 -> [\(pureCommand)]")
            return nil
        }
        
        let modeAndPID = String(pureCommand.prefix(4))
        let modeStr = String(modeAndPID.prefix(2))
        let pidHex = String(modeAndPID.suffix(2))
        let expectedMode = modeStr == "01" ? "41" : "42"
        let expectedPrefix = expectedMode + pidHex // 例如 "410C"
        
        // 🌟 4. 【核心重构】：多 ECU 节点防撞与分离 (逐行解析)
        let lines = response.uppercased().components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: "\r") } // 兼容 \r 或 \n
            .map { $0.filter { hexValid.contains($0) } }  // 每一行单独提纯 Hex
            .filter { !$0.isEmpty }
        
        // 存放不同 ECU 返回的有效数据载荷
        var parsedPayloadsByECU: [String: String] = [:]
        
        for line in lines {
            if let range = line.range(of: expectedPrefix) {
                // 提取发出这条回复的 ECU 报头 (通常在 expectedPrefix 之前)
                // 例如 "7E804410C1A7C" 中，报头是 "7E8"
                let headerPart = String(line[..<range.lowerBound])
                
                // 提取报头：取前 3 位 (11-bit CAN) 或 前 8 位 (29-bit CAN)
                var ecuHeader = "UNKNOWN"
                if headerPart.count >= 8 { ecuHeader = String(headerPart.prefix(8)) }
                else if headerPart.count >= 3 { ecuHeader = String(headerPart.prefix(3)) }
                
                // 截取目标数据载荷
                let rawDataPart = String(line[range.upperBound...])
                parsedPayloadsByECU[ecuHeader] = rawDataPart
            }
        }
        
        // 如果没有收到任何有效载荷，拦截
        guard !parsedPayloadsByECU.isEmpty else {
            // PTOBDLogger.obd.ptLog("❌ 拦截：所有节点均未返回目标报头 [\(expectedPrefix)]")
            return nil
        }
        
        // 🌟 5. ECU 优先级仲裁引擎 (Priority Matrix)
        var targetPayload: String? = nil
        
        // 汽油/纯电/混动车的标准发动机主模块报头 (优先级最高)
        let primaryECUHeaders = ["7E8", "18DAF110", "18DAF100"]
        
        for primary in primaryECUHeaders {
            if let payload = parsedPayloadsByECU[primary] {
                targetPayload = payload
                break // 找到了主 ECU 的数据，立刻跳出！
            }
        }
        
        // 如果没有主模块的数据（例如某些特定探针只有变速箱 7E9 支持），则使用第一个拿到的数据作为备胎
        if targetPayload == nil {
            if let fallback = parsedPayloadsByECU.first {
                targetPayload = fallback.value
                PTOBDLogger.obd.ptLog("⚠️ [多模块仲裁] 未命中主ECU，采用备用节点数据: 节点[\(fallback.key)], 指令[\(modeAndPID)]")
            }
        }
        
        guard let finalRawDataPart = targetPayload else { return nil }
        
        // 🌟 6. 切分字节
        func getByte(at index: Int) -> Double? {
            let startOffset = index * 2
            guard finalRawDataPart.count >= startOffset + 2 else { return nil }
            let startIndex = finalRawDataPart.index(finalRawDataPart.startIndex, offsetBy: startOffset)
            let endIndex = finalRawDataPart.index(startIndex, offsetBy: 2)
            if let intVal = Int(finalRawDataPart[startIndex..<endIndex], radix: 16) { return Double(intVal) }
            return nil
        }
        
        let A = getByte(at: 0)
        let B = getByte(at: 1)
        let C = getByte(at: 2)
        let D = getByte(at: 3)

        // 🌟 7. 去字典里找到对应的 Enum，命令它自己计算并返回！
        if let commandEnum = OBDCommand.from(command: modeAndPID) {
            return commandEnum.decodeValue(A: A, B: B, C: C, D: D)
        }
        
        PTOBDLogger.obd.ptLog("⚠️ 字典中未注册公式的指令: \(modeAndPID)")
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
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        isConnected = false
        obdInfo.supportCommand = []
        delegates.forEach { $0.delegate?.telemetryManager(self, didChangeConnectionState: false) }
        PTOBDLogger.obd.stopFileLogging()
    }
    
    public func clearDiagnosticTroubleCodes() async -> Bool {
        guard isConnected else { return false }
        do {
            let response = try await self.sendRawCommandAsync("04")
            let cleanResponse = response.obdCleaned
            if cleanResponse.hasPrefix("44") || cleanResponse.contains("OK") { return true }
            else { return false }
        } catch { return false }
    }
}

extension PTMotoTelemetryManager {
    
    // MARK: - 🚀 Mode 3: 获取车辆故障码 (DTCs)
    public func getConfirmedDTCs() async -> [String: [PTTroubleCode]] {
        return await fetchDTCs(command: "03", expectedHeader: "43")
    }
    
    /// 2. 获取待定/偶发故障码 (潜伏期，尚未亮灯) - Mode 7
    public func getPendingDTCs() async -> [String: [PTTroubleCode]] {
        return await fetchDTCs(command: "07", expectedHeader: "47")
    }
    
    /// 3. 获取永久故障码 (无法手动清除，必须修复硬件) - Mode A (0A)
    public func getPermanentDTCs() async -> [String: [PTTroubleCode]] {
        return await fetchDTCs(command: "0A", expectedHeader: "4A")
    }

    private func fetchDTCs(command: String, expectedHeader: String) async -> [String: [PTTroubleCode]] {
        guard isConnected else { return [:] }
        do {
            let response = try await self.sendRawCommandAsync(command)
            
            // 🌟 1. 逐行剥离总线数据，防止 CAN 多帧交错污染
            let hexValid = "0123456789ABCDEF"
            let lines = response.uppercased().components(separatedBy: .newlines)
                .flatMap { $0.components(separatedBy: "\r") }
                .map { $0.filter { hexValid.contains($0) } }
                .filter { !$0.isEmpty }
            
            // 存放每个 ECU 的专属原始报文流
            var ecuRawData: [String: String] = [:]
            
            for line in lines {
                var ecuHeader = "UNKNOWN"
                // 识别 29-bit CAN 报头 (如 18DAF110) 或 11-bit CAN 报头 (如 7E8)
                if line.count >= 8 && line.hasPrefix("18DA") {
                    ecuHeader = String(line.prefix(8))
                } else if line.count >= 3 {
                    ecuHeader = String(line.prefix(3))
                }
                
                // 将报文拼接到对应 ECU 的缓存中 (保留换行以便后续提取纯净负载)
                ecuRawData[ecuHeader, default: ""] += line + "\n"
            }
            
            // 🌟 2. 遍历每个 ECU，独立解析故障码
            var finalResult: [String: [PTTroubleCode]] = [:]
            
            for (ecu, rawFlow) in ecuRawData {
                // 使用我们强大的多帧解析器，针对单个 ECU 提取纯净数据
                let purePayload = PTMultiFrameParser.extractPureHexPayload(response: rawFlow)
                
                // 寻找成功响应头 (例如 "43")
                guard let range = purePayload.range(of: expectedHeader) else { continue }
                let dtcData = String(purePayload[range.upperBound...])
                
                var dtcs: [PTTroubleCode] = []
                var i = dtcData.startIndex
                
                // 每 4 个十六进制字符代表一个故障码
                while i < dtcData.endIndex {
                    let nextI = dtcData.index(i, offsetBy: 4, limitedBy: dtcData.endIndex) ?? dtcData.endIndex
                    if dtcData.distance(from: i, to: nextI) == 4 {
                        let dtcHex = String(dtcData[i..<nextI])
                        
                        // 过滤掉 ECU 用来补位的 "0000"
                        if dtcHex != "0000" {
                            if let parsedCode = PTMultiFrameParser.decodeSingleDTC(dtcHex) {
                                let detailedDTC = PTDTCManager.getTroubleCodeDetails(for: parsedCode)
                                dtcs.append(detailedDTC)
                                PTOBDLogger.obd.ptLog("⚠️ [模块 \(ecu) 异常] 发现故障码: \(parsedCode)")
                            }
                        }
                    }
                    i = nextI
                }
                
                // 如果该模块确实有故障码，存入最终结果
                if !dtcs.isEmpty {
                    finalResult[ecu] = dtcs
                }
            }
            
            return finalResult
        } catch {
            PTOBDLogger.obd.ptLog("❌ 读取故障码发生异常: \(error)")
            return [:]
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
                let response = try await self.sendRawCommandAsync(currentMid)
                let cleanResponse = response.obdCleaned
                
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
                PTOBDLogger.obd.ptLog("❌ [Mode 6] 扫描目录 \(currentMid) 失败")
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
                PTOBDLogger.obd.ptLog("⚠️ [Mode 6] 发现车厂私有监控项，SwiftOBD2 暂未收录: \(hexCmd)")
            }
        }
        
        PTOBDLogger.obd.ptLog("🔬 [Mode 6] 扫描完毕，支持 \(supportedMode6Enums.count) 项化验单")
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
        let safePid = pidHex.hexOnly
        guard safePid.count == 2 else { return nil }
        
        let command = "02" + safePid + frameNumber
        
        do {
            let response = try await self.sendRawCommandAsync(command)
            let cleanResponse = response.obdCleaned
            
            if cleanResponse.contains("NODATA") || cleanResponse.contains("ERROR") {
                return nil // 说明没有故障，或者这个 PID 没有被冻结记录
            }
            
            // 丢给双模无敌装甲解析器
            let val = self.parseSingleResponse(command: command, response: response)
            if let v = val as? Double {
                PTOBDLogger.obd.ptLog("📸 [冻结帧快照] 捕获 PID:\(safePid) 故障时数据 -> \(v)")
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
        PTOBDLogger.obd.ptLog("⚠️ [Mode 8] 准备执行双向控制硬件测试: \(command.properties.description) (\(hexCommand))")
        
        // 🌟 1. 挂起当前的轮询引擎！绝对不能让 10ms 的数据流打断硬件测试！
        let wasPolling = (self.telemetryPollingTask != nil)
        if wasPolling {
            PTOBDLogger.obd.ptLog("⏸️ [Mode 8] 正在挂起高频轮询引擎...")
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
                PTOBDLogger.obd.ptLog("✅ [Mode 8] 测试命令已被 ECU 接受并成功执行！")
                isTestSuccessful = true
            } else if purePayload.contains("7F") {
                // 7F 是 OBD2 的否定响应 (Negative Response)
                PTOBDLogger.obd.ptLog("❌ [Mode 8] 被 ECU 拒绝。可能原因：引擎未熄火、车速不为零或该模块不支持被外部唤醒。原始回传: \(purePayload)")
                isTestSuccessful = false
            } else {
                PTOBDLogger.obd.ptLog("❌ [Mode 8] 执行失败或设备不支持。回传: \(purePayload)")
                isTestSuccessful = false
            }
        } catch {
            PTOBDLogger.obd.ptLog("❌ [Mode 8] 指令发送发生异常: \(error)")
            isTestSuccessful = false
        }
        
        // 🌟 4. 无论测试成功还是失败，都必须恢复被挂起的轮询引擎
        if wasPolling {
            PTOBDLogger.obd.ptLog("▶️ [Mode 8] 测试结束，恢复高频轮询引擎...")
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
        PTOBDLogger.obd.ptLog("🥷 [原生注入] 准备向总线发射深度指令: \(cleanHex)")
        
        let wasPolling = (self.telemetryPollingTask != nil)
        
        //  如果需要独占总线，挂起轮询引擎
        if requiresPause && wasPolling {
            PTOBDLogger.obd.ptLog("⏸️ [原生注入] 正在挂起轮询引擎以保障总线带宽...")
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
            PTOBDLogger.obd.ptLog("✅ [原生注入] 收到底层原始响应: \(rawResponse)")
            
        } catch {
            rawResponse = "ERROR: \(error.localizedDescription)"
            PTOBDLogger.obd.ptLog("❌ [原生注入] 发送发生异常: \(error)")
        }
        
        // 释放总线，恢复日常生命体征监测
        if requiresPause && wasPolling {
            PTOBDLogger.obd.ptLog("▶️ [原生注入] 注入完毕，恢复轮询引擎...")
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
                
        let cleanHeader = header.obdCleaned
        let cleanCRA = receiveAddress.obdCleaned
        let cleanCommand = udsCommand.obdCleaned
        
        PTOBDLogger.obd.ptLog("🥷 [私有探针] 目标: \(cleanHeader) | 监听: \(cleanCRA) | 指令: \(cleanCommand)")
        
        // 1. 霸占总线
        let wasPolling = (self.telemetryPollingTask != nil)
        if wasPolling {
            self.telemetryPollingTask?.cancel()
            self.telemetryPollingTask = nil
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        var finalResult = ""
        
        do {
            // 2. 寻址与底层流控制配置 (全自动支持长数据与车架号提取！)
            _ = try await self.sendRawCommandAsync("ATSH\(cleanHeader)")
            _ = try await self.sendRawCommandAsync("ATCRA\(cleanCRA)")
            _ = try await self.sendRawCommandAsync("ATSTFF") // 延长等待时间
            _ = try await self.sendRawCommandAsync("ATFCSM1") // 自定义流控制
            _ = try await self.sendRawCommandAsync("ATFCSH\(cleanHeader)")
            _ = try await self.sendRawCommandAsync("ATFCSD300000")
            
            // 3. 发射探针
            let response = try await self.sendRawCommandAsync(cleanCommand)
            finalResult = response.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch {
            finalResult = "ERROR: \(error.localizedDescription)"
            PTOBDLogger.obd.ptLog("❌ [私有探针] 渗透失败: \(error)")
        }
        
        // 4. 清理现场
        _ = try? await self.sendRawCommandAsync("ATST32")
        _ = try? await self.sendRawCommandAsync("ATD")
        _ = try? await self.sendRawCommandAsync("ATE0")
        _ = try? await self.sendRawCommandAsync("ATL0")
        _ = try? await self.sendRawCommandAsync("ATH1")
        
        if wasPolling {
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
        
        PTOBDLogger.obd.ptLog("🕵️‍♂️ [嗅探系统] 警告：正在进入总线监听模式！")
        
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
                PTOBDLogger.obd.ptLog("🎯 [嗅探系统] 过滤器已激活，仅监听地址: \(cleanTarget)")
            }
            
            // 4. 拨下开关，进入瀑布流模式！
            // 注意：底层的 isSnifferMode 必须在发 ATMA 之前设置为 true
            switch activeConnectionType {
            case .bluetooth:
                PTHiddenOBDConnector.shared.isSnifferMode = true
            default:
                PTWifiOBDConnector.shared.isSnifferMode = true
            }
            
            PTOBDLogger.obd.ptLog("🚀 [嗅探系统] 启动指令已发送，正在录制通讯流量，请操作原厂诊断仪...")
            
            // 发送 ATMA (Monitor All)。注意：ELM327 收到这个后就不会返回 ">" 了，直到我们打断它
            // 所以我们不等待它的 await 结果，直接使用底层对象的 writeRawData
            switch activeConnectionType {
            case .bluetooth:
                PTHiddenOBDConnector.shared.writeRawData("ATMA")
            default:
                PTWifiOBDConnector.shared.writeRawData("ATMA")
            }
        } catch {
            PTOBDLogger.obd.ptLog("❌ [嗅探系统] 启动监听失败: \(error)")
        }
    }
    
    /// 停止抓包并恢复日常监控
    public func stopCANSniperMode() async {
        guard isConnected else { return }
        
        PTOBDLogger.obd.ptLog("🛑 [嗅探系统] 正在停止抓包...")
        
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
        
        PTOBDLogger.obd.ptLog("▶️ [嗅探系统] 抓包结束，正在恢复常规轮询引擎。")
        
        let rawPIDsToResume = PTHiddenOBDConnector.shared.collectedPIDResponses.isEmpty ? PTWifiOBDConnector.shared.collectedPIDResponses : PTHiddenOBDConnector.shared.collectedPIDResponses
        self.startLightweightPolling(rawPIDs: rawPIDsToResume)
    }
}

extension PTMotoTelemetryManager {
    
    // MARK: - 🧠 智能动力类型指纹推断
    internal func autoDetectEngineType(supportedHexPIDs: [String]) async {
        PTOBDLogger.obd.ptLog("🧠 [智能推断] 开始对车辆进行动力系统侧写 (Profiling)...")
        
        // 1. 标准探针询问：如果车辆支持 0151，直接问它！
        if supportedHexPIDs.contains("0151") {
            if let response = try? await self.sendRawCommandAsync("0151"),
               let fuelObj = self.parseSingleResponse(command: "0151", response: response) as? PTFuelType {
                
                PTOBDLogger.obd.ptLog("🧠 [智能推断] 车辆通过 0151 主动坦白燃料类型: \(fuelObj.stringValue)")
                
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
            PTOBDLogger.obd.ptLog("🧠 [智能推断] 无氧传感器 + 支持电池寿命 = 纯电动 (EV)！")
            self.obdInfo.engineType = .ev
        }
        else if supportsBatteryLife && supportsO2Sensors {
            PTOBDLogger.obd.ptLog("🧠 [智能推断] 有氧传感器 + 支持电池寿命 = 混合动力 (HEV)！")
            self.obdInfo.engineType = .hybrid
        }
        else if supportsRPM && supportsO2Sensors {
            PTOBDLogger.obd.ptLog("🧠 [智能推断] 标准油车指纹 = 燃油车 (ICE)！")
            self.obdInfo.engineType = .ice
        }
        else if supportedHexPIDs.isEmpty {
            // 3. 极端情况：硬件连上了，但全频段不支持 Mode 1，大概率是全私有协议电车
            PTOBDLogger.obd.ptLog("🧠 [智能推断] Mode 1 全盲，推测为使用私有协议的纯电车 (EV)。")
            self.obdInfo.engineType = .ev
        } else {
            PTOBDLogger.obd.ptLog("🧠 [智能推断] 无法精准定性，默认降级为 燃油车 (ICE)。")
            self.obdInfo.engineType = .ice
        }
    }
}

extension PTMotoTelemetryManager {
    // MARK: - 🌟 非阻塞式超时计时器
    private func startConnectionTimeoutTimer() {
        // 每次连接前，先取消上一次可能存在的旧计时器
        connectionTimeoutTask?.cancel()
        
        connectionTimeoutTask = Task { [weak self] in
            let times:UInt64 = 10_000_000_000
            let seconds = times / 1_000_000_000
            try? await Task.sleep(nanoseconds: times)
            
            guard let self = self, !Task.isCancelled else { return }
            
            // 醒来后，如果依然没有连接成功，触发回调！
            // ⚠️ 极其关键：这里绝对不调用底层的取消扫描方法，让硬件继续默默寻找！
            if !self.isConnected {
                PTOBDLogger.obd.ptLog("⏳ [连接管家] \(seconds)秒连接超时，触发 UI 提示，底层持续扫描中...")
                DispatchQueue.main.async {
                    self.onConnectionTimeout?()
                }
            }
        }
    }
}

extension PTMotoTelemetryManager {
    
    // MARK: - 💓 ECU 防休眠心跳保活引擎 (Tester Present)
    
    // 维护一个专用的后台心跳任务
    private static var testerPresentTask: Task<Void, Never>?
    
    /// 启动 UDS 3E 心跳保活服务，阻止仪表盘或 ECU 在 KOEO 状态下自动关机
    /// 建议在通电且不打火的情况下，由 UI 层的 Switch 开关手动触发
    public func startKeepAliveHeartbeat(targetTx: String = "700") {
        guard isConnected else { return }
        
        // 防止重复启动
        stopKeepAliveHeartbeat()
        
        PTMotoTelemetryManager.testerPresentTask = Task { [weak self] in
            PTOBDLogger.obd.ptLog("💓 [心跳引擎] 启动！开始向 \(targetTx) 发送 3E 80 阻止系统休眠...")
            
            while !Task.isCancelled {
                guard let self = self, self.isConnected else { break }
                
                // 直接使用我们写好的原生注入通道，要求其必须挂起高频轮询！
                // 3E80: 3E 代表诊断仪在线，80 代表抑制肯定响应 (让 ECU 别回话，节约总线带宽)
                _ = await self.injectRawHexCommand("ATSH\(targetTx)", requiresPause: true)
                _ = await self.injectRawHexCommand("3E80", requiresPause: false)
                
                // 恢复默认寻址
                _ = await self.injectRawHexCommand("ATD", requiresPause: false)
                
                // 行业标准：每隔 2000 毫秒 (2秒) 发送一次心跳
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
    
    /// 停止心跳保活服务
    public func stopKeepAliveHeartbeat() {
        if PTMotoTelemetryManager.testerPresentTask != nil {
            PTMotoTelemetryManager.testerPresentTask?.cancel()
            PTMotoTelemetryManager.testerPresentTask = nil
            PTOBDLogger.obd.ptLog("🛑 [心跳引擎] 已停止。车辆电源管理系统接管控制权。")
        }
    }
}

public extension PTMotoTelemetryManager {
    // MARK: - 🛡️ 全局总线独占锁 (Bus Lock)
    /// 执行连续的极客入侵、OTA 或刷写操作时，死锁总线，绝对禁止常规轮询介入
    func performExclusiveTask(action: () async -> Void) async {
        let wasPolling = (self.telemetryPollingTask != nil)
        
        // 1. 强制挂起并休眠，等待总线彻底安静
        if wasPolling {
            PTOBDLogger.obd.ptLog("⏸️ [总线锁] 已强制接管总线，挂起高频轮询引擎...")
            self.telemetryPollingTask?.cancel()
            self.telemetryPollingTask = nil
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // 2. 执行不可被打断的连续危险操作
        await action()
        
        // 3. 释放锁，恢复生命体征监测
        if wasPolling {
            PTOBDLogger.obd.ptLog("▶️ [总线锁] 危险操作结束，交还总线控制权...")
            let rawPIDsToResume = PTHiddenOBDConnector.shared.collectedPIDResponses.isEmpty ? PTWifiOBDConnector.shared.collectedPIDResponses : PTHiddenOBDConnector.shared.collectedPIDResponses
            self.startLightweightPolling(rawPIDs: rawPIDsToResume)
        }
    }
}
