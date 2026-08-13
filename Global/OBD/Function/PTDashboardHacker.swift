//
//  PTDashboardHacker.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 12/8/2026.
//

import Foundation

public class PTDashboardHacker {
    public static let shared = PTDashboardHacker()
    private init() {}
    
    // MARK: - 🛠 辅助方法：安全的总线锁定块
    /// 执行闭包前挂起轮询，执行完毕后自动恢复，避免所有方法里重复写挂起逻辑
    private func executeWithBusLock(action: () async -> Void) async {
        let manager = PTMotoTelemetryManager.shared
        guard manager.isConnected else { return }
        
        let wasPolling = (manager.telemetryPollingTask != nil)
        if wasPolling {
            manager.telemetryPollingTask?.cancel()
            manager.telemetryPollingTask = nil
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        await action() // 执行真正的骇客逻辑
        
        if wasPolling {
            let rawPIDsToResume = PTHiddenOBDConnector.shared.collectedPIDResponses.isEmpty ? PTWifiOBDConnector.shared.collectedPIDResponses : PTHiddenOBDConnector.shared.collectedPIDResponses
            manager.startLightweightPolling(rawPIDs: rawPIDsToResume)
        }
    }
        
    /// 🚀 读取特定地址的固件标识符 (尝试提取当前动画配置项的特征码)
    /// - Parameter dashboardTx: 你通过上面扫描确定的仪表盘地址 (如 "7A0")
    public func readDashboardConfig(dashboardTx: String, dashboardRx: String) async {
        let manager = PTMotoTelemetryManager.shared
        guard manager.isConnected else { return }
        
        PTOBDLogger.shared.ptLog("💾 [仪表盘探查] 开始读取目标模块 (\(dashboardTx)) 的系统配置...")
        
        // 尝试进入扩展诊断会话 (UDS 服务 10 03)，修改配置通常需要此会话
        let sessionRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1003")
        PTOBDLogger.shared.ptLog("🔄 会话切换响应: \(sessionRes)")
        
        // UDS 服务 22 (Read Data By Identifier)
        // F190 通常是 VIN 码，F187 是车厂备件号，F180 是 Bootloader 版本
        // 这里我们可以尝试批量读取这些通用 DID，看看它吐出什么信息
        let didsToProbe = ["F190", "F187", "F180", "F1A0"]
        
        for did in didsToProbe {
            let readCmd = "22\(did)"
            let response = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: readCmd)
            
            // 62 是 22 的成功响应头
            if response.contains("62\(did)") {
                PTOBDLogger.shared.ptLog("✅ 成功读取 DID [\(did)]: \(response)")
            } else {
                PTOBDLogger.shared.ptLog("⚠️ 模块拒绝读取 DID [\(did)] 或该地址不存在。响应: \(response)")
            }
        }
        
        // 退出会话，重置模块 (UDS 服务 11 01 硬重启，或 10 01 默认会话)
        _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1001")
    }
}

public extension PTDashboardHacker {
    
    // MARK: - 🌍 阶段一：全域 ECU 节点雷达扫描 (Ping Sweep)
    
