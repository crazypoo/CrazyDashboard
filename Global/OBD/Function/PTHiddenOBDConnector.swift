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
import SwiftOBD2
import Combine

let developerOBDID = "C688934C-8A62-4C35-872F-B07ED5415E94"

public struct YmobdCrypt {
    public static let defaultKey: Int32 = 0x263D9A7E

    /// 核心 crypt32 算法，完美还原官方 Kotlin 中的 32 位有符号位运算逻辑
    public static func crypt32(input: Int32, key: Int32 = defaultKey) -> Int32 {
        let b0 = input & 0xFF
        let b1 = (input >> 8) & 0xFF
        let b2 = (input >> 16) & 0xFF
        let b3 = (input >> 24) & 0xFF

        // 严格遵循算术右移和整除逻辑
        let r = (b2 >> (b0 / 50)) | ((b1 << 2) ^ (key << (b3 / 12)))
        let d = (b0 >> (b1 / 63)) | ((key << (b3 / 11)) ^ (b2 >> 1))
        let l = (b0 >> (b1 / 46)) | ((key << (b0 / 34)) ^ b3)
        let m = (b1 << (b3 / 35)) | ((key << (b0 / 49)) & (key >> 18))

        // 重新拼接为 32 位整数 (使用 bitPattern 防止 Swift 溢出崩溃)
        let part1 = (m << 24) & Int32(bitPattern: 0xFF000000)
        let part2 = (l << 16) & 0x00FF0000
        let part3 = (d << 8) & 0x0000FF00
        let part4 = r & 0x000000FF

        return part1 | part2 | part3 | part4
    }

    /// 将计算结果转为 8 位大写的 HEX 字符串，用于组装 AT 指令
    public static func hex8(value: Int32) -> String {
        let uValue = UInt32(bitPattern: value)
        return String(format: "%08X", uValue)
    }

    /// 生成随机的 Challenge
    public static func newChallenge() -> Int32 {
        return Int32.random(in: 0x12345678...0x7FFFFFFE)
    }
    
    /// 针对返回 crypt 字段的解锁指令生成器
    public static func setCryptCommand(cryptFromVersion: String) -> String {
        // 从 HEX 字符串解析为 UInt32，再转为有符号 Int32 进行计算
        guard let uInput = UInt32(cryptFromVersion, radix: 16) else { return "" }
        let input = Int32(bitPattern: uInput)
        let encrypted = crypt32(input: input)
        
        // 组装最终解锁指令，注意只能加 \r 不能加 \n
        return "AT+SETCRYPT\(hex8(value: encrypted))\r"
    }
    
    /// 针对没有 crypt 字段的解锁指令生成器
    public static func challengeCommand(challenge: Int32) -> String {
        return "AT+CRYPT\(hex8(value: challenge))\r"
    }
}

// MARK: - 专属的隐藏 OBD 蓝牙破冰船 (完整加密握手版)
public class PTHiddenOBDConnector: NSObject {
    
    public static let shared = PTHiddenOBDConnector()
    
    public var onIceBroken: (() -> Void)?
    
    // 🌟 当遇到非加密的普通 ELM327 时，触发此回调让 SwiftOBD2 接管
    public var onStandardDeviceDetected: ((CBPeripheral) -> Void)?
    
    private var centralManager: CBCentralManager!
    public var obdPeripheral: CBPeripheral? // 开放给外部
    private var writeCharacteristic: CBCharacteristic?
    
    private var isUnlocked: Bool = false
    private var pendingConnection: Bool = false
    
    private var initQueue: [String] = [OBDCommand.General.ATZ.properties.command, OBDCommand.General.ATE0.properties.command, OBDCommand.General.ATL0.properties.command, OBDCommand.General.ATH1.properties.command, OBDCommand.Protocols.ATSP0.properties.command, "AT+VERSION","ATI",OBDCommand.General.ATRV.properties.command, "<AUTH>"]
    private var currentQueueIndex: Int = 0
    private var activeCommand: String? = nil
    private var rxBuffer: String = ""
    
    // 🌟 核心异步延续器：用于将回调转换为 async/await
    private var responseContinuation: CheckedContinuation<String, any Error>?
    private var timeoutTask: Task<Void, Never>?
    
    // 🌟 官方反编译文档 6.3 节：严格的本地默认白名单，规避乱连导致的弹框
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
        pendingConnection = false
        isUnlocked = false
        
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
                self.centralManager.connect(targetPeripheral, options: nil)
                return
            }
        }
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }
    
    // 🌟 核心新增：真正防堵塞的 Async 发送方法
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
            
            let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            peripheral.writeValue(data, for: writeChar, type: writeType)
            
            // 🌟 核心修复 2：每次发新指令前，先取消掉上一个还在倒数的旧定时器
            self.timeoutTask?.cancel()
            
            // 启动全新的 20 秒倒计时任务
            self.timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 20_000_000_000) // 20秒
                
                // 只有当这个任务没有被取消时，才代表是真的超时了！
                if !Task.isCancelled {
                    PTNSLogConsole("⏳ [安全守护] 指令 \(command) 20秒未收到 '>'，触发强制断开超时机制。")
                    self.responseContinuation?.resume(throwing: NSError(domain: "OBDError", code: -3, userInfo: [NSLocalizedDescriptionKey: "等待硬件响应超时"]))
                    self.responseContinuation = nil
                    
                    self.centralManager.cancelPeripheralConnection(peripheral)
                }
            }
        }
    }
}

