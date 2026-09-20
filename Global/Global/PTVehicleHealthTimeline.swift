//
//  PTVehicleHealthTimeline.swift
//  CrazyDashboard
//
//  EN: Build 78 stores a bounded, read-only health timeline above existing data sources.
//  ES: Build 78 guarda una línea temporal acotada y de solo lectura sobre las fuentes existentes.
//  中文：Build 78 在现有数据源之上提供有界的只读车辆健康时间线。
//

import Foundation

public nonisolated enum PTVehicleHealthPointSource: String, Codable, Equatable, Sendable {
    case liveTelemetry
    case batteryHistory
    case diagnostic
    case maintenance
    case trip
}

public nonisolated enum PTVehicleHealthChartMetric: String, Codable, CaseIterable, Equatable, Sendable {
    case battery
    case mileage
    case confirmedDTC
}

public nonisolated enum PTVehicleHealthOverallState: String, Codable, Equatable, Sendable {
    case unknown
    case healthy
    case attention
    case critical
}

public nonisolated struct PTVehicleHealthPoint: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let vehicleID: UUID
    public let capturedAt: Date
    public let source: PTVehicleHealthPointSource
    public let sourceID: String?
    public let isSynthetic: Bool

    public let batteryVoltage: Double?
    public let restingVoltage: Double?
    public let crankVoltage: Double?
    public let runningVoltage: Double?
    public let idleRPM: Double?
    public let mileageKm: Double?
    public let maintenanceDistanceKm: Double?
    public let maintenanceFlag: Int?
    public let connectionQuality: PTVehicleConnectionQuality?

    public let confirmedDTCCount: Int?
    public let pendingDTCCount: Int?
    public let permanentDTCCount: Int?
    public let freezeFrameAvailable: Bool?
    public let mode6ResultCount: Int?

    public let tripDistanceKm: Double?
    public let tripMaxSpeedKmh: Double?
    public let tripMaxRPM: Int?
    public let tripDurationMinutes: Int?

    public init(
        id: UUID = UUID(),
        vehicleID: UUID,
        capturedAt: Date = Date(),
        source: PTVehicleHealthPointSource,
        sourceID: String? = nil,
        isSynthetic: Bool = false,
        batteryVoltage: Double? = nil,
        restingVoltage: Double? = nil,
        crankVoltage: Double? = nil,
        runningVoltage: Double? = nil,
        idleRPM: Double? = nil,
        mileageKm: Double? = nil,
        maintenanceDistanceKm: Double? = nil,
        maintenanceFlag: Int? = nil,
        connectionQuality: PTVehicleConnectionQuality? = nil,
        confirmedDTCCount: Int? = nil,
        pendingDTCCount: Int? = nil,
        permanentDTCCount: Int? = nil,
        freezeFrameAvailable: Bool? = nil,
        mode6ResultCount: Int? = nil,
        tripDistanceKm: Double? = nil,
        tripMaxSpeedKmh: Double? = nil,
        tripMaxRPM: Int? = nil,
        tripDurationMinutes: Int? = nil
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.capturedAt = capturedAt
        self.source = source
        self.sourceID = Self.normalizedSourceID(sourceID)
        self.isSynthetic = isSynthetic
        self.batteryVoltage = Self.valid(batteryVoltage, in: 0...20)
        self.restingVoltage = Self.valid(restingVoltage, in: 0...20)
        self.crankVoltage = Self.valid(crankVoltage, in: 0...20)
        self.runningVoltage = Self.valid(runningVoltage, in: 0...20)
        self.idleRPM = Self.valid(idleRPM, in: 0...30_000)
        self.mileageKm = Self.valid(mileageKm, in: 0...2_000_000)
        self.maintenanceDistanceKm = Self.valid(maintenanceDistanceKm, in: 0...65_535)
        self.maintenanceFlag = maintenanceFlag.map { max(0, $0) }
        self.connectionQuality = connectionQuality
        self.confirmedDTCCount = confirmedDTCCount.map { max(0, $0) }
        self.pendingDTCCount = pendingDTCCount.map { max(0, $0) }
        self.permanentDTCCount = permanentDTCCount.map { max(0, $0) }
        self.freezeFrameAvailable = freezeFrameAvailable
        self.mode6ResultCount = mode6ResultCount.map { max(0, $0) }
        self.tripDistanceKm = Self.valid(tripDistanceKm, in: 0...2_000_000)
        self.tripMaxSpeedKmh = Self.valid(tripMaxSpeedKmh, in: 0...400)
        self.tripMaxRPM = tripMaxRPM.map { min(max($0, 0), 30_000) }
        self.tripDurationMinutes = tripDurationMinutes.map { max(0, $0) }
    }

    public var hasMeasuredValue: Bool {
        batteryVoltage != nil
            || restingVoltage != nil
            || crankVoltage != nil
            || runningVoltage != nil
            || idleRPM != nil
            || mileageKm != nil
            || maintenanceDistanceKm != nil
            || connectionQuality != nil
            || confirmedDTCCount != nil
            || pendingDTCCount != nil
            || permanentDTCCount != nil
            || freezeFrameAvailable != nil
            || mode6ResultCount != nil
            || tripDistanceKm != nil
            || tripMaxSpeedKmh != nil
            || tripMaxRPM != nil
            || tripDurationMinutes != nil
    }

    public var deduplicationKey: String {
        if let sourceID {
            return "\(source.rawValue):\(sourceID)"
        }
        let minute = Int(capturedAt.timeIntervalSince1970 / 60)
        return "\(source.rawValue):\(minute)"
    }

    private static func valid(_ value: Double?, in range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite, range.contains(value) else { return nil }
        return value
    }

    private static func normalizedSourceID(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(160))
    }
}

