//
//  PTTripManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 23/7/2026.
//

import Foundation
import PooTools
import CoreLocation

public struct PTTripOffRoadEvent: Codable {
    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double
    public let slipRatio: Double
    public let info: String
}

public struct PTLiveTripStats {
    public let runTime: TimeInterval       // 运行时长 (秒)
    public let idleTime: TimeInterval      // 怠速时长 (秒)
    public let distanceKm: Double          // 当前行驶里程 (km)
    public let avgSpeedKmh: Double         // 实时平均速度
    public let maxSpeedKmh: Double         // 当前最高速度
    public let minSpeedKmh: Double         // 当前最低速度
    public let best0To100Time: TimeInterval? // 最佳 0-100 成绩
    public let currentSlipRatio: Double
    public let tractionLevelName: String
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
    public let gForceZ: Double   // 颠簸冲击 G 值
    public let slipRatio: Double
}

public enum PTTripDistanceSource: String, Codable, Sendable {
    case odometer
    case gps
}

public enum PTRideReviewEventType: String, Codable, Sendable, CaseIterable {
    case hardBraking
    case hardAcceleration
    case heavyBump
    case highLean
    case suspectedSlip

    public var title: String {
        switch self {
        case .hardBraking: return "急刹"
        case .hardAcceleration: return "突加速"
        case .heavyBump: return "重颠簸"
        case .highLean: return "高倾角"
        case .suspectedSlip: return "疑似打滑"
        }
    }
}

public struct PTRideReviewEvent: Codable, Hashable, Sendable {
    public let type: PTRideReviewEventType
    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double
    public let peakValue: Double
    public let speedKmh: Double
    public let severity: Double

    public init(type: PTRideReviewEventType,
                timestamp: Date,
                latitude: Double,
                longitude: Double,
                peakValue: Double,
                speedKmh: Double,
                severity: Double) {
        self.type = type
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.peakValue = peakValue
        self.speedKmh = speedKmh
        self.severity = severity
    }
}

// 🚨 升级 1：让模型支持 Codable，以便于本地持久化存储
public struct PTTripReport: Codable {
    public let schemaVersion: Int = 2
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
    public let speedTrace: [Double]     // 车速轨迹 (km/h)
    public let rpmTrace: [Int]          // 转速轨迹 (RPM)
    public let best0To100Time: TimeInterval?  // 0-100加速最佳成绩(秒)
    public let gpsAvgSpeedKmh: Double         // GPS 平均速度
    public let gpsMaxSpeedKmh: Double         // GPS 最高速度
    public let gpsMinSpeedKmh: Double         // GPS 最低速度

    public let gpxFileName: String?
    
    public let maxSlipRatio: Double             // 本次行程极值
    public let heavySlipCount: Int              // 严重打滑次数
    public let slipRatioTrace: [Double]         // 1Hz 遥测轨迹 (用于画折线图)
    public let offRoadEvents: [PTTripOffRoadEvent] // 危险/脱困坐标点集合
    public let distanceSource: PTTripDistanceSource
    public let reviewEvents: [PTRideReviewEvent]
}

private struct PTTripHistoryDocument: Codable {
    let schemaVersion: Int
    let trips: [PTTripReport]
}