extension PTHiddenOBDConnector: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && pendingConnection { startIcebreakerConnection() }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        
        if allowedDeviceNames.contains(deviceName) {
            PTNSLogConsole("🎯 [蓝牙直连] 发现官方白名单设备: \(deviceName)")
            centralManager.stopScan()
            self.obdPeripheral = peripheral
            self.obdPeripheral?.delegate = self
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let targetServiceUUID = CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB")
        peripheral.discoverServices([targetServiceUUID])
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isUnlocked = false
        responseContinuation?.resume(throwing: NSError(domain: "OBDError", code: -2, userInfo: [NSLocalizedDescriptionKey: "蓝牙断开"]))
        responseContinuation = nil
    }
}

extension PTHiddenOBDConnector: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: char)
            }
            if char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse) {
                self.writeCharacteristic = char // 官方要求保留最后一个有效通道[cite: 1]
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.isNotifying {
            currentQueueIndex = 0
            rxBuffer = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.sendNextCommand() }
        }
    }
    
    private func sendNextCommand() {
        guard currentQueueIndex < initQueue.count else {
            self.isUnlocked = true
            DispatchQueue.main.async { [weak self] in self?.onIceBroken?() }
            return
        }
        
        let rawCommand = initQueue[currentQueueIndex]
        activeCommand = rawCommand
        rxBuffer = ""
        
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
            
            // 💡 调试打印：把自带的 >>>>> 换成更清晰的包裹符，让你看清真实的 chunk 到底是什么
            PTNSLogConsole("📦 [蓝牙接收] 收到真实数据切片: '\(chunk)'")
            
            var isComplete = false
            var endRange: Range<String.Index>? = nil
            
            // 🌟 智能结束符判定
            // 1. 正常情况：寻找标准的 '>' 提示符
            if let range = rxBuffer.range(of: ">") {
                isComplete = true
                endRange = range
            }
            // 2. 🛠 特判补丁：针对不守规矩的模块，如果查电压 (ATRV) 时收到了 "V"，就算它回答完毕！
            else if activeCommand == OBDCommand.General.ATRV.properties.command && rxBuffer.contains("V") {
                isComplete = true
                // 我们伪造一个截断点，截到 'V' 的位置
                if let vIndex = rxBuffer.firstIndex(of: "V") {
                    let afterV = rxBuffer.index(after: vIndex)
                    endRange = afterV..<afterV
                }
            }
            
            // 既然满足了完成条件，就开始处理数据
            if isComplete, let range = endRange {
                
                // 🌟 核心修复：立刻取消 20 秒死亡倒计时！
                self.timeoutTask?.cancel()
                self.timeoutTask = nil
                
                // 提取出一个完整的命令响应（不包含 '>'）
                let completeResponse = String(rxBuffer[..<range.lowerBound])
                
                // 将缓冲区截断，保留结束符之后可能粘包带来的新数据
                if range.upperBound < rxBuffer.endIndex {
                    rxBuffer = String(rxBuffer[range.upperBound...])
                } else {
                    rxBuffer = ""
                }
                
                let cleanResponse = completeResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if isUnlocked {
                    responseContinuation?.resume(returning: cleanResponse)
                    responseContinuation = nil
                } else {
                    processCompleteResponse(cleanResponse)
                }
            }
        }
    }
    
    private func processCompleteResponse(_ response: String) {
        let cleanResponseForCheck = response.replacingOccurrences(of: " ", with: "").uppercased()
        
        // 1. 验证 ATZ[cite: 3]
        if activeCommand == OBDCommand.general(.ATZ).properties.command && cleanResponseForCheck.contains("STOPPED") {
            PTNSLogConsole("⚠️ [破冰船] ATZ 验证失败 (STOPPED)，根据协议要求原地重试...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.sendNextCommand() }
            return
        }
        
        // 2. 验证基础设置指令是否返回 OK[cite: 3]
        
        let okCheckCommands = [OBDCommand.general(.ATE0).properties.command, OBDCommand.general(.ATL0).properties.command, OBDCommand.general(.ATH1).properties.command, "ATS0"]
        if let cmd = activeCommand, okCheckCommands.contains(cmd) {
            if !cleanResponseForCheck.contains("OK") {
                PTNSLogConsole("⚠️ [破冰船] \(cmd) 未返回 OK，根据协议要求原地重试...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.sendNextCommand() }
                return
            }
        }
        
        // 3. 处理 AT+VERSION 与加密
        if activeCommand == "AT+VERSION" {
            if response.contains("?") || response.isEmpty {
                PTNSLogConsole("⚠️ [破冰船] 未发现官方加密特征，识别为普通 OBD 模块，转交 SwiftOBD2...")
                self.obdPeripheral?.delegate = nil
                if let p = self.obdPeripheral {
                    DispatchQueue.main.async { [weak self] in self?.onStandardDeviceDetected?(p) }
                }
                return
            }
            
            var cryptSeed = ""
            let lines = response.components(separatedBy: "\n")
            for line in lines {
                let lowerLine = line.replacingOccurrences(of: " ", with: "").lowercased()
                if lowerLine.contains("crypt:") {
                    cryptSeed = String(lowerLine.dropFirst(6)).trimmingCharacters(in: .controlCharacters)
                }
            }
            
            let authCommand = !cryptSeed.isEmpty ? YmobdCrypt.setCryptCommand(cryptFromVersion: cryptSeed) : YmobdCrypt.challengeCommand(challenge: YmobdCrypt.newChallenge())
            let cleanAuthCommand = authCommand.replacingOccurrences(of: "\r", with: "")
            if currentQueueIndex + 1 < initQueue.count { initQueue[currentQueueIndex + 1] = cleanAuthCommand }
        }
        
        // 推进到下一步
        currentQueueIndex += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.sendNextCommand() }
    }
}

