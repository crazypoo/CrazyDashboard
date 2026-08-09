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
    private var isUsingSwiftOBD2: Bool = false

    public private(set) var supportedCommands: [String] = []
    
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
            
            // 🌟 1. 动态探针：发送 0100 查询车机真实支持的指令
            PTNSLogConsole("🔍 [自定义引擎] 正在向加密车机查询支持的 PID 列表 (0100)...")
            
            // ATRV 是芯片层面的直读电压指令，并非车机 ECU 协议，因此它必定支持，默认加入
            var supportedPIDs: [String] = ["ATRV"]
            
            do {
                // 向车机发送 0100
                let response0100 = try await PTHiddenOBDConnector.shared.sendOBDCommandAsync("0100")
                
                // 解析返回的二进制掩码
                let pids = self.parseSupportedPIDs(response: response0100, baseCommand: 0x00)
                supportedPIDs.append(contentsOf: pids)
                PTNSLogConsole("📋 [自定义引擎] 成功解析出车机支持的指令清单: \(supportedPIDs)")
                
            } catch {
                PTNSLogConsole("⚠️ [自定义引擎] 查询 0100 失败，回退至基础安全列表")
                supportedPIDs.append(contentsOf: ["010C", "010D", "0104", "0105"])
            }
            
            // 🌟 2. 菜单过滤：用你想查询的完整菜单，和车机真实支持的菜单进行“交集”过滤
            let desiredCommands = [
                "010C", "010D", "0104",
                "0105", "ATRV", "010F",
                "010B", "010E", "0110", "011F",
                "012F", "015E", "0133", "0131"
            ]
                        
            var activeCommands: [String] = []
            for cmd in desiredCommands {
                if supportedPIDs.contains(cmd) {
                    activeCommands.append(cmd)
                }
            }
            
            self.supportedCommands = activeCommands
            
            PTNSLogConsole("💡 [自定义引擎] 动态轮询菜单装载完毕，共激活 \(activeCommands.count) 项: \(activeCommands)")
            
            // 通知 UI 层连接成功，并告知它当前激活了哪些指令
            await MainActor.run {
                self.delegates.forEach { wrapper in
                    wrapper.delegate?.telemetryManager(self, didChangeConnectionState: true)
                }
            }
            
            // 🌟 3. 开始死循环高频轮询 (只轮询激活的指令)
            while !Task.isCancelled && self.isConnected {
                var currentMeasurements: [String: Any] = [:]
                
                for commandString in activeCommands {
                    if Task.isCancelled { break }
                    
                    do {
                        let response = try await PTHiddenOBDConnector.shared.sendOBDCommandAsync(commandString)
                        
                        if let val = self.parseSingleResponse(command: commandString, response: response) {
                            currentMeasurements[commandString] = val
                        }
                    } catch {
                        // 忽略偶发的单条超时
                    }
                }
                
                await MainActor.run {
                    self.dispatchMeasurementsToDelegates(measurements: currentMeasurements)
                }
                
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒刷新
            }
        }
    }
    
    // MARK: - 原生 PID 掩码解析器 (还原官方算法)
    /// 专门用于解析 0100、0120 等指令返回的 32 位支持位掩码
    private func parseSupportedPIDs(response: String, baseCommand: Int) -> [String] {
        let clean = response.replacingOccurrences(of: " ", with: "")
                            .replacingOccurrences(of: ">", with: "")
                            .replacingOccurrences(of: "\r", with: "")
                            .replacingOccurrences(of: "\n", with: "")
                            .uppercased()
        
        // 如果查询的是 0100，成功的前缀应该是 4100
        let prefix = String(format: "41%02X", baseCommand)
        
        guard clean.hasPrefix(prefix), clean.count >= prefix.count + 8 else { return [] }
        
        // 提取前缀后面的 8 个字符（即 32 位的 HEX 掩码），例如 BE1FA813
        let hexMask = String(clean.dropFirst(prefix.count).prefix(8))
        guard let maskValue = UInt32(hexMask, radix: 16) else { return [] }
        
        var supported: [String] = []
        
        // 遍历 32 个比特位，如果对应位是 1，则代表该 PID 被支持
        for i in 0..<32 {
            let bit = (maskValue >> (31 - i)) & 1
            if bit == 1 {
                let pid = baseCommand + i + 1
                supported.append(String(format: "01%02X", pid))
            }
        }
        
        return supported
    }

    private func parseSingleResponse(command: String, response: String) -> Double? {
        let cleanStr = response.replacingOccurrences(of: " ", with: "")
                                       .replacingOccurrences(of: ">", with: "")
                                       .replacingOccurrences(of: "\r", with: "")
                                       .replacingOccurrences(of: "\n", with: "")
                                       .uppercased()
                
        // 🌟 修复点 2：为 ATRV 开辟专属“绿色通道”，不经过 41 前缀校验
        if command == "ATRV" {
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
        case "010C": if let a = A, let b = B { return (a * 256 + b) / 4.0 }
        case "010D": if let a = A { return a }
        case "0104": if let a = A { return a * 100.0 / 255.0 }
        case "0105", "010F": if let a = A { return a - 40.0 }
        // 注意：这里的 0142 case 可以保留以防万一，但主要电压已经由上面的 ATRV 提供了
        case "0142": if let a = A, let b = B { return (a * 256 + b) / 1000.0 }
        case "015E": if let a = A, let b = B { return (a * 256 + b) / 20.0 }
        case "010B", "0133": if let a = A { return a }
        case "010E": if let a = A { return a / 2.0 - 64.0 }
        case "0110": if let a = A, let b = B { return (a * 256 + b) / 100.0 }
        case "011F", "0131": if let a = A, let b = B { return a * 256 + b }
        case "012F": if let a = A { return a * 100.0 / 255.0 }
        default: break
        }
        return nil
    }
    
    @MainActor
    private func dispatchMeasurementsToDelegates(measurements: [String: Any]) {
        self.cleanupDelegates()
        
        if let rpm = measurements["010C"] as? Double { self.currentRPM = rpm }
        if let speed = measurements["010D"] as? Double { self.currentSpeed = speed }
        
        self.delegates.forEach { wrapper in
            wrapper.delegate?.telemetryManager(self, didUpdateMeasurements: measurements)
        }
    }

    // MARK: - 极简 HEX 解析引擎
    private func parseOBDResponse(command: String, response: String) {
        let cleanHex = response.replacingOccurrences(of: " ", with: "")
                                       .replacingOccurrences(of: ">", with: "")
                                       .replacingOccurrences(of: "\r", with: "")
                                       .replacingOccurrences(of: "\n", with: "")
                                       .uppercased()
                
        // 确保收到的是有效的 41 开头的成功响应
        guard cleanHex.hasPrefix("41") else { return }
        
        // 缓存当前轮询到的字典，用于传递给 UI
        var currentMeasurements: [String: Any] = [:]
        
        // --- 内部安全提取字节的工具方法 ---
        // A 的起始位是 4，B 的起始位是 6，C 的起始位是 8
        func getByte(at index: Int) -> Double? {
            guard cleanHex.count >= index + 2 else { return nil }
            let start = cleanHex.index(cleanHex.startIndex, offsetBy: index)
            let end = cleanHex.index(start, offsetBy: 2)
            if let intVal = Int(cleanHex[start..<end], radix: 16) {
                return Double(intVal)
            }
            return nil
        }
        
        let A = getByte(at: 4)
        let B = getByte(at: 6)
        
        // 🏎️ 基础动力数据
        if command == "010C", let a = A, let b = B { // 转速
            self.currentRPM = (a * 256 + b) / 4.0
            currentMeasurements["010C"] = self.currentRPM
        }
        else if command == "010D", let a = A { // 车速
            self.currentSpeed = a
            currentMeasurements["010D"] = self.currentSpeed
        }
        else if command == "0104", let a = A { // 计算负荷值/节气门百分比
            currentMeasurements["0104"] = a * 100.0 / 255.0
        }
        
        // 🌡️ 环境与健康数据
        else if command == "0105", let a = A { // 发动机水温 (℃)
            currentMeasurements["0105"] = a - 40.0
        }
        else if command == "010F", let a = A { // 进气温度 (℃)
            currentMeasurements["010F"] = a - 40.0
        }
        else if command == "0142", let a = A, let b = B { // 控制模块电压 (V)
            currentMeasurements["0142"] = (a * 256 + b) / 1000.0
        }
        
        // ⚙️ 进阶硬核工况数据
        else if command == "010B", let a = A { // 进气歧管绝对压力 MAP (kPa)
            currentMeasurements["010B"] = a
        }
        else if command == "010E", let a = A { // 1缸点火提前角 (°)
            currentMeasurements["010E"] = a / 2.0 - 64.0
        }
        else if command == "0110", let a = A, let b = B { // 空气流量 MAF (g/s)
            currentMeasurements["0110"] = (a * 256 + b) / 100.0
        }
        else if command == "011F", let a = A, let b = B { // 发动机启动后运行时间 (s)
            currentMeasurements["011F"] = a * 256 + b
        }
        
        // ⛽ 燃油与行程数据
        else if command == "012F", let a = A { // 燃油液位输入 (%)
            currentMeasurements["012F"] = a * 100.0 / 255.0
        }
        else if command == "015E", let a = A, let b = B { // 发动机瞬时燃油消耗率 (L/h)
            currentMeasurements["015E"] = (a * 256 + b) / 20.0
        }
        else if command == "0133", let a = A { // 大气压强 (kPa)
            currentMeasurements["0133"] = a
        }
        else if command == "0131", let a = A, let b = B { // 故障码清除后行驶距离 (km)
            currentMeasurements["0131"] = a * 256 + b
        }
        
        // 将成功解析出的数据分发给外部 UI 代理
        if !currentMeasurements.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // 打印调试日志，方便你在控制台观察解析结果是否正确
                for (cmd, val) in currentMeasurements {
                    PTNSLogConsole("📊 [数据解析] 成功解析指令 \(cmd): \(String(format: "%.2f", val as? Double ?? 0.0))")
                }
                
                // 动态抛给 UI。注意由于之前修改了代理，这里可以复用你自定义的分发方法
                // 或者直接通过统一的测量字典闭包抛出。
                self.delegates.forEach { wrapper in
                     wrapper.delegate?.telemetryManager(self, didUpdateMeasurements: currentMeasurements)
                }
            }
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
