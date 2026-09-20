//
//  PTRoadSurfaceIntelligence.swift
//  CrazyDashboard
//
//  EN: Build 79 turns existing GPS and motion samples into a bounded, read-only road-surface timeline.
//  ES: Build 79 convierte muestras GPS y de movimiento existentes en una línea temporal acotada y de solo lectura.
//  中文：Build 79 将现有 GPS 与运动传感器样本转换为有界的只读道路体验时间线。
//

import CoreLocation
import Foundation
import PooTools

public nonisolated enum PTRoadSurfaceQuality: String, Codable, CaseIterable, Equatable, Sendable {
    case smooth
    case moderate
    case rough
    case severe
    case unknown
}

public nonisolated enum PTRoadSurfaceEventKind: String, Codable, CaseIterable, Equatable, Sendable {
    case smooth
    case roughRoad
    case potholeCandidate
    case speedBump
    case repeatedVibration
    case strongImpact
}

// EN: Calibration is local and read-only; it corrects sensor bias without changing vehicle transport.
// ES: La calibración es local y de solo lectura; corrige el sesgo del sensor sin cambiar el transporte del vehículo.
// 中文：校准只保存在本地并且只读，不会改变任何车辆传输逻辑，只修正传感器偏置。
public nonisolated struct PTRoadSurfaceCalibration: Codable, Equatable, Sendable {
    public let verticalBiasG: Double
    public let lateralBiasG: Double
    public let longitudinalBiasG: Double
    public let leanBiasDegrees: Double
    public let updatedAt: Date

    public init(
        verticalBiasG: Double = 0,
        lateralBiasG: Double = 0,
        longitudinalBiasG: Double = 0,
        leanBiasDegrees: Double = 0,
        updatedAt: Date = Date()
    ) {
        self.verticalBiasG = Self.bounded(verticalBiasG, lower: -2, upper: 2)
        self.lateralBiasG = Self.bounded(lateralBiasG, lower: -2, upper: 2)
        self.longitudinalBiasG = Self.bounded(longitudinalBiasG, lower: -2, upper: 2)
        self.leanBiasDegrees = Self.bounded(leanBiasDegrees, lower: -45, upper: 45)
        self.updatedAt = updatedAt
    }

    public static let standard = PTRoadSurfaceCalibration()

    public func corrected(
        verticalG: Double,
        lateralG: Double,
        longitudinalG: Double,
        leanDegrees: Double
    ) -> (verticalG: Double, lateralG: Double, longitudinalG: Double, leanDegrees: Double) {
        (
            verticalG - verticalBiasG,
            lateralG - lateralBiasG,
            longitudinalG - longitudinalBiasG,
            leanDegrees - leanBiasDegrees
        )
    }

    private static func bounded(_ value: Double, lower: Double, upper: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, lower), upper)
    }
}

public nonisolated struct PTRoadSurfaceSample: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let vehicleID: UUID
    public let capturedAt: Date
    public let latitude: Double
    public let longitude: Double
    public let speedKmh: Double
    public let verticalG: Double
    public let lateralG: Double
    public let longitudinalG: Double
    public let leanDegrees: Double
    public let horizontalAccuracyMeters: Double?
    public let isSynthetic: Bool

    public init(
        id: UUID = UUID(),
        vehicleID: UUID,
        capturedAt: Date = Date(),
        latitude: Double,
        longitude: Double,
        speedKmh: Double,
        verticalG: Double,
        lateralG: Double,
        longitudinalG: Double,
        leanDegrees: Double = 0,
        horizontalAccuracyMeters: Double? = nil,
        isSynthetic: Bool = false
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.capturedAt = capturedAt
        self.latitude = latitude
        self.longitude = longitude
        self.speedKmh = Self.bounded(speedKmh, lower: 0, upper: 400)
        self.verticalG = Self.bounded(verticalG, lower: -10, upper: 10)
        self.lateralG = Self.bounded(lateralG, lower: -10, upper: 10)
        self.longitudinalG = Self.bounded(longitudinalG, lower: -10, upper: 10)
        self.leanDegrees = Self.bounded(leanDegrees, lower: -90, upper: 90)
        self.horizontalAccuracyMeters = horizontalAccuracyMeters.flatMap {
            guard $0.isFinite, $0 >= 0 else { return nil }
            return min($0, 500)
        }
        self.isSynthetic = isSynthetic
    }

    public var isValidCoordinate: Bool {
        latitude.isFinite
            && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }

    private static func bounded(_ value: Double, lower: Double, upper: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, lower), upper)
    }
}