extension PTTripReport {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, startTime, endTime, durationMinutes, maxSpeedKmh, maxRpm
        case startOdoKm, endOdoKm, distanceKm, avgConsumption, maxLeanAngleLeft, maxLeanAngleRight
        case leanAngleTrace, maxAccelerationG, maxBrakingG, maxCorneringG, maxBumpG, maxPitchUp, maxPitchDown
        case gForceYTrace, gForceXTrace, gForceZTrace, pitchTrace, relativeAltitudeTrace, pressureTrace
        case idleTimeSeconds, speedTrace, rpmTrace, best0To100Time, gpsAvgSpeedKmh, gpsMaxSpeedKmh, gpsMinSpeedKmh
        case gpxFileName, maxSlipRatio, heavySlipCount, slipRatioTrace, offRoadEvents, distanceSource, reviewEvents
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // schemaVersion 的默认值由当前模型统一管理；旧文件仍按兼容字段解码。
        // La versión del esquema la gestiona el modelo actual; los archivos antiguos siguen usando decodificación compatible.
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decode(Date.self, forKey: .endTime)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 0
        maxSpeedKmh = try container.decodeIfPresent(Double.self, forKey: .maxSpeedKmh) ?? 0
        maxRpm = try container.decodeIfPresent(Int.self, forKey: .maxRpm) ?? 0
        startOdoKm = try container.decodeIfPresent(Double.self, forKey: .startOdoKm) ?? 0
        endOdoKm = try container.decodeIfPresent(Double.self, forKey: .endOdoKm) ?? 0
        distanceKm = try container.decodeIfPresent(Double.self, forKey: .distanceKm) ?? 0
        avgConsumption = try container.decodeIfPresent(Double.self, forKey: .avgConsumption) ?? 0
        maxLeanAngleLeft = try container.decodeIfPresent(Double.self, forKey: .maxLeanAngleLeft) ?? 0
        maxLeanAngleRight = try container.decodeIfPresent(Double.self, forKey: .maxLeanAngleRight) ?? 0
        leanAngleTrace = try container.decodeIfPresent([Double].self, forKey: .leanAngleTrace) ?? []
        maxAccelerationG = try container.decodeIfPresent(Double.self, forKey: .maxAccelerationG) ?? 0
        maxBrakingG = try container.decodeIfPresent(Double.self, forKey: .maxBrakingG) ?? 0
        maxCorneringG = try container.decodeIfPresent(Double.self, forKey: .maxCorneringG) ?? 0
        maxBumpG = try container.decodeIfPresent(Double.self, forKey: .maxBumpG) ?? 0
        maxPitchUp = try container.decodeIfPresent(Double.self, forKey: .maxPitchUp) ?? 0
        maxPitchDown = try container.decodeIfPresent(Double.self, forKey: .maxPitchDown) ?? 0
        gForceYTrace = try container.decodeIfPresent([Double].self, forKey: .gForceYTrace) ?? []
        gForceXTrace = try container.decodeIfPresent([Double].self, forKey: .gForceXTrace) ?? []
        gForceZTrace = try container.decodeIfPresent([Double].self, forKey: .gForceZTrace) ?? []
        pitchTrace = try container.decodeIfPresent([Double].self, forKey: .pitchTrace) ?? []
        relativeAltitudeTrace = try container.decodeIfPresent([Double].self, forKey: .relativeAltitudeTrace) ?? []
        pressureTrace = try container.decodeIfPresent([Double].self, forKey: .pressureTrace) ?? []
        idleTimeSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .idleTimeSeconds) ?? 0
        speedTrace = try container.decodeIfPresent([Double].self, forKey: .speedTrace) ?? []
        rpmTrace = try container.decodeIfPresent([Int].self, forKey: .rpmTrace) ?? []
        best0To100Time = try container.decodeIfPresent(TimeInterval.self, forKey: .best0To100Time)
        gpsAvgSpeedKmh = try container.decodeIfPresent(Double.self, forKey: .gpsAvgSpeedKmh) ?? 0
        gpsMaxSpeedKmh = try container.decodeIfPresent(Double.self, forKey: .gpsMaxSpeedKmh) ?? 0
        gpsMinSpeedKmh = try container.decodeIfPresent(Double.self, forKey: .gpsMinSpeedKmh) ?? 0
        gpxFileName = try container.decodeIfPresent(String.self, forKey: .gpxFileName)
        maxSlipRatio = try container.decodeIfPresent(Double.self, forKey: .maxSlipRatio) ?? 0
        heavySlipCount = try container.decodeIfPresent(Int.self, forKey: .heavySlipCount) ?? 0
        slipRatioTrace = try container.decodeIfPresent([Double].self, forKey: .slipRatioTrace) ?? []
        offRoadEvents = try container.decodeIfPresent([PTTripOffRoadEvent].self, forKey: .offRoadEvents) ?? []
        distanceSource = try container.decodeIfPresent(PTTripDistanceSource.self, forKey: .distanceSource) ?? .gps
        reviewEvents = try container.decodeIfPresent([PTRideReviewEvent].self, forKey: .reviewEvents) ?? []
    }
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
    private var hasOdometerData = false
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
    private var currentLiveSpeed: Double = 0.0 // 🌟 新增：当前车速缓存
    private var currentLiveRpm: Int = 0        // 🌟 新增：当前转速缓存
    
    // 🌟 轨迹数组
    private var leanTraceArray: [Double] = []
    private var pitchTraceArray: [Double] = []
    private var gForceXTraceArray: [Double] = []
    private var gForceYTraceArray: [Double] = []
    private var gForceZTraceArray: [Double] = []
    private var altitudeTraceArray: [Double] = []
    private var pressureTraceArray: [Double] = [] // 🌟 新增：气压轨迹数组
    private var routeArray: [PTRoutePoint] = []
    private var speedTraceArray: [Double] = [] // 🌟 新增：车速轨迹数组
    private var rpmTraceArray: [Int] = []      // 🌟 新增：转速轨迹数组

    private var minSpeed: Double = 999.0
    private var idleTime: TimeInterval = 0.0
    private var lastControlUpdateTime: Date?       // 用于计算帧间差的怠速时间
    private var zeroToHundredStartTime: Date?      // 0-100 起步时刻
    private var best0To100Time: TimeInterval?      // 本次行程的最佳 0-100 成绩

    private var lastGpsLocation: CLLocation?
    private var accumulatedGpsDistance: Double = 0.0 // 纯 GPS 累计行驶里程 (km)

    // 🌟 新增 (ADV越野)：实时状态快照
    private var currentLiveSlipRatio: Double = 0.0
    private var currentTractionLevelName: String = "抓地力良好"
    private var lastFrontSpeed: Double = 0.0
    
    // 🌟 新增 (ADV越野)：统计与轨迹缓存
    private var maxSlipRatio: Double = 0.0
    private var slipRatioTraceArray: [Double] = []
    private var offRoadEventsArray: [PTTripOffRoadEvent] = []
    private var lastOffRoadEventTime: Date? // 防抖控制

    private override init() {
        super.init()
        loadHistory() // 初始化时，自动把本地保存的历史数据读进内存
        setupObservers()
    }
    
    private func broadcastLiveStats() {
        guard isRiding, let start = startTime else { return }
        
        let runTime = Date().timeIntervalSince(start)
        let distance = currentDistanceKm
        let durationHours = runTime / 3600.0
        let avgSpeed = durationHours > 0 ? (distance / durationHours) : 0.0
        
        let stats = PTLiveTripStats(
            runTime: runTime,
            idleTime: idleTime,
            distanceKm: distance,
            avgSpeedKmh: avgSpeed,
            maxSpeedKmh: maxSpeed,
            minSpeedKmh: minSpeed == 999.0 ? 0.0 : minSpeed,
            best0To100Time: best0To100Time,
            currentSlipRatio: currentLiveSlipRatio,
            tractionLevelName: currentTractionLevelName
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
                // 中文：兼容传感器异常浮点数；Español: tolerar valores flotantes no conformes del sensor.
                decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "INF", negativeInfinity: "-INF", nan: "NaN")

                let savedTrips: [PTTripReport]
                if let document = try? decoder.decode(PTTripHistoryDocument.self, from: data) {
                    savedTrips = document.trips
                } else {
                    savedTrips = try decoder.decode([PTTripReport].self, from: data)
                }

                self.tripHistory = savedTrips
                PTNSLogConsole("✅ [行程记录] 成功加载 \(savedTrips.count) 条历史记录")
            } catch {
                PTNSLogConsole("❌ [行程记录] 历史数据解析失败，保留原文件: \(error)")
                preserveCorruptHistory(data)
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
            
            let document = PTTripHistoryDocument(schemaVersion: 2, trips: tripHistory)
            // 中文：使用带版本的文档保存；Español: guardar un documento versionado.
            let data = try encoder.encode(document)
            
            // 2. 写入本地文件 (options: .atomic 保证即使写入时断电，文件也不会损坏)
            try data.write(to: localHistoryURL, options: .atomic)
            
            // 3. 🚨 核心联动：推送到 iCloud 进行云备份！
            PTiCloudFileManager.shared.backupDatabaseToICloud(dbName: historyFileName)
            
            PTNSLogConsole("💾 [行程记录] 完美保存至本地并已发起 iCloud 同步！当前历史总数: \(tripHistory.count)")
            
        } catch {
            PTNSLogConsole("❌ [行程记录] 数据编码保存严重失败: \(error)")
        }
    }

    private func preserveCorruptHistory(_ data: Data) {
        let backupURL = localHistoryURL.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
        do {
            try data.write(to: backupURL, options: .withoutOverwriting)
            PTNSLogConsole("⚠️ [行程记录] 已保留损坏历史备份: \(backupURL.lastPathComponent)")
        } catch {
            PTNSLogConsole("❌ [行程记录] 无法保留损坏历史备份: \(error.localizedDescription)")
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
        PTMotion.shared.addDelegate(self)
        PTBluetoothServerManager.shared.addDelegate(self)
        PTMotoTelemetryManager.shared.addDelegate(self)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLocationUpdate(_:)), name: PTLocationEngineDidUpdate, object: nil)
    }
    
    // MARK: - 业务逻辑处理
    @objc public func handleConnect() {
        guard !isRiding else { return }
        isRiding = true
        startTime = Date()
        maxSpeed = 0
        maxRpm = 0
        startOdo = 0
        latestOdo = 0
        hasOdometerData = false
        latestConsumption = 0
        accumulatedGpsDistance = 0.0 // 🌟 重置 GPS 里程
        lastGpsLocation = nil        // 🌟 重置 GPS 参考点
        
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
        currentLiveSpeed = 0.0 // 🌟 重置
        currentLiveRpm = 0     // 🌟 重置

        leanTraceArray.removeAll()
        pitchTraceArray.removeAll()
        gForceXTraceArray.removeAll()
        gForceYTraceArray.removeAll()
        gForceZTraceArray.removeAll()
        altitudeTraceArray.removeAll()
        pressureTraceArray.removeAll()
        routeArray.removeAll()
        speedTraceArray.removeAll() // 🌟 清空
        rpmTraceArray.removeAll()   // 🌟 清空

        minSpeed = 999.0
        idleTime = 0.0
        lastControlUpdateTime = nil
        zeroToHundredStartTime = nil
        best0To100Time = nil

        maxSlipRatio = 0.0
        currentLiveSlipRatio = 0.0
        lastFrontSpeed = 0.0
        currentTractionLevelName = "抓地力良好"
        slipRatioTraceArray.removeAll()
        offRoadEventsArray.removeAll()
        lastOffRoadEventTime = nil

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
            
            self.speedTraceArray.append(self.currentLiveSpeed)
            self.rpmTraceArray.append(self.currentLiveRpm)
            
            self.slipRatioTraceArray.append(self.currentLiveSlipRatio)
            self.broadcastLiveStats()
        }
            
        PTLocationEngine.shared.switchEngineMode(to: .riding)
        PTLocationEngine.shared.startTracking()
    }
        
    @objc private func handleLocationUpdate(_ notification: Notification) {
        guard let tripData = notification.object as? PTTripData,
              let coordinate = tripData.currentLocation,
              self.isRiding else { return }

        guard coordinate.horizontalAccuracy >= 0,
              coordinate.horizontalAccuracy <= 50,
              Date().timeIntervalSince(coordinate.timestamp) <= 10 else { return }
        
        if let last = lastGpsLocation {
            let distMeters = coordinate.distance(from: last)
            let elapsed = max(coordinate.timestamp.timeIntervalSince(last.timestamp), 0.1)
            let jumpSpeedKmh = distMeters / elapsed * 3.6
            // 过滤 GPS 漂移燥点 (位移大于 2 米才算有效移动)
            if distMeters > 2.0, jumpSpeedKmh <= 300 {
                accumulatedGpsDistance += (distMeters / 1000.0) // 转换为 km
            }
        }
        self.lastGpsLocation = coordinate

        if !PTDashboardConfig.shared.blueConnected {
            // iOS 系统的 coordinate.speed 是 m/s，需乘以 3.6 转换为 km/h
            let gpsSpeedKmh = max(0, coordinate.speed * 3.6)
            processSpeedMetrics(speedKmh: gpsSpeedKmh, timestamp: Date())
        }

        let point = PTRoutePoint(
            lat: coordinate.coordinate.latitude,
            lon: coordinate.coordinate.longitude,
            altitude: coordinate.altitude,
            timestamp: Date(),
            speed: PTMotion.shared.currentSpeedKmh,
            rpm: self.currentLiveRpm,
            leanAngle: self.currentLiveRoll,
            gForceY: self.currentLiveGForceY,
            gForceX: self.currentLiveGForceX,
            gForceZ: self.currentLiveGForceZ,
            slipRatio: self.currentLiveSlipRatio
        )
        self.routeArray.append(point)
    }
        
    @objc public func handleDisconnect() {
        guard isRiding, let start = startTime else { return }
        isRiding = false
                
        // 🚨 停止采样定时器
        telemetryTimer?.invalidate()
        telemetryTimer = nil

        let endTime = Date()
        let durationSec = endTime.timeIntervalSince(start)
        let durationMin = Int(durationSec / 60.0)
        
        let finalDistance = currentDistanceKm
        
        let durationHours = durationSec / 3600.0
        let hardwareAvgSpeed = durationHours > 0 ? (finalDistance / durationHours) : 0.0
        
        guard durationMin > 0 || finalDistance > 0.1 else {
            PTNSLogConsole("⚠️ [行程记录] 本次连接时间过短或未产生位移，已忽略。")
            // 记得把定位切回防盗模式
            PTLocationEngine.shared.switchEngineMode(to: .antiTheft)
            return
        }
        
        let reviewEvents = PTRideReviewAnalyzer.analyze(points: routeArray)

        // 3. 开始生成高德 GPX 和快照
        let generatedFileName = PTGPXRecorder.shared.exportGPX(from: routeArray)
        if let fileName = generatedFileName {
            // 在后台生成缩略图并上传 iCloud
            let coosMap = routeArray.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            PTRouteSnapshotManager.shared.generateAndSaveSnapshot(coordinates: coosMap, gpxFileName: fileName, reviewEvents: reviewEvents)
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
            distanceKm: finalDistance,
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
            speedTrace: speedTraceArray,
            rpmTrace: rpmTraceArray,
            best0To100Time: best0To100Time,
            gpsAvgSpeedKmh: hardwareAvgSpeed, // 虽然参数名还叫 gpsAvgSpeedKmh，但它现在是更准的表显平均速度
            gpsMaxSpeedKmh: maxSpeed,         // 保持一致
            gpsMinSpeedKmh: minSpeed == 999.0 ? 0.0 : minSpeed,
            
            gpxFileName: generatedFileName,
            
            maxSlipRatio: maxSlipRatio,
            heavySlipCount: offRoadEventsArray.count,
            slipRatioTrace: slipRatioTraceArray,
            offRoadEvents: offRoadEventsArray,
            distanceSource: hasOdometerData ? .odometer : .gps,
            reviewEvents: reviewEvents
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

    private var currentDistanceKm: Double {
        if hasOdometerData, latestOdo >= startOdo {
            return latestOdo - startOdo
        }
        return accumulatedGpsDistance
    }
}

//MARK: No Connect ble
extension PTTripManager {
    private func processSpeedMetrics(speedKmh: Double, timestamp: Date) {
        self.currentLiveSpeed = speedKmh
        
        // 1. 怠速时长计算 (利用两次数据包的时间差累加)
        if let lastTime = lastControlUpdateTime {
            let delta = timestamp.timeIntervalSince(lastTime)
            if speedKmh < 2.0 {
                idleTime += delta
            }
        }
        lastControlUpdateTime = timestamp
        
        // 2. 0-100 km/h 高精度自动计时
        if speedKmh <= 2.0 {
            zeroToHundredStartTime = timestamp
        } else if speedKmh >= 100.0 {
            if let start = zeroToHundredStartTime {
                let achievedTime = timestamp.timeIntervalSince(start)
                // 基础防噪：成绩需大于2秒才合理
                if achievedTime > 2.0 {
                    if best0To100Time == nil || achievedTime < best0To100Time! {
                        best0To100Time = achievedTime
                        PTNSLogConsole("🏎️💨 [测速引擎] 创造新的 0-100km/h 成绩: \(String(format: "%.2f", achievedTime))秒！")
                    }
                }
                zeroToHundredStartTime = nil
            }
        }
        
        // 3. 更新极限速度极值
        PTMotion.shared.currentSpeedKmh = speedKmh
        if speedKmh > maxSpeed { maxSpeed = speedKmh }
        if speedKmh > 1.0 && speedKmh < minSpeed { minSpeed = speedKmh }
    }
}

//MARK: - ADV 打滑率与事件引擎
extension PTTripManager {
        
    // 🌟 需在原有的 processSpeedMetrics 中被调用：当你更新了 currentLiveSpeed (后轮速) 后，触发计算
    // 请确保在 handleControlData 结尾处，调用了 processSpeedMetrics 之后，加上 calculateSlipRatio()
    
    private func calculateSlipRatio() {
        guard lastFrontSpeed > 2.0 || currentLiveSpeed > 2.0 else {
            self.currentLiveSlipRatio = 0.0
            self.currentTractionLevelName = "抓地力良好"
            return
        }
        
        let baseSpeed = max(lastFrontSpeed, 1.0)
        let speedDiff = currentLiveSpeed - lastFrontSpeed
        let ratio = (speedDiff / baseSpeed) * 100.0
        let clampedRatio = min(max(ratio, -50.0), 200.0)
        
        self.currentLiveSlipRatio = clampedRatio
        
        // 更新极值
        if clampedRatio > maxSlipRatio { maxSlipRatio = clampedRatio }
        
        // 判定级别并触发事件
        if clampedRatio >= 35.0 {
            self.currentTractionLevelName = "严重打滑/脱困"
            recordOffRoadEvent(ratio: clampedRatio)
        } else if clampedRatio >= 10.0 {
            self.currentTractionLevelName = "非铺装路面(碎石)"
        } else {
            self.currentTractionLevelName = "抓地力良好"
        }
    }
    
    private func recordOffRoadEvent(ratio: Double) {
        let now = Date()
        // ⏲ 防抖 5 秒：防止泥坑里疯狂打点
        if let last = lastOffRoadEventTime, now.timeIntervalSince(last) < 5.0 { return }
        guard let loc = lastGpsLocation else { return }
        
        let event = PTTripOffRoadEvent(
            timestamp: now,
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            slipRatio: ratio,
            info: "极限脱困"
        )
        self.offRoadEventsArray.append(event)
        self.lastOffRoadEventTime = now
        PTNSLogConsole("⚠️ [ADV 遥测] 在坐标 (\(loc.coordinate.latitude), \(loc.coordinate.longitude)) 处记录到一次越野脱困事件！")
    }
}

// MARK: - 单条历史记录删除引擎
extension PTTripManager {
    
    /// 删除指定的行程记录（包含清理本地 GPX 与 JPG 缓存文件）
    /// - Parameter trip: 需要删除的行程模型
    public func deleteTrip(_ trip: PTTripReport) {
        
        // 1. 从内存数组中安全移除 (利用 startTime 作为唯一标识符)
        // 使用 removeAll(where:) 是 Swift 中最高效的做法
        tripHistory.removeAll { $0.startTime == trip.startTime }
        
        // 2. 重新写入历史记录的 JSON 文件，并触发 iCloud 同步
        saveHistory()
        
        // 3. 深度清理：销毁与之关联的 GPX 轨迹文件和 JPG 缩略图文件
        if let gpxName = trip.gpxFileName {
            let jpgName = gpxName.replacingOccurrences(of: ".gpx", with: ".jpg")
            deleteFileFromDisk(fileName: gpxName)
            deleteFileFromDisk(fileName: jpgName)
        }
        
        PTNSLogConsole("🗑️ [行程管理] 完美删除行程: \(trip.startTime)，并已释放关联的磁盘空间。")
    }
    
    /// 辅助方法：物理删除 iOS 沙盒中的指定文件
    private func deleteFileFromDisk(fileName: String) {
        let fileManager = FileManager.default
        
        // 获取 Documents 目录
        guard let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = docsDir.appendingPathComponent(fileName)
        
        // 如果文件存在，则物理销毁
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
                PTNSLogConsole("🗑️ [文件清理] 已彻底删除本地缓存文件: \(fileName)")
            } catch {
                PTNSLogConsole("❌ [文件清理] 无法删除本地文件: \(fileName), 错误: \(error.localizedDescription)")
            }
        }
        
        // 🚨 联动清理 iCloud：如果你在 PTiCloudFileManager 中写过 delete 方法，可以在这里顺手调用
        PTiCloudFileManager.shared.deleteCloudFile(fileName: fileName)
    }
}