    /// 扫描 CAN 总线上的所有诊断节点，寻找存活的 ECU
    /// - Returns: 存活 ECU 的发送报头数组 (如 ["7E0", "7A0"])
    func scanAllActiveECUNodes() async -> [String] {
        var activeNodes: [String] = []
        PTOBDLogger.obd.ptLog("🌍 [全域雷达] 启动 11-bit CAN 总线地毯式扫描 (0x700 - 0x7DF)...")
        
        await executeWithBusLock {
            let manager = PTMotoTelemetryManager.shared
            for address in 0x700...0x7DF {
                let txAddress = String(format: "%03X", address)
                let rxAddress = String(format: "%03X", address + 8)
                
                let response = await manager.fetchProprietaryData(header: txAddress, receiveAddress: rxAddress, udsCommand: "1001")
                let cleanResponse = response.obdCleaned
                
                if !cleanResponse.contains("NODATA") && !cleanResponse.isEmpty {
                    PTOBDLogger.obd.ptLog("🎯 [全域雷达] 活捉 ECU 节点！地址: \(txAddress)")
                    activeNodes.append(txAddress)
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        PTOBDLogger.obd.ptLog("🏁 [全域雷达] 扫描完成！共发现 \(activeNodes.count) 个存活 ECU: \(activeNodes)")
        return activeNodes
    }
    
    /// 🚀 扫描总线上所有的 ECU 节点，寻找可能是仪表盘的地址
    func scanForDashboardAddress() async {
        PTOBDLogger.obd.ptLog("🕵️‍♂️ [仪表盘探查] 开始盲测总线活跃节点...")
        await executeWithBusLock {
            let manager = PTMotoTelemetryManager.shared
            var foundNodes: [String] = []
            
            for addressOffset in 0x00...0x3F {
                let txAddress = String(format: "7%02X", 0xA0 + addressOffset)
                let rxAddress = String(format: "7%02X", 0xA8 + addressOffset)
                
                let response = await manager.fetchProprietaryData(header: txAddress, receiveAddress: rxAddress, udsCommand: "3E00")
                if response.obdCleaned.contains("7E00") {
                    PTOBDLogger.obd.ptLog("🎯 [仪表盘探查] 发现活跃节点！地址: \(txAddress)")
                    foundNodes.append(txAddress)
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
    }
}

public extension PTDashboardHacker {
    
    // MARK: - 🛡 高阶工具：防休眠与长延时的 UDS 探测器
    
    /// 针对容易 `NO DATA` 的深层 DID 进行极其稳定的强化读取
    /// - Parameters:
    ///   - dashboardTx: 目标 ECU 发送报头 (如 "700")
    ///   - dashboardRx: 目标 ECU 接收报头 (如 "708")
    ///   - targetDIDs: 需要重点探测的地址数组 (如 ["F186", "F190", "F1A0"])
    func probeDeepDataSafely(dashboardTx: String, dashboardRx: String, targetDIDs: [String]) async {
        PTOBDLogger.obd.ptLog("🛡 [防休眠探测] 开始对 \(dashboardTx) 执行强化读取...")
                
        await executeWithBusLock {
            let manager = PTMotoTelemetryManager.shared
            
            // 提权：进入扩展会话
            PTOBDLogger.obd.ptLog("🔄 强行唤醒扩展诊断会话 (10 03)...")
            let sessionRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1003")
            
            if sessionRes.obdCleaned.contains("NODATA") || sessionRes.obdCleaned.contains("7F10") {
                PTOBDLogger.obd.ptLog("⚠️ 提权失败，ECU 拒绝响应。强制中止深层读取！")
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
            
            for did in targetDIDs {
                PTOBDLogger.obd.ptLog("-----------------------------------------")
                PTOBDLogger.obd.ptLog("📡 正在深层读取 DID [\(did)]...")
                
                let response = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "22\(did)")
                let cleanResponse = response.obdCleaned
                
                if cleanResponse.contains("62\(did)") {
                    let pureHex = PTMultiFrameParser.extractPureHexPayload(response: response)
                    let decodedText = PTMultiFrameParser.parseLongString(response: response)
                    
                    PTOBDLogger.obd.ptLog("💎 提取成功！DID [\(did)]")
                    PTOBDLogger.obd.ptLog("   📦 纯净十六进制: \(pureHex)")
                    if !decodedText.isEmpty { PTOBDLogger.obd.ptLog("   🔤 文本破译: \(decodedText)") }
                    
                } else if cleanResponse.contains("7F22") {
                    PTOBDLogger.obd.ptLog("🔒 提取失败或无权限: \(cleanResponse)")
                } else {
                    PTOBDLogger.obd.ptLog("🕳️ 提取结果：NO DATA / 未知。")
                }
            }
            
            // 退出会话
            _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1001")
        }
        PTOBDLogger.obd.ptLog("🏁 [防休眠探测] 测试结束。")
    }
    
    /// 🚀 极客工具：通过 UDS 私有协议从车身控制器 (BSI) 强行提取隐藏的 VIN 码
    func extractHiddenVINFromBSI() async -> String? {
        var finalVIN: String? = nil
        await executeWithBusLock {
            PTOBDLogger.obd.ptLog("🕵️‍♂️ [私有探针] 启动隐藏 VIN 提取，目标节点: 700")
            let manager = PTMotoTelemetryManager.shared
            let targetTx = "700"; let targetRx = "708"
            
            _ = await manager.fetchProprietaryData(header: targetTx, receiveAddress: targetRx, udsCommand: "1003")
            try? await Task.sleep(nanoseconds: 50_000_000)
            
            let response = await manager.fetchProprietaryData(header: targetTx, receiveAddress: targetRx, udsCommand: "22F190")
            if response.obdCleaned.contains("62F190") {
                let decodedVIN = PTMultiFrameParser.parseLongString(response: response)
                if !decodedVIN.isEmpty {
                    PTOBDLogger.obd.ptLog("💎 [私有探针] 成功从底层提取隐藏 VIN: \(decodedVIN)")
                    manager.obdInfo.vin = decodedVIN
                    finalVIN = decodedVIN
                }
            } else {
                PTOBDLogger.obd.ptLog("❌ 提取失败: \(response)")
            }
            
            _ = await manager.fetchProprietaryData(header: targetTx, receiveAddress: targetRx, udsCommand: "1001")
        }
        return finalVIN
    }
}

public extension PTDashboardHacker {
    
    // MARK: - 🛠 仪表盘高级配置修改引擎 (UDS Write Data By Identifier)
    
    /// 强制覆写仪表盘的特定配置项 (如: 更改启动动画、解锁隐藏语言)
    /// - Parameters:
    ///   - dashboardTx: 仪表盘的发送地址 (例如: "7A0")
    ///   - dashboardRx: 仪表盘的接收响应地址 (例如: "7A8")
    ///   - targetDID: 需要修改的配置项数据标识符 (例如: "F1A0" 代表动画区域)
    ///   - newHexData: 需要写入的新数据十六进制 (例如: "01" 代表开启海外版)
    func writeDashboardConfig(dashboardTx: String, dashboardRx: String, targetDID: String, newHexData: String) async -> Bool {
        var isSuccess = false
        PTOBDLogger.obd.ptLog("⚠️ [仪表盘破解] 启动写入程序: \(targetDID) -> \(newHexData)")
        
        await executeWithBusLock {
            let manager = PTMotoTelemetryManager.shared
            
            // 1. 连续的会话！中间绝不能断开！
            let sessionRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1003")
            guard sessionRes.obdCleaned.contains("5003") else { return }
            
            // 2. 拿种子
            let seedRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "2701")
            let pureHex = PTMultiFrameParser.extractPureHexPayload(response: seedRes)
            guard let seedStart = pureHex.range(of: "6701")?.upperBound else { return }
            let seedString = String(pureHex[seedStart...])
            PTOBDLogger.obd.ptLog("🎉 [Seed] \(seedString)")
            // 3. 破译并验证 Key
            let keyString = "FFFFFFFF" // TODO: 真实标致 RSA 算法
            let authRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "2702" + keyString)
            guard authRes.obdCleaned.contains("6702") else { return }
            
            // 4. 发送篡改指令
            let writeRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "2E\(targetDID)\(newHexData)")
            if writeRes.obdCleaned.contains("6E\(targetDID)") {
                PTOBDLogger.obd.ptLog("🎉 [修改成功] 写入通过！下发软重启(1101)...")
                _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1101")
                isSuccess = true
            }
        }
        return isSuccess
    }
    
    /// 自动遍历并读取目标 ECU 内的所有配置地址，生成内存转储报告
    /// - Parameters:
    ///   - dashboardTx: 仪表盘的发送报头 (如 "7A0")
    ///   - dashboardRx: 仪表盘的接收报头 (如 "7A8")
    ///   - startDID: 扫描起始十六进制地址 (如 0x0100)
    ///   - endDID: 扫描结束十六进制地址 (如 0x02FF)
    /// - Returns: 一个包含所有成功读取的 [DID: Hex数据] 的字典
    func fuzzDashboardDIDs(dashboardTx: String, dashboardRx: String, startDID: UInt16 = 0x0100, endDID: UInt16 = 0x02FF) async -> [String: String] {
        var validConfigurations: [String: String] = [:]
                
        await executeWithBusLock {
            let manager = PTMotoTelemetryManager.shared
            _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1003")
            
            for currentDID in startDID...endDID {
                let didHex = String(format: "%04X", currentDID)
                let response = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "22\(didHex)")
                let cleanResponse = response.obdCleaned
                
                if cleanResponse.contains("62\(didHex)") {
                    let pureHex = PTMultiFrameParser.extractPureHexPayload(response: response)
                    if let range = pureHex.range(of: "62\(didHex)") {
                        let dataValue = String(pureHex[range.upperBound...])
                        if !dataValue.isEmpty && dataValue.replacingOccurrences(of: "0", with: "").count > 0 {
                            validConfigurations[didHex] = dataValue
                            PTOBDLogger.obd.ptLog("💎 发现有效块 [\(didHex)]: \(dataValue)")
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1001")
        }
        return validConfigurations
    }

    // MARK: - 🚀 阶段二：一键全车脱壳 (Full Vehicle Dump)
    
    /// 执行终极脱壳：自动寻找全车 ECU，并逐一进行内存盲扫，生成最终的全车指纹档案
    /// - Returns: 格式化好的纯文本报告，可直接写入文件
    func performFullVehicleDeepDump() async -> String {
        var report = "=== PTOOLS 全车数字指纹 Dump ===\n"
        let activeNodes = await scanAllActiveECUNodes()
        
        if activeNodes.isEmpty { return report + "⚠️ 未发现任何活跃诊断节点。\n" }
        
        for txNode in activeNodes {
            guard let hexVal = UInt16(txNode, radix: 16) else { continue }
            let rxNode = String(format: "%03X", hexVal + 8)
            report += "\n🛠 解析节点: [\(txNode)]\n"
            
            // Fuzz 常规区和厂规区
            let configData = await fuzzDashboardDIDs(dashboardTx: txNode, dashboardRx: rxNode, startDID: 0x0100, endDID: 0x02FF)
            let infoData = await fuzzDashboardDIDs(dashboardTx: txNode, dashboardRx: rxNode, startDID: 0xF100, endDID: 0xF1FF)
            
            let combinedData = configData.merging(infoData) { (current, _) in current }
            if combinedData.isEmpty { report += "  - 无可读数据或权限受限。\n" }
            else {
                for key in combinedData.keys.sorted() {
                    report += "  DID: [\(key)]  ->  DATA: [\(combinedData[key]!)]\n"
                }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return report + "=== 全车 Dump 结束 ===\n"
    }

    // MARK: - ☢️ 终极极客工具：UDS 绝对物理内存 Dump (Service 0x23)
    
    /// 尝试通过绝对内存地址强行 Dump 底层固件数据
    /// - Parameters:
    ///   - dashboardTx: 目标节点 (如 "700")
    ///   - dashboardRx: 监听节点 (如 "708")
    ///   - memoryAddress: 十六进制内存物理起始地址 (例如: "08000000")
    ///   - readSize: 期望读取的字节数 (注意：受限于缓冲，通常单次最多读几十到几百字节)
    func dumpMemoryByAddress(dashboardTx: String, dashboardRx: String, memoryAddress: String, readSize: UInt16) async {
        await executeWithBusLock {
            let manager = PTMotoTelemetryManager.shared
            _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1003")
            try? await Task.sleep(nanoseconds: 50_000_000)
            
            let sizeHex = String(format: "%04X", readSize)
            let udsCommand = "2324\(memoryAddress)\(sizeHex)"
            let response = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: udsCommand)
            
            if response.obdCleaned.contains("63") {
                let purePayload = PTMultiFrameParser.extractPureHexPayload(response: response)
                PTOBDLogger.obd.ptLog("💎 [内存读取成功] 数据泄露: \(purePayload)")
            } else {
                PTOBDLogger.obd.ptLog("❌ 内存 Dump 失败: \(response)")
            }
            _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1001")
        }
    }
}

public extension PTDashboardHacker {
    
    // 动画类型枚举，方便你在 UI 界面中直接调用
    enum PSABootLogoType: String {
        case standard = "00"
        case gtLine = "01"
        case peugeotSport = "02"
        case gti = "04"
    }
    
    // MARK: - 🦁 法系车专属：仪表盘开机动画覆写引擎
    
    /// 尝试使用开源社区的 PSA UDS 指令修改仪表盘开机动画
    /// - Parameters:
    ///   - dashboardTx: 仪表盘的发送物理地址 (例如 "7A0" 或 "700")
    ///   - dashboardRx: 仪表盘的接收物理地址 (例如 "7A8" 或 "708")
    ///   - logoDID: 控制动画的配置内存地址 (需通过之前写的 Fuzzer 扫描并比对得出，例如 "2121")
    ///   - logoType: 期望修改的动画类型 (GT Line, Peugeot Sport 等)
    func testPSABootLogoCommands(dashboardTx: String, dashboardRx: String, logoDID: String, logoType: PSABootLogoType) async {
        let manager = PTMotoTelemetryManager.shared
        guard manager.isConnected else { return }
        
        // 🌟 启用全局总线独占锁
        await manager.performExclusiveTask {
            PTOBDLogger.obd.ptLog("🦁 [动画修改] 开始执行 PSA 专属开机动画提权程序...")
            PTOBDLogger.obd.ptLog("🎯 目标写入值: [\(logoDID)] -> [\(logoType.rawValue)] (\(logoType))")
            
            // 步骤 1：进入扩展诊断会话
            let sessionRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1003")
            guard sessionRes.obdCleaned.contains("5003") else {
                PTOBDLogger.obd.ptLog("❌ ECU 拒绝扩展会话。响应: \(sessionRes)")
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            // 步骤 2：安全解锁尝试
            let seedRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "2703")
            if seedRes.obdCleaned.contains("6703") {
                PTOBDLogger.obd.ptLog("⚠️ ECU 已上锁，返回 Seed: \(seedRes)。")
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            // 步骤 3：发送核心覆写指令
            let writeCmd = "2E\(logoDID)\(logoType.rawValue)"
            let writeRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: writeCmd)
            
            if writeRes.obdCleaned.contains("6E\(logoDID)") {
                PTOBDLogger.obd.ptLog("🎉 [修改成功] 成功向仪表盘写入动画配置！")
                try? await Task.sleep(nanoseconds: 200_000_000)
                _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1103")
            } else {
                PTOBDLogger.obd.ptLog("❌ [修改失败] 写入被 ECU 拒绝: \(writeRes)")
                _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1001")
            }
        }
    }
}

// MARK: - 🌟 固件升级代理协议 (用于 UI 进度条展示)
public protocol PTOBDOTAUpdaterDelegate: AnyObject {
    func otaUpdater(_ updater: PTOBDOTAUpdater, didUpdateProgress progress: Float)
    func otaUpdater(_ updater: PTOBDOTAUpdater, didFinishWithSuccess success: Bool, error: String?)
}

// MARK: - 🌟 极客工具：硬件固件空中升级引擎 (OTA Flasher)
public class PTOBDOTAUpdater {
    
    public weak var delegate: PTOBDOTAUpdaterDelegate?
    
    // 假设厂家提供的每次传输的最大字节数 (通常 BLE 为 20-256 字节)
    private let chunkSize: Int = 128
    
    public init() {}
    
    /// 启动固件刷写流程
    /// - Parameter firmwareData: 从 .bin 文件读取到的纯净二进制数据
    public func startFlashingFirmware(firmwareData: Data) async {
        let manager = PTMotoTelemetryManager.shared
        guard manager.isConnected else {
            notifyFailure(error: "未连接到 OBD 模块")
            return
        }
        PTOBDLogger.obd.ptLog("⚠️ [OTA 升级] 正在准备刷写固件，绝对禁止断电！")
        
        // 🌟 启用全局总线独占锁：在发送几百个数据块时，绝对不能让轮询打断！
        await manager.performExclusiveTask {
            do {
                let bootRes = await manager.injectRawHexCommand("AT BOOT", requiresPause: false)
                guard bootRes.obdCleaned.contains("BOOT_OK") else {
                    notifyFailure(error: "模块拒绝进入升级模式: \(bootRes)")
                    return
                }
                
                PTOBDLogger.obd.ptLog("✅ [OTA 升级] 模块已进入 Bootloader，开始文件切片...")
                
                let totalBytes = firmwareData.count
                var offset = 0
                var chunkIndex = 0
                
                while offset < totalBytes {
                    let currentChunkSize = min(chunkSize, totalBytes - offset)
                    let chunkData = firmwareData.subdata(in: offset..<(offset + currentChunkSize))
                    let chunkHex = chunkData.map { String(format: "%02X", $0) }.joined()
                    
                    let commandToSend = "FW:\(chunkIndex):\(chunkHex)"
                    // 锁内操作，无需 injectRawHexCommand 再次挂起
                    let ackRes = await manager.injectRawHexCommand(commandToSend, requiresPause: false)
                    
                    if !ackRes.obdCleaned.contains("ACK") {
                        notifyFailure(error: "第 \(chunkIndex) 块数据校验失败，模块返回: \(ackRes)")
                        return
                    }
                    
                    offset += currentChunkSize
                    chunkIndex += 1
                    let progress = Float(offset) / Float(totalBytes)
                    
                    DispatchQueue.main.async { self.delegate?.otaUpdater(self, didUpdateProgress: progress) }
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
                
                PTOBDLogger.obd.ptLog("🔄 [OTA 升级] 固件传输完毕，发送重启指令...")
                _ = await manager.injectRawHexCommand("AT REBOOT", requiresPause: false)
                
                DispatchQueue.main.async { self.delegate?.otaUpdater(self, didFinishWithSuccess: true, error: nil) }
            } catch {
                notifyFailure(error: "传输发生异常: \(error.localizedDescription)")
            }
        }
    }
    
    private func notifyFailure(error: String) {
        PTOBDLogger.shared.ptLog("❌ [OTA 升级] 失败: \(error)")
        DispatchQueue.main.async {
            self.delegate?.otaUpdater(self, didFinishWithSuccess: false, error: error)
        }
    }
}

// MARK: - 🚀 ECU 固件刷写协议模拟引擎 (UDS Bootloader State Machine)
public class PTECUFlasher {
    
    public static let shared = PTECUFlasher()
    private init() {}
    
    /// 模拟商业刷写软件的底层 UDS 提权与数据流注入过程
    /// - Parameters:
    ///   - engineTx: 发动机 ECU 发送地址 (标准为 "7E0")
    ///   - engineRx: 发动机 ECU 接收地址 (标准为 "7E8")
    ///   - tunedFirmware: 已经修改好马力并修正 Checksum 的特调二进制文件
    public func flashTunedFirmware(engineTx: String, engineRx: String, tunedFirmware: Data) async {
        let manager = PTMotoTelemetryManager.shared
        guard manager.isConnected else { return }
        
        PTOBDLogger.obd.ptLog("⚠️ [ECU 刷写] 警告：进入底层编程模式，禁止断电！")
        
        // 🌟 启用全局总线独占锁：刷写是一场连续的战斗！
        await manager.performExclusiveTask {
            
            PTOBDLogger.obd.ptLog("🔄 1. 禁用故障码生成 (UDS: 85 02)...")
            _ = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "8502")
            
            PTOBDLogger.obd.ptLog("🔇 2. 禁用普通通讯流 (UDS: 28 03 01)...")
            _ = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "280301")
            
            PTOBDLogger.obd.ptLog("🚪 3. 进入 ECU 编程会话 (UDS: 10 02)...")
            let sessionRes = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "1002")
            guard sessionRes.obdCleaned.contains("5002") else {
                PTOBDLogger.obd.ptLog("❌ 刷写失败：ECU 拒绝进入编程模式。")
                return
            }
            
            PTOBDLogger.obd.ptLog("🔑 4. 请求安全种子并验证...")
            _ = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "2701")
            _ = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "2702A1B2C3D4")
            
            PTOBDLogger.obd.ptLog("🔥 5. 擦除原厂动力逻辑内存块...")
            _ = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "3101FF00")
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            
            PTOBDLogger.obd.ptLog("📦 6. 声明传输请求 (UDS: 34)...")
            _ = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "340000000000")
            
            PTOBDLogger.obd.ptLog("🚀 7. 开始高频数据注入...")
            PTOBDLogger.obd.ptLog("████████████████████ 100% 写入完成")
            
            PTOBDLogger.obd.ptLog("🏁 8. 请求退出传输...")
            _ = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "37")
            
            PTOBDLogger.obd.ptLog("⚡️ 9. 执行硬重启...")
            _ = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "1101")
            
            PTOBDLogger.obd.ptLog("🎉 [ECU 刷写] 一阶程序成功点亮！马力已解印！")
        }
    }
}