public nonisolated struct PTRoadSurfaceSegment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let vehicleID: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let startLatitude: Double
    public let startLongitude: Double
    public let endLatitude: Double
    public let endLongitude: Double
    public let sampleCount: Int
    public let distanceMeters: Double
    public let score: Double
    public let quality: PTRoadSurfaceQuality
    public let eventKind: PTRoadSurfaceEventKind?
    public let maxVerticalImpactG: Double
    public let maxLateralG: Double
    public let maxLongitudinalG: Double
    public let averageSpeedKmh: Double
    public let confidence: Double
    public let sourceTripID: String?
    public let isSynthetic: Bool

    public init(
        id: UUID = UUID(),
        vehicleID: UUID,
        startedAt: Date,
        endedAt: Date,
        startLatitude: Double,
        startLongitude: Double,
        endLatitude: Double,
        endLongitude: Double,
        sampleCount: Int,
        distanceMeters: Double,
        score: Double,
        quality: PTRoadSurfaceQuality,
        eventKind: PTRoadSurfaceEventKind? = nil,
        maxVerticalImpactG: Double,
        maxLateralG: Double,
        maxLongitudinalG: Double,
        averageSpeedKmh: Double,
        confidence: Double,
        sourceTripID: String? = nil,
        isSynthetic: Bool = false
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.endLatitude = endLatitude
        self.endLongitude = endLongitude
        self.sampleCount = max(0, sampleCount)
        self.distanceMeters = max(distanceMeters.isFinite ? distanceMeters : 0, 0)
        self.score = min(max(score.isFinite ? score : 0, 0), 100)
        self.quality = quality
        self.eventKind = eventKind
        self.maxVerticalImpactG = abs(maxVerticalImpactG.isFinite ? maxVerticalImpactG : 0)
        self.maxLateralG = abs(maxLateralG.isFinite ? maxLateralG : 0)
        self.maxLongitudinalG = abs(maxLongitudinalG.isFinite ? maxLongitudinalG : 0)
        self.averageSpeedKmh = max(averageSpeedKmh.isFinite ? averageSpeedKmh : 0, 0)
        self.confidence = min(max(confidence.isFinite ? confidence : 0, 0), 1)
        self.sourceTripID = sourceTripID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isSynthetic = isSynthetic
    }
}

