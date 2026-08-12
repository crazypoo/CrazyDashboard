//
//  PTOBDOTAUpdater.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 12/8/2026.
//

import Foundation

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
        
        PTOBDLogger.shared.ptLog("⚠️ [OTA 升级] 警告：正在准备刷写固件，请绝对不要断开电源或关闭蓝牙！")
        
        do {
            // 🌟 1. 挂起我们的高频轮询引擎，绝对霸占总线
            PTOBDLogger.shared.ptLog("⏸️ [OTA 升级] 挂起日常轮询，接管总线...")
            // 这里我们调用之前写好的 UDS 注入通道即可达到独占总线的目的
            
            // 🌟 2. 发送进入 Bootloader 的私有指令 (具体指令需厂家提供，此处为示例 "AT BOOT")
            PTOBDLogger.shared.ptLog("🔓 [OTA 升级] 发送进入升级模式指令...")
            let bootRes = await manager.injectRawHexCommand("AT BOOT", requiresPause: true)
            
            // 假设厂家规定模块进入升级模式后返回 "BOOT_OK"
            guard bootRes.contains("BOOT_OK") else {
                notifyFailure(error: "模块拒绝进入升级模式: \(bootRes)")
                return
            }
            
            PTOBDLogger.shared.ptLog("✅ [OTA 升级] 模块已进入 Bootloader，开始文件切片...")
            
            // 🌟 3. 文件切片与循环发送
            let totalBytes = firmwareData.count
            var offset = 0
            var chunkIndex = 0
            
            while offset < totalBytes {
                // 计算当前块的大小
                let currentChunkSize = min(chunkSize, totalBytes - offset)
                let chunkData = firmwareData.subdata(in: offset..<(offset + currentChunkSize))
                
                // 将二进制块转为 Hex 字符串发送 (或者根据厂家的协议直接发二进制流)
                let chunkHex = chunkData.map { String(format: "%02X", $0) }.joined()
                let commandToSend = "FW:\(chunkIndex):\(chunkHex)" // 假设的封包格式
                
                // 🌟 4. 发送数据并等待模块的 ACK 确认
                let ackRes = await manager.injectRawHexCommand(commandToSend, requiresPause: false)
                
                // 假设厂家规定收到数据后回复 "ACK"
                if !ackRes.contains("ACK") {
                    notifyFailure(error: "第 \(chunkIndex) 块数据校验失败，模块返回: \(ackRes)")
                    return
                }
                
                // 更新进度
                offset += currentChunkSize
                chunkIndex += 1
                let progress = Float(offset) / Float(totalBytes)
                
                DispatchQueue.main.async {
                    self.delegate?.otaUpdater(self, didUpdateProgress: progress)
                }
                
                // 给硬件一点写入 Flash 芯片的时间 (例如 20ms)
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            
            // 🌟 5. 固件传输完成，发送重启指令
            PTOBDLogger.shared.ptLog("🔄 [OTA 升级] 固件传输完毕，发送重启指令...")
            _ = await manager.injectRawHexCommand("AT REBOOT", requiresPause: false)
            
            // 重启后蓝牙会断开，底层会自动触发 disconnect
            DispatchQueue.main.async {
                self.delegate?.otaUpdater(self, didFinishWithSuccess: true, error: nil)
            }
            
        } catch {
            notifyFailure(error: "传输过程中发生异常: \(error.localizedDescription)")
        }
    }
    
    private func notifyFailure(error: String) {
        PTOBDLogger.shared.ptLog("❌ [OTA 升级] 失败: \(error)")
        DispatchQueue.main.async {
            self.delegate?.otaUpdater(self, didFinishWithSuccess: false, error: error)
        }
    }
}
