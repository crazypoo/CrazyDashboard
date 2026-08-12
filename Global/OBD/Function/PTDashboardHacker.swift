//
//  PTDashboardHacker.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 12/8/2026.
//

import Foundation

public class PTDashboardHacker {
    public static let shared = PTDashboardHacker()
    
    let manager = PTMotoTelemetryManager.shared
    
    private init() {}
    
    /// 🚀 扫描总线上所有的 ECU 节点，寻找可能是仪表盘的地址
    /// 标致 (PSA集团) 的非动力模块地址通常在 7A0 - 7CF 之间
    public func scanForDashboardAddress() async {
        let manager = PTMotoTelemetryManager.shared
        guard manager.isConnected else {
            PTOBDLogger.shared.ptLog("❌ [仪表盘探查] 模块未连接！")
            return
        }
        
        PTOBDLogger.shared.ptLog("🕵️‍♂️ [仪表盘探查] 开始盲测总线活跃节点...")
        
        // UDS 服务 3E 00 (Tester Present) - 询问节点“你在吗？”
        let pingCommand = "3E00"
        
        // 挂起你底层的 10ms 常规轮询，防止总线拥堵
        let wasPolling = (manager.telemetryPollingTask != nil)
        if wasPolling { manager.telemetryPollingTask?.cancel() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        var foundNodes: [String] = []
        
        // 尝试遍历 7A0 到 7DF 的可能地址 (这里仅作示例，缩小范围提高速度)
        for addressOffset in 0x00...0x3F {
            let txAddress = String(format: "7%02X", 0xA0 + addressOffset)
            let rxAddress = String(format: "7%02X", 0xA8 + addressOffset) // 假设响应地址是 TX + 8
            
            // 使用之前写好的万能私有探针发起探测
            let response = await manager.fetchProprietaryData(header: txAddress, receiveAddress: rxAddress, udsCommand: pingCommand)
            
            // 7E 是 3E 成功的响应头
            if response.contains("7E00") {
                PTOBDLogger.shared.ptLog("🎯 [仪表盘探查] 发现活跃节点！地址: \(txAddress) -> 响应: \(rxAddress)")
                foundNodes.append(txAddress)
            }
            
            // 给总线留点喘息时间
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        
        PTOBDLogger.shared.ptLog("🏁 [仪表盘探查] 扫描完毕，活跃节点列表: \(foundNodes)")
        
        // 恢复日常轮询
        if wasPolling {
            // manager.startLightweightPolling(...) // 呼叫你的底层恢复方法
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
    
    // MARK: - 🛠 仪表盘高级配置修改引擎 (UDS Write Data By Identifier)
    
    /// 强制覆写仪表盘的特定配置项 (如: 更改启动动画、解锁隐藏语言)
    /// - Parameters:
    ///   - dashboardTx: 仪表盘的发送地址 (例如: "7A0")
    ///   - dashboardRx: 仪表盘的接收响应地址 (例如: "7A8")
    ///   - targetDID: 需要修改的配置项数据标识符 (例如: "F1A0" 代表动画区域)
    ///   - newHexData: 需要写入的新数据十六进制 (例如: "01" 代表开启海外版)
    func writeDashboardConfig(dashboardTx: String, dashboardRx: String, targetDID: String, newHexData: String) async -> Bool {
        
        let manager = PTMotoTelemetryManager.shared
        guard manager.isConnected else {
            PTOBDLogger.shared.ptLog("❌ [仪表盘破解] 模块未连接，无法执行写入！")
            return false
        }
        
        PTOBDLogger.shared.ptLog("⚠️ [仪表盘破解] 警告：正在启动底层写入程序，修改 DID: \(targetDID) -> \(newHexData)")
        
        // 步骤 1：进入扩展诊断会话 (UDS 10 03)
        // 只有在这个会话下，仪表盘才允许进行安全解锁和写入
        let sessionRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1003")
        guard sessionRes.contains("5003") else {
            PTOBDLogger.shared.ptLog("❌ [步骤 1 失败] 模块拒绝进入扩展会话: \(sessionRes)")
            return false
        }
        PTOBDLogger.shared.ptLog("✅ [步骤 1 成功] 已进入扩展诊断会话")
        
        // 步骤 2：请求安全种子 (UDS 27 01)
        let seedRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "2701")
        guard seedRes.contains("6701") else {
            PTOBDLogger.shared.ptLog("❌ [步骤 2 失败] 无法获取安全 Seed: \(seedRes)")
            return false
        }
        
        // 提取返回的 Seed 数据 (假设 67 01 后面的字节就是 Seed)
        let pureHex = PTMultiFrameParser.extractPureHexPayload(response: seedRes)
        guard let seedStart = pureHex.range(of: "6701")?.upperBound else { return false }
        let seedString = String(pureHex[seedStart...])
        PTOBDLogger.shared.ptLog("🔑 获取到安全种子 Seed: \(seedString)")
        
        // 步骤 3：计算并发送密钥 Key (UDS 27 02)
        // ⚠️ 注意：这里使用了一个模拟的演示计算算法。
        // 在实战中，你需要根据标致机车的原厂 Seed-Key 算法来计算，否则仪表盘会返回 7F 27 35 (Invalid Key)
        let keyString = calculatePeugeotSecurityKey(seedHex: seedString)
        
        let authRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "2702" + keyString)
        guard authRes.contains("6702") else {
            PTOBDLogger.shared.ptLog("❌ [步骤 3 失败] 密钥验证失败 (安全访问被拒绝): \(authRes)")
            return false
        }
        PTOBDLogger.shared.ptLog("✅ [步骤 3 成功] 安全访问解锁完成，获取写入权限！")
        
        // 步骤 4：写入新配置数据 (UDS 2E + DID + Data)
        let writeCommand = "2E" + targetDID + newHexData
        let writeRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: writeCommand)
        
        // 6E 是 2E 写入成功的标准返回报头
        guard writeRes.contains("6E\(targetDID)") else {
            PTOBDLogger.shared.ptLog("❌ [步骤 4 失败] 写入配置失败: \(writeRes)")
            return false
        }
        PTOBDLogger.shared.ptLog("✅ [步骤 4 成功] 新配置数据已成功刷入仪表盘内存！")
        
        // 步骤 5：硬重启 ECU，让新配置生效 (UDS 11 01)
        PTOBDLogger.shared.ptLog("🔄 [步骤 5] 正在发送重启指令，请观察仪表盘是否重启...")
        _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1101")
        
        return true
    }
    
    // MARK: - 🔒 原厂安全密钥计算器 (模拟)
    private func calculatePeugeotSecurityKey(seedHex: String) -> String {
        // TODO: 填入真实的逆向算法
        // 这里仅作为代码演示：假设算法是将 Seed 原样返回，或者固定返回 "FFFFFFFF"
        PTOBDLogger.shared.ptLog("正在使用内置算法计算 Key...")
        return "FFFFFFFF"
    }
}


public extension PTDashboardHacker {
    
