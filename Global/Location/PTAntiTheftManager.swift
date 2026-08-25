//
//  PTAntiTheftManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 23/7/2026.
//

import Foundation
import CoreLocation
import UserNotifications
import PooTools

/// 摩托车智能防丢车监控中心 (基于高德定位协同版)
@objcMembers
public class PTAntiTheftManager: NSObject {
    
    public static let shared = PTAntiTheftManager()
    
    private var isArmed: Bool = false
    private var expectedShutdownUntil: Date?
    private var pendingDisconnectWork: DispatchWorkItem?
    private var alarmSuppressedUntil: Date?

    private let shutdownGracePeriod: TimeInterval = 30
    private let disconnectConfirmationDelay: TimeInterval = 5
    private let nearbyRadius: CLLocationDistance = 15
    
    private override init() {
        super.init()
        setupObservers()
    }
    
    // MARK: - 绑定蓝牙状态源
    private func setupObservers() {
        PTBluetoothServerManager.shared.addDelegate(self)
    }
    
    // MARK: - 状态机流转
    @objc private func handleData2(_ notification: Notification) {
        guard let data2 = notification.object as? PTDashboardData2 else { return }
        
        // 引擎未转动 (0) 时，代表可能已停车，进入防盗警戒模式
        updateArmingState(engineStatus: data2.engineStatus)
    }

    private func updateArmingState(engineStatus: Int) {
        if engineStatus == 0 && !isArmed {
            isArmed = true
            expectedShutdownUntil = Date().addingTimeInterval(shutdownGracePeriod)
            PTNSLogConsole("🛡️ [防盗系统] 引擎已熄火，进入正常关机宽限期。")
            PTMOTOParkingManager.shared.saveCurrentLocationAsParkingSpot()
        } else if engineStatus == 2 && isArmed {
            isArmed = false
            expectedShutdownUntil = nil
            pendingDisconnectWork?.cancel()
            PTNSLogConsole("🔓 [防盗系统] 引擎已启动，解除警戒。")
        }
    }
    
    // MARK: - 核心防盗推演逻辑
    @objc private func handleDisconnect() {
        // 确保系统处于警戒状态，并且之前确实保存过停车点
        guard isArmed, let anchorCoord = PTMOTOParkingManager.shared.getLastParkedLocation() else { return }

        if let expectedShutdownUntil, Date() < expectedShutdownUntil {
            PTNSLogConsole("ℹ️ [防盗系统] 断连发生在正常关机宽限期内，不触发报警。")
            return
        }

        pendingDisconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.evaluateDisconnect(anchorCoord: anchorCoord)
        }
        pendingDisconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + disconnectConfirmationDelay, execute: work)
    }

    private func evaluateDisconnect(anchorCoord: CLLocationCoordinate2D) {
        guard isArmed, !PTDashboardConfig.shared.blueConnected else { return }
        
        let anchorLocation = CLLocation(latitude: anchorCoord.latitude, longitude: anchorCoord.longitude)
        
        PTNSLogConsole("🔍 [防盗推演] 蓝牙断连。开始抓取手机当前热坐标...")
        
        // 调用我们刚刚在高德管理器里增加的闭包方法
        PTMOTOParkingManager.shared.requestSingleLocationForAntiTheft { [weak self] currentPhoneLocation in
            guard let self = self, let currentPhoneLocation = currentPhoneLocation else { return }
            
            // 计算高德坐标锚点与手机当前位置的物理距离（米）
            let distanceFromBike = currentPhoneLocation.distance(from: anchorLocation)
            PTNSLogConsole("📐 [防盗推演] 手机当前距离停车点 \(distanceFromBike) 米。")
            
            if distanceFromBike < self.nearbyRadius {
                guard self.alarmSuppressedUntil.map({ Date() >= $0 }) ?? true else { return }
                self.alarmSuppressedUntil = Date().addingTimeInterval(60)
                // 中文：仅报告异常断连，不把断连单独解释为车辆已移动。
                // Español: Informar solo de una desconexión anómala; no afirmar movimiento del vehículo.
                self.triggerTheftAlarm()
            } else {
                // 中文：骑手已离开停车点，断连视为正常。
                // Español: El piloto se alejó del punto de estacionamiento; la desconexión es normal.
                PTNSLogConsole("✅ [防盗推演] 骑手已离开车辆安全距离，属于正常断连，解除武装。")
                self.isArmed = false
            }
        }
    }
    
    // MARK: - iOS 15+ 穿透式报警
    private func triggerTheftAlarm() {
        PTNotificationCenter.pushCenter(title: "🚨 车辆连接异常", body: "车辆在骑手附近断开连接，请确认车辆状态。")
    }
    
    deinit { }
}

extension PTAntiTheftManager:PTBLEDashboardDelegate {
    func dashboardManager(_ manager: PTBluetoothServerManager, didChangeConnectionState isConnected: Bool) {
        if isConnected {
            pendingDisconnectWork?.cancel()
            pendingDisconnectWork = nil
        } else {
            handleDisconnect()
        }
    }
    
    func dashboardManager(_ manager: PTBluetoothServerManager, dashboardData data: Any?) {
        if let data2 = data as? PTDashboardData2 {
            updateArmingState(engineStatus: data2.engineStatus)
        }
    }
}
