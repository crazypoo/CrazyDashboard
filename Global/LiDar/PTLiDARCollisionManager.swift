//
//  PTLiDARCollisionManager.swift
//  PTSpeed
//
//  EN: Foreground-only LiDAR assistance with bounded sampling and stable alerts.
//  ES: Asistencia LiDAR solo en primer plano, con muestreo acotado y alertas estables.
//  中文：仅前台运行的 LiDAR 辅助服务，使用有界采样和稳定报警。
//

import ARKit
import AVFoundation
import Foundation
import PooTools
import UIKit

// MARK: - Public models

// EN: The mounted mode is gated by fresh vehicle speed; garage mode is an explicit measuring tool.
// ES: El modo montado exige una velocidad reciente; el modo garaje es una herramienta de medición explícita.
// 中文：安装模式必须有新鲜车速门禁，车库模式是用户主动开启的测距工具。
public enum PTLiDARAssistMode: String, Codable, CaseIterable, Sendable {
    case mountedLowSpeed
    case garageMeasure
}

public enum PTLiDARZone: String, Codable, CaseIterable, Sendable {
    case left
    case center
    case right
}

@available(*, deprecated, renamed: "PTLiDARZone")
public typealias PTBlindSpotZone = PTLiDARZone

public enum PTLiDARDepthConfidence: String, Codable, Sendable {
    case unavailable
    case low
    case medium
    case high
}

public enum PTLiDARAlertLevel: String, Codable, Sendable {
    case none
    case warning
    case critical
}

public enum PTLiDARSpeedSource: String, Codable, CaseIterable, Sendable {
    case dashboard
    case obd
    case gps
}

public enum PTLiDARStandbyReason: String, Codable, Sendable {
    case none
    case speedUnavailable
    case speedStale
    case speedTooHigh
    case speedHysteresis
    case cameraPermission
    case unsupported
    case appBackground
    case systemInterruption
    case failed
}

public enum PTLiDARRunState: String, Codable, Sendable {
    case idle
    case running
    case armed
    case standby
    case interrupted
    case permissionDenied
    case unsupported
    case failed
}

public enum PTLiDARStartResult: Equatable, Sendable {
    case started
    case alreadyRunning
    case waitingForCameraPermission
    case cameraPermissionDenied
    case unsupported
    case failed(String)
}

public struct PTLiDARSpeedSample: Sendable {
    public let speedKmh: Double
    public let source: PTLiDARSpeedSource
    public let timestamp: Date

    public init(speedKmh: Double, source: PTLiDARSpeedSource, timestamp: Date = Date()) {
        self.speedKmh = speedKmh
        self.source = source
        self.timestamp = timestamp
    }
}

// EN: Keep the low-speed gate pure so stale data and hysteresis are testable without ARKit hardware.
// ES: Mantén pura la puerta de baja velocidad para probar datos obsoletos e histéresis sin hardware ARKit.
// 中文：将低速门禁保持为纯值逻辑，便于无 ARKit 硬件测试过期数据和滞回。
struct PTLiDARRidingSpeedGate: Sendable {
    private(set) var isArmed = false

    mutating func reset() {
        isArmed = false
    }

    mutating func update(
        sample: PTLiDARSpeedSample?,
        now: Date,
        entrySpeedKmh: Double,
        maximumSpeedKmh: Double
    ) -> (isArmed: Bool, state: PTLiDARRunState, reason: PTLiDARStandbyReason) {
        guard let sample else {
            isArmed = false
            return (false, .standby, .speedUnavailable)
        }

        let age = now.timeIntervalSince(sample.timestamp)
        let maximumAge: TimeInterval = sample.source == .gps ? 3 : 2
        guard age >= 0, age <= maximumAge else {
            isArmed = false
            return (false, .standby, .speedStale)
        }

        if sample.speedKmh <= entrySpeedKmh {
            isArmed = true
            return (true, .armed, .none)
        }
        if sample.speedKmh > maximumSpeedKmh {
            isArmed = false
            return (false, .standby, .speedTooHigh)
        }
        if isArmed {
            return (true, .armed, .none)
        }
        return (false, .standby, .speedHysteresis)
    }
}