public nonisolated struct PTVehicleHealthTimelineDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let points: [PTVehicleHealthPoint]
    public let modifiedAt: Date

    public init(
        schemaVersion: Int = 1,
        points: [PTVehicleHealthPoint] = [],
        modifiedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.points = points
        self.modifiedAt = modifiedAt
    }
}

public nonisolated struct PTVehicleHealthMetricTrend: Codable, Equatable, Sendable {
    public let latest: Double?
    public let minimum: Double?
    public let maximum: Double?
    public let average: Double?
    public let slopePerDay: Double?
    public let sampleCount: Int

    public init(
        latest: Double? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        average: Double? = nil,
        slopePerDay: Double? = nil,
        sampleCount: Int = 0
    ) {
        self.latest = latest
        self.minimum = minimum
        self.maximum = maximum
        self.average = average
        self.slopePerDay = slopePerDay
        self.sampleCount = max(0, sampleCount)
    }
}

public nonisolated struct PTVehicleHealthSummary: Codable, Equatable, Sendable {
    public let vehicleID: UUID
    public let generatedAt: Date
    public let latestPointAt: Date?
    public let totalPointCount: Int
    public let realPointCount: Int
    public let isSyntheticOnly: Bool
    public let overallState: PTVehicleHealthOverallState

    public let battery: PTVehicleHealthMetricTrend
    public let restingVoltage: PTVehicleHealthMetricTrend
    public let crankVoltage: PTVehicleHealthMetricTrend
    public let runningVoltage: PTVehicleHealthMetricTrend
    public let idleRPM: PTVehicleHealthMetricTrend
    public let mileage: PTVehicleHealthMetricTrend

    public let latestConnectionQuality: PTVehicleConnectionQuality?
    public let latestConfirmedDTCCount: Int?
    public let latestPendingDTCCount: Int?
    public let latestPermanentDTCCount: Int?
    public let latestMaintenanceDistanceKm: Double?
    public let latestMaintenanceFlag: Int?
    public let lastRideAt: Date?
    public let lastRideDistanceKm: Double?

    public init(
        vehicleID: UUID,
        generatedAt: Date = Date(),
        latestPointAt: Date? = nil,
        totalPointCount: Int = 0,
        realPointCount: Int = 0,
        isSyntheticOnly: Bool = false,
        overallState: PTVehicleHealthOverallState = .unknown,
        battery: PTVehicleHealthMetricTrend = PTVehicleHealthMetricTrend(),
        restingVoltage: PTVehicleHealthMetricTrend = PTVehicleHealthMetricTrend(),
        crankVoltage: PTVehicleHealthMetricTrend = PTVehicleHealthMetricTrend(),
        runningVoltage: PTVehicleHealthMetricTrend = PTVehicleHealthMetricTrend(),
        idleRPM: PTVehicleHealthMetricTrend = PTVehicleHealthMetricTrend(),
        mileage: PTVehicleHealthMetricTrend = PTVehicleHealthMetricTrend(),
        latestConnectionQuality: PTVehicleConnectionQuality? = nil,
        latestConfirmedDTCCount: Int? = nil,
        latestPendingDTCCount: Int? = nil,
        latestPermanentDTCCount: Int? = nil,
        latestMaintenanceDistanceKm: Double? = nil,
        latestMaintenanceFlag: Int? = nil,
        lastRideAt: Date? = nil,
        lastRideDistanceKm: Double? = nil
    ) {
        self.vehicleID = vehicleID
        self.generatedAt = generatedAt
        self.latestPointAt = latestPointAt
        self.totalPointCount = max(0, totalPointCount)
        self.realPointCount = max(0, realPointCount)
        self.isSyntheticOnly = isSyntheticOnly
        self.overallState = overallState
        self.battery = battery
        self.restingVoltage = restingVoltage
        self.crankVoltage = crankVoltage
        self.runningVoltage = runningVoltage
        self.idleRPM = idleRPM
        self.mileage = mileage
        self.latestConnectionQuality = latestConnectionQuality
        self.latestConfirmedDTCCount = latestConfirmedDTCCount
        self.latestPendingDTCCount = latestPendingDTCCount
        self.latestPermanentDTCCount = latestPermanentDTCCount
        self.latestMaintenanceDistanceKm = latestMaintenanceDistanceKm
        self.latestMaintenanceFlag = latestMaintenanceFlag
        self.lastRideAt = lastRideAt
        self.lastRideDistanceKm = lastRideDistanceKm
    }
}

