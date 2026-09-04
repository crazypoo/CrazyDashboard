//
//  PTTripManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 23/7/2026.
//

import Foundation
import PooTools
import CoreLocation

public struct PTTripOffRoadEvent: Codable, Sendable {
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

public struct PTRoutePoint: Codable, Sendable {
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
public struct PTTripReport: Codable, Sendable {
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

private nonisolated struct PTTripHistoryDocument: Codable, Sendable {
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
public let MotorcycleTripHistoryLoaded = NSNotification.Name("MotorcycleTripHistoryLoaded")
public let PTRideBlackBoxUpdated = NSNotification.Name("PTRideBlackBoxUpdated")

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
    public private(set) var lastPersistenceError: String?
    
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
    private var manualBlackBoxEvents: [PTRideBlackBoxEvent] = []
    private var lastBlackBoxCheckpointAt: Date?
    private var blackBoxCheckpointTask: Task<Void, Never>?
    private var blackBoxRecoveryTask: Task<Void, Never>?

    private var historyWriteRevision: Int64 = 0
    private var historyLoadTask: Task<Void, Never>?
    private var historyHasLoaded = false
    private var historyMutationPendingBeforeLoad = false
    private var historyWasClearedBeforeLoad = false
    private var historyDeletedStartTimesBeforeLoad = Set<Date>()

    private override init() {
        super.init()
        loadHistory()
        setupObservers()
        recoverBlackBoxJournal()
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
    private enum HistoryLoadResult: Sendable {
        case loaded([PTTripReport])
        case empty
        case corrupt(String)
        case failed(String)
    }

    /// EN: Decode history off the main thread and keep legacy array files readable.
    /// ES: Decodifica el historial fuera del hilo principal y conserva la lectura de archivos heredados en forma de array.
    /// 中文：在后台解码历史记录，并继续兼容旧版数组格式文件。
    nonisolated private static func decodeHistory(_ data: Data) throws -> [PTTripReport] {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "INF",
            negativeInfinity: "-INF",
            nan: "NaN"
        )

        if let document = try? decoder.decode(PTTripHistoryDocument.self, from: data) {
            return document.trips
        }
        return try decoder.decode([PTTripReport].self, from: data)
    }

    /// EN: Loading is asynchronous so first launch never performs large disk or cloud I/O on the UI thread.
    /// ES: La carga es asíncrona para que el primer lanzamiento nunca haga I/O grande de disco o nube en la UI.
    /// 中文：异步加载，确保首次启动不会在 UI 线程执行大文件或云端 I/O。
    private func loadHistory() {
        let fileName = historyFileName
        let loadTask = Task.detached(priority: .utility) {
            do {
                let data = try await PTDataPersistenceActor.shared.readData(
                    fileName: fileName,
                    restoreFromICloud: true,
                    downloadTimeout: 8
                )
                do {
                    return HistoryLoadResult.loaded(try Self.decodeHistory(data))
                } catch {
                    _ = try? await PTDataPersistenceActor.shared.preserveCorruptData(
                        data,
                        fileName: fileName
                    )
                    return HistoryLoadResult.corrupt(error.localizedDescription)
                }
            } catch let error as PTDataPersistenceError {
                switch error {
                case .fileNotFound, .iCloudUnavailable:
                    return HistoryLoadResult.empty
                default:
                    return HistoryLoadResult.failed(error.localizedDescription)
                }
            } catch {
                return HistoryLoadResult.failed(error.localizedDescription)
            }
        }

        historyLoadTask = Task { [weak self] in
            let result = await loadTask.value
            await MainActor.run { [weak self] in
                self?.applyHistoryLoadResult(result)
            }
        }
    }

    private func applyHistoryLoadResult(_ result: HistoryLoadResult) {
        switch result {
        case .loaded(let savedTrips):
            if historyMutationPendingBeforeLoad {
                var mergedTrips = historyWasClearedBeforeLoad ? [] : tripHistory
                let existingStartTimes = Set(mergedTrips.map(\.startTime))
                if !historyWasClearedBeforeLoad {
                    let pendingDeletes = historyDeletedStartTimesBeforeLoad
                    for savedTrip in savedTrips where
                        !pendingDeletes.contains(savedTrip.startTime) &&
                        !existingStartTimes.contains(savedTrip.startTime) {
                        mergedTrips.append(savedTrip)
                    }
                }
                tripHistory = mergedTrips.sorted { $0.startTime > $1.startTime }
                lastPersistenceError = nil
                historyHasLoaded = true
                resetPendingHistoryMutations()
                saveHistory()
                PTNSLogConsole("✅ [行程记录] 已合并加载结果，当前历史总数: \(tripHistory.count)")
            } else {
                tripHistory = savedTrips
                historyHasLoaded = true
                lastPersistenceError = nil
                PTNSLogConsole("✅ [行程记录] 成功加载 \(savedTrips.count) 条历史记录")
            }
        case .empty:
            historyHasLoaded = true
            lastPersistenceError = nil
            PTNSLogConsole("ℹ️ [行程记录] 本地与云端均无数据，初始化为空列表")
        case .corrupt(let message):
            historyHasLoaded = true
            lastPersistenceError = "历史数据损坏：\(message)"
            PTNSLogConsole("❌ [行程记录] 历史数据解析失败，已保留原文件: \(message)")
        case .failed(let message):
            historyHasLoaded = true
            lastPersistenceError = message
            PTNSLogConsole("❌ [行程记录] 历史数据加载失败: \(message)")
        }
        NotificationCenter.default.post(name: MotorcycleTripHistoryLoaded, object: self)
    }

    /// EN: Keep user mutations made before the asynchronous load finishes.
    /// ES: Conserva las mutaciones del usuario realizadas antes de terminar la carga asíncrona.
    /// 中文：保留异步加载完成前用户已经做出的修改。
    private func markHistoryMutation() {
        guard !historyHasLoaded else { return }
        historyMutationPendingBeforeLoad = true
    }

    /// EN: Clear the temporary merge markers after applying a loaded snapshot.
    /// ES: Limpia los marcadores temporales después de aplicar una instantánea cargada.
    /// 中文：应用加载快照后清理临时合并标记。
    private func resetPendingHistoryMutations() {
        historyMutationPendingBeforeLoad = false
        historyWasClearedBeforeLoad = false
        historyDeletedStartTimesBeforeLoad.removeAll()
    }

    /// EN: Encode and persist a snapshot in a utility task; the actor serializes writes and rejects stale snapshots.
    /// ES: Codifica y guarda una instantánea en una tarea de utilidad; el actor serializa las escrituras y rechaza instantáneas obsoletas.
    /// 中文：在后台任务编码并保存快照，由 actor 串行写入并拒绝过期快照。
    private func saveHistory() {
        markHistoryMutation()
        historyWriteRevision &+= 1
        let revision = historyWriteRevision
        let trips = tripHistory
        let count = trips.count
        let fileName = historyFileName

        Task.detached(priority: .utility) {
            do {
                let encoder = JSONEncoder()
                encoder.nonConformingFloatEncodingStrategy = .convertToString(
                    positiveInfinity: "INF",
                    negativeInfinity: "-INF",
                    nan: "NaN"
                )
                let data = try encoder.encode(PTTripHistoryDocument(schemaVersion: 2, trips: trips))
                let result = try await PTDataPersistenceActor.shared.writeData(
                    data,
                    fileName: fileName,
                    revision: revision,
                    syncToICloud: true
                )

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if let cloudErrorDescription = result.cloudErrorDescription {
                        self.lastPersistenceError = cloudErrorDescription
                        PTNSLogConsole("⚠️ [行程记录] 本地已保存，但 iCloud 同步失败: \(cloudErrorDescription)")
                    } else if !result.didSkipStaleWrite {
                        self.lastPersistenceError = nil
                        PTNSLogConsole("💾 [行程记录] 已原子保存，当前历史总数: \(count)")
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.lastPersistenceError = error.localizedDescription
                    PTNSLogConsole("❌ [行程记录] 数据编码或本地保存失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// 提供给外部：清空所有历史记录 (可绑定到 UI 上的"清空记录"按钮)
    public func clearAllTrips() {
        markHistoryMutation()
        if !historyHasLoaded {
            historyWasClearedBeforeLoad = true
            historyDeletedStartTimesBeforeLoad.removeAll()
        }
        tripHistory.removeAll()
        saveHistory()
        Task {
            try? await PTRideBlackBoxStore.shared.deleteAll()
            await MainActor.run {
                NotificationCenter.default.post(name: PTRideBlackBoxUpdated, object: nil)
            }
        }
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
        manualBlackBoxEvents.removeAll()
        lastBlackBoxCheckpointAt = nil
        blackBoxCheckpointTask = nil

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
        checkpointBlackBoxIfNeeded()
    }
        
    @objc public func handleDisconnect() {
        guard isRiding, let start = startTime else { return }
        checkpointBlackBoxIfNeeded(force: true)
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
            let checkpointTask = blackBoxCheckpointTask
            Task {
                _ = await checkpointTask?.value
                try? await PTRideBlackBoxStore.shared.clearJournal()
            }
            // 记得把定位切回防盗模式
            PTLocationEngine.shared.switchEngineMode(to: .antiTheft)
            return
        }
        
        let reviewEvents = PTRideReviewAnalyzer.analyze(points: routeArray)
        let offRoadEventsForBlackBox = offRoadEventsArray
        let manualEventsForBlackBox = manualBlackBoxEvents
        let generatedFileName = routeArray.isEmpty ? nil : PTGPXRecorder.shared.makeGPXFileName()
        let routePointsForExport = routeArray
        let coordinatesForSnapshot = routeArray.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
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
        
        if let fileName = generatedFileName {
            // EN: Persist GPX off the main thread before asking the map SDK to render its snapshot.
            // ES: Guarda el GPX fuera del hilo principal antes de pedir al SDK del mapa la instantánea.
            // 中文：先在后台完成 GPX 持久化，再请求地图 SDK 生成缩略图。
            Task { [routePointsForExport, coordinatesForSnapshot, reviewEvents] in
                do {
                    _ = try await PTGPXRecorder.shared.exportGPXAsync(
                        from: routePointsForExport,
                        fileName: fileName
                    )
                    await MainActor.run {
                        PTRouteSnapshotManager.shared.generateAndSaveSnapshot(
                            coordinates: coordinatesForSnapshot,
                            gpxFileName: fileName,
                            reviewEvents: reviewEvents
                        )
                    }
                } catch {
                    PTNSLogConsole("❌ [行程报告] GPX 保存失败 [\(fileName)]: \(error.localizedDescription)")
                }
            }
        }

        // EN: Persist local event clips after the ride report is built; no telemetry transport is added.
        // ES: Guarda clips locales después de crear el informe; no se añade ningún transporte de telemetría.
        // 中文：行程报告生成后保存本地事件片段，不新增任何遥测传输层。
        let blackBoxPoints = routePointsForExport
        let blackBoxBuildTask = Task.detached(priority: .utility) {
            PTRideBlackBoxBuilder.makeClips(
                rideStartTime: start,
                reviewEvents: reviewEvents,
                offRoadEvents: offRoadEventsForBlackBox,
                manualEvents: manualEventsForBlackBox,
                points: blackBoxPoints
            )
        }
        let checkpointTask = blackBoxCheckpointTask
        Task {
            let clips = await blackBoxBuildTask.value
            do {
                _ = await checkpointTask?.value
                if !clips.isEmpty {
                    _ = try await PTRideBlackBoxStore.shared.append(clips)
                    await MainActor.run {
                        NotificationCenter.default.post(name: PTRideBlackBoxUpdated, object: clips)
                    }
                }
                try await PTRideBlackBoxStore.shared.clearJournal()
            } catch {
                PTNSLogConsole("❌ [Moto Black Box] 本地事件片段保存失败: \(error.localizedDescription)")
            }
        }

        PTNSLogConsole("🏁 [行程报告生成] 已提交持久化，当前共保存 \(tripHistory.count) 条记录。")
    }

    public var isRecordingRide: Bool {
        isRiding
    }

    /// EN: Add a manual marker to the current ride without changing the vehicle command path.
    /// ES: Añade una marca manual a la ruta actual sin cambiar el canal de comandos del vehículo.
    /// 中文：为当前行程添加手动标记，不改变车辆指令链路。
    @discardableResult
    public func markCurrentRideEvent(title: String = "手动事件") -> Bool {
        guard isRiding,
              let timestamp = routeArray.last?.timestamp ?? lastGpsLocation?.timestamp else {
            return false
        }

        let coordinate = routeArray.last.map {
            PTRideCoordinate(latitude: $0.lat, longitude: $0.lon)
        } ?? lastGpsLocation.map {
            PTRideCoordinate(
                latitude: $0.coordinate.latitude,
                longitude: $0.coordinate.longitude
            )
        }
        guard let coordinate, coordinate.isValid else { return false }

        let event = PTRideBlackBoxEvent(
            rideStartTime: startTime ?? timestamp,
            timestamp: timestamp,
            source: .manual,
            title: title.isEmpty ? "手动事件" : title,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            peakValue: 0,
            speedKmh: currentLiveSpeed,
            severity: 1
        )
        manualBlackBoxEvents.append(event)
        checkpointBlackBoxIfNeeded(force: true)
        PTNSLogConsole("📍 [Moto Black Box] 已加入手动事件标记")
        return true
    }

    // EN: Checkpoint only the bounded active-ride window; this is best-effort and never blocks telemetry.
    // ES: Solo guarda un punto de control de la ventana limitada; es un esfuerzo opcional y nunca bloquea la telemetría.
    // 中文：只检查点保存活动行程的有界窗口，失败可接受且不会阻塞遥测。
    private func checkpointBlackBoxIfNeeded(force: Bool = false) {
        guard let rideStartTime = startTime else { return }
        let now = Date()
        if !force,
           let lastBlackBoxCheckpointAt,
           now.timeIntervalSince(lastBlackBoxCheckpointAt) < 10 {
            return
        }
        lastBlackBoxCheckpointAt = now
        let points = Array(routeArray.suffix(PTRideBlackBoxStore.maximumJournalPointCount))
        let events = Array(manualBlackBoxEvents.suffix(PTRideBlackBoxStore.maximumJournalEventCount))
        let checkpointTask = Task.detached(priority: .utility) {
            do {
                try await PTRideBlackBoxStore.shared.checkpoint(
                    rideStartTime: rideStartTime,
                    points: points,
                    manualEvents: events,
                    checkpointAt: now
                )
            } catch {
                PTNSLogConsole("⚠️ [Moto Black Box] 活动行程检查点保存失败: \(error.localizedDescription)")
            }
        }
        blackBoxCheckpointTask = checkpointTask
    }

    // EN: Recover an interrupted ride journal before the next ride can overwrite its bounded checkpoint.
    // ES: Recupera el diario de un viaje interrumpido antes de que el siguiente viaje sobrescriba su punto de control limitado.
    // 中文：在下一次行程覆盖有界检查点前，先恢复被中断行程的日志。
    private func recoverBlackBoxJournal() {
        blackBoxRecoveryTask = Task { [weak self] in
            do {
                guard let journal = try await PTRideBlackBoxStore.shared.recoverJournal() else { return }
                let reviewEvents = PTRideReviewAnalyzer.analyze(points: journal.points)
                let clips = PTRideBlackBoxBuilder.makeClips(
                    rideStartTime: journal.rideStartTime,
                    reviewEvents: reviewEvents,
                    offRoadEvents: [],
                    manualEvents: journal.manualEvents,
                    points: journal.points,
                    createdAt: journal.checkpointAt,
                    origin: .recovered
                )
                if !clips.isEmpty {
                    _ = try await PTRideBlackBoxStore.shared.append(clips)
                    await MainActor.run {
                        NotificationCenter.default.post(name: PTRideBlackBoxUpdated, object: clips)
                    }
                }
                try await PTRideBlackBoxStore.shared.clearJournal()
                PTNSLogConsole("✅ [Moto Black Box] 已恢复中断行程检查点，片段数: \(clips.count)")
            } catch {
                PTNSLogConsole("⚠️ [Moto Black Box] 中断行程检查点恢复失败: \(error.localizedDescription)")
            }
            self?.blackBoxRecoveryTask = nil
        }
    }
    
    deinit {
        blackBoxRecoveryTask?.cancel()
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
        markHistoryMutation()
        if !historyHasLoaded {
            historyDeletedStartTimesBeforeLoad.insert(trip.startTime)
        }
        tripHistory.removeAll { $0.startTime == trip.startTime }
        
        // 2. 重新写入历史记录的 JSON 文件，并触发 iCloud 同步
        saveHistory()
        
        // 3. 深度清理：销毁与之关联的 GPX 轨迹文件和 JPG 缩略图文件
        if let gpxName = trip.gpxFileName {
            let jpgName = gpxName.replacingOccurrences(of: ".gpx", with: ".jpg")
            deleteFileFromDisk(fileName: gpxName)
            deleteFileFromDisk(fileName: jpgName)
        }

        Task {
            do {
                let deletedCount = try await PTRideBlackBoxStore.shared.deleteClips(
                    forRideStartTime: trip.startTime
                )
                if deletedCount > 0 {
                    await MainActor.run {
                        NotificationCenter.default.post(name: PTRideBlackBoxUpdated, object: nil)
                    }
                }
            } catch {
                PTNSLogConsole("⚠️ [Moto Black Box] 关联事件片段清理失败: \(error.localizedDescription)")
            }
        }

        PTNSLogConsole("🗑️ [行程管理] 完美删除行程: \(trip.startTime)，并已释放关联的磁盘空间。")
    }
    
    /// 辅助方法：物理删除 iOS 沙盒中的指定文件
    private func deleteFileFromDisk(fileName: String) {
        // EN: Delete local and cloud copies through the same serialized persistence boundary.
        // ES: Elimina las copias local y de nube mediante el mismo límite de persistencia serializado.
        // 中文：通过同一个串行持久化边界删除本地和云端副本。
        Task {
            do {
                let result = try await PTDataPersistenceActor.shared.delete(
                    fileName: fileName,
                    deleteFromICloud: true
                )
                if result.didDeleteLocal {
                    PTNSLogConsole("🗑️ [文件清理] 已删除本地缓存文件: \(fileName)")
                }
                if let cloudErrorDescription = result.cloudErrorDescription {
                    PTNSLogConsole("⚠️ [文件清理] 本地已处理，但 iCloud 删除失败 [\(fileName)]: \(cloudErrorDescription)")
                } else if result.didDeleteCloud {
                    PTNSLogConsole("☁️🗑️ [文件清理] 已删除 iCloud 文件: \(fileName)")
                }
            } catch {
                PTNSLogConsole("❌ [文件清理] 删除失败 [\(fileName)]: \(error.localizedDescription)")
            }
        }
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
            // EN: Ignore unavailable dashboard metrics so a sentinel cannot alter trip statistics.
            // ES: Ignora las métricas no disponibles para que un centinela no altere las estadísticas.
            // 中文：忽略不可用仪表指标，避免哨兵值改变骑行统计。
            if data1.odometerAvailability.isAvailable, !hasOdometerData, data1.odoKm > 0 {
                startOdo = data1.odoKm
                hasOdometerData = true
            }
            if data1.odometerAvailability.isAvailable {
                latestOdo = data1.odoKm
            }
            if data1.averageConsumptionAvailability.isAvailable {
                latestConsumption = data1.avgConsumptionLt
            }
        } else if isRiding, let control = data as? PTDashboardControl,!PTMotoTelemetryManager.shared.isConnected{
            if control.engineRpmAvailability.isAvailable {
                let rpm = control.engineRpm
                self.currentLiveRpm = rpm
                if rpm > maxRpm { maxRpm = rpm }
            }

            // EN: Feed only an available BLE speed into ride metrics.
            // ES: Alimenta las métricas solo con una velocidad BLE disponible.
            // 中文：只有 BLE 车速有效时，才写入骑行分析。
            if control.vehicleSpeedAvailability.isAvailable {
                processSpeedMetrics(speedKmh: control.vehicleSpeedKmh, timestamp: Date())
            }
        } else if isRiding, let absStatus = data as? PTAbsStatus {
            if absStatus.frontWheelSpeedAvailability.isAvailable {
                self.lastFrontSpeed = absStatus.frontWheelSpeedKmh
                calculateSlipRatio()
            }
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