    // MARK: - 🕵️‍♂️ 终极黑客工具：UDS 内存配置全量盲扫器 (DID Fuzzer)
    
    /// 自动遍历并读取目标 ECU 内的所有配置地址，生成内存转储报告
    /// - Parameters:
    ///   - dashboardTx: 仪表盘的发送报头 (如 "7A0")
    ///   - dashboardRx: 仪表盘的接收报头 (如 "7A8")
    ///   - startDID: 扫描起始十六进制地址 (如 0x0100)
    ///   - endDID: 扫描结束十六进制地址 (如 0x02FF)
    /// - Returns: 一个包含所有成功读取的 [DID: Hex数据] 的字典
    func fuzzDashboardDIDs(dashboardTx: String, dashboardRx: String, startDID: UInt16 = 0x0100, endDID: UInt16 = 0x02FF) async -> [String: String] {
        
        let manager = PTMotoTelemetryManager.shared
        guard manager.isConnected else {
            PTOBDLogger.shared.ptLog("❌ [Fuzzer] 未连接到总线，扫描中止。")
            return [:]
        }
        
        let startHexStr = String(format: "%04X", startDID)
        let endHexStr = String(format: "%04X", endDID)
        let totalCount = endDID - startDID + 1
        
        PTOBDLogger.shared.ptLog("🚀 [Fuzzer] 开始执行暴力内存盲扫！区间: \(startHexStr) 到 \(endHexStr) (共 \(totalCount) 个地址)")
        
        // 挂起日常轮询，霸占总线绝对控制权
        let wasPolling = (manager.telemetryPollingTask != nil)
        if wasPolling { manager.telemetryPollingTask?.cancel() }
        
        // 尝试进入扩展会话 (10 03)，因为很多配置项在默认会话下会隐藏或拒绝读取
        _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1003")
        
        var validConfigurations: [String: String] = [:]
        
        for currentDID in startDID...endDID {
            let didHex = String(format: "%04X", currentDID)
            let readCommand = "22\(didHex)"
            
            // 发送读取请求
            let response = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: readCommand)
            
            let cleanResponse = response.replacingOccurrences(of: " ", with: "").uppercased()
            let expectedSuccessHeader = "62\(didHex)"
            
            // 如果响应中包含了 62 + DID，说明提取成功！
            if cleanResponse.contains(expectedSuccessHeader), let range = cleanResponse.range(of: expectedSuccessHeader) {
                // 截取该 DID 背后隐藏的具体配置数据
                let dataValue = String(cleanResponse[range.upperBound...])
                
                // 排除掉全 0 的空数据占位符
                if !dataValue.isEmpty && dataValue.replacingOccurrences(of: "0", with: "").count > 0 {
                    validConfigurations[didHex] = dataValue
                    PTOBDLogger.shared.ptLog("💎 [Fuzzer 命中] 发现有效配置块！DID: [\(didHex)] -> 数据: [\(dataValue)]")
                }
            } else if cleanResponse.contains("7F2233") {
                // 7F 22 33 代表 Security Access Denied，说明找对地方了，但需要密码解锁才能看
                PTOBDLogger.shared.ptLog("🔒 [Fuzzer 遇阻] 发现加密块！DID: [\(didHex)] 需要 27 服务安全解锁。")
            }
            
            // 极其关键的休眠：千万不能毫无间隔地轰炸 ECU，否则会导致仪表盘死机重启
            try? await Task.sleep(nanoseconds: 30_000_000) // 30 毫秒间隔
        }
        
