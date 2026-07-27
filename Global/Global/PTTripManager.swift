//
//  PTTripManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 23/7/2026.
//

import Foundation
import PooTools

public struct PTRoutePoint: Codable {
    public let lat: Double
    public let lon: Double
    
    public let altitude: Double
    public let timestamp: Date
    
    public let speed: Double
    public let rpm: Int
    public let leanAngle: Double // 把倾角也导进去！
    public let gForceY: Double   // 加减速 G 值
    public let gForceX: Double   // 过弯 G 值
}

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
    
    public let maxLeanAngleLeft: Double
    public let maxLeanAngleRight: Double
    public let leanAngleTrace: [Double]
    // 🌟 新增：极限物理状态记录
    public let maxAccelerationG: Double // 最大加速 G 值 (+Y)
    public let maxBrakingG: Double      // 最大刹车 G 值 (-Y)
    public let maxCorneringG: Double    // 最大过弯向心力 (X 绝对值)
    public let maxBumpG: Double         // 最大颠簸冲击 (Z)
    public let maxPitchUp: Double       // 最大上坡角度 (+Pitch)
    public let maxPitchDown: Double     // 最大下坡角度 (-Pitch)
    
    // 🌟 新增：时间轴遥测轨迹数组 (与 leanAngleTrace 长度严格一致)
    public let gForceYTrace: [Double]   // 加减速轨迹
    public let gForceXTrace: [Double]   // 左右侧向力轨迹
    public let gForceZTrace: [Double]   // 左右侧向力轨迹
    public let pitchTrace: [Double]     // 坡度轨迹
    public let relativeAltitudeTrace: [Double] // 海拔起伏轨迹
    
    public let gpxFileName: String?
}

// 🚨 升级 2：定义一个新的通知，告诉 UI 界面 "有新报告生成了"
public let MotorcycleTripReportGenerated = NSNotification.Name("MotorcycleTripReportGenerated")
public let MotorcycleMotionUpdate = NSNotification.Name("MotorcycleMotionUpdate")

/// 骑行行程统计与存储管理器
@objcMembers
public class PTTripManager: NSObject {
    
    public static let shared = PTTripManager()
    
    private let historyFileName = "PTTripHistory.json"
    
    private var localHistoryURL: URL {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docsDir.appendingPathComponent(historyFileName)
    }

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
    
    private var maxLeanLeft: Double = 0
    private var maxLeanRight: Double = 0
    private var telemetryTimer: Timer?

    // 🌟 极限值缓存
    private var maxAccelG: Double = 0.0
    private var maxBrakeG: Double = 0.0
    private var maxCornerG: Double = 0.0
    private var maxBump: Double = 0.0
    private var maxPitchUp: Double = 0.0
    private var maxPitchDown: Double = 0.0

    // 🌟 1Hz 线程安全快照缓存
    private var currentLiveRoll: Double = 0.0
    private var currentLivePitch: Double = 0.0
    private var currentLiveGForceX: Double = 0.0
    private var currentLiveGForceY: Double = 0.0
    private var currentLiveGForceZ: Double = 0.0
    private var currentLiveAltitude: Double = 0.0
    
    // 🌟 轨迹数组
    private var leanTraceArray: [Double] = []
    private var pitchTraceArray: [Double] = []
    private var gForceXTraceArray: [Double] = []
    private var gForceYTraceArray: [Double] = []
    private var gForceZTraceArray: [Double] = []
    private var altitudeTraceArray: [Double] = []
    private var routeArray: [PTRoutePoint] = []
    
    private override init() {
        super.init()
        loadHistory() // 初始化时，自动把本地保存的历史数据读进内存
        setupObservers()
    }
    
