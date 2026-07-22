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
        let nc = NotificationCenter.default
        // 根据协议，保养状态标志位在 DATA2 中[cite: 4]
        nc.addObserver(self, selector: #selector(handleData2(_:)), name: MotorcycleDATA2, object: nil)
        // 根据协议，保养剩余里程在 DATA3 中[cite: 4]
        nc.addObserver(self, selector: #selector(handleData3(_:)), name: MotorcycleDATA3, object: nil)
    }
    
    @objc private func handleData2(_ notification: Notification) {
        guard let data2 = notification.object as? PTDashboardData2 else { return }
        
        // 协议规定 maintenance 的 0x20 位表示“需要保养”[cite: 4]
        // 这里假设你在解析层已经处理好了 (raw & 0xE0) != 0 的判断
        if data2.maintenance != 0 {
            triggerWarningIfNeeded(title: "🛠️ 车辆保养提醒", body: "车机系统提示需要进行常规保养检查，请及时预约售后服务。")
        }
    }
    
    @objc private func handleData3(_ notification: Notification) {
        guard let data3 = notification.object as? PTDashboardData3 else { return }
        
        // 当剩余保养里程小于阈值且大于 0 时，触发预警
        if data3.distToMaintenance <= warningThresholdKm && data3.distToMaintenance > 0 {
            triggerWarningIfNeeded(title: "⚙️ 保养里程预警", body: "距离下次保养仅剩 \(data3.distToMaintenance) 公里，为了最佳骑行体验，请提前准备耗材。")
        }
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
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