        PTOBDLogger.shared.ptLog("🏁 [Fuzzer] 扫描完毕！共挖掘出 \(validConfigurations.count) 个有效配置项。")
        
        // 退出扩展会话，恢复常态
        _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1001")
        
        // 如果要恢复日常数据轮询，可以在这里触发
        // if wasPolling { ... }
        
        return validConfigurations
    }
}

public extension PTDashboardHacker {
    
    // MARK: - 🌍 阶段一：全域 ECU 节点雷达扫描 (Ping Sweep)
    
    /// 扫描 CAN 总线上的所有诊断节点，寻找存活的 ECU
    /// - Returns: 存活 ECU 的发送报头数组 (如 ["7E0", "7A0"])
    func scanAllActiveECUNodes() async -> [String] {
        let manager = PTMotoTelemetryManager.shared
        guard manager.isConnected else { return [] }
        
        PTOBDLogger.shared.ptLog("🌍 [全域雷达] 启动 11-bit CAN 总线地毯式扫描 (0x700 - 0x7DF)...")
        
        // 挂起轮询，霸占总线
        let wasPolling = (manager.telemetryPollingTask != nil)
        if wasPolling { manager.telemetryPollingTask?.cancel() }
        
        var activeNodes: [String] = []
        
        // 遍历标准的诊断地址段
        for address in 0x700...0x7DF {
            let txAddress = String(format: "%03X", address)
            // 在 ISO 15765-4 协议中，接收地址通常是发送地址 + 8
            let rxAddress = String(format: "%03X", address + 8)
            
            // 使用 UDS 10 01 (默认诊断会话) 作为 Ping 指令，它是最安全且各模块必须响应的指令
            let response = await manager.fetchProprietaryData(header: txAddress, receiveAddress: rxAddress, udsCommand: "1001")
            let cleanResponse = response.replacingOccurrences(of: " ", with: "").uppercased()
            
            // 5001 是成功响应，7F10 是否定响应(但证明节点存在)。排除 NO DATA
            if !cleanResponse.contains("NODATA") && !cleanResponse.isEmpty {
                PTOBDLogger.shared.ptLog("🎯 [全域雷达] 活捉 ECU 节点！地址: \(txAddress) -> 响应: \(cleanResponse)")
                activeNodes.append(txAddress)
            }
            
            // 极速扫描间隔，保护总线不崩溃
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        
        PTOBDLogger.shared.ptLog("🏁 [全域雷达] 扫描完成！共发现 \(activeNodes.count) 个存活 ECU: \(activeNodes)")
        
        return activeNodes
    }
    
    // MARK: - 🚀 阶段二：一键全车脱壳 (Full Vehicle Dump)
    
    /// 执行终极脱壳：自动寻找全车 ECU，并逐一进行内存盲扫，生成最终的全车指纹档案
    /// - Returns: 格式化好的纯文本报告，可直接写入文件
    func performFullVehicleDeepDump() async -> String {
        let manager = PTMotoTelemetryManager.shared
        guard manager.isConnected else { return "错误：模块未连接" }
        
        var report = "=== PTOOLS 全车深度数字指纹 Dump ===\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        report += "记录时间: \(formatter.string(from: Date()))\n"
        report += "=========================================\n\n"
        
        // 1. 先雷达全域扫图
        let activeNodes = await scanAllActiveECUNodes()
        
        if activeNodes.isEmpty {
            report += "⚠️ 全域雷达未发现任何活跃诊断节点 (可能设备已断开或总线休眠)。\n"
            return report
        }
        
        // 2. 针对每一个抓到的 ECU，进行深度提权和 DID 盲扫
        // 我们扫最常见的配置区域: 0x0100~0x02FF (常规配置), 以及 0xF100~0xF1FF (车厂识别区)
        for txNode in activeNodes {
            // 计算对应的接收地址
            guard let hexVal = UInt16(txNode, radix: 16) else { continue }
            let rxNode = String(format: "%03X", hexVal + 8)
            
            report += "-----------------------------------------\n"
            report += "🛠 开始解析 ECU 节点: [TX: \(txNode) | RX: \(rxNode)]\n"
            report += "-----------------------------------------\n"
            
            PTOBDLogger.shared.ptLog("☢️ [深度脱壳] 正在向 ECU \(txNode) 发起内存遍历攻击...")
            
            // 第一波：盲扫 0100 - 02FF
            let configData = await fuzzDashboardDIDs(dashboardTx: txNode, dashboardRx: rxNode, startDID: 0x0100, endDID: 0x02FF)
            // 第二波：盲扫 F100 - F1FF (这一段通常包含固件版本、零件号、开发商等绝对机密)
            let infoData = await fuzzDashboardDIDs(dashboardTx: txNode, dashboardRx: rxNode, startDID: 0xF100, endDID: 0xF1FF)
            
            // 合并结果并写入报告
            let combinedData = configData.merging(infoData) { (current, _) in current }
            
            if combinedData.isEmpty {
                report += "  - 该节点拒绝访问或区间内无有效数据。\n\n"
            } else {
                let sortedKeys = combinedData.keys.sorted()
                for key in sortedKeys {
                    if let value = combinedData[key] {
                        report += "  DID: [\(key)]  ->  DATA: [\(value)]\n"
                    }
                }
                report += "\n"
            }
            
            // 扫完一个节点，硬休眠 1 秒，让总线网络和手机蓝牙缓冲层散散热
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        
        report += "=== 全车 Dump 结束 ===\n"
        
        // 恢复被挂起的底层高频轮询引擎 (为了不破坏你的主逻辑，我们在扫描结束时重启日常数据)
        let rawPIDsToResume = PTHiddenOBDConnector.shared.collectedPIDResponses.isEmpty ? PTWifiOBDConnector.shared.collectedPIDResponses : PTHiddenOBDConnector.shared.collectedPIDResponses
        manager.startLightweightPolling(rawPIDs: rawPIDsToResume)
        
        return report
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
        let manager = PTMotoTelemetryManager.shared
        guard manager.isConnected else { return }
        
        PTOBDLogger.shared.ptLog("🛡 [防休眠探测] 开始对 \(dashboardTx) 执行强化读取...")
        
        // 挂起日常轮询，霸占总线
        let wasPolling = (manager.telemetryPollingTask != nil)
        if wasPolling { manager.telemetryPollingTask?.cancel() }
        
        // 🌟 核心升级 1：延长 ELM327 的 CAN 接收超时时间
        // AT ST FF 表示将模块的等待时间设置到最大值 (约 1020 毫秒)，给 ECU 充足的思考时间
        _ = try? await manager.sendRawCommandAsync("ATSTFF")
        
        for did in targetDIDs {
            PTOBDLogger.shared.ptLog("-----------------------------------------")
            
            // 🌟 核心升级 2：防休眠机制 (每次读取前，强行刷新 10 03 扩展会话)
            // 这样保证无论前面经历了什么，ECU 此刻绝对处于最高权限状态！
            PTOBDLogger.shared.ptLog("🔄 强行唤醒扩展诊断会话 (10 03)...")
            let sessionRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1003")
            
            if sessionRes.contains("NODATA") {
                PTOBDLogger.shared.ptLog("⚠️ ECU 拒绝进入扩展会话，可能当前车辆状态不允许 (如引擎正在运转)。")
            }
            
            // 给 ECU 50 毫秒时间切换会话状态
            try? await Task.sleep(nanoseconds: 50_000_000)
            
            // 🌟 发送真正的读取指令 (22 服务)
            let readCmd = "22\(did)"
            PTOBDLogger.shared.ptLog("📡 正在深层读取 DID [\(did)]...")
            
            let response = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: readCmd)
            let cleanResponse = response.replacingOccurrences(of: " ", with: "").uppercased()
            
            // 🌟 核心升级 3：精准分析各种反馈结果
            if cleanResponse.contains("62\(did)") {
                // 成功读取！62 是 22 服务的成功回复
                PTOBDLogger.shared.ptLog("💎 提取成功！DID [\(did)] 的数据为: \(cleanResponse)")
            } else if cleanResponse.contains("7F22") {
                // 收到 7F 报错，说明 ECU 听到了，但拒绝了你
                if cleanResponse.contains("7F2231") {
                    PTOBDLogger.shared.ptLog("❌ 提取失败：ECU 明确表示该地址 [\(did)] 没有数据 (Out of Range)。")
                } else if cleanResponse.contains("7F2233") {
                    PTOBDLogger.shared.ptLog("🔒 提取失败：地址 [\(did)] 被密码锁定了！必须先通过 27 服务安全解锁！")
                } else {
                    PTOBDLogger.shared.ptLog("⚠️ 提取被 ECU 拒绝，错误码: \(cleanResponse)")
                }
            } else if cleanResponse.contains("NODATA") {
                // 如果在加长了超时时间、且确认了 10 03 会话后，还是 NO DATA
                // 这 100% 说明这台标致机车在这个 DID 上是个空壳，ECU 选择了无视。
                PTOBDLogger.shared.ptLog("🕳️ 提取结果：NO DATA。ECU 保持沉默，确定此地址无数据。")
            } else {
                PTOBDLogger.shared.ptLog("❓ 收到未知格式的回复: \(cleanResponse)")
            }
        }
        
        // 扫尾工作：恢复 ELM327 默认超时时间 (AT ST 32 = 约 200ms)，避免影响后续高频轮询的帧率
        _ = try? await manager.sendRawCommandAsync("ATST32")
        
        // 退出扩展会话
        _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1001")
        
        PTOBDLogger.shared.ptLog("🏁 [防休眠探测] 测试结束。")
        
        if wasPolling {
            let rawPIDsToResume = PTHiddenOBDConnector.shared.collectedPIDResponses.isEmpty ? PTWifiOBDConnector.shared.collectedPIDResponses : PTHiddenOBDConnector.shared.collectedPIDResponses
            manager.startLightweightPolling(rawPIDs: rawPIDsToResume)
        }
    }
}

extension PTDashboardHacker {
    
