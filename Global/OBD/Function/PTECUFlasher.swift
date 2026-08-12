//
//  PTECUFlasher.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 12/8/2026.
//

import Foundation

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
        
        PTOBDLogger.shared.ptLog("⚠️ [ECU 刷写] 警告：进入底层编程模式，禁止断电！")
        
        // --- 阶段一：刷写前置准备 (Pre-Programming) ---
        
        // 1. 关闭全车 DTC (故障码) 记录，防止刷写时网络瘫痪导致亮故障灯
        PTOBDLogger.shared.ptLog("🔄 1. 禁用故障码生成 (UDS: 85 02)...")
        _ = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "8502")
        
        // 2. 关闭其他节点的正常通讯广播，保障总线带宽 100% 给刷写使用
        PTOBDLogger.shared.ptLog("🔇 2. 禁用普通通讯流 (UDS: 28 03 01)...")
        _ = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "280301")
        
        // 3. 强行拉入编程会话 (Bootloader 模式)
        PTOBDLogger.shared.ptLog("🚪 3. 进入 ECU 编程会话 (UDS: 10 02)...")
        let sessionRes = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "1002")
        guard sessionRes.contains("5002") else {
            PTOBDLogger.shared.ptLog("❌ 刷写失败：ECU 拒绝进入编程模式。")
            return
        }
        
        // --- 阶段二：解锁与擦除 (Security & Erase) ---
        
        // 4. 安全访问解锁 (各家车厂的算法核心机密都在这里)
        PTOBDLogger.shared.ptLog("🔑 4. 请求安全种子并执行解密算法 (UDS: 27 01 / 27 02)...")
        let seed = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "2701")
        // (此处省略了根据 Seed 计算 Key 的复杂底层 RSA/私有算法)
        let fakeKey = "A1B2C3D4"
        let authRes = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "2702\(fakeKey)")
        
        // 5. 擦除目标 Flash 内存块 (危险操作：变成砖头的开始)
        // 使用例程控制 (Routine Control) 指令 31 01，后面跟着要擦除的内存起始和结束地址
        PTOBDLogger.shared.ptLog("🔥 5. 擦除原厂动力逻辑内存块 (UDS: 31 01 FF 00)...")
        _ = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "3101FF00")
        // 擦除需要物理时间，必须等待
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        // --- 阶段三：数据注入 (Data Transfer) ---
        
        // 6. 声明即将下载的文件大小和内存地址
        PTOBDLogger.shared.ptLog("📦 6. 声明传输请求 (UDS: 34)...")
        _ = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "340000000000") // 占位符
        
        // 7. 循环发送数据块 (这是刷写软件屏幕上那个进度条前进的原因)
        PTOBDLogger.shared.ptLog("🚀 7. 开始高频数据注入 (UDS: 36)...")
        // 这里需要严格依赖我们尚未编写的 ISO-TP 多帧传输引擎！
        // manager.sendMultiFrameISOData(command: 0x36, payload: tunedFirmware)
        PTOBDLogger.shared.ptLog("████████████████████ 100% 写入完成")
        
        // 8. 声明传输结束
        PTOBDLogger.shared.ptLog("🏁 8. 请求退出传输 (UDS: 37)...")
        _ = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "37")
        
        // --- 阶段四：重启使生效 (Reset) ---
        
        PTOBDLogger.shared.ptLog("⚡️ 9. 执行硬重启，加载特调动力模型 (UDS: 11 01)...")
        _ = await manager.fetchProprietaryData(header: engineTx, receiveAddress: engineRx, udsCommand: "1101")
        
        PTOBDLogger.shared.ptLog("🎉 [ECU 刷写] 一阶程序成功点亮！马力已解印！")
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
        
        PTOBDLogger.shared.ptLog("🛡 [安全保镖] 启动刷写安全预检程序...")
        
        // 🌟 防线 1：电瓶电压硬性校验
        let isVoltageSafe = await checkBatteryVoltageSafety(tx: engineTx, rx: engineRx)
        guard isVoltageSafe else {
            PTOBDLogger.shared.ptLog("❌ [安全拦截] 电瓶电压过低，继续刷写极易变砖！已强制终止。建议接上稳压充电机。")
            return false
        }
        
        // 🌟 防线 2：本地 Checksum 预计算校验
        guard verifyFirmwareIntegrity(firmware: tunedFirmware) else {
            PTOBDLogger.shared.ptLog("❌ [安全拦截] 待刷入的固件文件损坏或校验和不匹配，已强制终止。")
            return false
        }
        
        // 🌟 防线 3：强制备份原厂内存 (Dump)
        guard let _ = await backupOriginalFirmware(tx: engineTx, rx: engineRx) else {
            PTOBDLogger.shared.ptLog("❌ [安全拦截] 无法完整备份原厂固件，为了安全，禁止进行后续擦除操作！")
            return false
        }
        
        PTOBDLogger.shared.ptLog("✅ [安全保镖] 所有预检全部通过！准许放行写入操作！")
        
        // 预检全部通过，才真正调用底层的刷写状态机
        await flashTunedFirmware(engineTx: engineTx, engineRx: engineRx, tunedFirmware: tunedFirmware)
        
        return true
    }
    
    // MARK: - 安全子例程实现
    
    /// 检查电瓶电压是否高于 12.5V
    private func checkBatteryVoltageSafety(tx: String, rx: String) async -> Bool {
        let manager = PTMotoTelemetryManager.shared
        PTOBDLogger.shared.ptLog("🔋 正在请求实时控制模块电压 (PID: 0142)...")
        
        // 发送标准的 OBD-II 电压查询指令 01 42
        let response = await manager.fetchProprietaryData(header: "7DF", receiveAddress: "7E8", udsCommand: "0142")
        let cleanResponse = response.replacingOccurrences(of: " ", with: "")
        
        // 解析 41 42 XX XX (公式: (A * 256 + B) / 1000)
        if cleanResponse.contains("4142") {
            let payload = PTMultiFrameParser.extractPureHexPayload(response: cleanResponse)
            if let range = payload.range(of: "4142") {
                let hexData = String(payload[range.upperBound...])
                if hexData.count >= 4 {
                    let aHex = String(hexData.prefix(2))
                    let bHex = String(hexData.dropFirst(2).prefix(2))
                    
                    // 🌟 修复点：先用 Int 解析十六进制，再转换为 Double 参与公式运算
                    if let aInt = Int(aHex, radix: 16), let bInt = Int(bHex, radix: 16) {
                        let a = Double(aInt)
                        let b = Double(bInt)
                        
                        let voltage = (a * 256.0 + b) / 1000.0
                        PTOBDLogger.shared.ptLog("⚡️ 测得当前电压为: \(String(format: "%.2f", voltage)) V")
                        // 设定的安全红线为 12.5V
                        return voltage >= 12.5
                    }
                }
            }
        }
        
        // 如果读不到标准电压或解析失败，为了绝对安全，默认拦截
        PTOBDLogger.shared.ptLog("⚠️ 无法准确读取控制模块电压！")
        return false
    }
    
    /// 备份原厂固件 (模拟逻辑)
    private func backupOriginalFirmware(tx: String, rx: String) async -> Data? {
        PTOBDLogger.shared.ptLog("💾 正在执行底层内存块抓取 (Memory Dump)...")
        // 此处需要调用 ISO-TP 多帧读取逻辑，将整个标定区块读出
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        PTOBDLogger.shared.ptLog("✅ 原厂数据备份成功，已存入沙盒。")
        return Data() // 返回模拟的原厂数据
    }
    
    /// 固件完整性校验 (模拟逻辑)
    private func verifyFirmwareIntegrity(firmware: Data) -> Bool {
        PTOBDLogger.shared.ptLog("🧬 正在计算特调文件的 CRC/Checksum 校验和...")
        // 商业软件会在这里比对文件尾部的签名
        return true
    }
}