    // MARK: - 持久化存储逻辑
    /// 从本地加载历史记录
    private func loadHistory() {
        let fileURL = localHistoryURL
        let fileManager = FileManager.default
        
        // 🚨 云端恢复逻辑：如果本地发现没有历史文件（比如刚装 App 或换了新手机）
        if !fileManager.fileExists(atPath: fileURL.path) {
            PTNSLogConsole("ℹ️ 本地未找到行程记录，尝试从 iCloud 恢复...")
            // 巧妙借用你写好的数据库恢复方法，其实它对 json 文件也完全适用
            let restored = PTiCloudFileManager.shared.restoreDatabaseFromICloud(dbName: historyFileName)
            if restored {
                PTNSLogConsole("☁️ 成功从 iCloud 拉取历史行程数据！")
            }
        }
        
        // 尝试读取文件数据
        if let data = try? Data(contentsOf: fileURL) {
            do {
                let decoder = JSONDecoder()
                // 工业级容错：防止传感器产生异常浮点数导致解析崩溃
                decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "INF", negativeInfinity: "-INF", nan: "NaN")
                
                let savedTrips = try decoder.decode([PTTripReport].self, from: data)
                self.tripHistory = savedTrips
                PTNSLogConsole("✅ [行程记录] 成功加载 \(savedTrips.count) 条历史记录")
                
            } catch {
                PTNSLogConsole("❌ [行程记录] 历史数据解析严重失败: \(error)")
                self.tripHistory = []
            }
        } else {
            PTNSLogConsole("ℹ️ [行程记录] 本地与云端均无数据，初始化为空列表")
        }
    }

    /// 保存记录到本地沙盒
    private func saveHistory() {
        do {
            let encoder = JSONEncoder()
            // 工业级容错：防止传感器异常浮点数导致编码崩溃
            encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "INF", negativeInfinity: "-INF", nan: "NaN")
            
            // 1. 将数组编码为 JSON 二进制数据
            let data = try encoder.encode(tripHistory)
            
            // 2. 写入本地文件 (options: .atomic 保证即使写入时断电，文件也不会损坏)
            try data.write(to: localHistoryURL, options: .atomic)
            
            // 3. 🚨 核心联动：推送到 iCloud 进行云备份！
            PTiCloudFileManager.shared.backupDatabaseToICloud(dbName: historyFileName)
            
            PTNSLogConsole("💾 [行程记录] 完美保存至本地并已发起 iCloud 同步！当前历史总数: \(tripHistory.count)")
            
        } catch {
            PTNSLogConsole("❌ [行程记录] 数据编码保存严重失败: \(error)")
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
        
        // 重置倾角状态
        maxLeanLeft = 0
        maxLeanRight = 0
        currentLiveRoll = 0.0
        maxAccelG = 0
        maxBrakeG = 0
        maxCornerG = 0
        maxBump = 0
        maxPitchUp = 0
        maxPitchDown = 0
        
        leanTraceArray.removeAll()
        pitchTraceArray.removeAll()
        gForceXTraceArray.removeAll()
        gForceYTraceArray.removeAll()
        gForceZTraceArray.removeAll()
        altitudeTraceArray.removeAll()
        routeArray.removeAll()

        PTMotion.shared.resetLeanAngles()
        PTMotion.shared.startMotion()
        
        // 🚨 启动遥测定时器 (1Hz 采样率)
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRiding else { return }
            // 从倾角管理器中直接抓拍当前的平滑角度
            self.leanTraceArray.append(self.currentLiveRoll)
            self.pitchTraceArray.append(self.currentLivePitch)
            self.gForceXTraceArray.append(self.currentLiveGForceX)
            self.gForceYTraceArray.append(self.currentLiveGForceY)
            self.gForceZTraceArray.append(self.currentLiveGForceZ)
            self.altitudeTraceArray.append(self.currentLiveAltitude)
        }
        
        PTMotion.shared.motionBlock = { [weak self] data in
            guard let self = self else { return }
            self.maxLeanLeft = data.maxLeftLean
            self.maxLeanRight = data.maxRightLean
            self.currentLiveRoll = data.roll
            self.currentLivePitch = data.pitch
            self.currentLiveGForceX = data.gForceX
            self.currentLiveGForceY = data.gForceY
            self.currentLiveGForceZ = data.gForceZ
            self.currentLiveAltitude = data.relativeAltitude
            
            if data.gForceY > self.maxAccelG { self.maxAccelG = data.gForceY }
            if data.gForceY < self.maxBrakeG { self.maxBrakeG = data.gForceY } // 刹车通常为负值
            if abs(data.gForceX) > self.maxCornerG { self.maxCornerG = abs(data.gForceX) }
            if abs(data.gForceZ) > self.maxBump { self.maxBump = abs(data.gForceZ) }
            if data.pitch > self.maxPitchUp { self.maxPitchUp = data.pitch }
            if data.pitch < self.maxPitchDown { self.maxPitchDown = data.pitch }
        }
        
        PTLocationEngine.shared.switchEngineMode(to: .riding)
        PTLocationEngine.shared.locationBlock = { [weak self] tripData in
            guard let self = self, self.isRiding else { return }
            // 只要拿到了有效的新坐标，就追加到地图轨迹数组中
            if let loc = tripData.currentLocation {
                let point = PTRoutePoint(
                    lat: loc.coordinate.latitude,
                    lon: loc.coordinate.longitude,
                    altitude: loc.altitude,
                    timestamp: Date(),
                    speed: tripData.speedKmh, // 使用高德计算出的精准速度，或者如果你喜欢机车表显速度也可以换
                    rpm: self.maxRpm,         // (你可以在 manager 中加一个 currentRpm 属性)
                    leanAngle: self.currentLiveRoll,
                    gForceY: self.currentLiveGForceY,
                    gForceX: self.currentLiveGForceX
                )
                self.routeArray.append(point)
            }
        }
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
        
        let generatedFileName = PTGPXRecorder.shared.exportGPX(from: routeArray)
        if let fileName = generatedFileName {
            // 这个过程是在后台悄悄进行的，完全不会卡顿用户的操作
            let coosMap = routeArray.map { value in
                let coo = CLLocationCoordinate2D(latitude: value.lat, longitude: value.lon)
                return coo
            }
            PTRouteSnapshotManager.shared.generateAndSaveSnapshot(coordinates: coosMap, gpxFileName: fileName)
        }
        PTLocationEngine.shared.switchEngineMode(to: .antiTheft)
        
        // 🚨 停止采样定时器
        telemetryTimer?.invalidate()
        telemetryTimer = nil

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
            avgConsumption: latestConsumption,
            maxLeanAngleLeft: maxLeanLeft,
            maxLeanAngleRight: maxLeanRight,
            leanAngleTrace: leanTraceArray,
            
            // 新增的极限数据
            maxAccelerationG: maxAccelG,
            maxBrakingG: maxBrakeG,
            maxCorneringG: maxCornerG,
            maxBumpG: maxBump,
            maxPitchUp: maxPitchUp,
            maxPitchDown: maxPitchDown,
            
            // 新增的轨迹数据
            gForceYTrace: gForceYTraceArray,
            gForceXTrace: gForceXTraceArray,
            gForceZTrace: gForceZTraceArray,
            pitchTrace: pitchTraceArray,
            
            relativeAltitudeTrace: altitudeTraceArray,
            gpxFileName: generatedFileName
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