    /// 🚀 极客工具：通过 UDS 私有协议从车身控制器 (BSI) 强行提取隐藏的 VIN 码
    /// 标致 (PSA) 车系的标准私有 VIN 存放地址通常为 F190
    public func extractHiddenVINFromBSI() async -> String? {
        let manager = PTMotoTelemetryManager.shared
        guard manager.isConnected else { return nil }
        
        PTOBDLogger.shared.ptLog("🕵️‍♂️ [私有探针] 启动隐藏 VIN 提取，目标节点: 700")
        
        // 目标节点：700 (BSI/仪表主节点)，预期回复：708
        let targetTx = "700"
        let targetRx = "708"
        
        // 1. 尝试进入扩展诊断会话 (10 03)，读取敏感信息通常需要提权
        _ = await manager.fetchProprietaryData(header: targetTx, receiveAddress: targetRx, udsCommand: "1003")
        
        // 给 ECU 一点切换会话的反应时间
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        // 2. 发送 UDS 22 服务，读取 F190 (VIN 的工业惯用 DID)
        let response = await manager.fetchProprietaryData(header: targetTx, receiveAddress: targetRx, udsCommand: "22F190")
        let cleanResponse = response.replacingOccurrences(of: " ", with: "").uppercased()
        
        // 3. 验证是否成功返回 (成功标志为 62 F1 90)
        if cleanResponse.contains("62F190") {
            // 剥离掉非数据部分的 CAN 帧格式
            let purePayload = PTMultiFrameParser.extractPureHexPayload(response: cleanResponse)
            if let range = purePayload.range(of: "62F190") {
                let vinHex = String(purePayload[range.upperBound...])
                // 将十六进制 ASCII 转换为人类可读的字符串
                if let decodedVIN = String(bytes: hexStringToBytes(vinHex), encoding: .ascii) {
                    PTOBDLogger.shared.ptLog("💎 [私有探针] 成功从底层提取隐藏 VIN: \(decodedVIN)")
                    // 自动存入模型，供 UI 刷新
                    manager.obdInfo.vin = decodedVIN
                    return decodedVIN
                }
            }
        } else {
            PTOBDLogger.shared.ptLog("❌ [私有探针] 提取失败，节点返回: \(response)")
        }
        
        // 4. 退出扩展会话
        _ = await manager.fetchProprietaryData(header: targetTx, receiveAddress: targetRx, udsCommand: "1001")
        
        return nil
    }
    