public nonisolated enum PTVehicleHealthAnalyzer {
    public static func summarize(
        points: [PTVehicleHealthPoint],
        vehicleID: UUID,
        includeSynthetic: Bool = true,
        now: Date = Date()
    ) -> PTVehicleHealthSummary {
        let selected = points
            .filter { $0.vehicleID == vehicleID }
            .filter { includeSynthetic || !$0.isSynthetic }
            .sorted { $0.capturedAt < $1.capturedAt }
        let realPoints = selected.filter { !$0.isSynthetic }
        let latest = selected.last

        let summary = PTVehicleHealthSummary(
            vehicleID: vehicleID,
            generatedAt: now,
            latestPointAt: latest?.capturedAt,
            totalPointCount: selected.count,
            realPointCount: realPoints.count,
            isSyntheticOnly: !selected.isEmpty && realPoints.isEmpty,
            overallState: overallState(points: selected),
            battery: trend(series: series(selected, keyPath: \.batteryVoltage)),
            restingVoltage: trend(series: series(selected, keyPath: \.restingVoltage)),
            crankVoltage: trend(series: series(selected, keyPath: \.crankVoltage)),
            runningVoltage: trend(series: series(selected, keyPath: \.runningVoltage)),
            idleRPM: trend(series: series(selected, keyPath: \.idleRPM)),
            mileage: trend(series: series(selected, keyPath: \.mileageKm)),
            latestConnectionQuality: latestValue(from: selected, keyPath: \.connectionQuality),
            latestConfirmedDTCCount: latestValue(from: selected, keyPath: \.confirmedDTCCount),
            latestPendingDTCCount: latestValue(from: selected, keyPath: \.pendingDTCCount),
            latestPermanentDTCCount: latestValue(from: selected, keyPath: \.permanentDTCCount),
            latestMaintenanceDistanceKm: latestValue(from: selected, keyPath: \.maintenanceDistanceKm),
            latestMaintenanceFlag: latestValue(from: selected, keyPath: \.maintenanceFlag),
            lastRideAt: selected.last(where: { $0.source == .trip })?.capturedAt,
            lastRideDistanceKm: selected.last(where: { $0.source == .trip })?.tripDistanceKm
        )
        return summary
    }

    public static func chartValues(
        for metric: PTVehicleHealthChartMetric,
        points: [PTVehicleHealthPoint],
        vehicleID: UUID,
        includeSynthetic: Bool = true
    ) -> [(date: Date, value: Double)] {
        points
            .filter { $0.vehicleID == vehicleID && (includeSynthetic || !$0.isSynthetic) }
            .sorted { $0.capturedAt < $1.capturedAt }
            .compactMap { point in
                let value: Double?
                switch metric {
                case .battery:
                    value = point.batteryVoltage ?? point.runningVoltage ?? point.restingVoltage
                case .mileage:
                    value = point.mileageKm
                case .confirmedDTC:
                    value = point.confirmedDTCCount.map(Double.init)
                }
                return value.map { (date: point.capturedAt, value: $0) }
            }
    }

    private static func series(
        _ points: [PTVehicleHealthPoint],
        keyPath: KeyPath<PTVehicleHealthPoint, Double?>
    ) -> [(date: Date, value: Double)] {
        points
            .sorted { $0.capturedAt < $1.capturedAt }
            .compactMap { point in
                point[keyPath: keyPath].map { (date: point.capturedAt, value: $0) }
            }
    }

    private static func trend(
        series: [(date: Date, value: Double)]
    ) -> PTVehicleHealthMetricTrend {
        guard !series.isEmpty else { return PTVehicleHealthMetricTrend() }
        let values = series.map(\.value)
        let sorted = values.sorted()
        let first = series.first
        let last = series.last
        let slope: Double?
        if let first, let last {
            let days = last.date.timeIntervalSince(first.date) / 86_400
            slope = days > 0 ? (last.value - first.value) / days : nil
        } else {
            slope = nil
        }
        return PTVehicleHealthMetricTrend(
            latest: values.last,
            minimum: sorted.first,
            maximum: sorted.last,
            average: values.reduce(0, +) / Double(values.count),
            slopePerDay: slope,
            sampleCount: values.count
        )
    }

    private static func latestValue<Value>(
        from points: [PTVehicleHealthPoint],
        keyPath: KeyPath<PTVehicleHealthPoint, Value?>
    ) -> Value? {
        points.reversed().compactMap { $0[keyPath: keyPath] }.first
    }

    private static func overallState(points: [PTVehicleHealthPoint]) -> PTVehicleHealthOverallState {
        guard !points.isEmpty else { return .unknown }
        guard points.contains(where: { !$0.isSynthetic }) else { return .unknown }

        let latestDiagnostic = points.reversed().first {
            $0.confirmedDTCCount != nil || $0.pendingDTCCount != nil || $0.permanentDTCCount != nil
        }
        if latestDiagnostic?.confirmedDTCCount.map({ $0 > 0 }) == true {
            return .critical
        }

        let latestVoltage = points.reversed().compactMap { $0.crankVoltage ?? $0.restingVoltage }.first
        if latestVoltage.map({ $0 < 10.0 }) == true {
            return .attention
        }

        let latestMaintenanceDistance = points.reversed().compactMap(\.maintenanceDistanceKm).first
        if latestMaintenanceDistance.map({ $0 <= 0 }) == true {
            return .attention
        }

        return .healthy
    }
}

