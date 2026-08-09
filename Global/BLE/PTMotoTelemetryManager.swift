//
//  PTODBManager.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 5/8/2026.
//

import Foundation
import SwiftOBD2
import Combine
import PooTools

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
            
            PTNSLogConsole("🔍 [自定义引擎] 正在向加密车机查询支持的 PID 列表...")
            
            // 🌟 1. 动态探针：获取车机真实支持的 PID 掩码解析结果
            let pids = await self.fetchSupportedPIDsWithRetry()
            
            // 🌟 2. 菜单过滤：与 SwiftOBD2 指令库求交集
            var activeCommands: [String] = ["ATRV"] // ATRV 是芯片层级直读电压指令，永远保留
            
            if !pids.isEmpty {
                // 遍历 SwiftOBD2 中定义的所有 Mode1 (实时数据) 指令
                for command in OBDCommand.Mode1.allCases {
                    let cmdString = OBDCommand.mode1(command).properties.command
                    
                    // 排除掉用来查询支持列表的特殊指令，我们只要具体的数据 PID
                    let skipPIDs = [
                        OBDCommand.mode1(.pidsA).properties.command, // 0100
                        OBDCommand.mode1(.pidsB).properties.command, // 0120
                        OBDCommand.mode1(.pidsC).properties.command  // 0140
                    ]
                    
                    // 💡 核心交集逻辑：如果 ECU 说支持，且不是查询指令，就加入激活菜单！
                    if pids.contains(cmdString) && !skipPIDs.contains(cmdString) {
                        activeCommands.append(cmdString)
                    }
                }
                PTNSLogConsole("📋 [自定义引擎] 通过掩码交集，精准提取出 \(activeCommands.count) 项支持的实时数据: \(activeCommands)")
            } else {
                PTNSLogConsole("⚠️ [自定义引擎] 0100 探针最终超时或为空，回退至基础安全列表")
                activeCommands = [
                    OBDCommand.mode1(.rpm).properties.command,
                    OBDCommand.mode1(.speed).properties.command,
                    OBDCommand.mode1(.engineLoad).properties.command,
                    OBDCommand.mode1(.coolantTemp).properties.command,
                    "ATRV"
                ]
            }
            
            // 将最终提取出的全量支持菜单持久化
            self.supportedCommands = activeCommands
            
            // 通知 UI 层连接成功，可以开始构建格子了
            await MainActor.run {
                self.delegates.forEach { wrapper in
                    wrapper.delegate?.telemetryManager(self, didChangeConnectionState: true)
                }
            }
            
            // 🌟 3. 构建官方加权轮询队列 (解决转速卡顿)
            var pollingQueue: [String] = []
            
            let rpmCmd = OBDCommand.mode1(.rpm).properties.command
            let speedCmd = OBDCommand.mode1(.speed).properties.command
            let tempCmd = OBDCommand.mode1(.coolantTemp).properties.command
            let voltCmd = "ATRV"
            
            let hasRPM = activeCommands.contains(rpmCmd)
            let hasSpeed = activeCommands.contains(speedCmd)
            let hasTemp = activeCommands.contains(tempCmd)
            let hasVolt = activeCommands.contains(voltCmd)
            
            // 官方的 6 步小循环模式
            let corePattern = [
                hasRPM ? rpmCmd : nil,
                hasSpeed ? speedCmd : nil,
                hasRPM ? rpmCmd : nil,
                hasTemp ? tempCmd : nil,
                hasRPM ? rpmCmd : nil,
                hasVolt ? voltCmd : nil
            ].compactMap { $0 }
            
            if corePattern.count >= 3 {
                pollingQueue.append(contentsOf: corePattern)
                // 把剩余的高级指令 (比如油耗、气压、进气温) 追加在基础循环的后面
                let otherCommands = activeCommands.filter { !([rpmCmd, speedCmd, tempCmd, voltCmd].contains($0)) }
                pollingQueue.append(contentsOf: otherCommands)
            } else {
                pollingQueue = activeCommands
            }
            
            PTNSLogConsole("⚡️ [性能优化] 最终执行的高频轮询队列: \(pollingQueue)")
            
            // 🌟 4. 开始死循环高频轮询
            while !Task.isCancelled && self.isConnected {
                var currentMeasurements: [String: Any] = [:]
                
                for commandString in pollingQueue {
                    if Task.isCancelled { break }
                    
                    do {
                        let response = try await PTHiddenOBDConnector.shared.sendOBDCommandAsync(commandString)
                        
                        // 交给自定义解析器处理
                        if let val = self.parseSingleResponse(command: commandString, response: response) {
                            currentMeasurements[commandString] = val
                        } else {
                            // 💡 调试利器：如果我们还没给这个指令写解析公式，就把原始 HEX 数据抛出去！
                            let cleanResponse = self.clearString(response: response)
                            if cleanResponse.hasPrefix("41") && cleanResponse.count > 4 {
                                let rawData = String(cleanResponse.dropFirst(4))
                                currentMeasurements[commandString] = rawData
                            }
                        }
                    } catch {
                        // 忽略偶发的单条超时
                    }
                }
                
                await MainActor.run {
                    self.dispatchMeasurementsToDelegates(measurements: currentMeasurements)
                    
                    // 因为我们可能提取出了几十个支持的指令，需要持续通知 UI，确保 UI 能够渲染出来
                    self.delegates.forEach { wrapper in
                        wrapper.delegate?.telemetryManager(self, didDiscoverSupportedCommands: activeCommands)
                    }
                }
                
                // 为了保证大量数据轮询不过度拥挤，依然保持 0.3~0.5 秒左右的间隙
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
        
        // 读取车辆协议[cite: 3]
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
        _ = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("0904")
        _ = try? await PTHiddenOBDConnector.shared.sendOBDCommandAsync("0906")
        
        return allSupportedPIDs
    }
    
    private func parseSingleResponse(command: String, response: String) -> Double? {
        
        let cleanStr = clearString(response: response)
                
        // 🌟 修复点 2：为 ATRV 开辟专属“绿色通道”，不经过 41 前缀校验
        if command == OBDCommand.General.ATRV.properties.command {
            // ATRV 的返回值通常是 "12.4V" 或 "12.4"
            let voltStr = cleanStr.replacingOccurrences(of: "V", with: "")
            return Double(voltStr)
        }
        
        // 对于其他的标准 OBD 01 服务请求，依然严格校验 41 前缀
        guard cleanStr.hasPrefix("41") else { return nil }
        
        func getByte(at index: Int) -> Double? {
            guard cleanStr.count >= index + 2 else { return nil }
            let start = cleanStr.index(cleanStr.startIndex, offsetBy: index)
            let end = cleanStr.index(start, offsetBy: 2)
            if let intVal = Int(cleanStr[start..<end], radix: 16) { return Double(intVal) }
            return nil
        }
        
        let A = getByte(at: 4)
        let B = getByte(at: 6)
        
        switch command {
        case OBDCommand.mode1(.rpm).properties.command: if let a = A, let b = B { return (a * 256 + b) / 4.0 }
        case OBDCommand.mode1(.speed).properties.command: if let a = A { return a }
        case OBDCommand.mode1(.engineLoad).properties.command: if let a = A { return a * 100.0 / 255.0 }
        case OBDCommand.mode1(.coolantTemp).properties.command, OBDCommand.mode1(.intakeTemp).properties.command: if let a = A { return a - 40.0 }
        // 注意：这里的 0142 case 可以保留以防万一，但主要电压已经由上面的 ATRV 提供了
        case OBDCommand.mode1(.controlModuleVoltage).properties.command: if let a = A, let b = B { return (a * 256 + b) / 1000.0 }
        case OBDCommand.mode1(.fuelRate).properties.command: if let a = A, let b = B { return (a * 256 + b) / 20.0 }
        case OBDCommand.mode1(.intakePressure).properties.command, OBDCommand.mode1(.barometricPressure).properties.command: if let a = A { return a }
        case OBDCommand.mode1(.timingAdvance).properties.command: if let a = A { return a / 2.0 - 64.0 }
        case OBDCommand.mode1(.maf).properties.command: if let a = A, let b = B { return (a * 256 + b) / 100.0 }
        case OBDCommand.mode1(.runTime).properties.command, OBDCommand.mode1(.distanceSinceDTCCleared).properties.command: if let a = A, let b = B { return a * 256 + b }
        case OBDCommand.mode1(.fuelLevel).properties.command: if let a = A { return a * 100.0 / 255.0 }
        default: break
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
}