    // 辅助工具：十六进制字符串转字节数组
    private func hexStringToBytes(_ hex: String) -> [UInt8] {
        var bytes = [UInt8]()
        var startIndex = hex.startIndex
        while startIndex < hex.endIndex {
            let endIndex = hex.index(startIndex, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[startIndex..<endIndex], radix: 16) {
                bytes.append(byte)
            }
            startIndex = endIndex
        }
        return bytes
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
        guard manager.isConnected else {
            PTOBDLogger.shared.ptLog("❌ [动画修改] 模块未连接！")
            return
        }
        
        PTOBDLogger.shared.ptLog("🦁 [动画修改] 开始执行 PSA 集团标致专属开机动画提权程序...")
        PTOBDLogger.shared.ptLog("🎯 目标写入值: [\(logoDID)] -> [\(logoType.rawValue)] (\(logoType))")
        
        // 挂起日常轮询，确保总线带宽完全属于 UDS 配置流
        let wasPolling = (manager.telemetryPollingTask != nil)
        if wasPolling { manager.telemetryPollingTask?.cancel() }
        
        // 步骤 1：进入扩展诊断会话 (PSA 标准配置提权)
        PTOBDLogger.shared.ptLog("🔄 [步骤 1] 正在请求扩展编程会话 (10 03)...")
        let sessionRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1003")
        guard sessionRes.contains("5003") else {
            PTOBDLogger.shared.ptLog("❌ ECU 拒绝扩展会话，可能车速不为 0 或引擎正在运转。响应: \(sessionRes)")
            resumePollingIfNeeded(manager, wasPolling)
            return
        }
        
        // 给 ECU 预留切换会话的缓冲时间
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // 步骤 2：安全解锁尝试 (针对 PSA 27 03 配置模式)
        // 提示：如果你的仪表盘该 DID 区域没有加锁，可以注释掉这段逻辑直接执行步骤 3
        PTOBDLogger.shared.ptLog("🔑 [步骤 2] 尝试请求安全种子 (27 03)...")
        let seedRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "2703")
        if seedRes.contains("6703") {
            PTOBDLogger.shared.ptLog("⚠️ ECU 已上锁，返回 Seed: \(seedRes)。由于缺少开源 RSA 证书，后续写入可能被拒！")
        } else {
            PTOBDLogger.shared.ptLog("✅ ECU 未返回 Seed，可能当前配置区未上锁，继续执行。")
        }
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // 步骤 3：发送核心覆写指令 (Write Data By Identifier)
        // 指令拼接：2E (写服务) + DID (如 2121) + 动画类型单字节 (如 02 代表 Peugeot Sport)
        let writeCmd = "2E\(logoDID)\(logoType.rawValue)"
        PTOBDLogger.shared.ptLog("💾 [步骤 3] 发射内存篡改指令: \(writeCmd)")
        let writeRes = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: writeCmd)
        
