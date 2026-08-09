//
//  PTHiddenOBDConnector.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 8/8/2026.
//

import Foundation
import CoreBluetooth
import PooTools
import CryptoKit // 苹果官方加密库，需要 iOS 13.0+

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
        return Int32.random(in: 0x12345678...Int32.max)
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
    
    private var initQueue: [String] = ["ATZ", "ATE0", "ATL0", "ATH1", "ATSP0", "AT+VERSION", "<AUTH>", "0100"]
    private var currentQueueIndex: Int = 0
    private var activeCommand: String? = nil
    private var rxBuffer: String = ""
    
    // 🌟 核心异步延续器：用于将回调转换为 async/await
    private var responseContinuation: CheckedContinuation<String, any Error>?
    
    // 🌟 官方反编译文档 6.3 节：严格的本地默认白名单，规避乱连导致的弹框
    private let allowedDeviceNames: Set<String> = [
        "OBDII", "MS310", "B25", "V500", "YM529", "YM329", "YM129",
        "YM819", "BT529", "OBD114", "OBD147", "BROM S10", "BROM S15", "BROM S20"
    ]
    
    private let targetDeviceUUIDString = "C688934C-8A62-4C35-872F-B07ED5415E94"
    
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
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            guard isUnlocked, let writeChar = self.writeCharacteristic,
                  let data = "\(command)\r".data(using: .ascii),
                  let peripheral = self.obdPeripheral else {
                continuation.resume(throwing: NSError(domain: "OBDError", code: -1, userInfo: [NSLocalizedDescriptionKey: "底层未准备好"]))
                return
            }
            PTNSLogConsole("加密请求：\(command)")
            // 记录当前的延续器，等待蓝牙回调时 resume
            self.responseContinuation = continuation
            self.activeCommand = command
            self.rxBuffer = ""
            let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            // 遵循文档 8.3 节：保留原生 writeType[cite: 1]
            peripheral.writeValue(data, for: writeChar, type: writeType)
        }
    }
}

extension PTHiddenOBDConnector: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && pendingConnection { startIcebreakerConnection() }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        
        // 🌟 规避弹框：只连接官方白名单设备[cite: 1]
        if allowedDeviceNames.contains(deviceName) {
            PTNSLogConsole("🎯 [蓝牙直连] 发现官方白名单设备: \(deviceName)")
            centralManager.stopScan()
            self.obdPeripheral = peripheral
            self.obdPeripheral?.delegate = self
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // 🌟 规避弹框：文档 6.2 节要求仅锁定 FFF0 服务[cite: 1]
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
            
            // 🌟 严格等待官方定义的完整 prompt[cite: 1]
            if rxBuffer.contains(">") {
                let cleanResponse = rxBuffer.replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                rxBuffer = ""
                
                if isUnlocked {
                    // 🌟 如果是轮询阶段，通过 continuation 返回，唤醒挂起的 async 任务
                    responseContinuation?.resume(returning: cleanResponse)
                    responseContinuation = nil
                } else {
                    processCompleteResponse(cleanResponse)
                }
            }
            PTNSLogConsole("回复数据：\(chunk)")
        } else {
            PTNSLogConsole("没回复")
        }
    }
    
    private func processCompleteResponse(_ response: String) {
        if activeCommand == "AT+VERSION" {
            // 如果 AT+VERSION 返回了错误 (例如 '?')，说明这不是 YMOBD 定制模块，直接切标准库！
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
        
        currentQueueIndex += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.sendNextCommand() }
    }
}