public nonisolated struct PTRoadSurfaceSummary: Codable, Equatable, Sendable {
    public let vehicleID: UUID
    public let generatedAt: Date
    public let segmentCount: Int
    public let sampleCount: Int
    public let coveredDistanceMeters: Double
    public let averageScore: Double?
    public let maximumScore: Double?
    public let maximumVerticalImpactG: Double?
    public let roughSegmentCount: Int
    public let severeSegmentCount: Int
    public let overallQuality: PTRoadSurfaceQuality
    public let latestSegmentAt: Date?
    public let isSyntheticOnly: Bool

    public init(
        vehicleID: UUID,
        generatedAt: Date = Date(),
        segmentCount: Int = 0,
        sampleCount: Int = 0,
        coveredDistanceMeters: Double = 0,
        averageScore: Double? = nil,
        maximumScore: Double? = nil,
        maximumVerticalImpactG: Double? = nil,
        roughSegmentCount: Int = 0,
        severeSegmentCount: Int = 0,
        overallQuality: PTRoadSurfaceQuality = .unknown,
        latestSegmentAt: Date? = nil,
        isSyntheticOnly: Bool = false
    ) {
        self.vehicleID = vehicleID
        self.generatedAt = generatedAt
        self.segmentCount = max(segmentCount, 0)
        self.sampleCount = max(sampleCount, 0)
        self.coveredDistanceMeters = max(coveredDistanceMeters.isFinite ? coveredDistanceMeters : 0, 0)
        self.averageScore = averageScore.map { min(max($0.isFinite ? $0 : 0, 0), 100) }
        self.maximumScore = maximumScore.map { min(max($0.isFinite ? $0 : 0, 0), 100) }
        self.maximumVerticalImpactG = maximumVerticalImpactG.map { abs($0.isFinite ? $0 : 0) }
        self.roughSegmentCount = max(roughSegmentCount, 0)
        self.severeSegmentCount = max(severeSegmentCount, 0)
        self.overallQuality = overallQuality
        self.latestSegmentAt = latestSegmentAt
        self.isSyntheticOnly = isSyntheticOnly
    }
}

public nonisolated struct PTRoadSurfaceTimelineDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let segments: [PTRoadSurfaceSegment]
    public let modifiedAt: Date

    public init(
        schemaVersion: Int = 1,
        segments: [PTRoadSurfaceSegment] = [],
        modifiedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.segments = segments
        self.modifiedAt = modifiedAt
    }
}

