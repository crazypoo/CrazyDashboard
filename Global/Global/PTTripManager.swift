//
//  PTTripManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 23/7/2026.
//

import Foundation
import PooTools

// 🌟 新增：专门用于给 UI 界面实时刷新用的数据模型
public struct PTLiveTripStats {
    public let runTime: TimeInterval       // 运行时长 (秒)
    public let idleTime: TimeInterval      // 怠速时长 (秒)
    public let distanceKm: Double          // 当前行驶里程 (km)
    public let avgSpeedKmh: Double         // 实时平均速度
    public let maxSpeedKmh: Double         // 当前最高速度
    public let minSpeedKmh: Double         // 当前最低速度
    public let best0To100Time: TimeInterval? // 最佳 0-100 成绩
}

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
    
    public let pressureTrace: [Double]
    public let idleTimeSeconds: TimeInterval  // 怠速时长(秒)
    public let best0To100Time: TimeInterval?  // 0-100加速最佳成绩(秒)
    public let gpsAvgSpeedKmh: Double         // GPS 平均速度
    public let gpsMaxSpeedKmh: Double         // GPS 最高速度
    public let gpsMinSpeedKmh: Double         // GPS 最低速度

    public let gpxFileName: String?
}

// 🚨 升级 2：定义一个新的通知，告诉 UI 界面 "有新报告生成了"
public let MotorcycleTripReportGenerated = NSNotification.Name("MotorcycleTripReportGenerated")
public let MotorcycleMotionUpdate = NSNotification.Name("MotorcycleMotionUpdate")

/// 骑行行程统计与存储管理器
@objcMembers
public class PTTripManager: NSObject {
    
    public static let shared = PTTripManager()
    
    public var liveStatsBlock: ((PTLiveTripStats) -> Void)?
    
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
    private var currentLivePressure: Double = 0.0 // 🌟 新增：当前气压缓存
    
    // 🌟 轨迹数组
    private var leanTraceArray: [Double] = []
    private var pitchTraceArray: [Double] = []
    private var gForceXTraceArray: [Double] = []
    private var gForceYTraceArray: [Double] = []
    private var gForceZTraceArray: [Double] = []
    private var altitudeTraceArray: [Double] = []
    private var pressureTraceArray: [Double] = [] // 🌟 新增：气压轨迹数组
    private var routeArray: [PTRoutePoint] = []
    
    private var minSpeed: Double = 999.0
    private var idleTime: TimeInterval = 0.0
    private var lastControlUpdateTime: Date?       // 用于计算帧间差的怠速时间
    private var zeroToHundredStartTime: Date?      // 0-100 起步时刻
    private var best0To100Time: TimeInterval?      // 本次行程的最佳 0-100 成绩

    private override init() {
        super.init()
        loadHistory() // 初始化时，自动把本地保存的历史数据读进内存
        setupObservers()
    }
    
    private func broadcastLiveStats() {
        guard isRiding, let start = startTime else { return }
        
        let runTime = Date().timeIntervalSince(start)
        let distance = (latestOdo > startOdo) ? (latestOdo - startOdo) : 0
        let durationHours = runTime / 3600.0
        let avgSpeed = durationHours > 0 ? (distance / durationHours) : 0.0
        
        let stats = PTLiveTripStats(
            runTime: runTime,
            idleTime: idleTime,
            distanceKm: distance,
            avgSpeedKmh: avgSpeed,
            maxSpeedKmh: maxSpeed,
            minSpeedKmh: minSpeed == 999.0 ? 0.0 : minSpeed,
            best0To100Time: best0To100Time
        )
        
        // 保证回调在主线程执行，防止 UI 界面崩溃
        DispatchQueue.main.async { [weak self] in
            self?.liveStatsBlock?(stats)
        }
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
        currentLivePressure = 0
        
        leanTraceArray.removeAll()
        pitchTraceArray.removeAll()
        gForceXTraceArray.removeAll()
        gForceYTraceArray.removeAll()
        gForceZTraceArray.removeAll()
        altitudeTraceArray.removeAll()
        pressureTraceArray.removeAll()
        routeArray.removeAll()

        minSpeed = 999.0
        idleTime = 0.0
        lastControlUpdateTime = nil
        zeroToHundredStartTime = nil
        best0To100Time = nil

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
            self.pressureTraceArray.append(self.currentLivePressure)
            
            self.broadcastLiveStats()
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
            self.currentLivePressure = data.pressure
            
            if data.gForceY > self.maxAccelG { self.maxAccelG = data.gForceY }
            if data.gForceY < self.maxBrakeG { self.maxBrakeG = data.gForceY } // 刹车通常为负值
            if abs(data.gForceX) > self.maxCornerG { self.maxCornerG = abs(data.gForceX) }
            if abs(data.gForceZ) > self.maxBump { self.maxBump = abs(data.gForceZ) }
            if data.pitch > self.maxPitchUp { self.maxPitchUp = data.pitch }
            if data.pitch < self.maxPitchDown { self.maxPitchDown = data.pitch }
        }
        
