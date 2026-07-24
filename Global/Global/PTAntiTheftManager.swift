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
    
    private override init() {
        super.init()
        setupObservers()
    }
    
    // MARK: - 绑定蓝牙状态源
    private func setupObservers() {
        let nc = NotificationCenter.default
        // 监听引擎状态，决定是否进入警戒
        nc.addObserver(self, selector: #selector(handleData2(_:)), name: MotorcycleDATA2, object: nil)
        // 监听物理断电，触发防盗逻辑推演
        nc.addObserver(self, selector: #selector(handleDisconnect), name: MotorcycleDisconnected, object: nil)
    }
    
    // MARK: - 状态机流转
    @objc private func handleData2(_ notification: Notification) {
        guard let data2 = notification.object as? PTDashboardData2 else { return }
        
        // 引擎未转动 (0) 时[cite: 4]，代表可能已停车，进入防盗警戒模式
        if data2.engineStatus == 0 && !isArmed {
            isArmed = true
            PTNSLogConsole("🛡️ [防盗系统] 引擎已熄火，防盗系统已武装。")
            // 直接调用你写好的高德定位进行打卡！
            PTMOTOParkingManager.shared.saveCurrentLocationAsParkingSpot()
        }
        // 引擎运转中时，解除警戒
        else if data2.engineStatus == 2 && isArmed {
            isArmed = false
            PTNSLogConsole("🔓 [防盗系统] 引擎已启动，防盗系统已解除。")
        }
    }
    
    // MARK: - 核心防盗推演逻辑
    @objc private func handleDisconnect() {
        // 确保系统处于警戒状态，并且之前确实保存过停车点
        guard isArmed, let anchorCoord = PTMOTOParkingManager.shared.getLastParkedLocation() else { return }
        
        let anchorLocation = CLLocation(latitude: anchorCoord.latitude, longitude: anchorCoord.longitude)
        
        PTNSLogConsole("🔍 [防盗推演] 蓝牙断连。开始抓取手机当前热坐标...")
        
        // 调用我们刚刚在高德管理器里增加的闭包方法
        PTMOTOParkingManager.shared.requestSingleLocationForAntiTheft { [weak self] currentPhoneLocation in
            guard let self = self, let currentPhoneLocation = currentPhoneLocation else { return }
            
            // 计算高德坐标锚点与手机当前位置的物理距离（米）
            let distanceFromBike = currentPhoneLocation.distance(from: anchorLocation)
            PTNSLogConsole("📐 [防盗推演] 手机当前距离停车点 \(distanceFromBike) 米。")
            
            if distanceFromBike < 15.0 {
                // 🚨 人在原地没动，但车机蓝牙断开了！极大可能是车辆被物理推离了蓝牙范围！
                self.triggerTheftAlarm()
            } else {
                // ✅ 人走远了，蓝牙自然断开，正常现象
                PTNSLogConsole("✅ [防盗推演] 骑手已离开车辆安全距离，属于正常断连，解除武装。")
                self.isArmed = false
            }
        }
    }
    
    // MARK: - iOS 15+ 穿透式报警
    private func triggerTheftAlarm() {
        PTNotificationCenter.pushCenter(title: "🚨 车辆异常移动警告", body: "检测到您的爱车在未启动状态下丢失连接，可能正被非法移动，请立即确认！")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
