//
//  PTDiagnosticManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 23/7/2026.
//

import Foundation
import PooTools

/// 深度车辆健康与环境诊断矩阵
@objcMembers
public class PTDiagnosticManager: NSObject {
    
    public static let shared = PTDiagnosticManager()
    
    // 防止重复报警的标记
    private var hasWarnedBattery: Bool = false
    private var hasWarnedIcyRoad: Bool = false
    
    private override init() {
        super.init()
        setupObserver()
    }
    
    private func setupObserver() {
        PTBluetoothServerManager.shared.addDelegate(self)
    }
    
    @objc private func resetWarnings() {
        hasWarnedBattery = false
        hasWarnedIcyRoad = false
    }

    // EN: Health alerts use the shared typed center so repeated dashboard frames cannot create duplicate system notifications.
    // ES: Las alertas de salud usan el centro tipado compartido para que las tramas repetidas no creen notificaciones duplicadas.
    // 中文：健康提醒统一使用类型化通知中心，避免重复仪表帧产生重复系统通知。
    private func notify(
        identifier: String,
        deduplicationKey: String,
        title: String,
        body: String
    ) {
        PTNotificationCenter.schedule(
            PTNotificationRequest(
                kind: .diagnostic,
                title: title,
                body: body,
                identifier: identifier,
                deduplicationKey: deduplicationKey,
                cooldown: 6 * 60 * 60,
                categoryIdentifier: PTNotificationCenter.diagnosticCategoryIdentifier,
                userInfo: ["pt_notification_kind": PTAppNotificationKind.diagnostic.rawValue]
            )
        )
    }
        
    deinit { }
}

extension PTDiagnosticManager:PTBLEDashboardDelegate {
    func dashboardManager(_ manager: PTBluetoothServerManager, didChangeConnectionState isConnected: Bool) {
        if isConnected {
            resetWarnings()
        }
    }
    
    func dashboardManager(_ manager: PTBluetoothServerManager, dashboardData data: Any?) {
        if let data2 = data as? PTDashboardData2 {
            // 1. 电瓶健康诊断逻辑
            // 只有在引擎未启动 (状态 0) 时，测量到的才是真实的电瓶静态电压。
            // EN: Sentinel values must not enter health thresholds.
            // ES: Los valores centinela no deben entrar en los umbrales de salud.
            // 中文：哨兵值不能参与健康阈值判断。
            if data2.engineAvailability.isAvailable,
               data2.batteryAvailability.isAvailable,
               data2.engineStatus == 0 {
                // 🚨 核心修复 1：加入 > 6.0 的下限约束。
                // 蓝牙能连上说明电瓶至少有 6V 以上的残余电量，低于 6V(尤其是 0V) 绝对是刚开机传感器还没采集到的假数据。
                if data2.batteryVolt < 11.0 && data2.batteryVolt > 6.0 && !hasWarnedBattery && PTDashboardConfig.shared.blueConnected {
                    
                    hasWarnedBattery = true
                    
                    notify(
                        identifier: "pt.notification.diagnostic.battery",
                        deduplicationKey: "diagnostic-battery",
                        title: "⚠️" + PTDashboardConfig.languageFunc(text: "batt_warning_title"),
                        body: PTDashboardConfig.language(key: "batt_warning_msg", data2.batteryVolt)
                    )
                    PTNSLogConsole("🔋 [健康诊断] 检测到真实的电瓶低电压: \(data2.batteryVolt)V")
                }
            }
            
            // 2. 环境温度与路面结冰诊断逻辑
            // 🚨 核心修复 2：加入 > -40 的下限约束。
            // -50°C 通常是底层硬件传过来的 0 值 (0 - 50 = -50)，代表温度传感器尚未工作。
            if data2.outsideTemperatureAvailability.isAvailable,
               data2.outsideTempC <= 3,
               data2.outsideTempC > -40,
               !hasWarnedIcyRoad,
               PTDashboardConfig.shared.blueConnected {
                
                hasWarnedIcyRoad = true
                
                notify(
                    identifier: "pt.notification.diagnostic.ice",
                    deduplicationKey: "diagnostic-ice",
                    title: "❄️" + PTDashboardConfig.languageFunc(text: "freeze_warning_title"),
                    body: PTDashboardConfig.language(key: "freeze_warning_msg", data2.outsideTempC)
                )
                PTNSLogConsole("🌡️ [环境诊断] 检测到真实的极寒天气: \(data2.outsideTempC)°C")
            }
        }
    }
}