        // 校验 6E (2E 的成功响应)
        if writeRes.contains("6E\(logoDID)") {
            PTOBDLogger.shared.ptLog("🎉 [修改成功] 成功向仪表盘写入动画配置！")
            
            // 步骤 4：下发软重启指令，使动画立刻生效 (PSA 标准重启指令)
            try? await Task.sleep(nanoseconds: 200_000_000)
            PTOBDLogger.shared.ptLog("🔄 [步骤 4] 正在发送 ECU 软重启指令 (11 03)，请观察仪表盘是否黑屏重启...")
            _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1103")
            
        } else {
            PTOBDLogger.shared.ptLog("❌ [修改失败] 写入被 ECU 拒绝，错误信息: \(writeRes)")
            // 退出扩展会话，恢复常态
            _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1001")
        }
        
        resumePollingIfNeeded(manager, wasPolling)
    }
    
    // 恢复轮询的辅助方法
    private func resumePollingIfNeeded(_ manager: PTMotoTelemetryManager, _ wasPolling: Bool) {
        if wasPolling {
            let rawPIDsToResume = PTHiddenOBDConnector.shared.collectedPIDResponses.isEmpty ? PTWifiOBDConnector.shared.collectedPIDResponses : PTHiddenOBDConnector.shared.collectedPIDResponses
            manager.startLightweightPolling(rawPIDs: rawPIDsToResume)
        }
    }
}

