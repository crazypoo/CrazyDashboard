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
    
    /// 🚀 读取特定地址的固件标识符 (尝试提取当前动画配置项的特征码)
    /// - Parameter dashboardTx: 你通过上面扫描确定的仪表盘地址 (如 "7A0")
    @discardableResult
    public func readDashboardConfig(
        dashboardTx: String,
        dashboardRx: String
    ) async -> [PTOBDIDReadResult] {
        guard let address = PTOBDDiagnosticAddress(tx: dashboardTx, rx: dashboardRx) else {
            PTOBDLogger.obd.ptLog("❌ [仪表盘探查] 地址格式无效")
            return []
        }

        do {
            let results = try await PTUDSReadService.shared.readDIDs(
                address: address,
                dids: ["F190", "F187", "F180", "F1A0"]
            )

            results.forEach { result in
                PTOBDLogger.obd.ptLog(
                    "[仪表盘探查] DID \(result.did) \(result.status.rawValue): \(result.rawResponse)"
                )
            }
            return results
        } catch {
            PTOBDLogger.obd.ptLog("❌ [仪表盘探查] 读取失败: \(error.localizedDescription)")
            return []
        }
    }
}

public extension PTDashboardHacker {
    
    // MARK: - 🌍 阶段一：全域 ECU 节点雷达扫描 (Ping Sweep)
    
    /// 扫描 CAN 总线上的所有诊断节点，寻找存活的 ECU
    /// - Returns: 存活 ECU 的发送报头数组 (如 ["7E0", "7A0"])
    func scanAllActiveECUNodes() async -> [String] {
        PTOBDLogger.obd.ptLog("🌍 [全域雷达] 启动 11-bit CAN 总线地毯式扫描 (0x700 - 0x7DF)...")

        do {
            let nodes = try await PTUDSReadService.shared.scanECUNodes { index, total in
                if index == total || index % 32 == 0 {
                    PTOBDLogger.obd.ptLog("[全域雷达] 进度 \(index)/\(total)")
                }
            }
            let activeNodes = nodes.map(\.address.tx)
            PTOBDLogger.obd.ptLog("🏁 [全域雷达] 扫描完成！共发现 \(activeNodes.count) 个存活 ECU: \(activeNodes)")
            return activeNodes
        } catch {
            PTOBDLogger.obd.ptLog("❌ [全域雷达] 扫描失败: \(error.localizedDescription)")
            return []
        }
    }
    
