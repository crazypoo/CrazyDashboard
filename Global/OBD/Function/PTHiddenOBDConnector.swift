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
        // 🌟 防线：确保丢进 UInt32 的字符串绝对干净，剔除任何非 HEX 字符
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

// MARK: - 专属的隐藏 OBD 蓝牙破冰船 (大一统无缝状态机版)
public class PTHiddenOBDConnector: NSObject {
    public static let shared = PTHiddenOBDConnector()
    
    public var onIceBroken: (() -> Void)?
    public var onStandardDeviceDetected: ((CBPeripheral) -> Void)?
    
    private var centralManager: CBCentralManager!
    public var obdPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    
    private var isUnlocked: Bool = false
    private var pendingConnection: Bool = false
    
    // 统一 19 步解锁队列，严格还原官方文献连招[cite: 3]
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
        pendingConnection = false
        isUnlocked = false
        collectedPIDResponses.removeAll()
        debugFlagSent = false
        currentQueueIndex = 0
        
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
            
            self.timeoutTask?.cancel()
            self.timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                if !Task.isCancelled {
                    PTNSLogConsole("⏳ [安全守护] 指令 \(command) 超时。")
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
        if central.state == .poweredOn && pendingConnection { startIcebreakerConnection() }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        if allowedDeviceNames.contains(deviceName) {
            PTNSLogConsole("🎯 [蓝牙直连] 发现设备: \(deviceName)")
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
                self.writeCharacteristic = char
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
            PTNSLogConsole("✅ [破冰船] 19 步硬件大满贯解锁完毕！芯片防盗版权限已彻底解除！")
            self.isUnlocked = true
            DispatchQueue.main.async { [weak self] in self?.onIceBroken?() }
            return
        }
        
        let rawCommand = initQueue[currentQueueIndex]
        activeCommand = rawCommand
        rxBuffer = ""
        
        PTNSLogConsole("🔓 [硬件解锁] 发送第 \(currentQueueIndex + 1)/19 步: \(rawCommand)")
        
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
            
            var isComplete = false
            var endRange: Range<String.Index>? = nil
            
            if let range = rxBuffer.range(of: ">") {
                isComplete = true
                endRange = range
            } else if activeCommand == "ATRV" && rxBuffer.contains("V") {
                isComplete = true
                if let vIndex = rxBuffer.firstIndex(of: "V") {
                    let afterV = rxBuffer.index(after: vIndex)
                    endRange = afterV..<afterV
                }
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
                    responseContinuation?.resume(returning: cleanResponse)
                    responseContinuation = nil
                } else {
                    processCompleteResponse(cleanResponse)
                }
            }
        }
    }
    
    // 🌟 一气呵成的底层状态机，应对 19 步中的特殊应答[cite: 3]
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
        
        if cmd == "AT+VERSION" {
            if response.contains("?") || response.isEmpty {
                self.obdPeripheral?.delegate = nil
                if let p = self.obdPeripheral {
                    DispatchQueue.main.async { [weak self] in self?.onStandardDeviceDetected?(p) }
                }
                return
            }
            var cryptSeed = ""
            // 🌟 致命修复 1：最强装甲级解析器！把毒害算法的 > 和换行彻底粉碎！
            let safeResponse = response.replacingOccurrences(of: ">", with: "").replacingOccurrences(of: " ", with: "")
            let lines = safeResponse.components(separatedBy: .newlines)
            for line in lines {
                let lowerLine = line.lowercased()
                if lowerLine.hasPrefix("crypt:") {
                    let seedPart = lowerLine.dropFirst(6)
                    // 极致过滤，只留 HEX，绝不留任何隐患
                    cryptSeed = String(seedPart.filter { "0123456789abcdef".contains($0) })
                }
            }
            
            let authCommand = !cryptSeed.isEmpty ? YmobdCrypt.setCryptCommand(cryptFromVersion: cryptSeed) : YmobdCrypt.challengeCommand(challenge: YmobdCrypt.newChallenge())
            let cleanAuthCommand = authCommand.replacingOccurrences(of: "\r", with: "")
            
            if let authIndex = initQueue.firstIndex(of: "<AUTH>") {
                initQueue[authIndex] = cleanAuthCommand
                PTNSLogConsole("🔐 [加密认证] 成功拦截并注入纯净密钥！[\(cleanAuthCommand)]")
            }
        }
        
        if cmd == "0100" {
            if cleanResponseForCheck.contains("UNABLETOCONNECT") {
                if !debugFlagSent {
                    initQueue.insert("AT+DEBUG_FLG", at: currentQueueIndex)
                    debugFlagSent = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.sendNextCommand() }
                    return
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.sendNextCommand() }
                    return
                }
            }
            if cleanResponseForCheck.contains("NODATA") || cleanResponseForCheck.contains("SEARCHING") {
                PTNSLogConsole("⚠️ [破冰船] \(cmd) 收到纯错误，进行重试...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.sendNextCommand() }
                return
            }
            collectedPIDResponses.append(response)
        }
        
        if cmd == "0120" || cmd == "0140" { collectedPIDResponses.append(response) }
        if cmd == "ATDP" { PTMotoTelemetryManager.shared.setProtocol(cleanResponseForCheck) }
        if cmd == "0902" { PTMotoTelemetryManager.shared.setVin(cleanResponseForCheck.hasPrefix("4902") ? String(cleanResponseForCheck.dropFirst(4)) : cleanResponseForCheck) }
        if cmd == "0904" { PTMotoTelemetryManager.shared.setEcuVersion(cleanResponseForCheck) }
        if cmd == "0906" { PTMotoTelemetryManager.shared.setCvn(cleanResponseForCheck) }
        
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
    
    func setProtocol(_ p: String) { self.protocolName = p }
    func setVin(_ v: String) { self.vin = v }
    func setEcuVersion(_ v: String) { self.ecuVersion = v }
    func setCvn(_ v: String) { self.cvn = v }

    private init() {}
    
    public func addDelegate(_ delegate: PTMotoTelemetryDelegate) {
        cleanupDelegates()
        let isAlreadyAdded = delegates.contains { $0.delegate === delegate }
        if !isAlreadyAdded {
            delegates.append(WeakDelegateWrapper(delegate))
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
            self.setupConnectionListener()
            self.startOBDServiceHandshake()
        }

        PTHiddenOBDConnector.shared.onIceBroken = { [weak self] in
            guard let self = self else { return }
            self.isConnected = true
            self.startLightweightPolling(rawPIDs: PTHiddenOBDConnector.shared.collectedPIDResponses)
        }
        
        PTHiddenOBDConnector.shared.startIcebreakerConnection()
    }
    
    // MARK: - 极简轮询引擎 (极致狂闪连射版)
    private func startLightweightPolling(rawPIDs: [String]) {
        telemetryPollingTask?.cancel()
        
        telemetryPollingTask = Task { [weak self] in
            guard let self = self else { return }
            
            let pids = self.parseAllPIDs(rawResponses: rawPIDs)
            guard !pids.isEmpty else {
                PTNSLogConsole("❌ [自定义引擎] 探针解析全 0，车辆不支持标准协议！")
                await MainActor.run { self.disconnect() }
                return
            }
            PTNSLogConsole("✅ [自定义引擎] 成功提取支持列表：\(pids)")
            
            // 🌟 致命修复 2：彻底锁定官方的 4 指令安全菜单，砍掉所有的贪婪查询[cite: 3]
            let rpmCmd = OBDCommand.mode1(.rpm).properties.command
            let speedCmd = OBDCommand.mode1(.speed).properties.command
            let tempCmd = OBDCommand.mode1(.coolantTemp).properties.command
            let voltCmd = "ATRV"
            
            let safeCommands = [rpmCmd, speedCmd, tempCmd, voltCmd]
            self.supportedCommands = safeCommands
            
            await MainActor.run {
                self.delegates.forEach { wrapper in
                    wrapper.delegate?.telemetryManager(self, didChangeConnectionState: true)
                    wrapper.delegate?.telemetryManager(self, didDiscoverSupportedCommands: safeCommands)
                }
            }
            
            // 🌟 致命修复 3：完全还原官方 24 步高频轮询队列[cite: 3]
            let pollingQueue: [String] = [
                rpmCmd, speedCmd, rpmCmd, tempCmd, rpmCmd, voltCmd,
                rpmCmd, speedCmd, rpmCmd, tempCmd, rpmCmd, voltCmd,
                rpmCmd, speedCmd, rpmCmd, tempCmd, rpmCmd, voltCmd,
                rpmCmd, speedCmd, rpmCmd, tempCmd, rpmCmd, voltCmd
            ]
            PTNSLogConsole("⚡️ [极速狂飙] 已启动官方 24 步安全队列，拆除所有等待刹车！")
            
            while !Task.isCancelled && self.isConnected {
                var currentMeasurements: [String: Any] = [:]
                for command in safeCommands { currentMeasurements[command] = 0.0 }
                
                for commandString in pollingQueue {
                    if Task.isCancelled { break }
                    
                    do {
                        let response = try await PTHiddenOBDConnector.shared.sendOBDCommandAsync(commandString)
                        let cleanResponse = self.clearString(response: response)
                        
                        // 干净优雅地提取数据，无视偶尔出现的 NO DATA，绝不打断轮询！
                        if !cleanResponse.isEmpty && !cleanResponse.contains("NODATA") && !cleanResponse.contains("ERROR") && !cleanResponse.contains("NO DATA") {
                            if let val = self.parseSingleResponse(command: commandString, response: response) {
                                currentMeasurements[commandString] = val
                            } else {
                                if cleanResponse.contains("41") {
                                    currentMeasurements[commandString] = cleanResponse
                                }
                            }
                        }
                    } catch {}
                    
                    // 🚀 致命修复 4：彻底移除 Task.sleep 长延迟，依靠底层蓝牙应答自然推动！
                    // 这是黄绿双灯能否同步狂闪的关键！模块一回应 ">"，我们立马发射下一发！
                }
                
                await MainActor.run {
                    var map:[String:Any] = [:]
                    currentMeasurements.forEach { value in map[value.key] = value.value }
                    self.dispatchMeasurementsToDelegates(measurements: map)
                }
                
                // 仅保留 50 毫秒的超低底噪，让 UI 转速表极度丝滑
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

    private func parseSingleResponse(command: String, response: String) -> Double? {
        let cleanStr = clearString(response: response)
        
        if command == OBDCommand.General.ATRV.properties.command || command == "ATRV" {
            let voltStr = cleanStr.replacingOccurrences(of: "V", with: "")
            return Double(voltStr)
        }
        
        guard command.hasPrefix("01") && command.count == 4 else { return nil }
        
        let expectedPrefix = "41" + command.dropFirst(2)
        guard let range = cleanStr.range(of: expectedPrefix) else { return nil }
        
        let rawDataPart = String(cleanStr[range.upperBound...])
        let dataPart = rawDataPart.filter { "0123456789ABCDEF".contains($0) }
        
        func getByte(at index: Int) -> Double? {
            let startOffset = index * 2
            guard dataPart.count >= startOffset + 2 else { return nil }
            let start = dataPart.index(dataPart.startIndex, offsetBy: startOffset)
            let end = dataPart.index(start, offsetBy: 2)
            if let intVal = Int(dataPart[start..<end], radix: 16) { return Double(intVal) }
            return nil
        }
        
        let A = getByte(at: 0)
        let B = getByte(at: 1)
        
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
    
    public func fetchVehicleStaticInfo() async -> [String: String] {
        guard isConnected else { return [:] }
        var infoReport: [String: String] = [:]
        if !self.vin.isEmpty && !self.vin.contains("NODATA") { infoReport["VIN"] = self.vin }
        if !self.ecuVersion.isEmpty && !self.ecuVersion.contains("NODATA") { infoReport["ECU_Version"] = self.ecuVersion }
        if !self.cvn.isEmpty && !self.cvn.contains("NODATA") { infoReport["CVN"] = self.cvn }
        return infoReport
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
            telemetryPollingTask?.cancel()
            isConnected = false
            supportedCommands = []
            delegates.forEach { $0.delegate?.telemetryManager(self, didChangeConnectionState: false) }
        }
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
                let obdInfo = try await obdService.startConnection()
                let supportedPIDs = await obdService.getSupportedPIDs()
                let map = supportedPIDs.map { $0.properties.command }
                self.supportedCommands = map

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
                let response = try await obdService.sendCommand(.mode3(.GET_DTC))
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