public nonisolated enum PTRoadSurfaceAnalyzer {
    public static func score(for sample: PTRoadSurfaceSample) -> Double {
        guard sample.isValidCoordinate else { return 0 }
        let vertical = abs(sample.verticalG) * 180
        let lateral = max(abs(sample.lateralG) - 0.08, 0) * 55
        let longitudinal = max(abs(sample.longitudinalG) - 0.15, 0) * 25
        return min(max(vertical + lateral + longitudinal, 0), 100)
    }

    public static func quality(for score: Double) -> PTRoadSurfaceQuality {
        switch score {
        case ..<15: return .smooth
        case ..<35: return .moderate
        case ..<65: return .rough
        case 65...: return .severe
        default: return .unknown
        }
    }

    public static func makeSegments(
        from samples: [PTRoadSurfaceSample],
        vehicleID: UUID,
        sourceTripID: String? = nil,
        maximumSamplesPerSegment: Int = 40
    ) -> [PTRoadSurfaceSegment] {
        let validSamples = samples
            .filter { $0.vehicleID == vehicleID && $0.isValidCoordinate }
            .sorted { $0.capturedAt < $1.capturedAt }
        guard !validSamples.isEmpty else { return [] }

        let boundedMaximumSamples = max(maximumSamplesPerSegment, 1)
        var groups: [[PTRoadSurfaceSample]] = []
        var current: [PTRoadSurfaceSample] = []
        current.reserveCapacity(boundedMaximumSamples)

        for sample in validSamples {
            if let previous = current.last {
                let timeGap = sample.capturedAt.timeIntervalSince(previous.capturedAt)
                let distance = CLLocation(
                    latitude: previous.latitude,
                    longitude: previous.longitude
                ).distance(from: CLLocation(latitude: sample.latitude, longitude: sample.longitude))
                let shouldSplit = timeGap > 4 || distance > 60 || current.count >= boundedMaximumSamples
                if shouldSplit, !current.isEmpty {
                    groups.append(current)
                    current.removeAll(keepingCapacity: true)
                }
            }
            current.append(sample)
        }
        if !current.isEmpty {
            groups.append(current)
        }

        return groups.compactMap {
            makeSegment(from: $0, sourceTripID: sourceTripID)
        }
    }

    public static func summary(
        for segments: [PTRoadSurfaceSegment],
        vehicleID: UUID,
        now: Date = Date()
    ) -> PTRoadSurfaceSummary {
        let selected = segments
            .filter { $0.vehicleID == vehicleID }
            .sorted { $0.endedAt < $1.endedAt }
        guard !selected.isEmpty else {
            return PTRoadSurfaceSummary(vehicleID: vehicleID, generatedAt: now)
        }

        let totalSamples = selected.reduce(0) { $0 + $1.sampleCount }
        let totalDistance = selected.reduce(0) { $0 + $1.distanceMeters }
        let averageScore = selected.reduce(0.0) { partial, segment in
            partial + segment.score * Double(max(segment.sampleCount, 1))
        } / Double(max(totalSamples, 1))
        let maximumScore = selected.map(\.score).max()
        let maximumVertical = selected.map(\.maxVerticalImpactG).max()
        let roughCount = selected.filter { $0.quality == .rough }.count
        let severeCount = selected.filter { $0.quality == .severe }.count
        let overall = quality(for: maximumScore ?? averageScore)

        return PTRoadSurfaceSummary(
            vehicleID: vehicleID,
            generatedAt: now,
            segmentCount: selected.count,
            sampleCount: totalSamples,
            coveredDistanceMeters: totalDistance,
            averageScore: averageScore,
            maximumScore: maximumScore,
            maximumVerticalImpactG: maximumVertical,
            roughSegmentCount: roughCount,
            severeSegmentCount: severeCount,
            overallQuality: overall,
            latestSegmentAt: selected.last?.endedAt,
            isSyntheticOnly: selected.allSatisfy(\.isSynthetic)
        )
    }

    private static func makeSegment(
        from samples: [PTRoadSurfaceSample],
        sourceTripID: String?
    ) -> PTRoadSurfaceSegment? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let scores = samples.map { score(for: $0) }
        let average = scores.reduce(0, +) / Double(scores.count)
        let peak = scores.max() ?? 0
        let blendedScore = min(100, average + (peak - average) * 0.35)
        let totalDistance = zip(samples, samples.dropFirst()).reduce(0.0) { partial, pair in
            partial + CLLocation(
                latitude: pair.0.latitude,
                longitude: pair.0.longitude
            ).distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }
        let accuracy = samples.compactMap(\.horizontalAccuracyMeters)
        let confidence = accuracy.isEmpty
            ? 0.5
            : accuracy.reduce(0.0) { partial, value in
                partial + min(max(1 - value / 50, 0.2), 1)
            } / Double(accuracy.count)

        return PTRoadSurfaceSegment(
            vehicleID: first.vehicleID,
            startedAt: first.capturedAt,
            endedAt: last.capturedAt,
            startLatitude: first.latitude,
            startLongitude: first.longitude,
            endLatitude: last.latitude,
            endLongitude: last.longitude,
            sampleCount: samples.count,
            distanceMeters: totalDistance,
            score: blendedScore,
            quality: quality(for: blendedScore),
            eventKind: eventKind(for: samples, score: blendedScore),
            maxVerticalImpactG: samples.map { abs($0.verticalG) }.max() ?? 0,
            maxLateralG: samples.map { abs($0.lateralG) }.max() ?? 0,
            maxLongitudinalG: samples.map { abs($0.longitudinalG) }.max() ?? 0,
            averageSpeedKmh: samples.map(\.speedKmh).reduce(0, +) / Double(samples.count),
            confidence: confidence,
            sourceTripID: sourceTripID,
            isSynthetic: samples.allSatisfy(\.isSynthetic)
        )
    }

    public static func eventKind(
        for samples: [PTRoadSurfaceSample],
        score: Double
    ) -> PTRoadSurfaceEventKind {
        guard !samples.isEmpty else { return .smooth }
        let verticalPeaks = samples.filter { abs($0.verticalG) >= 0.45 }
        let peakVertical = samples.map { abs($0.verticalG) }.max() ?? 0
        let duration = samples.last?.capturedAt.timeIntervalSince(samples.first?.capturedAt ?? .distantPast) ?? 0
        let elevatedSamples = samples.filter { Self.score(for: $0) >= 35 }.count

        if peakVertical >= 1.25 { return .strongImpact }
        if verticalPeaks.count >= 2, (0.25...3).contains(duration) { return .speedBump }
        if peakVertical >= 0.65, samples.count <= 8 { return .potholeCandidate }
        if elevatedSamples >= max(3, samples.count / 3) { return .repeatedVibration }
        if score >= 35 { return .roughRoad }
        return .smooth
    }
}