public struct PTLiDARZoneReading: Codable, Equatable, Sendable {
    public let zone: PTLiDARZone
    public let distanceMeters: Float?
    public let confidence: PTLiDARDepthConfidence
    public let coverage: Float
    public let alertLevel: PTLiDARAlertLevel

    public init(
        zone: PTLiDARZone,
        distanceMeters: Float?,
        confidence: PTLiDARDepthConfidence,
        coverage: Float,
        alertLevel: PTLiDARAlertLevel = .none
    ) {
        self.zone = zone
        self.distanceMeters = distanceMeters
        self.confidence = confidence
        self.coverage = coverage
        self.alertLevel = alertLevel
    }
}

public struct PTLiDARProximitySnapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let mode: PTLiDARAssistMode
    public let state: PTLiDARRunState
    public let standbyReason: PTLiDARStandbyReason
    public let speedKmh: Double?
    public let speedSource: PTLiDARSpeedSource?
    public let readings: [PTLiDARZoneReading]

    public init(
        timestamp: Date = Date(),
        mode: PTLiDARAssistMode,
        state: PTLiDARRunState,
        standbyReason: PTLiDARStandbyReason = .none,
        speedKmh: Double? = nil,
        speedSource: PTLiDARSpeedSource? = nil,
        readings: [PTLiDARZoneReading] = []
    ) {
        self.timestamp = timestamp
        self.mode = mode
        self.state = state
        self.standbyReason = standbyReason
        self.speedKmh = speedKmh
        self.speedSource = speedSource
        self.readings = readings
    }

    public func reading(for zone: PTLiDARZone) -> PTLiDARZoneReading? {
        readings.first { $0.zone == zone }
    }
}

public struct PTLiDARMeasurement: Codable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let vehicleID: UUID?
    public let note: String
    public let snapshot: PTLiDARProximitySnapshot

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        vehicleID: UUID? = nil,
        note: String = "",
        snapshot: PTLiDARProximitySnapshot
    ) {
        self.id = id
        self.createdAt = createdAt
        self.vehicleID = vehicleID
        self.note = note
        self.snapshot = snapshot
    }

    public func reading(for zone: PTLiDARZone) -> PTLiDARZoneReading? {
        snapshot.reading(for: zone)
    }
}

// EN: Delegate callbacks are delivered on the main actor because they update UI state.
// ES: Las devoluciones del delegado llegan en el actor principal porque actualizan la interfaz.
// 中文：代理回调在主 actor 上交付，因为它们会更新界面状态。
@MainActor
public protocol PTLiDARCollisionDelegate: AnyObject {
    func lidarManager(_ manager: PTLiDARCollisionManager, didUpdateDistances left: Float, center: Float, right: Float)
    func lidarManager(_ manager: PTLiDARCollisionManager, didTriggerWarningIn zones: [PTLiDARZone])
    func lidarManager(_ manager: PTLiDARCollisionManager, didUpdate snapshot: PTLiDARProximitySnapshot)
    func lidarManager(_ manager: PTLiDARCollisionManager, didChangeState state: PTLiDARRunState, reason: PTLiDARStandbyReason)
}

public extension PTLiDARCollisionDelegate {
    func lidarManager(_ manager: PTLiDARCollisionManager, didUpdateDistances left: Float, center: Float, right: Float) {}
    func lidarManager(_ manager: PTLiDARCollisionManager, didTriggerWarningIn zones: [PTLiDARZone]) {}
    func lidarManager(_ manager: PTLiDARCollisionManager, didUpdate snapshot: PTLiDARProximitySnapshot) {}
    func lidarManager(_ manager: PTLiDARCollisionManager, didChangeState state: PTLiDARRunState, reason: PTLiDARStandbyReason) {}
}

// MARK: - Local measurement store

