//
//  PTMaintenanceManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 23/7/2026.
//

import Foundation
import UserNotifications
import PooTools

@objcMembers
public class PTMaintenanceManager: NSObject {
    
    public static let shared = PTMaintenanceManager()
    
    // 提醒阈值：距离下次保养剩余多少公里时开始提醒
    private let warningThresholdKm: Int = 500
    
    // 防止频繁打扰：通过 UserDefaults 记录上次提醒的日期
    private let lastWarningDateKey = "PTLastMaintenanceWarningDate"
    
    private override init() {
        super.init()
        setupObservers()
    }
    
    private func setupObservers() {
        PTBluetoothServerManager.shared.addDelegate(self)
    }
            
    private func triggerWarningIfNeeded(title: String, body: String) {
        let now = Date()
        let lastDate = UserDefaults.standard.object(forKey: lastWarningDateKey) as? Date ?? Date(timeIntervalSince1970: 0)
        
        // 限制：同一种警告，至少间隔 7 天才弹一次，避免骑手每天被烦死
        if now.timeIntervalSince(lastDate) > 7 * 24 * 3600 {
            PTMessagePusher.pushToDashboard(title: title, body: body)
            UserDefaults.standard.set(now, forKey: lastWarningDateKey)
            PTNSLogConsole("🚨 [保养管家] 触发保养通知：\(title)")
        }
    }
    
    deinit { }
}

extension PTMaintenanceManager:PTBLEDashboardDelegate {
    func dashboardManager(_ manager: PTBluetoothServerManager, dashboardData data: Any?) {
        if let data2 = data as? PTDashboardData2 {
            // 协议规定 maintenance 的 0x20 位表示“需要保养”
            // 这里假设你在解析层已经处理好了 (raw & 0xE0) != 0 的判断
            if data2.maintenance != 0 {
                triggerWarningIfNeeded(title: "🛠️" + PTDashboardConfig.languageFunc(text: "maintenance_need_title"), body: PTDashboardConfig.languageFunc(text: "maintenance_need_msg"))
            }
        } else if let data3 = data as? PTDashboardData3 {
            // 当剩余保养里程小于阈值且大于 0 时，触发预警
            if data3.distToMaintenance <= warningThresholdKm && data3.distToMaintenance > 0 {
                
                triggerWarningIfNeeded(title: "⚙️" + PTDashboardConfig.languageFunc(text: "maintenance_warning_title"), body: PTDashboardConfig.language(key: "maintenance_warning_msg", data3.distToMaintenance))
            }
        }
    }
}