// EN: This repository adapts existing battery, diagnostic, trip and garage stores; it never creates a second transport or battery database.
// ES: Este repositorio adapta los almacenes existentes de batería, diagnóstico, viajes y garaje; nunca crea otro transporte ni otra base de batería.
// 中文：该仓库只适配现有电池、诊断、行程和车库存储，不创建第二套传输层或电池数据库。
@MainActor
public final class PTVehicleHealthRepository: NSObject {
    public static let shared = PTVehicleHealthRepository()
    public static let didChange = Notification.Name("PTVehicleHealthRepository.didChange")
    public static let fileName = "PTVehicleHealthTimeline.json"
    public static let retention: TimeInterval = 365 * 24 * 60 * 60
    public static let maximumPointsPerVehicle = 2_000

    public private(set) var isLoaded = false
    public private(set) var lastPersistenceError: String?

    private var pointsByVehicle: [UUID: [PTVehicleHealthPoint]] = [:]
    private var pendingPoints: [PTVehicleHealthPoint] = []
    private var lastLivePointAtByVehicle: [UUID: Date] = [:]
    private var loadTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var didStart = false

    private override init() {
        super.init()
    }

    public func start() {
        guard !didStart else { return }
        didStart = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTelemetryChange),
            name: PTVehicleConnectivityCoordinator.telemetryDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGarageChange),
            name: PTMotorcycleGarageStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTripReport(_:)),
            name: MotorcycleTripReportGenerated,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDiagnosticChange),
            name: PTBuild68DiagnosticCoordinator.didChange,
            object: nil
        )
        loadTask = Task { @MainActor [weak self] in
            await self?.loadAndMigrate()
        }
    }

    public func points(for vehicleID: UUID) -> [PTVehicleHealthPoint] {
        let stored = pointsByVehicle[vehicleID] ?? []
        let pending = pendingPoints.filter { $0.vehicleID == vehicleID }
        return merge(stored + pending)
    }

    public func summary(
        for vehicleID: UUID,
        includeSynthetic: Bool = true,
        now: Date = Date()
    ) -> PTVehicleHealthSummary {
        PTVehicleHealthAnalyzer.summarize(
            points: points(for: vehicleID),
            vehicleID: vehicleID,
            includeSynthetic: includeSynthetic,
            now: now
        )
    }

    public func chartValues(
        for metric: PTVehicleHealthChartMetric,
        vehicleID: UUID,
        includeSynthetic: Bool = true
    ) -> [(date: Date, value: Double)] {
        PTVehicleHealthAnalyzer.chartValues(
            for: metric,
            points: points(for: vehicleID),
            vehicleID: vehicleID,
            includeSynthetic: includeSynthetic
        )
    }

    public func recordLiveTelemetry(
        telemetry: PTVehicleTelemetrySnapshot,
        connection: PTVehicleSnapshot,
        battery: PTBatteryHealthSummary,
        at date: Date = Date()
    ) {
        guard let vehicleID = PTVehicleConnectivityCoordinator.shared.dashboardGarageVehicleID
                ?? PTMotorcycleGarageStore.shared.selectedVehicleID else {
            return
        }
        guard date.timeIntervalSince(lastLivePointAtByVehicle[vehicleID] ?? .distantPast) >= 60 else {
            return
        }
        let quality = PTVehicleConnectionQualityEvaluator.evaluate(snapshot: telemetry, at: date)
        let point = PTVehicleHealthPoint(
            vehicleID: vehicleID,
            capturedAt: date,
            source: .liveTelemetry,
            isSynthetic: telemetry.containsMockData
                || connection.dashboard.transport == .dashboardMock
                || connection.obd.transport == .obdMock,
            batteryVoltage: telemetry.batteryVoltage?.value,
            restingVoltage: battery.restingMedianVoltage,
            crankVoltage: battery.crankingMinimumVoltage,
            runningVoltage: battery.runningMedianVoltage,
            idleRPM: Self.idleRPM(from: telemetry),
            mileageKm: telemetry.odometerKm?.value,
            maintenanceDistanceKm: telemetry.maintenanceDistanceKm.map { Double($0.value) },
            maintenanceFlag: telemetry.maintenanceFlag?.value,
            connectionQuality: quality
        )
        guard point.hasMeasuredValue else { return }
        lastLivePointAtByVehicle[vehicleID] = date
        insert(point)
    }

    public func recordDiagnosticReport(
        _ report: PTGarageDiagnosticReport,
        for vehicleID: UUID,
        isSynthetic: Bool = false
    ) {
        let point = PTVehicleHealthPoint(
            vehicleID: vehicleID,
            capturedAt: report.capturedAt,
            source: .diagnostic,
            sourceID: "diagnostic-\(report.id.uuidString)",
            isSynthetic: isSynthetic,
            batteryVoltage: report.batteryHealthSummary?.runningMedianVoltage,
            restingVoltage: report.batteryHealthSummary?.restingMedianVoltage,
            crankVoltage: report.batteryHealthSummary?.crankingMinimumVoltage,
            runningVoltage: report.batteryHealthSummary?.runningMedianVoltage,
            mileageKm: PTMotorcycleGarageStore.shared.vehicle(id: vehicleID)?.odometerKm,
            connectionQuality: report.connectionQuality,
            confirmedDTCCount: report.confirmedDTCs?.count,
            freezeFrameAvailable: report.freezeFrame?.isEmpty == false,
            mode6ResultCount: report.mode6Results?.count
        )
        insert(point)
    }

    public func recordDiagnosticSession(
        _ session: PTBuild68DiagnosticSessionRecord,
        for vehicleID: UUID,
        isSynthetic: Bool = false
    ) {
        let confirmed = session.troubleCodes.filter { $0.source.rawValue == "confirmed" }.count
        let pending = session.troubleCodes.filter { $0.source.rawValue == "pending" }.count
        let permanent = session.troubleCodes.filter { $0.source.rawValue == "permanent" }.count
        let mode6Count = session.rawCommandResults.filter {
            $0.command.hasPrefix("06") && $0.status.rawValue == "success"
        }.count
        let point = PTVehicleHealthPoint(
            vehicleID: vehicleID,
            capturedAt: session.endedAt ?? session.startedAt,
            source: .diagnostic,
            sourceID: session.sessionID.uuidString,
            isSynthetic: isSynthetic,
            batteryVoltage: session.voltage.controlModuleVoltage,
            mileageKm: PTMotorcycleGarageStore.shared.vehicle(id: vehicleID)?.odometerKm,
            confirmedDTCCount: confirmed,
            pendingDTCCount: pending,
            permanentDTCCount: permanent,
            freezeFrameAvailable: session.freezeFrame != nil,
            mode6ResultCount: mode6Count
        )
        insert(point)
    }

    public func recordMaintenance(
        for vehicle: PTMotorcycleProfile,
        at date: Date = Date(),
        isSynthetic: Bool = false
    ) {
        let latestRecord = vehicle.maintenanceRecords.sorted { $0.completedAt > $1.completedAt }.first
        let remaining = vehicle.dashboardMaintenanceDistanceKm.map(Double.init)
            ?? latestRecord.flatMap { record in
                record.nextDueMileageKm.map { max(0, $0 - vehicle.odometerKm) }
            }
        guard remaining != nil || vehicle.dashboardMaintenanceFlag != nil || latestRecord != nil else {
            return
        }
        let sourceID = latestRecord.map { "maintenance-\($0.id.uuidString)" }
            ?? "dashboard-\(vehicle.lastDashboardSyncAt?.timeIntervalSince1970 ?? 0)"
        let point = PTVehicleHealthPoint(
            vehicleID: vehicle.id,
            capturedAt: vehicle.lastDashboardSyncAt ?? latestRecord?.completedAt ?? date,
            source: .maintenance,
            sourceID: sourceID,
            isSynthetic: isSynthetic,
            mileageKm: vehicle.odometerKm,
            maintenanceDistanceKm: remaining,
            maintenanceFlag: vehicle.dashboardMaintenanceFlag
        )
        insert(point)
    }

    public func recordTrip(_ report: PTTripReport) {
        guard let vehicleID = report.vehicleID ?? PTMotorcycleGarageStore.shared.selectedVehicleID else {
            return
        }
        let point = PTVehicleHealthPoint(
            vehicleID: vehicleID,
            capturedAt: report.endTime,
            source: .trip,
            sourceID: report.id,
            mileageKm: report.endOdoKm > 0 ? report.endOdoKm : nil,
            tripDistanceKm: report.distanceKm,
            tripMaxSpeedKmh: report.maxSpeedKmh,
            tripMaxRPM: report.maxRpm,
            tripDurationMinutes: report.durationMinutes
        )
        insert(point)
    }

    public func exportURL(for vehicleID: UUID, includeSynthetic: Bool = true) throws -> URL? {
        let points = points(for: vehicleID).filter { includeSynthetic || !$0.isSynthetic }
        guard !points.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(PTVehicleHealthTimelineDocument(points: points))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xp400-health-\(vehicleID.uuidString).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    @objc private func handleTelemetryChange() {
        let coordinator = PTVehicleConnectivityCoordinator.shared
        recordLiveTelemetry(
            telemetry: coordinator.telemetrySnapshot,
            connection: coordinator.snapshot,
            battery: coordinator.batteryHealthSummary
        )
    }

    @objc private func handleGarageChange() {
        for vehicle in PTMotorcycleGarageStore.shared.vehicles {
            recordMaintenance(for: vehicle)
            for report in vehicle.diagnosticReports.prefix(3) {
                recordDiagnosticReport(
                    report,
                    for: vehicle.id,
                    isSynthetic: false
                )
            }
        }
        publishChange()
    }

    @objc private func handleTripReport(_ notification: Notification) {
        guard let report = notification.object as? PTTripReport else { return }
        recordTrip(report)
    }

    @objc private func handleDiagnosticChange() {
        let coordinator = PTBuild68DiagnosticCoordinator.shared
        guard let session = coordinator.latestSession,
              let vehicleID = PTMotorcycleGarageStore.shared.selectedVehicleID else {
            return
        }
        recordDiagnosticSession(
            session,
            for: vehicleID,
            isSynthetic: PTVehicleConnectivityCoordinator.shared.snapshot.obd.transport == .obdMock
        )
    }

    private func loadAndMigrate() async {
        var data: Data?
        do {
            data = try await PTDataPersistenceActor.shared.readData(
                fileName: Self.fileName,
                restoreFromICloud: false
            )
        } catch {
            data = try? await PTDataPersistenceActor.shared.readData(
                fileName: Self.fileName,
                restoreFromICloud: true
            )
        }

        if let data,
           let document = try? Self.decodeDocument(data) {
            pointsByVehicle = Dictionary(grouping: document.points, by: \.vehicleID)
        }
        isLoaded = true

        let queued = pendingPoints
        pendingPoints.removeAll(keepingCapacity: true)
        queued.forEach { insert($0, shouldSchedulePersistence: false, notify: false) }
        migrateExistingSources()
        if !queued.isEmpty {
            schedulePersistence()
        }
        publishChange()
    }

    private func migrateExistingSources() {
        var didChange = false
        let garage = PTMotorcycleGarageStore.shared
        for vehicle in garage.vehicles {
            for summary in PTBatteryHealthHistoryStore.shared.summaries(for: vehicle.id) {
                let point = PTVehicleHealthPoint(
                    vehicleID: vehicle.id,
                    capturedAt: summary.capturedAt,
                    source: .batteryHistory,
                    sourceID: "battery-\(summary.id)",
                    batteryVoltage: summary.summary.runningMedianVoltage ?? summary.summary.restingMedianVoltage,
                    restingVoltage: summary.summary.restingMedianVoltage,
                    crankVoltage: summary.summary.crankingMinimumVoltage,
                    runningVoltage: summary.summary.runningMedianVoltage
                )
                didChange = insert(point, shouldSchedulePersistence: false, notify: false) || didChange
            }
            for report in vehicle.diagnosticReports {
                didChange = insert(
                    makeDiagnosticPoint(report, vehicle: vehicle),
                    shouldSchedulePersistence: false,
                    notify: false
                ) || didChange
            }
            if let latestMaintenance = vehicle.maintenanceRecords.sorted(by: { $0.completedAt > $1.completedAt }).first {
                let point = PTVehicleHealthPoint(
                    vehicleID: vehicle.id,
                    capturedAt: latestMaintenance.completedAt,
                    source: .maintenance,
                    sourceID: "maintenance-\(latestMaintenance.id.uuidString)",
                    mileageKm: vehicle.odometerKm,
                    maintenanceDistanceKm: latestMaintenance.nextDueMileageKm.map { max(0, $0 - vehicle.odometerKm) }
                )
                didChange = insert(point, shouldSchedulePersistence: false, notify: false) || didChange
            }
        }

        for report in PTTripManager.shared.tripHistory {
            didChange = insert(
                makeTripPoint(report),
                    shouldSchedulePersistence: false,
                notify: false
            ) || didChange
        }
        if didChange {
            schedulePersistence()
        }
    }

    private func makeDiagnosticPoint(
        _ report: PTGarageDiagnosticReport,
        vehicle: PTMotorcycleProfile
    ) -> PTVehicleHealthPoint {
        PTVehicleHealthPoint(
            vehicleID: vehicle.id,
            capturedAt: report.capturedAt,
            source: .diagnostic,
            sourceID: "diagnostic-\(report.id.uuidString)",
            batteryVoltage: report.batteryHealthSummary?.runningMedianVoltage,
            restingVoltage: report.batteryHealthSummary?.restingMedianVoltage,
            crankVoltage: report.batteryHealthSummary?.crankingMinimumVoltage,
            runningVoltage: report.batteryHealthSummary?.runningMedianVoltage,
            mileageKm: vehicle.odometerKm,
            connectionQuality: report.connectionQuality,
            confirmedDTCCount: report.confirmedDTCs?.count,
            freezeFrameAvailable: report.freezeFrame?.isEmpty == false,
            mode6ResultCount: report.mode6Results?.count
        )
    }

    private func makeTripPoint(_ report: PTTripReport) -> PTVehicleHealthPoint {
        PTVehicleHealthPoint(
            vehicleID: report.vehicleID ?? PTMotorcycleGarageStore.shared.selectedVehicleID ?? UUID(),
            capturedAt: report.endTime,
            source: .trip,
            sourceID: report.id,
            mileageKm: report.endOdoKm > 0 ? report.endOdoKm : nil,
            tripDistanceKm: report.distanceKm,
            tripMaxSpeedKmh: report.maxSpeedKmh,
            tripMaxRPM: report.maxRpm,
            tripDurationMinutes: report.durationMinutes
        )
    }

    @discardableResult
    private func insert(
        _ point: PTVehicleHealthPoint,
        shouldSchedulePersistence: Bool = true,
        notify: Bool = true
    ) -> Bool {
        guard point.hasMeasuredValue else { return false }
        guard isLoaded else {
            pendingPoints.removeAll { $0.deduplicationKey == point.deduplicationKey }
            pendingPoints.append(point)
            return true
        }

        var values = pointsByVehicle[point.vehicleID] ?? []
        if let index = values.firstIndex(where: { $0.deduplicationKey == point.deduplicationKey }) {
            guard values[index].capturedAt < point.capturedAt else { return false }
            values[index] = point
        } else {
            values.append(point)
        }
        values = compact(values, now: Date())
        pointsByVehicle[point.vehicleID] = values
        if shouldSchedulePersistence {
            schedulePersistence()
        }
        if notify {
            publishChange(for: point.vehicleID)
        }
        return true
    }

    private func compact(_ values: [PTVehicleHealthPoint], now: Date) -> [PTVehicleHealthPoint] {
        let cutoff = now.addingTimeInterval(-Self.retention)
        return Array(
            values
                .filter { $0.capturedAt >= cutoff }
                .sorted { $0.capturedAt > $1.capturedAt }
                .prefix(Self.maximumPointsPerVehicle)
        )
    }

    private func merge(_ values: [PTVehicleHealthPoint]) -> [PTVehicleHealthPoint] {
        var byKey: [String: PTVehicleHealthPoint] = [:]
        for point in values {
            if byKey[point.deduplicationKey]?.capturedAt ?? .distantPast < point.capturedAt {
                byKey[point.deduplicationKey] = point
            }
        }
        return compact(Array(byKey.values), now: Date())
    }

    private func schedulePersistence() {
        persistTask?.cancel()
        let document = PTVehicleHealthTimelineDocument(
            points: pointsByVehicle.values.flatMap { $0 }
        )
        persistTask = Task { @MainActor [weak self, document] in
            try? await Task.sleep(nanoseconds: 750_000_000)
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

    private func publishChange(for vehicleID: UUID? = nil) {
        let userInfo: [AnyHashable: Any]? = vehicleID.map { ["vehicleID": $0] }
        NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: userInfo)
    }

    private static func decodeDocument(_ data: Data) throws -> PTVehicleHealthTimelineDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PTVehicleHealthTimelineDocument.self, from: data)
    }

    private static func idleRPM(from telemetry: PTVehicleTelemetrySnapshot) -> Double? {
        guard telemetry.engineStatus?.value == 2,
              let rpm = telemetry.engineRPM?.value,
              (0...2_000).contains(rpm) else {
            return nil
        }
        return Double(rpm)
    }
}