// EN: Garage measurements stay local and bounded; the existing garage iCloud schema is not changed in this build.
// ES: Las mediciones del garaje son locales y limitadas; el esquema iCloud del garaje no cambia en esta versión.
// 中文：车库测距记录仅本地保存并限制数量，本版本不改变车库 iCloud 数据结构。
@MainActor
public final class PTLiDARMeasurementStore {
    public static let shared = PTLiDARMeasurementStore()
    public static let maximumRecordCount = 100

    private let userDefaults: UserDefaults
    private let storageKey = "PTLiDARMeasurementStore.v1"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var measurements: [PTLiDARMeasurement] {
        guard let data = userDefaults.data(forKey: storageKey),
              let values = try? Self.decoder.decode([PTLiDARMeasurement].self, from: data) else {
            return []
        }
        return Array(values.suffix(Self.maximumRecordCount))
    }

    @discardableResult
    public func save(snapshot: PTLiDARProximitySnapshot, vehicleID: UUID? = nil, note: String = "") -> PTLiDARMeasurement? {
        guard snapshot.readings.contains(where: { $0.distanceMeters != nil }) else { return nil }
        let measurement = PTLiDARMeasurement(vehicleID: vehicleID, note: note.trimmingCharacters(in: .whitespacesAndNewlines), snapshot: snapshot)
        var values = measurements
        values.append(measurement)
        if values.count > Self.maximumRecordCount {
            values.removeFirst(values.count - Self.maximumRecordCount)
        }
        persist(values)
        return measurement
    }

    public func delete(id: UUID) {
        persist(measurements.filter { $0.id != id })
    }

    public func removeAll() {
        userDefaults.removeObject(forKey: storageKey)
    }

    public enum ExportFormat: Sendable {
        case json
        case csv
    }

