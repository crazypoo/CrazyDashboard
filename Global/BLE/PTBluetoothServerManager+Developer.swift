//
//  PTBluetoothServerManager+Developer.swift
//  CrazyDashboard
//
//  EN: Contains explicitly developer-facing fuzzing operations while reusing the established send path.
//  ES: Contiene operaciones de fuzzing explícitamente orientadas al desarrollo y reutiliza la ruta de envío establecida.
//  中文：承载明确面向开发者的 Fuzz 操作，并复用既有发送路径。
//
import UIKit
import CoreBluetooth
import PooTools
import UserNotifications

extension PTBluetoothServerManager {
    // MARK: - 深度逆向：自动化 Fuzz 扫描器
        
    /// 启动全频段自动化指令探测
    public func startAutomatedFuzzing() {
        guard authenticated else {
            PTOBDLogger.moto.ptLog("⚠️ 尚未完成认证，无法进行 Fuzz 扫描")
            return
        }
        let startString = "🚀 [自动化 Fuzz] 扫描任务已启动！请密切观察机车仪表盘反应..."
        PTOBDLogger.moto.ptLog(startString)
        delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: startString) })
        fuzzTimer?.invalidate()
        currentFuzzID = 0x00
        
        // 每 1.5 秒发送一次探测帧，给车机留出反应和回传数据的时间
        fuzzTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 🚨 跳过已知的指令 ID，防止干扰正常的仪表盘运作或导致重复断连
            let knownIDs: [UInt8] = [0x01,0x07,0x08]
            while knownIDs.contains(self.currentFuzzID) {
                // 使用溢出运算符 &+ 防止越界崩溃
                self.currentFuzzID = self.currentFuzzID &+ 1
            }
            
            // 扫描结束条件
            if self.currentFuzzID == 0xFF {
                let finishString = "🏁 [自动化 Fuzz] 全频段扫描完成！"
                PTOBDLogger.moto.ptLog(finishString)
                delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: finishString) })
                self.fuzzTimer?.invalidate()
                return
            }
            
            // 构造探测 Payload：
            // 很多工厂指令使用 0x00(查询), 0x01(开启), 或 0xFF(出厂重置) 作为标识
            let testPayload: [UInt8] = [0x02, 0x10, 0x03]
            let searchingString = "📡 [自动化 Fuzz] 正在探测 ID: 0x\(String(format: "%02X", self.currentFuzzID)) ..."
            PTOBDLogger.moto.ptLog(searchingString)
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: searchingString) })
            self.sendFuzzTest(targetID: self.currentFuzzID, payloadBytes: testPayload)
            
            self.currentFuzzID = self.currentFuzzID &+ 1
        }
    }
    
    /// 停止自动化探测
    public func stopAutomatedFuzzing() {
        fuzzTimer?.invalidate()
        fuzzTimer = nil
        let stopString = "🛑 [自动化 Fuzz] 扫描已手动终止。"
        PTOBDLogger.moto.ptLog(stopString)
        delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: stopString) })
    }
}