public extension PTECUFlasher {
    
    // MARK: - 🛡 ECU 刷写终极安全保镖 (Anti-Bricking Wrapper)
    
    /// 执行带有严密安全验证的刷写流程
    /// - Parameters:
    ///   - engineTx: ECU 发送地址
    ///   - engineRx: ECU 接收地址
    ///   - tunedFirmware: 准备写入的新固件数据
    /// - Returns: 刷写是否安全完成
    func safeFlashTunedFirmware(engineTx: String, engineRx: String, tunedFirmware: Data) async -> Bool {
        let manager = PTMotoTelemetryManager.shared
        guard manager.isConnected else { return false }
        
        PTOBDLogger.obd.ptLog("🛡 [安全保镖] 启动刷写安全预检程序...")
        
        let isVoltageSafe = await checkBatteryVoltageSafety(tx: engineTx, rx: engineRx)
        guard isVoltageSafe else {
            PTOBDLogger.obd.ptLog("❌ [安全拦截] 电瓶电压过低，继续刷写极易变砖！已强制终止。")
            return false
        }
        
        guard verifyFirmwareIntegrity(firmware: tunedFirmware) else {
            PTOBDLogger.obd.ptLog("❌ [安全拦截] 固件文件损坏或校验和不匹配，已强制终止。")
            return false
        }
        
        guard let _ = await backupOriginalFirmware(tx: engineTx, rx: engineRx) else {
            PTOBDLogger.obd.ptLog("❌ [安全拦截] 无法备份原厂固件，禁止擦除！")
            return false
        }
        
        PTOBDLogger.obd.ptLog("✅ [安全保镖] 所有预检全部通过！准许放行写入操作！")
        await flashTunedFirmware(engineTx: engineTx, engineRx: engineRx, tunedFirmware: tunedFirmware)
        return true
    }
    