    /// 🚀 扫描总线上所有的 ECU 节点，寻找可能是仪表盘的地址
    @discardableResult
    func scanForDashboardAddress(progress: ((Int, Int) -> Void)? = nil) async -> [PTOBDECUNode] {
        do {
            let nodes = try await PTUDSReadService.shared.scanDashboardNodes(progress: progress)
            PTOBDLogger.obd.ptLog("🏁 [仪表盘探查] 找到 \(nodes.count) 个候选节点")
            return nodes
        } catch {
            PTOBDLogger.obd.ptLog("❌ [仪表盘探查] 扫描失败: \(error.localizedDescription)")
            return []
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
    @discardableResult
    func probeDeepDataSafely(
        dashboardTx: String,
        dashboardRx: String,
        targetDIDs: [String],
        progress: ((Int, Int, PTOBDIDReadResult) -> Void)? = nil
    ) async -> [PTOBDIDReadResult] {
        guard let address = PTOBDDiagnosticAddress(tx: dashboardTx, rx: dashboardRx) else {
            PTOBDLogger.obd.ptLog("❌ [防休眠探测] 地址格式无效")
            return []
        }

        do {
            let results = try await PTUDSReadService.shared.readDIDs(
                address: address,
                dids: targetDIDs,
                progress: { index, total, result in
                    progress?(index, total, result)
                    PTOBDLogger.obd.ptLog(
                        "[防休眠探测] \(index)/\(total) DID \(result.did) \(result.status.rawValue)"
                    )
                }
            )
            PTOBDLogger.obd.ptLog("🏁 [防休眠探测] 测试结束。")
            return results
        } catch {
            PTOBDLogger.obd.ptLog("❌ [防休眠探测] 读取失败: \(error.localizedDescription)")
            return []
        }
    }
    
    /// 🚀 极客工具：通过 UDS 私有协议从车身控制器 (BSI) 强行提取隐藏的 VIN 码
    func extractHiddenVINFromBSI(dashboardTx: String = "700", dashboardRx: String = "708") async -> String? {
        guard let address = PTOBDDiagnosticAddress(tx: dashboardTx, rx: dashboardRx) else {
            return nil
        }

        do {
            let vin = try await PTUDSReadService.shared.readVIN(address: address)
            if let vin, !vin.isEmpty {
                PTMotoTelemetryManager.shared.obdInfo.vin = vin
                PTOBDLogger.obd.ptLog("💎 [私有探针] 成功从底层提取隐藏 VIN: \(vin)")
            }
            return vin
        } catch {
            PTOBDLogger.obd.ptLog("❌ [私有探针] 提取失败: \(error.localizedDescription)")
            return nil
        }
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
        PTOBDLogger.obd.ptLog("⛔️ [仪表盘写入] 当前版本为只读诊断模式，拒绝发送写入指令")
        return false
    }
    
    /// 自动遍历并读取目标 ECU 内的所有配置地址，生成内存转储报告
    /// - Parameters:
    ///   - dashboardTx: 仪表盘的发送报头 (如 "7A0")
    ///   - dashboardRx: 仪表盘的接收报头 (如 "7A8")
    ///   - startDID: 扫描起始十六进制地址 (如 0x0100)
    ///   - endDID: 扫描结束十六进制地址 (如 0x02FF)
    /// - Returns: 一个包含所有成功读取的 [DID: Hex数据] 的字典
    func fuzzDashboardDIDs(
        dashboardTx: String,
        dashboardRx: String,
        startDID: UInt16 = 0x0100,
        endDID: UInt16 = 0x02FF,
        progress: ((Int, Int, PTOBDIDReadResult) -> Void)? = nil
    ) async -> [String: String] {
        guard startDID <= endDID,
              Int(endDID) - Int(startDID) <= 0x03FF,
              let address = PTOBDDiagnosticAddress(tx: dashboardTx, rx: dashboardRx) else {
            PTOBDLogger.obd.ptLog("❌ [DID 扫描] 参数无效或扫描范围过大")
            return [:]
        }

        let dids = (startDID...endDID).map { String(format: "%04X", $0) }

        do {
            let results = try await PTUDSReadService.shared.readDIDs(
                address: address,
                dids: dids,
                progress: progress
            )

            return results.reduce(into: [String: String]()) { output, result in
                guard result.status == .success,
                      let payload = result.payloadHex,
                      !payload.isEmpty else {
                    return
                }
                output[result.did] = payload
            }
        } catch {
            PTOBDLogger.obd.ptLog("❌ [DID 扫描] 失败: \(error.localizedDescription)")
            return [:]
        }

    }

    // MARK: - 🚀 阶段二：一键全车脱壳 (Full Vehicle Dump)
    
    /// 执行终极脱壳：自动寻找全车 ECU，并逐一进行内存盲扫，生成最终的全车指纹档案
    /// - Returns: 格式化好的纯文本报告，可直接写入文件
    @discardableResult
    func performFullVehicleDeepDumpReport(
        addresses: [PTOBDDiagnosticAddress]? = nil,
        progress: ((Int, Int) -> Void)? = nil
    ) async -> PTOBDFullVehicleDumpReport {
        let startedAt = Date()
        let targetAddresses: [PTOBDDiagnosticAddress]
        var cancelled = false

        if let addresses {
            targetAddresses = addresses
        } else {
            do {
                targetAddresses = try await PTUDSReadService.shared.scanECUNodes().map(\.address)
            } catch {
                targetAddresses = []
                cancelled = Task.isCancelled
            }
        }

        var nodeReports: [PTOBDNodeDumpReport] = []

        for (index, address) in targetAddresses.enumerated() {
            if Task.isCancelled {
                cancelled = true
                break
            }

            let dids = (0x0100...0x02FF).map { String(format: "%04X", $0) }
                + (0xF100...0xF1FF).map { String(format: "%04X", $0) }

            do {
                let results = try await PTUDSReadService.shared.readDIDs(address: address, dids: dids)
                nodeReports.append(PTOBDNodeDumpReport(address: address, results: results))
            } catch {
                nodeReports.append(PTOBDNodeDumpReport(address: address, failureReason: error.localizedDescription))
                if error is CancellationError {
                    cancelled = true
                    break
                }
            }

            progress?(index + 1, targetAddresses.count)
        }

        return PTOBDFullVehicleDumpReport(
            startedAt: startedAt,
            endedAt: Date(),
            nodes: nodeReports,
            cancelled: cancelled
        )
    }

    func performFullVehicleDeepDump() async -> String {
        let dump = await performFullVehicleDeepDumpReport()
        var report = "=== PTOOLS 全车数字指纹 Dump ===\n"

        if dump.nodes.isEmpty {
            report += "⚠️ 未发现任何活跃诊断节点。\n"
        }

        for node in dump.nodes {
            report += "\n🛠 解析节点: [\(node.address.tx)]\n"
            if let failureReason = node.failureReason {
                report += "  - 失败: \(failureReason)\n"
                continue
            }

            let readable = node.results.filter { $0.status == .success }
            if readable.isEmpty {
                report += "  - 无可读数据或权限受限。\n"
            } else {
                for result in readable {
                    report += "  DID: [\(result.did)] -> DATA: [\(result.payloadHex ?? "")]\n"
                }
            }
        }

        if dump.cancelled {
            report += "⚠️ 扫描已取消，以上为已完成节点。\n"
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
    @discardableResult
    func dumpMemoryByAddress(
        dashboardTx: String,
        dashboardRx: String,
        memoryAddress: String,
        readSize: UInt16
    ) async -> PTOBDRawReadResult? {
        guard let address = PTOBDDiagnosticAddress(tx: dashboardTx, rx: dashboardRx) else {
            PTOBDLogger.obd.ptLog("❌ [内存读取] 地址格式无效")
            return nil
        }

        do {
            let result = try await PTUDSReadService.shared.readMemory(
                address: address,
                memoryAddress: memoryAddress,
                readSize: readSize
            )
            PTOBDLogger.obd.ptLog(
                "[内存读取] \(result.status.rawValue): \(result.payloadHex ?? result.rawResponse)"
            )
            return result
        } catch {
            PTOBDLogger.obd.ptLog("❌ [内存读取] 失败: \(error.localizedDescription)")
            return nil
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
        PTOBDLogger.obd.ptLog("⛔️ [开机动画] 当前版本为只读诊断模式，拒绝发送写入指令")
        return

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
    
    public init() {}
    
    /// 启动固件刷写流程
    /// - Parameter firmwareData: 从 .bin 文件读取到的纯净二进制数据
    public func startFlashingFirmware(firmwareData: Data) async {
        notifyFailure(error: "只读诊断模式未启用 OTA 刷写")
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
        PTOBDLogger.obd.ptLog("⛔️ [ECU 刷写] 当前版本为只读诊断模式，拒绝发送刷写指令")
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
        PTOBDLogger.obd.ptLog("⛔️ [ECU 刷写] 当前版本为只读诊断模式，拒绝执行安全保镖流程")
        return false
    }
}