// EN: The repository observes existing motion and location streams; it never starts a second sensor or transport stack.
// ES: El repositorio observa los flujos existentes de movimiento y ubicación; nunca inicia otra pila de sensores o transporte.
// 中文：仓库只监听现有运动与定位流，不启动第二套传感器或传输栈。
@MainActor
public final class PTRoadSurfaceRepository: NSObject, PTMotionDelegate, PTVehicleTelemetryConsumer {
    public static let shared = PTRoadSurfaceRepository()
    public static let didChange = Notification.Name("PTRoadSurfaceRepository.didChange")
    public static let impactDidDetect = Notification.Name("PTRoadSurfaceRepository.impactDidDetect")
    public static let fileName = "PTRoadSurfaceTimeline.json"
    public static let retention: TimeInterval = 180 * 24 * 60 * 60
    public static let maximumSegmentsPerVehicle = 2_000

    public private(set) var isLoaded = false
    public private(set) var lastPersistenceError: String?

    private var segmentsByVehicle: [UUID: [PTRoadSurfaceSegment]] = [:]
    private var pendingSegments: [PTRoadSurfaceSegment] = []
    private var activeSamples: [PTRoadSurfaceSample] = []
    private var activeVehicleID: UUID?
    private var latestLocation: CLLocation?
    private var lastSampleAt: Date?
    private var lastImpactPublishedAt: Date?
    private var lastPublishedAt: Date?
    private var loadTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var didStart = false

    private override init() {
        super.init()
    }