    public func exportURL(format: ExportFormat) throws -> URL {
        let values = measurements
        let fileExtension: String
        switch format {
        case .json: fileExtension = "json"
        case .csv: fileExtension = "csv"
        }
        let fileName = "PTLiDARMeasurements-\(Self.fileDateFormatter.string(from: Date())).\(fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let data: Data
        switch format {
        case .json:
            data = try Self.encoder.encode(values)
        case .csv:
            data = Self.csvData(values)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private func persist(_ values: [PTLiDARMeasurement]) {
        guard let data = try? Self.encoder.encode(values) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let fileDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter
    }()

    private static func csvData(_ values: [PTLiDARMeasurement]) -> Data {
        var rows = ["id,createdAt,vehicleID,mode,state,standbyReason,speedKmh,speedSource,zone,distanceMeters,confidence,coverage,alertLevel,note"]
        let dateFormatter = fileDateFormatter
        for measurement in values {
            let readings = measurement.snapshot.readings.isEmpty ? [nil] : measurement.snapshot.readings.map(Optional.some)
            for reading in readings {
                let fields: [String] = [
                    measurement.id.uuidString,
                    dateFormatter.string(from: measurement.createdAt),
                    measurement.vehicleID?.uuidString ?? "",
                    measurement.snapshot.mode.rawValue,
                    measurement.snapshot.state.rawValue,
                    measurement.snapshot.standbyReason.rawValue,
                    measurement.snapshot.speedKmh.map { String(format: "%.2f", $0) } ?? "",
                    measurement.snapshot.speedSource?.rawValue ?? "",
                    reading?.zone.rawValue ?? "",
                    reading?.distanceMeters.map { String(format: "%.3f", $0) } ?? "",
                    reading?.confidence.rawValue ?? "",
                    reading.map { String(format: "%.3f", $0.coverage) } ?? "",
                    reading?.alertLevel.rawValue ?? "",
                    measurement.note
                ]
                rows.append(fields.map(csvEscape).joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

// MARK: - Depth analyzer

struct PTLiDARRawZoneReading: Sendable {
    let zone: PTLiDARZone
    let distanceMeters: Float?
    let confidence: PTLiDARDepthConfidence
    let coverage: Float
}

struct PTLiDARRawFrame: Sendable {
    let timestamp: Date
    let readings: [PTLiDARRawZoneReading]
}

// EN: This analyzer locks each pixel buffer once and never retains a camera frame.
// ES: Este analizador bloquea cada buffer una sola vez y nunca conserva un fotograma de cámara.
// 中文：该分析器每个像素缓冲区只加锁一次，且不保存相机帧。
enum PTLiDARDepthAnalyzer {
    private static let minimumDepth: Float = 0.15
    private static let minimumCoverage: Float = 0.35
    private static let minimumConfidence = UInt8(ARConfidenceLevel.medium.rawValue)

    static func analyze(
        depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer?,
        regions: [PTLiDARZone: CGRect]
    ) -> [PTLiDARRawZoneReading] {
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        guard depthWidth > 0, depthHeight > 0,
              CVPixelBufferGetPixelFormatType(depthMap) == kCVPixelFormatType_DepthFloat32 else {
            return []
        }
        guard CVPixelBufferLockBaseAddress(depthMap, .readOnly) == kCVReturnSuccess else { return [] }
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let depthBaseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return [] }

        let confidenceLocked: Bool
        let confidenceBaseAddress: UnsafeMutableRawPointer?
        if let confidenceMap,
           CVPixelBufferLockBaseAddress(confidenceMap, .readOnly) == kCVReturnSuccess {
            confidenceLocked = true
            confidenceBaseAddress = CVPixelBufferGetBaseAddress(confidenceMap)
        } else {
            confidenceLocked = false
            confidenceBaseAddress = nil
        }
        defer {
            if let confidenceMap, confidenceLocked {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
        }

        let depthStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.stride
        guard depthStride >= depthWidth else { return [] }
        let depthPointer = depthBaseAddress.assumingMemoryBound(to: Float32.self)
        let confidenceWidth = confidenceMap.map(CVPixelBufferGetWidth) ?? 0
        let confidenceHeight = confidenceMap.map(CVPixelBufferGetHeight) ?? 0
        let confidenceStride = confidenceMap.map { CVPixelBufferGetBytesPerRow($0) } ?? 0
        let confidencePointer = confidenceBaseAddress?.assumingMemoryBound(to: UInt8.self)

        return PTLiDARZone.allCases.compactMap { zone in
            guard let normalizedRect = regions[zone]?.intersection(CGRect(x: 0, y: 0, width: 1, height: 1)),
                  !normalizedRect.isNull,
                  normalizedRect.width > 0,
                  normalizedRect.height > 0 else {
                return nil
            }

            var distances: [Float] = []
            let gridWidth = 9
            let gridHeight = 5
            let totalSamples = gridWidth * gridHeight
            for row in 0..<gridHeight {
                for column in 0..<gridWidth {
                    let xRatio = (CGFloat(column) + 0.5) / CGFloat(gridWidth)
                    let yRatio = (CGFloat(row) + 0.5) / CGFloat(gridHeight)
                    let normalizedX = normalizedRect.minX + normalizedRect.width * xRatio
                    let normalizedY = normalizedRect.minY + normalizedRect.height * yRatio
                    let x = min(depthWidth - 1, max(0, Int(normalizedX * CGFloat(depthWidth))))
                    let y = min(depthHeight - 1, max(0, Int(normalizedY * CGFloat(depthHeight))))
                    let distance = depthPointer[y * depthStride + x]
                    guard distance.isFinite, distance > minimumDepth else { continue }

                    if let confidencePointer,
                       confidenceWidth > 0,
                       confidenceHeight > 0 {
                        let confidenceX = min(confidenceWidth - 1, max(0, Int(normalizedX * CGFloat(confidenceWidth))))
                        let confidenceY = min(confidenceHeight - 1, max(0, Int(normalizedY * CGFloat(confidenceHeight))))
                        let confidence = confidencePointer[confidenceY * confidenceStride + confidenceX]
                        guard confidence >= minimumConfidence else { continue }
                    }
                    distances.append(distance)
                }
            }

            let coverage = Float(distances.count) / Float(totalSamples)
            guard coverage >= minimumCoverage else {
                return PTLiDARRawZoneReading(zone: zone, distanceMeters: nil, confidence: .unavailable, coverage: coverage)
            }

            distances.sort()
            let percentileIndex = min(distances.count - 1, max(0, Int(Double(distances.count - 1) * 0.15)))
            let distance = distances[percentileIndex]
            let confidence: PTLiDARDepthConfidence
            if confidencePointer == nil {
                confidence = .medium
            } else {
                confidence = .high
            }
            return PTLiDARRawZoneReading(zone: zone, distanceMeters: distance, confidence: confidence, coverage: coverage)
        }
    }
}

// MARK: - ARSession bridge

private enum PTLiDARSessionEvent: Sendable {
    case interrupted
    case interruptionEnded
    case failed
}

// EN: The proxy keeps ARKit objects on its serial processing queue and sends only value types to the main actor.
// ES: El proxy mantiene los objetos de ARKit en su cola serial y solo envía tipos valor al actor principal.
// 中文：代理把 ARKit 对象留在串行处理队列，只向主线程传递值类型结果。
private final class PTLiDARSessionProxy: NSObject, ARSessionDelegate, @unchecked Sendable {
    private let processingQueue = DispatchQueue(label: "com.yd.PTSpeed.lidar.processing", qos: .userInitiated)
    private let resultHandler: @Sendable (PTLiDARRawFrame) -> Void
    private let eventHandler: @Sendable (PTLiDARSessionEvent) -> Void
    private let projectionLock = NSLock()
    private let rateLimitLock = NSLock()
    private var orientation: UIInterfaceOrientation = .portrait
    private var viewportSize: CGSize = .zero
    private var lastFrameTimestamp: TimeInterval = 0

    private let fallbackRegions: [PTLiDARZone: CGRect] = [
        .left: CGRect(x: 0.02, y: 0.28, width: 0.30, height: 0.44),
        .center: CGRect(x: 0.35, y: 0.28, width: 0.30, height: 0.44),
        .right: CGRect(x: 0.68, y: 0.28, width: 0.30, height: 0.44)
    ]

    init(
        resultHandler: @escaping @Sendable (PTLiDARRawFrame) -> Void,
        eventHandler: @escaping @Sendable (PTLiDARSessionEvent) -> Void
    ) {
        self.resultHandler = resultHandler
        self.eventHandler = eventHandler
        super.init()
    }

    func updateProjection(orientation: UIInterfaceOrientation, viewportSize: CGSize) {
        projectionLock.lock()
        self.orientation = orientation
        self.viewportSize = viewportSize
        projectionLock.unlock()
    }

    func reset() {
        projectionLock.lock()
        orientation = .portrait
        viewportSize = .zero
        projectionLock.unlock()
        rateLimitLock.lock()
        lastFrameTimestamp = 0
        rateLimitLock.unlock()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard shouldProcess(frameTimestamp: frame.timestamp) else { return }
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }
        let projection = currentProjection()
        let readings = PTLiDARDepthAnalyzer.analyze(
            depthMap: depthData.depthMap,
            confidenceMap: depthData.confidenceMap,
            regions: makeRegions(frame: frame, orientation: projection.orientation, viewportSize: projection.viewportSize)
        )
        guard !readings.isEmpty else { return }
        let rawFrame = PTLiDARRawFrame(timestamp: Date(), readings: readings)
        processingQueue.async { [resultHandler] in
            resultHandler(rawFrame)
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        processingQueue.async { [eventHandler] in eventHandler(.interrupted) }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        processingQueue.async { [eventHandler] in eventHandler(.interruptionEnded) }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        PTNSLogConsole("❌ [LiDAR] ARSession 失败: \(error.localizedDescription)")
        processingQueue.async { [eventHandler] in eventHandler(.failed) }
    }

    private func currentProjection() -> (orientation: UIInterfaceOrientation, viewportSize: CGSize) {
        projectionLock.lock()
        defer { projectionLock.unlock() }
        return (orientation, viewportSize)
    }

    private func shouldProcess(frameTimestamp: TimeInterval) -> Bool {
        rateLimitLock.lock()
        defer { rateLimitLock.unlock() }
        guard lastFrameTimestamp == 0 || frameTimestamp < lastFrameTimestamp || frameTimestamp - lastFrameTimestamp >= 0.1 else {
            return false
        }
        lastFrameTimestamp = frameTimestamp
        return true
    }

    private func makeRegions(frame: ARFrame, orientation: UIInterfaceOrientation, viewportSize: CGSize) -> [PTLiDARZone: CGRect] {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return fallbackRegions }
        let inverse = frame.displayTransform(for: orientation, viewportSize: viewportSize).inverted()
        return fallbackRegions.mapValues { $0.applying(inverse).intersection(CGRect(x: 0, y: 0, width: 1, height: 1)) }
    }
}

// MARK: - Coordinator

// EN: This coordinator owns gating, smoothing, alert dwell time, and lifecycle; it does not own BLE or OBD transport.
// ES: Este coordinador posee las puertas, el suavizado, la permanencia de alertas y el ciclo de vida; no posee el transporte BLE/OBD.
// 中文：该协调器负责门禁、平滑、报警驻留和生命周期，不拥有 BLE/OBD 传输层。
@MainActor
public final class PTLiDARCollisionManager: NSObject {
    public static let shared = PTLiDARCollisionManager()

    public weak var delegate: PTLiDARCollisionDelegate?
    public let arSession: ARSession
    public private(set) var isRunning = false
    public private(set) var currentMode: PTLiDARAssistMode = .mountedLowSpeed
    public private(set) var state: PTLiDARRunState = .idle
    public private(set) var standbyReason: PTLiDARStandbyReason = .none
    public private(set) var latestSnapshot: PTLiDARProximitySnapshot?

    public var warningThreshold: Float = 1.8
    public var criticalThreshold: Float = 0.9
    public var maximumMountedSpeedKmh: Double = 10
    public var mountedEntrySpeedKmh: Double = 8

    private lazy var sessionProxy: PTLiDARSessionProxy = {
        PTLiDARSessionProxy(
            resultHandler: { [weak self] frame in
                Task { @MainActor [weak self] in
                    self?.consume(frame)
                }
            },
            eventHandler: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handle(event)
                }
            }
        )
    }()
    private var speedSamples: [PTLiDARSpeedSource: PTLiDARSpeedSample] = [:]
    private var distanceHistory: [PTLiDARZone: [Float?]] = [:]
    private var stableLevels: [PTLiDARZone: PTLiDARAlertLevel] = [:]
    private var pendingLevels: [PTLiDARZone: PTLiDARAlertLevel] = [:]
    private var pendingSince: [PTLiDARZone: Date] = [:]
    private var speedGate = PTLiDARRidingSpeedGate()
    private var backgroundObserver: NSObjectProtocol?

    private override init() {
        self.arSession = ARSession()
        super.init()
        arSession.delegate = sessionProxy
        arSession.delegateQueue = DispatchQueue(label: "com.yd.PTSpeed.lidar.delegate", qos: .userInitiated)
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pauseForBackground() }
        }
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    public func updateProjection(orientation: UIInterfaceOrientation, viewportSize: CGSize) {
        sessionProxy.updateProjection(orientation: orientation, viewportSize: viewportSize)
    }

    public func updateSpeedSample(_ sample: PTLiDARSpeedSample) {
        guard sample.speedKmh.isFinite, sample.speedKmh >= 0, sample.speedKmh <= 400 else { return }
        speedSamples[sample.source] = sample
        guard isRunning, currentMode == .mountedLowSpeed else { return }
        updateMountedGate(now: Date())
    }

    @discardableResult
    public func start(mode: PTLiDARAssistMode = .mountedLowSpeed) -> PTLiDARStartResult {
        guard !isRunning else { return .alreadyRunning }
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
                || ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) else {
            setState(.unsupported, reason: .unsupported)
            return .unsupported
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            runSession(mode: mode)
            return .started
        case .notDetermined:
            setState(.standby, reason: .cameraPermission)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard granted else {
                        self.setState(.permissionDenied, reason: .cameraPermission)
                        return
                    }
                    self.runSession(mode: mode)
                }
            }
            return .waitingForCameraPermission
        default:
            setState(.permissionDenied, reason: .cameraPermission)
            return .cameraPermissionDenied
        }
    }

