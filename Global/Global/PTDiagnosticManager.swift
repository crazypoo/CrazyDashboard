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
        // 监听包含电压和温度的 DATA2 数据流
        NotificationCenter.default.addObserver(self, selector: #selector(handleData2(_:)), name: MotorcycleDATA2, object: nil)
        
        // 当蓝牙重新连接时，重置报警状态，以便下一次骑行可以重新检测
        NotificationCenter.default.addObserver(self, selector: #selector(resetWarnings), name: BLEConnectSuccess, object: nil)
    }
    
    @objc private func resetWarnings() {
        hasWarnedBattery = false
        hasWarnedIcyRoad = false
    }
    
    @objc private func handleData2(_ notification: Notification) {
        guard let data2 = notification.object as? PTDashboardData2 else { return }
        
        // 1. 电瓶健康诊断逻辑
        // 只有在引擎未启动 (状态 0) 时，测量到的才是真实的电瓶静态电压。引擎启动后发电机介入，电压会升高。
        if data2.engineStatus == 0 {
            if data2.batteryVolt < 11.8 && !hasWarnedBattery {
                hasWarnedBattery = true
                // 调用我们写好的工具类，推送到车机或手机本地通知
                PTMessagePusher.pushToDashboard(title: "⚠️ 电瓶亏电警告", body: "当前静态电压仅 \(data2.batteryVolt)V，存在无法启动的风险，请尽快充电。")
                PTNSLogConsole("🔋 [健康诊断] 检测到电瓶低电压: \(data2.batteryVolt)V")
            }
        }
        
        // 2. 环境温度与路面结冰诊断逻辑
        if data2.outsideTempC <= 3 && !hasWarnedIcyRoad {
            hasWarnedIcyRoad = true
            PTMessagePusher.pushToDashboard(title: "❄️ 结冰预警", body: "车外温度 \(data2.outsideTempC)°C，道路极可能存在暗冰，请减速慢行！")
            PTNSLogConsole("🌡️ [环境诊断] 检测到极寒天气: \(data2.outsideTempC)°C")
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