        PTLocationEngine.shared.switchEngineMode(to: .riding)
        PTLocationEngine.shared.startTracking()
        PTLocationEngine.shared.locationBlock = { [weak self] tripData in
            guard let self = self, self.isRiding else { return }
            // 只要拿到了有效的新坐标，就追加到地图轨迹数组中
            if let loc = tripData.currentLocation {
                let point = PTRoutePoint(
                    lat: loc.coordinate.latitude,
                    lon: loc.coordinate.longitude,
                    altitude: loc.altitude,
                    timestamp: Date(),
                    speed: PTMotion.shared.currentSpeedKmh,
                    rpm: self.maxRpm,
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
                
        let speed = control.vehicleSpeedKmh
        let now = Date()
        
        // 1. 怠速时长计算 (利用两次数据包的时间差累加)
        if let lastTime = lastControlUpdateTime {
            let delta = now.timeIntervalSince(lastTime)
            // 如果车速小于 2.0 km/h，视为怠速停车状态
            if speed < 2.0 {
                idleTime += delta
            }
        }
        lastControlUpdateTime = now
        
        // 2. 0-100 km/h 高精度自动计时
        if speed <= 2.0 {
            // 处于静止，随时准备弹射起步
            zeroToHundredStartTime = now
        } else if speed >= 100.0 {
            // 突破 100 时，检查是否有起步记录
            if let start = zeroToHundredStartTime {
                let achievedTime = now.timeIntervalSince(start)
                // 基础防噪：成绩需大于2秒才合理，防止传感器跳变导致的 0.1秒“幽灵成绩”
                if achievedTime > 2.0 {
                    if best0To100Time == nil || achievedTime < best0To100Time! {
                        best0To100Time = achievedTime
                        PTNSLogConsole("🏎️💨 [硬件测速] 创造新的 0-100km/h 成绩: \(String(format: "%.2f", achievedTime))秒！")
                    }
                }
                // 成绩达成后清除起步时刻，等待下次重新静止
                zeroToHundredStartTime = nil
            }
        }
        
        // 3. 更新极限速度极值
        PTMotion.shared.currentSpeedKmh = speed // 给轨迹打点备用
        
        if speed > maxSpeed { maxSpeed = speed }
        // 最低速度需排除怠速状态
        if speed > 1.0 && speed < minSpeed { minSpeed = speed }
        
        // 更新转速
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
                
        // 🚨 停止采样定时器
        telemetryTimer?.invalidate()
        telemetryTimer = nil

        let endTime = Date()
        let durationSec = endTime.timeIntervalSince(start)
        let durationMin = Int(durationSec / 60.0)
        let distance = (latestOdo > startOdo) ? (latestOdo - startOdo) : 0
        
        let durationHours = durationSec / 3600.0
        let hardwareAvgSpeed = durationHours > 0 ? (distance / durationHours) : 0.0
        
        guard durationMin > 0 || distance > 0.1 else {
            PTNSLogConsole("⚠️ [行程记录] 本次连接时间过短或未产生位移，已忽略。")
            // 记得把定位切回防盗模式
            PTLocationEngine.shared.switchEngineMode(to: .antiTheft)
            return
        }
        
        // 3. 开始生成高德 GPX 和快照
        let generatedFileName = PTGPXRecorder.shared.exportGPX(from: routeArray)
        if let fileName = generatedFileName {
            // 在后台生成缩略图并上传 iCloud
            let coosMap = routeArray.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            PTRouteSnapshotManager.shared.generateAndSaveSnapshot(coordinates: coosMap, gpxFileName: fileName)
        }
        
        // 切回防盗模式
        PTLocationEngine.shared.switchEngineMode(to: .antiTheft)

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
            
            pressureTrace: pressureTraceArray,
            idleTimeSeconds: idleTime,
            best0To100Time: best0To100Time,
            gpsAvgSpeedKmh: hardwareAvgSpeed, // 虽然参数名还叫 gpsAvgSpeedKmh，但它现在是更准的表显平均速度
            gpsMaxSpeedKmh: maxSpeed,         // 保持一致
            gpsMinSpeedKmh: minSpeed == 999.0 ? 0.0 : minSpeed,
            
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