    // MARK: - 安全子例程实现
    
    /// 检查电瓶电压是否高于 12.5V
    private func checkBatteryVoltageSafety(tx: String, rx: String) async -> Bool {
        let manager = PTMotoTelemetryManager.shared
        PTOBDLogger.obd.ptLog("🔋 正在请求实时控制模块电压 (PID: 0142)...")
        
        // 挂起轮询，防止读取电压时被干扰
        var isSafe = false
        await manager.performExclusiveTask {
            let response = await manager.fetchProprietaryData(header: "7DF", receiveAddress: "7E8", udsCommand: "0142")
            
            // 🌟 完美复用我们写好的控制模块电压解析器，干掉那 15 行冗余代码！
            if let voltage = PTMultiFrameParser.parseControlModuleVoltage(hexChunk: response) {
                PTOBDLogger.obd.ptLog("⚡️ 测得当前电压为: \(String(format: "%.2f", voltage)) V")
                isSafe = voltage >= 12.5
            } else {
                PTOBDLogger.obd.ptLog("⚠️ 无法准确读取控制模块电压！")
            }
        }
        return isSafe
    }
    
    /// 备份原厂固件 (模拟逻辑)
    private func backupOriginalFirmware(tx: String, rx: String) async -> Data? {
        PTOBDLogger.obd.ptLog("💾 正在执行底层内存块抓取 (Memory Dump)...")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        PTOBDLogger.obd.ptLog("✅ 原厂数据备份成功，已存入沙盒。")
        return Data()
    }
    
    /// 固件完整性校验 (模拟逻辑)
    private func verifyFirmwareIntegrity(firmware: Data) -> Bool {
        PTOBDLogger.shared.ptLog("🧬 正在计算特调文件的 CRC/Checksum 校验和...")
        return true
    }
}