extension PTTripManager:PTMotionDelegate {
    public func motionManager(_ manager: PTMotion, didUpdateData data: PTMotionData) {
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
}

extension PTTripManager:PTBLEDashboardDelegate {
    func dashboardManager(_ manager: PTBluetoothServerManager, didChangeConnectionState isConnected: Bool) {
        if isConnected {
            handleConnect()
        } else {
            handleDisconnect()
        }
    }
    
    func dashboardManager(_ manager: PTBluetoothServerManager, dashboardData data: Any?) {
        if isRiding, let data1 = data as? PTDashboardData1 {
            if !hasOdometerData && data1.odoKm > 0 {
                startOdo = data1.odoKm
                hasOdometerData = true
            }
            latestOdo = data1.odoKm
            latestConsumption = data1.avgConsumptionLt
        } else if isRiding, let control = data as? PTDashboardControl,!PTMotoTelemetryManager.shared.isConnected{
            let rpm = control.engineRpm
            self.currentLiveRpm = rpm
            if rpm > maxRpm { maxRpm = rpm }
            
            // 🌟 将最高精度的蓝牙车速喂给分析引擎
            processSpeedMetrics(speedKmh: control.vehicleSpeedKmh, timestamp: Date())
        } else if isRiding, let absStatus = data as? PTAbsStatus {
            self.lastFrontSpeed = absStatus.frontWheelSpeedKmh
            calculateSlipRatio()
        }
    }
}

extension PTTripManager:PTMotoTelemetryDelegate {
    public func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateMeasurements measurements: [String: Any]) {
        if let speed = measurements[OBDCommand.mode1(.speed).properties.command] as? Double {
            processSpeedMetrics(speedKmh: speed, timestamp: Date())
        }
        if let rpm = measurements[OBDCommand.mode1(.rpm).properties.command] as? Double {
            self.currentLiveRpm = Int(rpm)
            if Int(rpm) > maxRpm { maxRpm = Int(rpm) }
        }
    }
}