// MARK: - 1. 定义纯 UIKit 风格的代理协议
/// 遵守此协议的 UIViewController 可以实时接收机车遥测数据
public protocol PTMotoTelemetryDelegate: AnyObject {
    /// 连接状态发生改变时调用
    func telemetryManager(_ manager: PTMotoTelemetryManager, didChangeConnectionState isConnected: Bool)
    /// 动态数据更新回调。直接将当前轮询到的所有有效指令及数值传给 UI
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateMeasurements measurements: [String: Any])
    /// 当成功探测到车机 ECU 支持的指令清单时调用（适合用来动态点亮 UI 功能）
    func telemetryManager(_ manager: PTMotoTelemetryManager, didDiscoverSupportedCommands commands: [String])
}

// 提供默认实现，保持代码整洁
public extension PTMotoTelemetryDelegate {
    func telemetryManager(_ manager: PTMotoTelemetryManager, didChangeConnectionState isConnected: Bool) {}
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateMeasurements measurements: [String: Any]) {}
    func telemetryManager(_ manager: PTMotoTelemetryManager, didDiscoverSupportedCommands commands: [String]) {}
}

public class PTMotoTelemetryManager {
    public static let shared = PTMotoTelemetryManager()
    
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

    public private(set) var supportedCommands: [String] = []
    
    public private(set) var vin: String = ""
    public private(set) var protocolName: String = ""
    public private(set) var ecuVersion: String = ""
    public private(set) var cvn: String = ""

    private init() {}
    
    public func addDelegate(_ delegate: PTMotoTelemetryDelegate) {
        cleanupDelegates() // 每次添加前先清理一下已经销毁的旧界面
        
        // 防止同一个 ViewController 重复添加
        let isAlreadyAdded = delegates.contains { $0.delegate === delegate }
        if !isAlreadyAdded {
            delegates.append(WeakDelegateWrapper(delegate))
            PTNSLogConsole("📡 [OBD2] 新增了一个数据监听者。当前监听者数量: \(delegates.count)")
            if isConnected && !supportedCommands.isEmpty {
                delegate.telemetryManager(self, didDiscoverSupportedCommands: supportedCommands)
            }
        }
    }
    
    public func connectToMotorcycle() {
        PTNSLogConsole("📡 [OBD2] 开始纯净直连模式...")
        isUsingSwiftOBD2 = false
        
        PTHiddenOBDConnector.shared.onStandardDeviceDetected = { [weak self] peripheral in
            guard let self = self else { return }
            self.isUsingSwiftOBD2 = true
            PTNSLogConsole("🔗 [OBD2] 切换至 SwiftOBD2 标准引擎...")
            self.setupConnectionListener()
            self.startOBDServiceHandshake()

        }

        PTHiddenOBDConnector.shared.onIceBroken = { [weak self] in
            guard let self = self else { return }
            PTNSLogConsole("🔗 [OBD2] 官方初始化全部完成，硬件已就绪！开始自定义高频轮询...")
            self.isConnected = true
            self.startLightweightPolling()
        }
        
        PTHiddenOBDConnector.shared.startIcebreakerConnection()
    }
    
