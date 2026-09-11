//
//  PTBluetoothServerManager+Commands.swift
//  CrazyDashboard
//
//  EN: Keeps navigation, dashboard controls, configuration, and developer command entry points behind the same transport.
//  ES: Mantiene la navegación, los controles del tablero, la configuración y las entradas de comandos de desarrollo detrás del mismo transporte.
//  中文：将导航、仪表控制、配置和开发者指令入口统一置于同一传输层之后。
//
import UIKit
import CoreBluetooth
import PooTools
import UserNotifications

extension PTBluetoothServerManager {
    
    // MARK: - 发送导航与控制指令
    func sendCustomAlertToDashboard(title: String, message: String) {
        // 1. 创建一个唯一的 UID
        let alertUid = UInt32(Date().timeIntervalSince1970) % 100000
        
        let notif = PTAncsNotif(uid: alertUid, title: title, message: message, category: 1, appId: "com.ptools.moto")
        
        // 2. 生成“通知到达”帧
        let _ = PTFrameBuilder.buildAncsNotifSourceFrame(notif: notif)
        
        // 3. 将数据压入蓝牙发送队列 (假设你有一个特征值专门处理 ANCS 数据)
        // sendChunkedData(data: sourceFrame, to: ancsCharacteristic)
    }
    
    // 发送导航定位信息
    func sendNavigation(info: PTNavigationInfo) {
        sendNavigation(info: info, bypassCoalescing: false)
    }

    // EN: Keep welcome text immediate while normal map updates use the latest-state gate.
    // ES: Mantén inmediato el texto de bienvenida mientras las actualizaciones normales usan la barrera de último estado.
    // 中文：欢迎文字保持即时发送，普通地图更新使用最新状态合并策略。
    private func sendNavigation(info: PTNavigationInfo, bypassCoalescing: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.sendNavigation(info: info, bypassCoalescing: bypassCoalescing)
            }
            return
        }

        guard authenticated else {
            PTOBDLogger.moto.ptLog( "⚠️ 尚未完成认证，无法发送导航数据")
            return
        }
        let frame = PTFrameBuilder.buildNavigationFrame(info: info)

        guard !bypassCoalescing else {
            sendChunkedData(data: frame, to: txChar)
            return
        }

        let fingerprint = PTNavigationFingerprint(info: info)
        if navigationScheduler.isDuplicate(fingerprint) {
            pendingNavigationFlushWorkItem?.cancel()
            pendingNavigationFlushWorkItem = nil
            pendingNavigation = nil
            return
        }
        if pendingNavigation?.fingerprint == fingerprint {
            return
        }

        removeQueuedNavigationJobs()
        let pending = PendingNavigation(frame: frame, fingerprint: fingerprint)
        guard sendCredits > 0 else {
            pendingNavigation = pending
            pumpQueue()
            return
        }

        let remaining = navigationScheduler.remainingDelay(at: Date())
        if remaining > 0 {
            pendingNavigation = pending
            schedulePendingNavigationFlush(after: remaining)
            return
        }

        enqueueNavigationFrame(frame, fingerprint: fingerprint)
    }
    
    public func sendWelcomeMessage(next:String = "",title:String,nextManeuver:UInt8 = PTManeuverMap.depart) {
        guard authenticated else { return }

        // 伪造一个导航对象
        let welcomeInfo = PTNavigationInfo(
            nextManeuver: nextManeuver, // 使用“出发”图标
            metersToNextManeuver: 999,
            nameNextRoad: next, // 下一条路留空
            nameCurrentRoad: title, // 🚨 你的专属欢迎语，建议用全大写英文
            currentSpeedLimit: 99,
            distanceToDestination: 0,
            estimatedTimeToDestinationSec: 0
        )
        
        PTOBDLogger.moto.ptLog("🎉 [视觉交互] 正在向仪表盘推送欢迎信息: \(welcomeInfo.nameCurrentRoad)")
        // 复用你已有的导航发送方法
        self.sendNavigation(info: welcomeInfo, bypassCoalescing: true)
    }

    // MARK: - 逆向工程：模糊测试 (Fuzzing) 通道
    
    /// 向机车发送任意 ID 和 Payload 的探测报文
    /// - Parameters:
    ///   - targetID: 目标指令 ID
    ///   - payloadBytes: 十六进制载荷数组
    public func sendFuzzTest(targetID: UInt8, payloadBytes: [UInt8] = [0x00]) {
        guard authenticated else {
            PTOBDLogger.moto.ptLog( "⚠️ 尚未完成认证，无法发送导航数据")
            return
        }
        let dataToWrite = PTFrameBuilder.buildFuzzFrame(idFrame: targetID, payload: payloadBytes)
        sendChunkedData(data: dataToWrite, to: txChar)
    }

    // 发送断开连接指令
    func sendDisconnect() {
        guard authenticated else { return }
        let frame = PTFrameBuilder.buildDisconnectFrame()
        sendChunkedData(data: frame, to: txChar)
    }
    
    func sendTCSMode(id:UInt8,mode: PTTCSMode) {
        guard authenticated else { return }
        let frame = PTFrameBuilder.buildTCSFrame(id: id, mode: mode)
        sendChunkedData(data: frame, to: txChar)
    }
    
    func sendLightMode(id:UInt8,mode: PTBacklightMode) {
        guard authenticated else { return }
        let frame = PTFrameBuilder.buildBacklightFrame(id: id, mode: mode)
        sendChunkedData(data: frame, to: txChar)
    }
    
    func sendConfiguration(color: PTConfigColor, unit: PTConfigUnit, language: PTConfigLanguage, completion: @escaping (Bool) -> Void) {
        // 🚨 安全解包：彻底根除在此处点击导致的强制解包闪退
        guard authenticated, let targetChar = txChar else {
            PTOBDLogger.moto.ptLog("⚠️ 尚未完成认证或 TX 通道未建立，拦截配置下发")
            completion(false)
            return
        }
        
        let frame = PTFrameBuilder.buildConfigurationFrame(
            color: color.rawValue,
            unit: unit.rawValue,
            language: language.rawValue
        )
        
        sendChunkedData(data: frame, to: targetChar) {
            PTOBDLogger.moto.ptLog("🎨 [配置下发] 指令已成功发射！")
            completion(true)
        }
    }
    
}