public extension PTDashboardHacker {
    
    // MARK: - ☢️ 终极极客工具：UDS 绝对物理内存 Dump (Service 0x23)
    
    /// 尝试通过绝对内存地址强行 Dump 底层固件数据
    /// - Parameters:
    ///   - dashboardTx: 目标节点 (如 "700")
    ///   - dashboardRx: 监听节点 (如 "708")
    ///   - memoryAddress: 十六进制内存物理起始地址 (例如: "08000000")
    ///   - readSize: 期望读取的字节数 (注意：受限于缓冲，通常单次最多读几十到几百字节)
    func dumpMemoryByAddress(dashboardTx: String, dashboardRx: String, memoryAddress: String, readSize: UInt16) async {
        let manager = PTMotoTelemetryManager.shared
        guard manager.isConnected else { return }
        
        PTOBDLogger.shared.ptLog("☢️ [全字库 Dump] 启动绝对内存读取引擎...")
        
        // 挂起正常轮询
        let wasPolling = (manager.telemetryPollingTask != nil)
        if wasPolling { manager.telemetryPollingTask?.cancel() }
        
        // 1. 进入扩展会话 (必须的权限门槛)
        _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1003")
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        // 2. 构造 23 服务的 Payload
        // 格式: [23] [格式标识符] [内存地址] [读取长度]
        // 格式标识符(Address And Length Format Identifier)：例如 14 代表 "长度占1个字节，地址占4个字节"
        // 假设我们读的是 32 位芯片，地址是 4 字节，读取长度我们用 2 字节表示
        let formatIdentifier = "24" // 2=长度占2字节(Length), 4=地址占4字节(Address)
        
        // 转换长度为十六进制字符串 (如读取 256 字节 -> 0100)
        let sizeHex = String(format: "%04X", readSize)
        
        let udsCommand = "23" + formatIdentifier + memoryAddress + sizeHex
        PTOBDLogger.shared.ptLog("📡 正在向内存地址 0x\(memoryAddress) 发射 Dump 指令: \(udsCommand)")
        
        // 3. 执行读取并捕获反馈
        let response = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: udsCommand)
        let cleanResponse = response.replacingOccurrences(of: " ", with: "").uppercased()
        