    // EN: Compatibility facade for the original prototype API.
    // ES: Fachada de compatibilidad para la API del prototipo original.
    // 中文：兼容原始原型 API 的外观方法。
    public func startScanning() {
        _ = start(mode: .mountedLowSpeed)
    }

    public func stop() {
        guard isRunning || state != .idle else { return }
        arSession.pause()
        isRunning = false
        releaseLocationLease()
        clearRuntimeState()
        setState(.idle, reason: .none)
        PTNSLogConsole("🔴 [LiDAR] 已关闭")
    }

    public func stopScanning() {
        stop()
    }

    public func resumeAfterSystemInterruption() {
        guard !isRunning, state == .interrupted else { return }
        _ = start(mode: currentMode)
    }

    private func runSession(mode: PTLiDARAssistMode) {
        currentMode = mode
        clearRuntimeState()
        var configuration = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics = .smoothedSceneDepth
        } else {
            configuration.frameSemantics = .sceneDepth
        }
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
        if mode == .mountedLowSpeed {
            PTLocationUsageCoordinator.shared.acquire(.lidar)
            updateMountedGate(now: Date())
        } else {
            setState(.running, reason: .none)
        }
        PTNSLogConsole("🟢 [LiDAR] \(mode.rawValue) 已启动")
    }

    private func consume(_ frame: PTLiDARRawFrame) {
        guard isRunning else { return }
        let speed = selectedFreshSpeed(at: frame.timestamp)
        if currentMode == .mountedLowSpeed {
            updateMountedGate(now: frame.timestamp)
            guard speedGate.isArmed else {
                publishSnapshot(timestamp: frame.timestamp, state: state, reason: standbyReason, speed: speed, readings: [])
                return
            }
        }

        let previousLevels = stableLevels
        let smoothedReadings = frame.readings.map { raw -> PTLiDARZoneReading in
            var history = distanceHistory[raw.zone, default: []]
            history.append(raw.distanceMeters)
            if history.count > 5 { history.removeFirst(history.count - 5) }
            distanceHistory[raw.zone] = history
            let validValues = history.compactMap { $0 }.sorted()
            let distance = validValues.isEmpty ? nil : validValues[validValues.count / 2]
            let level = stableLevel(for: raw.zone, distance: distance, timestamp: frame.timestamp)
            return PTLiDARZoneReading(
                zone: raw.zone,
                distanceMeters: distance,
                confidence: raw.confidence,
                coverage: raw.coverage,
                alertLevel: level
            )
        }
        publishSnapshot(timestamp: frame.timestamp, state: currentMode == .mountedLowSpeed ? .armed : .running, reason: .none, speed: speed, readings: smoothedReadings)

        let warningZones = smoothedReadings
            .filter { $0.alertLevel != .none && previousLevels[$0.zone] != $0.alertLevel }
            .map(\.zone)
        if !warningZones.isEmpty {
            delegate?.lidarManager(self, didTriggerWarningIn: warningZones)
        }
    }

    private func stableLevel(for zone: PTLiDARZone, distance: Float?, timestamp: Date) -> PTLiDARAlertLevel {
        let current = stableLevels[zone, default: .none]
        let desired: PTLiDARAlertLevel
        if let distance {
            if current != .none, distance <= warningThreshold + 0.25 {
                desired = distance <= criticalThreshold ? .critical : .warning
            } else if distance <= criticalThreshold {
                desired = .critical
            } else if distance <= warningThreshold {
                desired = .warning
            } else {
                desired = .none
            }
        } else {
            desired = .none
        }
        guard desired != current else {
            pendingLevels.removeValue(forKey: zone)
            pendingSince.removeValue(forKey: zone)
            return current
        }

        if pendingLevels[zone] != desired {
            pendingLevels[zone] = desired
            pendingSince[zone] = timestamp
            return current
        }
        let dwell: TimeInterval
        switch desired {
        case .critical: dwell = 0.3
        case .warning: dwell = 0.5
        case .none: dwell = 0.8
        }
        guard let since = pendingSince[zone], timestamp.timeIntervalSince(since) >= dwell else { return current }
        stableLevels[zone] = desired
        pendingLevels.removeValue(forKey: zone)
        pendingSince.removeValue(forKey: zone)
        return desired
    }

    private func updateMountedGate(now: Date) {
        let result = speedGate.update(
            sample: selectedFreshSpeed(at: now),
            now: now,
            entrySpeedKmh: mountedEntrySpeedKmh,
            maximumSpeedKmh: maximumMountedSpeedKmh
        )
        setState(result.state, reason: result.reason)
    }

    private func selectedFreshSpeed(at date: Date) -> PTLiDARSpeedSample? {
        for source in [PTLiDARSpeedSource.dashboard, .obd, .gps] {
            guard let sample = speedSamples[source] else { continue }
            let age = date.timeIntervalSince(sample.timestamp)
            let maximumAge: TimeInterval = source == .gps ? 3 : 2
            if age >= 0, age <= maximumAge { return sample }
        }
        return nil
    }

    private func publishSnapshot(
        timestamp: Date,
        state: PTLiDARRunState,
        reason: PTLiDARStandbyReason,
        speed: PTLiDARSpeedSample?,
        readings: [PTLiDARZoneReading]
    ) {
        let snapshot = PTLiDARProximitySnapshot(
            timestamp: timestamp,
            mode: currentMode,
            state: state,
            standbyReason: reason,
            speedKmh: speed?.speedKmh,
            speedSource: speed?.source,
            readings: readings
        )
        latestSnapshot = snapshot
        delegate?.lidarManager(self, didUpdate: snapshot)
        let values = Dictionary(uniqueKeysWithValues: readings.map { ($0.zone, $0.distanceMeters ?? 0) })
        delegate?.lidarManager(
            self,
            didUpdateDistances: values[.left] ?? 0,
            center: values[.center] ?? 0,
            right: values[.right] ?? 0
        )
    }

    private func handle(_ event: PTLiDARSessionEvent) {
        guard isRunning || event == .interrupted else { return }
        switch event {
        case .interrupted:
            arSession.pause()
            isRunning = false
            releaseLocationLease()
            setState(.interrupted, reason: .systemInterruption)
        case .interruptionEnded:
            guard state == .interrupted else { return }
            setState(.interrupted, reason: .systemInterruption)
        case .failed:
            arSession.pause()
            isRunning = false
            releaseLocationLease()
            setState(.failed, reason: .failed)
        }
    }

    private func pauseForBackground() {
        guard isRunning else { return }
        arSession.pause()
        isRunning = false
        releaseLocationLease()
        setState(.interrupted, reason: .appBackground)
    }

    private func releaseLocationLease() {
        guard currentMode == .mountedLowSpeed else { return }
        PTLocationUsageCoordinator.shared.release(.lidar)
    }

    private func clearRuntimeState() {
        distanceHistory.removeAll()
        stableLevels.removeAll()
        pendingLevels.removeAll()
        pendingSince.removeAll()
        speedSamples.removeAll()
        speedGate.reset()
        sessionProxy.reset()
    }

    private func setState(_ state: PTLiDARRunState, reason: PTLiDARStandbyReason) {
        let changed = self.state != state || standbyReason != reason
        self.state = state
        self.standbyReason = reason
        guard changed else { return }
        delegate?.lidarManager(self, didChangeState: state, reason: reason)
    }
}