    // MARK: - 极简轮询引擎
    private func startLightweightPolling() {
        telemetryPollingTask?.cancel()
        
        telemetryPollingTask = Task { [weak self] in
            guard let self = self else { return }
            
            // 初始状态：只轮询电压 (确保 UI 存活) 和 0100 探针 (尝试唤醒车机)
            var activeCommands: [String] = ["ATRV", "0100"]
            var isProtocolEstablished = false
            var debugFlagSent = false
            
            // 🌟 新增：记录 NO DATA 的次数，用于触发强制协议切换
            var noDataCount = 0
            
            PTNSLogConsole("🚀 [状态机引擎] 启动！当前处于【探测模式】，优先保障电压数据刷新。")
            
            await MainActor.run {
                self.delegates.forEach { wrapper in
                    wrapper.delegate?.telemetryManager(self, didChangeConnectionState: true)
                }
            }
            
            while !Task.isCancelled && self.isConnected {
                var currentMeasurements: [String: Any] = [:]
                
                for commandString in activeCommands {
                    if Task.isCancelled { break }
                    
                    do {
                        let response = try await PTHiddenOBDConnector.shared.sendOBDCommandAsync(commandString)
                        let cleanResponse = self.clearString(response: response)
                        
                        // ==========================================
                        // 逻辑 A：处理 0100 探针的特殊响应
                        // ==========================================
                        if commandString == "0100" && !isProtocolEstablished {
                            
                            if cleanResponse.contains("UNABLETOCONNECT") || cleanResponse.contains("UNABLE TO CONNECT") {
                                PTNSLogConsole("⚠️ [状态机引擎] 收到 UNABLE TO CONNECT")
                                if !debugFlagSent {
                                    PTNSLogConsole("🛠 [状态机引擎] 触发私有唤醒钩子 AT+DEBUG_FLG")
                                    _ = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("AT+DEBUG_FLG")
                                    debugFlagSent = true
                                }
                                continue
                            }
                            
                            // 🌟 核心升级：将空字符串 (isEmpty) 与 NO DATA 视作同等物理故障
                            if cleanResponse.isEmpty || cleanResponse.contains("NODATA") || cleanResponse.contains("SEARCHING") || cleanResponse.contains("NO DATA") {
                                noDataCount += 1
                                let failReason = cleanResponse.isEmpty ? "EMPTY_STRING" : cleanResponse
                                PTNSLogConsole("⏳ [状态机引擎] 协议寻址中 (\(failReason))，已尝试 \(noDataCount) 次...")
                                
                                // 强制协议切换逻辑
                                if noDataCount == 4 {
                                    PTNSLogConsole("🔧 [状态机引擎] 自动寻址无果！强制锁定现代 CAN 协议 (ATSP6)...")
                                    _ = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("ATSP6\r")
                                }
                                
                                if noDataCount == 8 {
                                    PTNSLogConsole("🔧 [状态机引擎] 尝试备用老式 K-Line 协议 (ATSP5)...")
                                    _ = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("ATSP5\r")
                                }
                                
                                // 如果超过 12 次还是空字符串或 NO DATA，重置芯片
                                if noDataCount == 12 {
                                    PTNSLogConsole("🔧 [状态机引擎] 硬件可能假死，发送 ATZ 强制重启模块...")
                                    _ = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("ATZ\r")
                                    noDataCount = 0 // 重置计数器，开启新一轮的轮回
                                }
                                
                                continue
                            }
                            
                            // 3. 尝试解析 0100 的支持位
                            let pids = self.parseSupportedPIDs(response: response, baseCommand: 0x00)
                            if !pids.isEmpty {
                                PTNSLogConsole("✅ [状态机引擎] 协议握手成功！获取到支持列表：\(pids)")
                                isProtocolEstablished = true
                                noDataCount = 0
                                
                                // 读取一下最终成功连上的到底是什么协议
                                if let dpRes = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("ATDP") {
                                    let cleanProtocol = dpRes.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: ">", with: "")
                                    self.protocolName = cleanProtocol
                                    PTNSLogConsole("🚗 [车辆信息] 当前成功锁定的通讯协议是: \(cleanProtocol)")
                                }
                                
                                // --- 后续的加权组装逻辑保持不变 ---
                                let desiredCommands = ["010C", "010D", "0104", "0105", "ATRV", "010F", "010B", "010E", "0110", "011F"]
                                var newCommands: [String] = ["ATRV"]
                                
                                for cmd in desiredCommands {
                                    if pids.contains(cmd) && cmd != "ATRV" {
                                        newCommands.append(cmd)
                                    }
                                }
                                
                                let hasRPM = newCommands.contains("010C")
                                let hasSpeed = newCommands.contains("010D")
                                let hasTemp = newCommands.contains("0105")
                                
                                var pollingQueue: [String] = []
                                let corePattern = [
                                    hasRPM ? "010C" : nil,
                                    hasSpeed ? "010D" : nil,
                                    hasRPM ? "010C" : nil,
                                    hasTemp ? "0105" : nil,
                                    hasRPM ? "010C" : nil,
                                    "ATRV"
                                ].compactMap { $0 }
                                
                                if corePattern.count >= 3 {
                                    pollingQueue.append(contentsOf: corePattern)
                                    let otherCommands = newCommands.filter { !["010C", "010D", "0105", "ATRV"].contains($0) }
                                    pollingQueue.append(contentsOf: otherCommands)
                                } else {
                                    pollingQueue = newCommands
                                }
                                
                                activeCommands = pollingQueue
                                self.supportedCommands = activeCommands
                                PTNSLogConsole("💡 [状态机引擎] 已无缝切换至【高频数据模式】，激活队列: \(activeCommands)")
                                
                                await MainActor.run {
                                    self.delegates.forEach { wrapper in
                                        wrapper.delegate?.telemetryManager(self, didDiscoverSupportedCommands: activeCommands)
                                    }
                                }
                            }
                        }
                        
                        // ==========================================
                        // 逻辑 B：处理正常的数值解析 (电压、转速等)
                        // ==========================================
                        else if commandString != "0100" {
                            // 💡 过滤掉空字符串，防止控制台刷出大量无意义的解析失败警告
                            if !cleanResponse.isEmpty {
                                if let val = self.parseSingleResponse(command: commandString, response: response) {
                                    currentMeasurements[commandString] = val
                                } else {
                                    if cleanResponse.hasPrefix("41") && cleanResponse.count > 4 {
                                        let rawData = String(cleanResponse.dropFirst(4))
                                        currentMeasurements[commandString] = rawData
                                    }
                                }
                            }
                        }
                        
                    } catch {
                        // 忽略超时，绝不阻塞！
                    }
                    
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                
                if !currentMeasurements.isEmpty {
                    await MainActor.run {
                        self.dispatchMeasurementsToDelegates(measurements: currentMeasurements)
                    }
                }
                
                try? await Task.sleep(nanoseconds: 300_000_000)
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
    
    // MARK: - 原生 PID 掩码解析器 (还原官方算法)
    /// 专门用于解析 0100、0120 等指令返回的 32 位支持位掩码
    private func parseSupportedPIDs(response: String, baseCommand: Int) -> [String] {
        let clean = clearString(response: response)
        
        let prefix = String(format: "41%02X", baseCommand)
        
        // 🌟 修复点 1：使用正则表达式提取所有 ECU 的响应
        // 等价于官方 Kotlin 源码中的 Regex("4100([0-9A-F]{8})")
        let pattern = "\(prefix)([0-9A-F]{8})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        
        let matches = regex.matches(in: clean, options: [], range: NSRange(location: 0, length: clean.count))
        
        var combinedMask: UInt32 = 0
        
        for match in matches {
            if let range = Range(match.range(at: 1), in: clean) {
                let hexString = String(clean[range])
                if let maskValue = UInt32(hexString, radix: 16) {
                    // 🌟 核心：将多个 ECU 返回的支持位进行“按位或”运算
                    combinedMask |= maskValue
                }
            }
        }
        
        guard combinedMask > 0 else { return [] }
        
        var supported: [String] = []
        
        // 遍历 32 个比特位，如果对应位是 1，则代表该 PID 被支持
        for i in 0..<32 {
            let bit = (combinedMask >> (31 - i)) & 1
            if bit == 1 {
                let pid = baseCommand + i + 1
                supported.append(String(format: "01%02X", pid))
            }
        }
        
        return supported
    }
    
    private func fetchSupportedPIDsWithRetry() async -> [String] {
        var retries = 0
        var debugFlagSent = false
        var allSupportedPIDs: [String] = []
        
        // 核心协议寻址探针 0100
        while retries < 20 {
            retries += 1
            PTNSLogConsole("🔍 [自定义引擎] 发送 0100 探针 (第 \(retries) 次尝试)...")
            
            do {
                let response = try await PTHiddenOBDConnector.shared.sendOBDCommandAsync(OBDCommand.mode1(.pidsA).properties.command)
                let cleanResponse = clearString(response: response)
                
                // 处理 UNABLE TO CONNECT，触发私有唤醒[cite: 3]
                if cleanResponse.contains("UNABLETOCONNECT") {
                    PTNSLogConsole("⚠️ [自定义引擎] 收到 UNABLE TO CONNECT")
                    if !debugFlagSent {
                        PTNSLogConsole("🛠 [自定义引擎] 发送私有唤醒指令 AT+DEBUG_FLG")
                        _ = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("AT+DEBUG_FLG")
                        debugFlagSent = true
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                
                // 处理 NO DATA 或 SEARCHING 协议寻址超时
                if cleanResponse.contains("NODATA") || cleanResponse.contains("SEARCHING") || cleanResponse.contains("NO DATA") {
                    PTNSLogConsole("⏳ [自定义引擎] 协议寻址中 (\(cleanResponse))，继续等待重试...")
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                
                let pids = self.parseSupportedPIDs(response: response, baseCommand: 0x00)
                if !pids.isEmpty {
                    PTNSLogConsole("✅ [自定义引擎] 探针命中！成功获取 01-20 支持列表。")
                    allSupportedPIDs.append(contentsOf: pids)
                    break
                }
                
            } catch {
                PTNSLogConsole("❌ [自定义引擎] 探针请求异常: \(error)")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        if allSupportedPIDs.isEmpty { return [] }
        
        // 🌟 修复点 2：严格遵循发送 020000, 0600, 0900
        PTNSLogConsole("🔍 [自定义引擎] 执行官方队列补全动作...")
        _ = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("020000")
        _ = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("0600")
        _ = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("0900")
        
        // 读取车辆协议
        if let dpRes = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("ATDP") {
            let cleanProtocol = dpRes.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: ">", with: "")
            self.protocolName = cleanProtocol
        }
        
        // 扩展 PID 探测 0120 和 0140[cite: 3]
        if let res20 = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync(OBDCommand.mode1(.pidsB).properties.command) {
            allSupportedPIDs.append(contentsOf: self.parseSupportedPIDs(response: res20, baseCommand: 0x20))
        }
        if let res40 = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync(OBDCommand.mode1(.pidsC).properties.command) {
            allSupportedPIDs.append(contentsOf: self.parseSupportedPIDs(response: res40, baseCommand: 0x40))
        }
        
        // 读取车辆 VIN 与后续校准信息[cite: 3]
        if let vinRes = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync(OBDCommand.mode9(.VIN).properties.command) {
            self.vin = vinRes
        }
        // 补齐最后的 0904, 0906[cite: 3]
        if let ecuVersion = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("0904") {
            self.ecuVersion = ecuVersion
        }
        if let cvn = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("0906") {
            self.cvn = cvn
        }
        
        return allSupportedPIDs
    }
        
    private func parseSingleResponse(command: String, response: String) -> Double? {
        
        let cleanStr = clearString(response: response)
                        
        // 1. 为 ATRV 开辟专属“绿色通道”
        if command == OBDCommand.General.ATRV.properties.command || command == "ATRV" {
            let voltStr = cleanStr.replacingOccurrences(of: "V", with: "")
            return Double(voltStr)
        }
        
        // 2. 确保这是 Mode 01 的指令请求 (例如 "010C")
        guard command.hasPrefix("01") && command.count == 4 else { return nil }
        
        // 3. 拦截物理层面的空数据
        if cleanStr.contains("NODATA") || cleanStr.contains("ERROR") { return nil }
        
        // 4. 🌟 核心修复：构造预期的响应头，例如 "010C" -> "410C"
        let expectedPrefix = "41" + command.dropFirst(2)
        
        // 5. 🌟 核心修复：在字符串中寻找 "410C" 的位置，彻底无视前面的 CAN 报头 (如 7E804)
        guard let range = cleanStr.range(of: expectedPrefix) else {
            return nil
        }
        
        // 截取 "41XX" 之后的所有纯数据部分，例如 "1AF8"
        let dataPart = String(cleanStr[range.upperBound...])
        
        // 安全提取十六进制字节的内部工具方法
        func getByte(at index: Int) -> Double? {
            // index: A=0, B=1, C=2, D=3. 每个字节占 2 个字符
            let startOffset = index * 2
            guard dataPart.count >= startOffset + 2 else { return nil }
            
            let start = dataPart.index(dataPart.startIndex, offsetBy: startOffset)
            let end = dataPart.index(start, offsetBy: 2)
            
            if let intVal = Int(dataPart[start..<end], radix: 16) {
                return Double(intVal)
            }
            return nil
        }
        
        // 提取 ABCD 字节
        let A = getByte(at: 0)
        let B = getByte(at: 1)
        
        // 6. SAE 标准工业数学公式匹配
        switch command {
        case OBDCommand.mode1(.rpm).properties.command:
            if let a = A, let b = B { return (a * 256 + b) / 4.0 }
        case OBDCommand.mode1(.speed).properties.command:
            if let a = A { return a }
        case OBDCommand.mode1(.engineLoad).properties.command:
            if let a = A { return a * 100.0 / 255.0 }
        case OBDCommand.mode1(.coolantTemp).properties.command, OBDCommand.mode1(.intakeTemp).properties.command:
            if let a = A { return a - 40.0 }
        case OBDCommand.mode1(.controlModuleVoltage).properties.command:
            if let a = A, let b = B { return (a * 256 + b) / 1000.0 }
        case OBDCommand.mode1(.fuelRate).properties.command:
            if let a = A, let b = B { return (a * 256 + b) / 20.0 }
        case OBDCommand.mode1(.intakePressure).properties.command, OBDCommand.mode1(.barometricPressure).properties.command:
            if let a = A { return a }
        case OBDCommand.mode1(.timingAdvance).properties.command:
            if let a = A { return a / 2.0 - 64.0 }
        case OBDCommand.mode1(.maf).properties.command:
            if let a = A, let b = B { return (a * 256 + b) / 100.0 }
        case OBDCommand.mode1(.runTime).properties.command, OBDCommand.mode1(.distanceSinceDTCCleared).properties.command:
            if let a = A, let b = B { return a * 256 + b }
        case OBDCommand.mode1(.fuelLevel).properties.command:
            if let a = A { return a * 100.0 / 255.0 }
        default:
            break
        }
        
        return nil
    }
    
    @MainActor
    private func dispatchMeasurementsToDelegates(measurements: [String: Any]) {
        self.cleanupDelegates()
        
        if let rpm = measurements[OBDCommand.mode1(.rpm).properties.command] as? Double { self.currentRPM = rpm }
        if let speed = measurements[OBDCommand.mode1(.speed).properties.command] as? Double { self.currentSpeed = speed }
        
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
            // 自定义引擎断开逻辑（由于是系统底层托管，一般直接销毁Task和刷新状态即可）
            telemetryPollingTask?.cancel()
            isConnected = false
            supportedCommands = [] // 断开时清空持久化菜单
            delegates.forEach { $0.delegate?.telemetryManager(self, didChangeConnectionState: false) }
        }
    }

    private func setupConnectionListener() {
        obdService.$connectionState
            .receive(on: DispatchQueue.main) // 确保在主线程回调代理
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
                    self.telemetryPollingTask?.cancel() // 🌟 停止轮询
                    self.isConnected = false
                    PTNSLogConsole("❌ [OBD2] 连接断开。")
                    self.delegates.forEach { wrapper in
                        guard let delegate = wrapper.delegate else { return }
                        delegate.telemetryManager(self, didChangeConnectionState: false)
                    }
                    // 全局广播：适合在 AppDelegate 或其他非 UI 类中监听断开事件
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
                PTNSLogConsole("🔗 [OBD2] 开始进行协议握手...")
                
                // 第一步：强制指定协议建立物理与应用层连接
                let obdInfo = try await obdService.startConnection()
                
                PTNSLogConsole("✅ [OBD2] 握手成功！车机协议已锁定: \(obdInfo.obdProtocol?.description ?? "未知")")
                
                // 第二步：成功后立刻调用，获取该车 ECU 支持的功能清单
                PTNSLogConsole("🔍 [OBD2] 正在向车机查询支持的 PID 列表...")
                let supportedPIDs = await obdService.getSupportedPIDs()
                PTNSLogConsole("📋 [OBD2] 车机 ECU 真实支持的 PID 原始数据: \(supportedPIDs)")
                
                let map = supportedPIDs.map { $0.properties.command }
                self.supportedCommands = map

                // 第三步：状态变更为已连接，并开启基于探测结果的智能轮询
                self.isConnected = true
                await MainActor.run {
                    self.cleanupDelegates()
                    self.delegates.forEach { wrapper in
                        wrapper.delegate?.telemetryManager(self, didChangeConnectionState: true)
                        wrapper.delegate?.telemetryManager(self, didDiscoverSupportedCommands: map)
                    }
                }
                
                // 启动高频轮询（可以把 supportedPIDs 传进去做智能过滤）
                self.startSmartFetching(with: supportedPIDs)
                
            } catch {
                PTNSLogConsole("❌ [OBD2] OBD 协议握手报错: \(error.localizedDescription)")
            }
        }
    }
    
    private func startSmartFetching(with supportedPIDs: [OBDCommand]) {
        telemetryPollingTask?.cancel()
        
        // 构建动态轮询菜单：以基础转速/车速为底，并把车机实际支持的指令安全地合并进来
        var activeCommands: [OBDCommand] = []
        
        if !supportedPIDs.isEmpty {
            // 过滤掉重复项，只请求车子明确说“我支持”的指令
            let extraCommands = supportedPIDs.filter { !activeCommands.contains($0) }
            activeCommands.append(contentsOf: extraCommands)
            PTNSLogConsole("💡 [OBD2] 动态轮询菜单装载完毕，本车共激活 \(activeCommands.count) 项监控指标。")
        } else {
            PTNSLogConsole("⚠️ [OBD2] 未能获取详细清单，已自动回退至标准基础轮询。")
        }
        
        telemetryPollingTask = Task { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled && self.isConnected {
                var currentMeasurements: [OBDCommand: Any] = [:]
                
                // 🌟 核心修复 1：兜底机制。
                // 在开始请求前，先把所有要请求的指令默认置为 0.0
                // 这样无论发生什么，传给 UI 的字典永远不会是空 [:]
                for command in activeCommands {
                    currentMeasurements[command] = 0.0
                }
                
                for command in activeCommands {
                    if Task.isCancelled { break }
                    
                    do {
                        let response = try await self.obdService.sendCommand(command)
                        
                        // 🌟 核心修复 2：更严谨的数据解包
                        switch response {
                        case .success(let result):
                            // 优先尝试获取 Double 类型的 measurementResult
                            if let val = result.measurementResult?.value {
                                currentMeasurements[command] = val
                            }
                        case .failure(let error):
                            // 请求失败，保持之前设置的 0.0 兜底值不变，仅打印日志排错
                            PTNSLogConsole("⚠️ [OBD2] \(command.properties.command) 无有效数据: \(error.localizedDescription)")
                        }
                        
                        // 微小防抖延迟 (50毫秒)
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        
                    } catch {
                        // 遇到超时异常，同样保持 0.0 兜底值不变
                        PTNSLogConsole("❌ [OBD2] \(command.properties.command) 请求超时/异常，启用默认值 0.0")
                    }
                }
                
                // 主线程分发数据给 UI 代理
                await MainActor.run {
                    var map:[String:Any] = [:]
                    currentMeasurements.forEach { value in
                        map[value.key.properties.command] = value.value
                    }
                    self.dispatchMeasurementsToDelegates(measurements: map)
                }
                
                // 轮询间隔 (例如 0.5 秒刷新一次)
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}

extension PTMotoTelemetryManager {
    public func runDeepDiagnosticScan() async -> [String: Any] {
        guard isConnected else {
            PTNSLogConsole("⚠️ [深度诊断] 未连接车辆，无法执行体检。")
            return ["error": "未连接车辆"]
        }
        
        PTNSLogConsole("🩺 [深度诊断] 开始对车辆执行全方位深度体检...")
        var diagnosticReport: [String: Any] = [:]
        
        // --------------------------------------------------------
        // 步骤 1：扫描各类发动机故障码 (Mode 03, 07, 0A)
        // --------------------------------------------------------
        PTNSLogConsole("🩺 [深度诊断] 步骤 1/2：扫描发动机健康状态...")
        
        var confirmedDTCs: [String] = []
        var pendingDTCs: [String] = []
        var permanentDTCs: [String] = []
        
        if isUsingSwiftOBD2 {
            // SwiftOBD2 模式
            if let res3 = try? await obdService.sendCommand(.mode3(.GET_DTC)), case .success(let suc3) = res3 {
                confirmedDTCs = suc3.troubleCode?.compactMap { $0.description } ?? []
            }
            // 注意：SwiftOBD2 早期版本可能未原生提供 07 和 0A 枚举，如果报错，可以直接用 sendCommand(RawCommand("07")) 等代替
            // 此处为了严谨，若库不支持枚举，我们后续可通过添加 Custom Command 解决。假设暂只读 03
        } else {
            // 🌟 纯原生加密通道模式：全量读取 03(确认), 07(待定), 0A(永久)
            if let res03 = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("03") {
                confirmedDTCs = parseRawDTC(hexResponse: clearString(response: res03), modePrefix: "43")
            }
            if let res07 = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("07") {
                pendingDTCs = parseRawDTC(hexResponse: clearString(response: res07), modePrefix: "47")
            }
            if let res0A = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("0A") {
                permanentDTCs = parseRawDTC(hexResponse: clearString(response: res0A), modePrefix: "4A")
            }
        }
        
        diagnosticReport["Confirmed_DTCs"] = confirmedDTCs
        diagnosticReport["Pending_DTCs"] = pendingDTCs
        diagnosticReport["Permanent_DTCs"] = permanentDTCs
        
        PTNSLogConsole("✅ [深度诊断] 确认故障: \(confirmedDTCs.count) 个, 潜在隐患: \(pendingDTCs.count) 个, 顽固故障: \(permanentDTCs.count) 个")
        
        // --------------------------------------------------------
        // 步骤 2：扫描 Mode 6 (特定的组件监视测试)
        // --------------------------------------------------------
        PTNSLogConsole("🩺 [深度诊断] 步骤 2/2：扫描底层组件监视结果 (Mode 6)...此过程较长，请耐心等待")
        var mode6Results: [String: String] = [:]
        
        // 遍历 SwiftOBD2 中定义的所有 Mode 6 测试指令
        for command in OBDCommand.Mode6.allCases {
            let skipMIDs: [OBDCommand.Mode6] = [.MIDS_A, .MIDS_B, .MIDS_C, .MIDS_D, .MIDS_E, .MIDS_F]
            if skipMIDs.contains(command) { continue }
            
            let commandString = OBDCommand.mode6(command).properties.command
            
            do {
                var cleanResponse = ""
                
                // 🚨 致命 Bug 修复：必须根据当前使用的引擎来选择发送通道！
                if isUsingSwiftOBD2 {
                    let response = try await obdService.sendCommand(OBDCommand.mode6(command))
                    switch response {
                    case .success(let result):
                        cleanResponse = "\(result.measurementResult?.value ?? 0) \(result.measurementResult?.unit ?? Unit(symbol: ""))"
                    case .failure: break
                    }
                } else {
                    let response = try await PTHiddenOBDConnector.shared.sendOBDCommandAsync(commandString)
                    cleanResponse = self.clearString(response: response)
                }
                
                // 正常的 Mode 6 响应以 46 开头
                if cleanResponse.hasPrefix("46") && !cleanResponse.contains("NODATA") && !cleanResponse.contains("ERROR") {
                    PTNSLogConsole("✅ [深度诊断] 扫出 Mode 6 隐藏数据 (\(commandString)): \(cleanResponse)")
                    mode6Results[commandString] = cleanResponse
                }
            } catch {
                // 超时或失败忽略即可
            }
            
            try? await Task.sleep(nanoseconds: 100_000_000) // 休息 100 毫秒
        }
        
        if !mode6Results.isEmpty {
            diagnosticReport["Mode6"] = mode6Results
        }
        
        PTNSLogConsole("🏥 [深度诊断] 体检报告生成完毕！")
        return diagnosticReport
    }

    private func parseRawDTC(hexResponse: String, modePrefix: String) -> [String] {
        var dtcList: [String] = []
        var cleanHex = hexResponse
        
        // ECU 可能会返回多个报文合并的结果，例如 "4301040000 4301050000"，先去掉成功标头
        cleanHex = cleanHex.replacingOccurrences(of: modePrefix, with: "")
        
        // OBD 故障码是按 2 个字节 (4 个十六进制字符) 一组存储的
        // 前两个字符通常表示系统，后两个字符是具体的编码
        var index = cleanHex.startIndex
        while index < cleanHex.endIndex {
            let nextIndex = cleanHex.index(index, offsetBy: 4, limitedBy: cleanHex.endIndex) ?? cleanHex.endIndex
            let dtcHex = String(cleanHex[index..<nextIndex])
            
            // 一个完整的 DTC 必须是 4 个字符长，且 "0000" 表示无故障占位符
            if dtcHex.count == 4 && dtcHex != "0000" {
                // SAE J2012 标准解码规则：
                // 第一位 Hex 转成 2 进制，前两位决定字母：00=P, 01=C, 10=B, 11=U
                // 后两位决定第二位数字：0=0, 1=1, 2=2, 3=3
                if let firstHexChar = dtcHex.first, let firstHexVal = Int(String(firstHexChar), radix: 16) {
                    let systemChar: String
                    switch (firstHexVal >> 2) & 0b11 {
                    case 0: systemChar = "P" // Powertrain (动力系统)
                    case 1: systemChar = "C" // Chassis (底盘系统)
                    case 2: systemChar = "B" // Body (车身系统)
                    case 3: systemChar = "U" // Network (网络系统)
                    default: systemChar = "P"
                    }
                    
                    let secondChar = String((firstHexVal & 0b11), radix: 16).uppercased()
                    let remainingChars = String(dtcHex.dropFirst())
                    
                    let finalDTC = "\(systemChar)\(secondChar)\(remainingChars)"
                    if !dtcList.contains(finalDTC) {
                        dtcList.append(finalDTC)
                    }
                }
            }
            index = nextIndex
        }
        
        return dtcList
    }
    
    // MARK: - 🌟 清除故障码 (Mode 04)
    /// 发送 Mode 04 指令，请求 ECU 清除发动机故障码并重置相关监视器状态
    /// 注意：执行此操作通常需要车辆处于 "通电但未启动发动机 (Key On Engine Off)" 状态
    public func clearDiagnosticTroubleCodes() async -> Bool {
        guard isConnected else {
            PTNSLogConsole("⚠️ [清码系统] 未连接车辆，无法清除故障码。")
            return false
        }
        
        PTNSLogConsole("🧹 [清码系统] 正在向 ECU 发送清除故障码指令 (04)...")
        
        if isUsingSwiftOBD2 {
            do {
                let response = try await obdService.sendCommand(.mode1(.EGRError))
                switch response {
                case .success:
                    PTNSLogConsole("✅ [清码系统] SwiftOBD2 通道清码指令执行成功！")
                    return true
                case .failure(let error):
                    PTNSLogConsole("❌ [清码系统] SwiftOBD2 清码失败: \(error.localizedDescription)")
                    return false
                }
            } catch {
                PTNSLogConsole("❌ [清码系统] 请求异常: \(error)")
                return false
            }
        } else {
            // 原生加密通道模式
            do {
                let response = try await PTHiddenOBDConnector.shared.sendOBDCommandAsync("04")
                let cleanResponse = self.clearString(response: response)
                
                // 成功清除故障码时，ECU 通常会回复 "44"
                if cleanResponse.hasPrefix("44") || cleanResponse.contains("OK") {
                    PTNSLogConsole("✅ [清码系统] 原生通道清码指令执行成功！(响应: \(cleanResponse))")
                    return true
                } else {
                    PTNSLogConsole("⚠️ [清码系统] 原生通道清码可能失败或被拒绝 (响应: \(cleanResponse))")
                    return false
                }
            } catch {
                PTNSLogConsole("❌ [清码系统] 原生通道请求异常: \(error)")
                return false
            }
        }
    }
}