        // 4. 分析提取结果
        if cleanResponse.contains("63") {
            // 成功响应 23 服务的标识是 63
            PTOBDLogger.shared.ptLog("💎 [大满贯] 内存读取成功！底层数据泄露: \(cleanResponse)")
        } else if cleanResponse.contains("7F23") {
            if cleanResponse.contains("7F2333") {
                PTOBDLogger.shared.ptLog("🔒 [Dump 失败] 内存被硬件级锁定，必须先用 27 服务算出 Seed-Key 才能读！")
            } else if cleanResponse.contains("7F2331") {
                PTOBDLogger.shared.ptLog("❌ [Dump 失败] 内存地址 0x\(memoryAddress) 越界或不存在。")
            } else {
                PTOBDLogger.shared.ptLog("⚠️ [Dump 失败] ECU 拒绝了物理内存读取请求，错误码: \(cleanResponse)")
            }
        } else if cleanResponse.contains("NODATA") {
            PTOBDLogger.shared.ptLog("🕳️ [Dump 失败] 目标毫无反应 (NO DATA)。")
        } else {
            PTOBDLogger.shared.ptLog("❓ 收到未知反馈: \(cleanResponse)")
        }
        
        // 恢复环境
        _ = await manager.fetchProprietaryData(header: dashboardTx, receiveAddress: dashboardRx, udsCommand: "1001")
        if wasPolling {
            let rawPIDsToResume = PTHiddenOBDConnector.shared.collectedPIDResponses.isEmpty ? PTWifiOBDConnector.shared.collectedPIDResponses : PTHiddenOBDConnector.shared.collectedPIDResponses
            manager.startLightweightPolling(rawPIDs: rawPIDsToResume)
        }
    }
}
