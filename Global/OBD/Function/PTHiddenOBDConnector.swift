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
        
        PTOBDLogger.shared.ptLog("⬆️ [TX Init \(currentQueueIndex + 1)/19] \(rawCommand)\\r")
        
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
            
            // 🌟 核心致命 Bug 修复：彻底废除 ATRV 包含 "V" 截断的逻辑，强迫状态机永远只在收到 ">" 符时才切断数据，避免状态机跳步引发断联！
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
        
        if cmd == "AT+VERSION" {
            if response.contains("?") || response.isEmpty {
                PTOBDLogger.shared.ptLog("⚠️ [认证] 未发现 YMOBD 加密特征，中断隐蔽初始化！")
                self.obdPeripheral?.delegate = nil
                if let p = self.obdPeripheral {
                    DispatchQueue.main.async { [weak self] in self?.onStandardDeviceDetected?(p) }
                }
                return
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
        
        if cmd == "0100" || cmd == "0120" || cmd == "0140" {
            let successHeader = "41" + cmd.dropFirst(2)
            
            // 🌟 完美避开 SEARCHING... 干扰：只要字符串里包含成功金块 4100，直接无视前面的 SEARCHING
            if cleanResponseForCheck.contains(successHeader) {
                collectedPIDResponses.append(response)
            } else {
                if cleanResponseForCheck.contains("UNABLETOCONNECT") {
                    PTOBDLogger.shared.ptLog("⚠️ [状态机] \(cmd) 提示 UNABLE TO CONNECT")
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
                    PTOBDLogger.shared.ptLog("⚠️ [状态机] \(cmd) 收到 NO DATA/SEARCHING，继续死磕重试...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.sendNextCommand() }
                    return
                }
            }
        }
        
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
    
    // MARK: - 极简轮询引擎 (双灯狂闪连发版)
    private func startLightweightPolling(rawPIDs: [String]) {
        telemetryPollingTask?.cancel()
        
        telemetryPollingTask = Task { [weak self] in
            guard let self = self else { return }
            
            let pids = self.parseAllPIDs(rawResponses: rawPIDs)
            guard !pids.isEmpty else {
                PTOBDLogger.shared.ptLog("❌ [轮询引擎] 探针解析全 0，主动断开！")
                await MainActor.run { self.disconnect() }
                return
            }
            
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
            
            // 完全严格执行官方 24 步高速循环队列，绝对不再引入乱七八糟的 PID[cite: 4]
            let pollingQueue: [String] = [
                rpmCmd, speedCmd, rpmCmd, tempCmd, rpmCmd, voltCmd,
                rpmCmd, speedCmd, rpmCmd, tempCmd, rpmCmd, voltCmd,
                rpmCmd, speedCmd, rpmCmd, tempCmd, rpmCmd, voltCmd,
                rpmCmd, speedCmd, rpmCmd, tempCmd, rpmCmd, voltCmd
            ]
            PTOBDLogger.shared.ptLog("⚡️ [轮询引擎] 启动 24 步高速连射阵列，准备引爆指示灯！")
            
            var consecutiveNoData = 0
            
            while !Task.isCancelled && self.isConnected {
                var currentMeasurements: [String: Any] = [:]
                for command in safeCommands { currentMeasurements[command] = 0.0 }
                
                for commandString in pollingQueue {
                    if Task.isCancelled { break }
                    
                    do {
                        let response = try await PTHiddenOBDConnector.shared.sendOBDCommandAsync(commandString)
                        let cleanResponse = self.clearString(response: response)
                        
                        if cleanResponse.contains("NODATA") || cleanResponse.contains("NO DATA") {
                            consecutiveNoData += 1
                            if consecutiveNoData >= 3 {
                                PTOBDLogger.shared.ptLog("⚠️ [防死机] 连续 NO DATA，中止队列连射，发送起搏器 0100 唤醒 ECU！")
                                _ = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("0100")
                                consecutiveNoData = 0
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                break
                            }
                        } else {
                            consecutiveNoData = 0
                            if !cleanResponse.isEmpty && !cleanResponse.contains("ERROR") {
                                if let val = self.parseSingleResponse(command: commandString, response: response) {
                                    currentMeasurements[commandString] = val
                                } else {
                                    if cleanResponse.contains("41") {
                                        currentMeasurements[commandString] = cleanResponse
                                    }
                                }
                            }
                        }
                    } catch {
                        PTOBDLogger.shared.ptLog("❌ [轮询引擎] 指令 \(commandString) 发送异常")
                    }
                    
                    // 🚀 维持高频连射，由于彻底清除了假 Bug，蓝牙将毫无顾虑地吞吐
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
                
                await MainActor.run {
                    var map:[String:Any] = [:]
                    currentMeasurements.forEach { value in map[value.key] = value.value }
                    self.dispatchMeasurementsToDelegates(measurements: map)
                }
                
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
                telemetryPollingTask = Task { [weak self] in
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