    public func start() {
        guard !didStart else { return }
        didStart = true
        PTVehicleTelemetryBridge.shared.startIfNeeded()
        PTMotion.shared.addDelegate(self)
        PTVehicleTelemetryConsumerHub.shared.register(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLocationUpdate(_:)),
            name: PTLocationEngineDidUpdate,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTripReport(_:)),
            name: MotorcycleTripReportGenerated,
            object: nil
        )
        latestLocation = PTLocationEngine.shared.lastLocation
        loadTask = Task { @MainActor [weak self] in
            await self?.load()
        }
    }

    public func segments(for vehicleID: UUID) -> [PTRoadSurfaceSegment] {
        let stored = segmentsByVehicle[vehicleID] ?? []
        let active = PTRoadSurfaceAnalyzer.makeSegments(
            from: activeSamples,
            vehicleID: vehicleID
        )
        return compact(stored + active, now: Date())
            .sorted { $0.endedAt > $1.endedAt }
    }

    public func summary(
        for vehicleID: UUID,
        now: Date = Date()
    ) -> PTRoadSurfaceSummary {
        PTRoadSurfaceAnalyzer.summary(
            for: segments(for: vehicleID),
            vehicleID: vehicleID,
            now: now
        )
    }

    public func exportURL(for vehicleID: UUID) throws -> URL? {
        let selected = segments(for: vehicleID)
        guard !selected.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(PTRoadSurfaceTimelineDocument(segments: selected))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xp400-road-surface-\(vehicleID.uuidString).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    nonisolated public func motionManager(_ manager: PTMotion, didUpdateData data: PTMotionData) {
        Task { @MainActor [weak self] in
            self?.ingest(motion: data)
        }
    }

    nonisolated public func motionManager(_ manager: PTMotion, didChangeDataSource source: PTMotionDataSource) {}

    public func vehicleTelemetryDidUpdate(_ snapshot: PTUnifiedVehicleTelemetrySnapshot) {
        guard snapshot.mode == .replay else { return }
        ingest(replaySnapshot: snapshot)
    }

    @objc private func handleLocationUpdate(_ notification: Notification) {
        guard let tripData = notification.object as? PTTripData,
              let location = tripData.currentLocation else { return }
        latestLocation = location
    }

    @objc private func handleTripReport(_ notification: Notification) {
        guard let report = notification.object as? PTTripReport else { return }
        flushActiveSamples(sourceTripID: report.id)
    }

    private func ingest(motion: PTMotionData, at date: Date = Date()) {
        guard PTMotion.shared.motionStarted,
              let location = latestLocation,
              isUsable(location, at: date),
              let vehicleID = currentVehicleID else { return }

        let speed = PTVehicleTelemetryBridge.shared.snapshot.speedKmh
            ?? PTMotion.shared.currentSpeedKmh
        guard speed.isFinite, (3...260).contains(speed), !motion.isTipOverDetected else { return }
        appendSample(
            vehicleID: vehicleID,
            date: date,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speed: speed,
            verticalG: motion.gForceZ,
            lateralG: motion.gForceX,
            longitudinalG: motion.gForceY,
            leanDegrees: motion.roll,
            horizontalAccuracy: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            isSynthetic: PTVehicleTelemetryBridge.shared.snapshot.containsSyntheticData
        )
    }

    // EN: Replay reuses the unified snapshot, so road analysis stays deterministic without replaying a second sensor source.
    // ES: La reproducción reutiliza la instantánea unificada para mantener el análisis determinista sin otro sensor.
    // 中文：回放复用统一快照，保证道路分析确定性，不重新启动第二套传感器。
    private func ingest(replaySnapshot snapshot: PTUnifiedVehicleTelemetrySnapshot) {
        guard let vehicleID = currentVehicleID,
              let location = snapshot.location,
              let speed = snapshot.speedKmh,
              let lateralG = snapshot.double(for: .gForceX),
              let longitudinalG = snapshot.double(for: .gForceY),
              let verticalG = snapshot.double(for: .gForceZ),
              speed.isFinite,
              (3...260).contains(speed),
              snapshot.updatedAt != .distantPast else { return }
        if let lastSampleAt, snapshot.updatedAt < lastSampleAt {
            flushActiveSamples(sourceTripID: nil)
        }
        appendSample(
            vehicleID: vehicleID,
            date: snapshot.updatedAt,
            latitude: location.latitude,
            longitude: location.longitude,
            speed: speed,
            verticalG: verticalG,
            lateralG: lateralG,
            longitudinalG: longitudinalG,
            leanDegrees: snapshot.double(for: .lean) ?? 0,
            horizontalAccuracy: nil,
            isSynthetic: true
        )
    }

    private func appendSample(
        vehicleID: UUID,
        date: Date,
        latitude: Double,
        longitude: Double,
        speed: Double,
        verticalG: Double,
        lateralG: Double,
        longitudinalG: Double,
        leanDegrees: Double,
        horizontalAccuracy: Double?,
        isSynthetic: Bool
    ) {
        if activeVehicleID != vehicleID {
            flushActiveSamples(sourceTripID: nil)
            activeVehicleID = vehicleID
            lastSampleAt = nil
        }
        guard lastSampleAt.map({ date.timeIntervalSince($0) >= 0.2 }) ?? true else { return }
        let calibration = calibration(for: vehicleID)
        let corrected = calibration.corrected(
            verticalG: verticalG,
            lateralG: lateralG,
            longitudinalG: longitudinalG,
            leanDegrees: leanDegrees
        )
        let sample = PTRoadSurfaceSample(
            vehicleID: vehicleID,
            capturedAt: date,
            latitude: latitude,
            longitude: longitude,
            speedKmh: speed,
            verticalG: corrected.verticalG,
            lateralG: corrected.lateralG,
            longitudinalG: corrected.longitudinalG,
            leanDegrees: corrected.leanDegrees,
            horizontalAccuracyMeters: horizontalAccuracy,
            isSynthetic: isSynthetic
        )
        guard sample.isValidCoordinate else { return }
        activeSamples.append(sample)
        lastSampleAt = date

        // EN: Emit a strong-impact event immediately; the later window flush only persists and deduplicates it.
        // ES: Emite inmediatamente un impacto fuerte; el cierre posterior de la ventana solo lo guarda y deduplica.
        // 中文：强冲击立即发布；后续窗口结束时只负责保存并去重，避免 Twin 延迟很久才提示。
        if abs(sample.verticalG) >= 1.25,
           let impact = PTRoadSurfaceAnalyzer.makeSegments(
               from: [sample],
               vehicleID: vehicleID
           ).first {
            publishEventIfNeeded(for: impact)
        }

        if activeSamples.count >= 400 {
            flushActiveSamples(sourceTripID: nil)
        } else {
            publishChange()
        }
    }

    private func flushActiveSamples(sourceTripID: String?) {
        guard let vehicleID = activeVehicleID,
              !activeSamples.isEmpty else { return }
        let generated = PTRoadSurfaceAnalyzer.makeSegments(
            from: activeSamples,
            vehicleID: vehicleID,
            sourceTripID: sourceTripID
        )
        generated.forEach { insert($0) }
        activeSamples.removeAll(keepingCapacity: true)
        activeVehicleID = nil
        lastSampleAt = nil
        generated.forEach { publishEventIfNeeded(for: $0) }
        publishChange(force: true)
    }

    private var currentVehicleID: UUID? {
        PTVehicleConnectivityCoordinator.shared.dashboardGarageVehicleID
            ?? PTMotorcycleGarageStore.shared.selectedVehicleID
    }

    private func isUsable(_ location: CLLocation, at date: Date) -> Bool {
        let coordinate = location.coordinate
        guard coordinate.latitude.isFinite,
              coordinate.longitude.isFinite,
              (-90...90).contains(coordinate.latitude),
              (-180...180).contains(coordinate.longitude),
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 50 else { return false }
        let age = date.timeIntervalSince(location.timestamp)
        return (-2...15).contains(age)
    }

    private func load() async {
        let data = try? await PTDataPersistenceActor.shared.readData(
            fileName: Self.fileName,
            restoreFromICloud: true
        )
        if let data,
           let document = try? Self.decode(data) {
            segmentsByVehicle = Dictionary(grouping: document.segments, by: \.vehicleID)
        }
        isLoaded = true
        let queued = pendingSegments
        pendingSegments.removeAll(keepingCapacity: true)
        queued.forEach { insert($0, shouldSchedulePersistence: false, notify: false) }
        if !queued.isEmpty {
            schedulePersistence()
        }
        publishChange(force: true)
    }

    @discardableResult
    private func insert(
        _ segment: PTRoadSurfaceSegment,
        shouldSchedulePersistence: Bool = true,
        notify: Bool = true
    ) -> Bool {
        guard segment.sampleCount > 0 else { return false }
        guard isLoaded else {
            pendingSegments.append(segment)
            return true
        }

        var values = segmentsByVehicle[segment.vehicleID] ?? []
        let duplicate = values.contains {
            $0.sourceTripID == segment.sourceTripID
                && abs($0.startedAt.timeIntervalSince(segment.startedAt)) < 0.5
                && $0.sampleCount == segment.sampleCount
        }
        guard !duplicate else { return false }
        values.append(segment)
        segmentsByVehicle[segment.vehicleID] = compact(values, now: Date())
        if shouldSchedulePersistence {
            schedulePersistence()
        }
        if notify {
            publishChange()
        }
        return true
    }

    private func compact(
        _ values: [PTRoadSurfaceSegment],
        now: Date
    ) -> [PTRoadSurfaceSegment] {
        let cutoff = now.addingTimeInterval(-Self.retention)
        let sorted = values
            .filter { $0.endedAt >= cutoff }
            .sorted { $0.endedAt > $1.endedAt }
        var deduplicated: [PTRoadSurfaceSegment] = []
        deduplicated.reserveCapacity(sorted.count)
        for segment in sorted {
            let duplicate = deduplicated.contains {
                $0.vehicleID == segment.vehicleID
                    && abs($0.startedAt.timeIntervalSince(segment.startedAt)) < 2
                    && abs($0.endedAt.timeIntervalSince(segment.endedAt)) < 2
                    && abs($0.score - segment.score) < 5
            }
            if !duplicate {
                deduplicated.append(segment)
            }
        }
        return Array(deduplicated.prefix(Self.maximumSegmentsPerVehicle))
    }

    private func schedulePersistence() {
        persistTask?.cancel()
        let document = PTRoadSurfaceTimelineDocument(
            segments: segmentsByVehicle.values.flatMap { $0 }
        )
        persistTask = Task { @MainActor [weak self, document] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(document)
                let result = try await PTDataPersistenceActor.shared.writeData(
                    data,
                    fileName: Self.fileName,
                    syncToICloud: true
                )
                self.lastPersistenceError = result.cloudErrorDescription
            } catch {
                self.lastPersistenceError = error.localizedDescription
            }
        }
    }

    private func publishChange(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastPublishedAt ?? .distantPast) >= 1 else { return }
        lastPublishedAt = now
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    // EN: Emit impact markers only through the existing trace recorder and notification bus.
    // ES: Emite marcadores de impacto solo mediante el registrador de trazas y el bus de notificaciones existentes.
    // 中文：冲击事件只通过现有 Trace 记录器和通知总线发布，不创建第二套回放管线。
    private func publishEventIfNeeded(for segment: PTRoadSurfaceSegment) {
        guard let eventKind = segment.eventKind,
              [.potholeCandidate, .speedBump, .strongImpact].contains(eventKind) else { return }
        if eventKind == .strongImpact,
           let lastImpactPublishedAt,
           segment.startedAt...segment.endedAt ~= lastImpactPublishedAt {
            return
        }
        let metadata = [
            "eventKind": eventKind.rawValue,
            "score": String(format: "%.1f", segment.score),
            "latitude": String(format: "%.6f", segment.endLatitude),
            "longitude": String(format: "%.6f", segment.endLongitude)
        ]
        PTCrazyTraceRecorder.shared.mark("road_surface_\(eventKind.rawValue)", metadata: metadata, at: segment.endedAt)
        if eventKind == .strongImpact {
            lastImpactPublishedAt = segment.startedAt
            NotificationCenter.default.post(
                name: Self.impactDidDetect,
                object: self,
                userInfo: ["segment": segment]
            )
        }
    }

    public func calibration(for vehicleID: UUID) -> PTRoadSurfaceCalibration {
        let key = "PTRoadSurfaceCalibration.\(vehicleID.uuidString)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(PTRoadSurfaceCalibration.self, from: data) else {
            return .standard
        }
        return value
    }

    @discardableResult
    public func calibrateCurrentMount(for vehicleID: UUID) -> Bool {
        guard currentVehicleID == vehicleID,
              PTMotion.shared.motionStarted,
              PTMotion.shared.currentSpeedKmh <= 2,
              !PTMotion.shared.currentData.isTipOverDetected else { return false }
        let motion = PTMotion.shared.currentData
        let value = PTRoadSurfaceCalibration(
            verticalBiasG: motion.gForceZ,
            lateralBiasG: motion.gForceX,
            longitudinalBiasG: motion.gForceY,
            leanBiasDegrees: motion.roll
        )
        let key = "PTRoadSurfaceCalibration.\(vehicleID.uuidString)"
        guard let data = try? JSONEncoder().encode(value) else { return false }
        UserDefaults.standard.set(data, forKey: key)
        publishChange(force: true)
        return true
    }

    private static func decode(_ data: Data) throws -> PTRoadSurfaceTimelineDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PTRoadSurfaceTimelineDocument.self, from: data)
    }
}
