//
//  PTTripManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 23/7/2026.
//

import Foundation
import PooTools

// 🚨 升级 1：让模型支持 Codable，以便于本地持久化存储
public struct PTTripReport: Codable {
    public let startTime: Date
    public let endTime: Date
    public let durationMinutes: Int
    public let maxSpeedKmh: Double
    public let maxRpm: Int
    public let startOdoKm: Double
    public let endOdoKm: Double
    public let distanceKm: Double
    public let avgConsumption: Double
}

// 🚨 升级 2：定义一个新的通知，告诉 UI 界面 "有新报告生成了"
public let MotorcycleTripReportGenerated = NSNotification.Name("MotorcycleTripReportGenerated")

/// 骑行行程统计与存储管理器
@objcMembers
public class PTTripManager: NSObject {
    
    public static let shared = PTTripManager()
    
    // 🚨 升级 3：对外暴露的历史记录数组，你的 UI 将直接读取这个属性！
    public private(set) var tripHistory: [PTTripReport] = []
    
    // 用于本地存储的 Key
    private let tripStorageKey = "PTTripHistoryStorageKey"
    
    // 内部状态记录
    private var isRiding: Bool = false
    private var startTime: Date?
    private var maxSpeed: Double = 0
    private var maxRpm: Int = 0
    private var startOdo: Double = 0
    private var latestOdo: Double = 0
    private var latestConsumption: Double = 0
    
    private override init() {
        super.init()
        loadHistory() // 初始化时，自动把本地保存的历史数据读进内存
        setupObservers()
    }
    
    // MARK: - 持久化存储逻辑
    /// 从本地加载历史记录
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: tripStorageKey),
           let savedTrips = try? JSONDecoder().decode([PTTripReport].self, from: data) {
            self.tripHistory = savedTrips
        }
    }
    
    /// 保存记录到本地沙盒
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(tripHistory) {
            UserDefaults.standard.set(data, forKey: tripStorageKey)
        }
    }
    
    /// 提供给外部：清空所有历史记录 (可绑定到 UI 上的"清空记录"按钮)
    public func clearAllTrips() {
        tripHistory.removeAll()
        saveHistory()
        PTNSLogConsole("🗑️ [行程记录] 已清空所有历史数据")
    }
    
    // MARK: - 绑定蓝牙数据源
    private func setupObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleConnect), name: BLEConnectSuccess, object: nil)
        nc.addObserver(self, selector: #selector(handleDisconnect), name: MotorcycleDisconnected, object: nil)
        nc.addObserver(self, selector: #selector(handleControlData(_:)), name: MotorcycleCONTROL, object: nil)
        nc.addObserver(self, selector: #selector(handleData1(_:)), name: MotorcycleDATA1, object: nil)
    }
    
    // MARK: - 业务逻辑处理
    @objc private func handleConnect() {
        isRiding = true
        startTime = Date()
        maxSpeed = 0
        maxRpm = 0
        startOdo = 0
        latestOdo = 0
        latestConsumption = 0
    }
    
    @objc private func handleControlData(_ notification: Notification) {
        guard isRiding, let control = notification.object as? PTDashboardControl else { return }
        if control.vehicleSpeedKmh > maxSpeed { maxSpeed = control.vehicleSpeedKmh }
        if control.engineRpm > maxRpm { maxRpm = control.engineRpm }
    }
    
    @objc private func handleData1(_ notification: Notification) {
        guard isRiding, let data1 = notification.object as? PTDashboardData1 else { return }
        if startOdo == 0 && data1.odoKm > 0 { startOdo = data1.odoKm }
        latestOdo = data1.odoKm
        latestConsumption = data1.avgConsumptionLt
    }
    
    @objc private func handleDisconnect() {
        guard isRiding, let start = startTime else { return }
        isRiding = false
        
        let endTime = Date()
        let durationSec = endTime.timeIntervalSince(start)
        let durationMin = Int(durationSec / 60.0)
        let distance = (latestOdo > startOdo) ? (latestOdo - startOdo) : 0
        
        // 🚨 升级 4：无效数据过滤。防止因为信号抖动或接通即断电产生的 0 距离垃圾数据污染列表
        guard durationMin > 0 || distance > 0.1 else {
            PTNSLogConsole("⚠️ [行程记录] 本次连接时间过短或未产生位移，已忽略。")
            return
        }
        
        let report = PTTripReport(
            startTime: start,
            endTime: endTime,
            durationMinutes: durationMin,
            maxSpeedKmh: maxSpeed,
            maxRpm: maxRpm,
            startOdoKm: startOdo,
            endOdoKm: latestOdo,
            distanceKm: distance,
            avgConsumption: latestConsumption
        )
        
        // 1. 存入内存数组的最前面 (保证最新记录在列表顶部)
        tripHistory.insert(report, at: 0)
        
        // 2. 写入本地磁盘
        saveHistory()
        
        // 3. 🚨 核心：向 UI 界面发出带数据的全局广播！
        NotificationCenter.default.post(name: MotorcycleTripReportGenerated, object: report)
        
        PTNSLogConsole("🏁 [行程报告生成] 已成功持久化，当前共保存 \(tripHistory.count) 条记录。")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
