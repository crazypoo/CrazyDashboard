//
//  PTVehicleIntelligence.swift
//  CrazyDashboard
//
//  EN: Build 85 turns mature read-only vehicle data into evidence-backed insights.
//  ES: Build 85 convierte datos maduros de solo lectura en observaciones con evidencia.
//  中文：Build 85 将成熟的只读车辆数据转换为带证据的可解释洞察。
//

import Foundation
import UIKit

// EN: Severity is deliberately descriptive; an insight never represents an ECU write or a repair diagnosis.
// ES: La severidad es descriptiva; una observación nunca representa una escritura en la ECU ni un diagnóstico de reparación.
// 中文：严重级别只用于描述；洞察不会代表 ECU 写入或维修诊断。
nonisolated enum PTVehicleIntelligenceSeverity: Int, Codable, CaseIterable, Equatable, Sendable {
    case unknown
    case healthy
    case observe
    case attention
    case critical
}

nonisolated enum PTVehicleIntelligenceEvidenceSource: String, Codable, CaseIterable, Equatable, Sendable {
    case healthTimeline
    case rideDNA
    case roadSurface
    case trip
    case diagnostic
    case maintenance
    case confirmedSemanticState
}

nonisolated enum PTVehicleIntelligenceEvidenceQuality: String, Codable, CaseIterable, Equatable, Sendable {
    case confirmed
    case observed
    case inferred
    case insufficient
    case syntheticExcluded

    var mayNotify: Bool {
        self == .confirmed || self == .observed
    }
}

nonisolated enum PTVehicleIntelligenceInsightKind: String, Codable, CaseIterable, Equatable, Sendable {
    case batteryTrend
    case batteryLow
    case engineBaseline
    case confirmedDTC
    case pendingDTC
    case maintenance
    case lastRide
    case rideReview
    case roadSummary
    case absWarning
}

nonisolated struct PTVehicleIntelligenceEvidence: Codable, Equatable, Sendable {
    let source: PTVehicleIntelligenceEvidenceSource
    let windowStart: Date
    let windowEnd: Date
    let sampleCount: Int
    let quality: PTVehicleIntelligenceEvidenceQuality
    let note: String

    init(
        source: PTVehicleIntelligenceEvidenceSource,
        windowStart: Date,
        windowEnd: Date,
        sampleCount: Int,
        quality: PTVehicleIntelligenceEvidenceQuality,
        note: String
    ) {
        self.source = source
        self.windowStart = min(windowStart, windowEnd)
        self.windowEnd = max(windowStart, windowEnd)
        self.sampleCount = max(sampleCount, 0)
        self.quality = quality
        self.note = String(note.prefix(240))
    }
}

nonisolated struct PTVehicleIntelligenceInsight: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: PTVehicleIntelligenceInsightKind
    let titleKey: String
    let severity: PTVehicleIntelligenceSeverity
    let primaryValue: Double?
    let secondaryValue: Double?
    let sampleCount: Int
    let evidence: [PTVehicleIntelligenceEvidence]
    let generatedAt: Date
    let expiresAt: Date?
    let isActionable: Bool
    let isSynthetic: Bool

    init(
        id: String,
        kind: PTVehicleIntelligenceInsightKind,
        titleKey: String,
        severity: PTVehicleIntelligenceSeverity,
        primaryValue: Double? = nil,
        secondaryValue: Double? = nil,
        sampleCount: Int = 0,
        evidence: [PTVehicleIntelligenceEvidence],
        generatedAt: Date,
        expiresAt: Date? = nil,
        isActionable: Bool,
        isSynthetic: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.titleKey = titleKey
        self.severity = severity
        self.primaryValue = primaryValue?.isFinite == true ? primaryValue : nil
        self.secondaryValue = secondaryValue?.isFinite == true ? secondaryValue : nil
        self.sampleCount = max(sampleCount, 0)
        self.evidence = evidence
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
        self.isActionable = isActionable
        self.isSynthetic = isSynthetic
    }
}

nonisolated struct PTVehicleIntelligenceReview: Codable, Equatable, Sendable {
    let evaluatedRuleCount: Int
    let actionableInsightCount: Int
    let suppressedRuleIDs: [String]

    init(
        evaluatedRuleCount: Int,
        actionableInsightCount: Int,
        suppressedRuleIDs: [String]
    ) {
        self.evaluatedRuleCount = max(evaluatedRuleCount, 0)
        self.actionableInsightCount = max(actionableInsightCount, 0)
        self.suppressedRuleIDs = Array(Set(suppressedRuleIDs)).sorted()
    }
}

nonisolated struct PTVehicleIntelligenceSummary: Codable, Equatable, Sendable {
    let vehicleID: UUID
    let generatedAt: Date
    let overallState: PTVehicleIntelligenceSeverity
    let insights: [PTVehicleIntelligenceInsight]
    let evidenceCount: Int
    let lastRideAt: Date?
    let maintenanceRemainingKm: Double?
    let falsePositiveReview: PTVehicleIntelligenceReview

    init(
        vehicleID: UUID,
        generatedAt: Date,
        overallState: PTVehicleIntelligenceSeverity,
        insights: [PTVehicleIntelligenceInsight],
        evidenceCount: Int,
        lastRideAt: Date?,
        maintenanceRemainingKm: Double?,
        falsePositiveReview: PTVehicleIntelligenceReview
    ) {
        self.vehicleID = vehicleID
        self.generatedAt = generatedAt
        self.overallState = overallState
        self.insights = insights
        self.evidenceCount = max(evidenceCount, 0)
        self.lastRideAt = lastRideAt
        self.maintenanceRemainingKm = maintenanceRemainingKm
        self.falsePositiveReview = falsePositiveReview
    }
}

// EN: The Twin adapter exposes only bounded, read-only presentation data to the renderer.
// ES: El adaptador del Twin expone al renderizador solo datos acotados y de presentación de solo lectura.
// 中文：Twin 适配器只向渲染器提供有界的只读展示数据。
nonisolated struct PTVehicleTwinIntelligencePresentation: Equatable, Sendable {
    let state: PTVehicleIntelligenceSeverity
    let evidenceCount: Int
    let maintenanceRemainingKm: Double?
    let insights: [PTVehicleIntelligenceInsight]
}

nonisolated enum PTVehicleTwinIntelligenceAdapter {
    static func make(from summary: PTVehicleIntelligenceSummary) -> PTVehicleTwinIntelligencePresentation {
        PTVehicleTwinIntelligencePresentation(
            state: summary.overallState,
            evidenceCount: summary.evidenceCount,
            maintenanceRemainingKm: summary.maintenanceRemainingKm,
            insights: Array(summary.insights.prefix(5))
        )
    }
}

// EN: The input is a snapshot of existing stores, so analysis cannot open BLE, ELM327, YMOBD, or a write path.
// ES: La entrada es una instantánea de almacenes existentes; el análisis no puede abrir BLE, ELM327, YMOBD ni una ruta de escritura.
// 中文：输入只是现有存储的快照，分析层不会打开 BLE、ELM327、YMOBD，也不会进入写入路径。
nonisolated struct PTVehicleIntelligenceInput: Sendable {
    let vehicleID: UUID
    let healthPoints: [PTVehicleHealthPoint]
    let roadSegments: [PTRoadSurfaceSegment]
    let tripReports: [PTTripReport]
    let profile: PTMotorcycleProfile?
    let twin: PTVehicleTwinSnapshot
    let now: Date
}

nonisolated enum PTVehicleIntelligenceAnalyzer {
    static let evaluatedRuleCount = 10

    static func make(input: PTVehicleIntelligenceInput) -> PTVehicleIntelligenceSummary {
        let health = input.healthPoints
            .filter { $0.vehicleID == input.vehicleID }
            .sorted { $0.capturedAt < $1.capturedAt }
        let realHealth = health.filter { !$0.isSynthetic }
        let realRoad = input.roadSegments
            .filter { $0.vehicleID == input.vehicleID && !$0.isSynthetic }
            .sorted { $0.endedAt < $1.endedAt }
        let vehicleTrips = input.tripReports
            .filter { $0.vehicleID == input.vehicleID }
            .sorted { $0.endTime < $1.endTime }

        var insights: [PTVehicleIntelligenceInsight] = []
        var suppressed: [String] = []

        appendBatteryInsights(
            health: health,
            realHealth: realHealth,
            now: input.now,
            insights: &insights,
            suppressed: &suppressed
        )
        appendEngineBaseline(
            realHealth: realHealth,
            now: input.now,
            insights: &insights,
            suppressed: &suppressed
        )
        appendDiagnosticInsights(
            realHealth: realHealth,
            now: input.now,
            insights: &insights,
            suppressed: &suppressed
        )
        let maintenanceRemaining = appendMaintenanceInsight(
            health: realHealth,
            profile: input.profile,
            now: input.now,
            insights: &insights,
            suppressed: &suppressed
        )
        appendRideInsights(
            trips: vehicleTrips,
            now: input.now,
            insights: &insights,
            suppressed: &suppressed
        )
        appendRoadInsights(
            segments: realRoad,
            vehicleID: input.vehicleID,
            now: input.now,
            insights: &insights,
            suppressed: &suppressed
        )
        appendConfirmedSemanticInsights(
            twin: input.twin,
            now: input.now,
            insights: &insights,
            suppressed: &suppressed
        )

        let activeInsights = deduplicated(insights, now: input.now)
        let actionableCount = activeInsights.filter { $0.isActionable }.count
        let state: PTVehicleIntelligenceSeverity
        if let highest = activeInsights
            .filter({ $0.isActionable })
            .map(\.severity)
            .max(by: { $0.rawValue < $1.rawValue }) {
            state = highest
        } else if !activeInsights.isEmpty {
            state = .observe
        } else if !realHealth.isEmpty || !realRoad.isEmpty || !vehicleTrips.isEmpty {
            state = .healthy
        } else {
            state = .unknown
        }

        return PTVehicleIntelligenceSummary(
            vehicleID: input.vehicleID,
            generatedAt: input.now,
            overallState: state,
            insights: activeInsights,
            evidenceCount: activeInsights.reduce(0) { partial, insight in
                partial + insight.evidence.reduce(0) { $0 + $1.sampleCount }
            },
            lastRideAt: vehicleTrips.last?.endTime,
            maintenanceRemainingKm: maintenanceRemaining,
            falsePositiveReview: PTVehicleIntelligenceReview(
                evaluatedRuleCount: evaluatedRuleCount,
                actionableInsightCount: actionableCount,
                suppressedRuleIDs: suppressed
            )
        )
    }

    private static func appendBatteryInsights(
        health: [PTVehicleHealthPoint],
        realHealth: [PTVehicleHealthPoint],
        now: Date,
        insights: inout [PTVehicleIntelligenceInsight],
        suppressed: inout [String]
    ) {
        let allSamples = health.compactMap { point -> (date: Date, value: Double, synthetic: Bool)? in
            let value = point.crankVoltage ?? point.restingVoltage ?? point.batteryVoltage
            guard let value, value.isFinite, value > 0 else { return nil }
            return (point.capturedAt, value, point.isSynthetic)
        }.sorted { $0.date < $1.date }
        let realSamples = realHealth.compactMap { point -> (date: Date, value: Double)? in
            let value = point.crankVoltage ?? point.restingVoltage ?? point.batteryVoltage
            guard let value, value.isFinite, value > 0 else { return nil }
            return (point.capturedAt, value)
        }.sorted { $0.date < $1.date }

        if realSamples.count < 6 {
            suppressed.append("battery.crank.trend.insufficient-samples")
        }

        if realSamples.count >= 6 {
            let window = Array(realSamples.suffix(6))
            let nonIncreasingTransitions = zip(window, window.dropFirst()).filter { $0.value >= $1.value }.count
            if nonIncreasingTransitions >= 4, let first = window.first, let latest = window.last, latest.value < first.value {
                insights.append(
                    PTVehicleIntelligenceInsight(
                        id: "battery.crank.trend",
                        kind: .batteryTrend,
                        titleKey: "obd_diagnostic_battery",
                        severity: .attention,
                        primaryValue: latest.value,
                        secondaryValue: first.value,
                        sampleCount: window.count,
                        evidence: [evidence(
                            source: .healthTimeline,
                            dates: window.map(\.date),
                            count: window.count,
                            quality: .observed,
                            note: "Six real startup voltage observations show a mostly non-increasing trend."
                        )],
                        generatedAt: now,
                        isActionable: true
                    )
                )
                return
            }
        }

        guard let latest = realSamples.last else {
            if allSamples.contains(where: { $0.synthetic }) {
                suppressed.append("battery.low.synthetic-only")
            }
            return
        }
        guard latest.value < 10.0, latest.value >= 6.0 else { return }
        insights.append(
            PTVehicleIntelligenceInsight(
                id: "battery.low-voltage",
                kind: .batteryLow,
                titleKey: "obd_diagnostic_battery",
                severity: .attention,
                primaryValue: latest.value,
                sampleCount: 1,
                evidence: [evidence(
                    source: .healthTimeline,
                    dates: [latest.date],
                    count: 1,
                    quality: .observed,
                    note: "The latest real startup or resting voltage is below the observation threshold."
                )],
                generatedAt: now,
                isActionable: true
            )
        )
    }

    private static func appendEngineBaseline(
        realHealth: [PTVehicleHealthPoint],
        now: Date,
        insights: inout [PTVehicleIntelligenceInsight],
        suppressed: inout [String]
    ) {
        let samples = realHealth.compactMap { point in
            point.idleRPM.map { (date: point.capturedAt, value: $0) }
        }
        guard samples.count >= 3 else {
            suppressed.append("engine.idle.baseline.insufficient-samples")
            return
        }
        let values = samples.map(\.value)
        let average = values.reduce(0, +) / Double(values.count)
        insights.append(
            PTVehicleIntelligenceInsight(
                id: "engine.idle.baseline",
                kind: .engineBaseline,
                titleKey: "ride_dna_engine",
                severity: .observe,
                primaryValue: average,
                secondaryValue: values.max(),
                sampleCount: values.count,
                evidence: [evidence(
                    source: .healthTimeline,
                    dates: samples.map(\.date),
                    count: samples.count,
                    quality: .observed,
                    note: "Observed idle RPM baseline; no factory fault threshold is asserted."
                )],
                generatedAt: now,
                isActionable: false
            )
        )
    }

    private static func appendDiagnosticInsights(
        realHealth: [PTVehicleHealthPoint],
        now: Date,
        insights: inout [PTVehicleIntelligenceInsight],
        suppressed: inout [String]
    ) {
        guard let point = realHealth.reversed().first(where: {
            $0.confirmedDTCCount != nil || $0.pendingDTCCount != nil || $0.permanentDTCCount != nil
        }) else {
            suppressed.append("diagnostic.no-confirmed-snapshot")
            return
        }
        let confirmed = max(point.confirmedDTCCount ?? 0, 0)
        let pending = max(point.pendingDTCCount ?? 0, 0)
        let permanent = max(point.permanentDTCCount ?? 0, 0)
        if confirmed > 0 {
            insights.append(
                diagnosticInsight(
                    id: "diagnostic.confirmed-dtc",
                    kind: .confirmedDTC,
                    count: confirmed,
                    severity: .critical,
                    point: point,
                    quality: .confirmed,
                    now: now,
                    actionable: true
                )
            )
        }
        if pending + permanent > 0 {
            insights.append(
                diagnosticInsight(
                    id: "diagnostic.pending-dtc",
                    kind: .pendingDTC,
                    count: pending + permanent,
                    severity: .attention,
                    point: point,
                    quality: .observed,
                    now: now,
                    actionable: true
                )
            )
        }
        if confirmed == 0, pending == 0, permanent == 0 {
            suppressed.append("diagnostic.empty-dtc-snapshot")
        }
    }

    private static func diagnosticInsight(
        id: String,
        kind: PTVehicleIntelligenceInsightKind,
        count: Int,
        severity: PTVehicleIntelligenceSeverity,
        point: PTVehicleHealthPoint,
        quality: PTVehicleIntelligenceEvidenceQuality,
        now: Date,
        actionable: Bool
    ) -> PTVehicleIntelligenceInsight {
        PTVehicleIntelligenceInsight(
            id: id,
            kind: kind,
            titleKey: "obd_diagnostic_dtcs",
            severity: severity,
            primaryValue: Double(count),
            sampleCount: 1,
            evidence: [evidence(
                source: .diagnostic,
                dates: [point.capturedAt],
                count: 1,
                quality: quality,
                note: "Structured diagnostic counts from the latest real diagnostic snapshot."
            )],
            generatedAt: now,
            isActionable: actionable
        )
    }

    private static func appendRideInsights(
        trips: [PTTripReport],
        now: Date,
        insights: inout [PTVehicleIntelligenceInsight],
        suppressed: inout [String]
    ) {
        guard let latest = trips.last else {
            suppressed.append("ride.last.no-report")
            return
        }
        let history = Array(trips.dropLast().suffix(10))
        let dna = PTRideDNABuilder.make(report: latest, comparisonPool: history, generatedAt: now)
        let rideExpiry = latest.endTime.addingTimeInterval(24 * 60 * 60)
        insights.append(
            PTVehicleIntelligenceInsight(
                id: "ride.last-summary",
                kind: .lastRide,
                titleKey: "ride_analysis_history",
                severity: .observe,
                primaryValue: latest.distanceKm,
                secondaryValue: latest.maxSpeedKmh,
                sampleCount: max(dna.sampleCount, 1),
                evidence: [
                    evidence(
                        source: .trip,
                        dates: [latest.startTime, latest.endTime],
                        count: 1,
                        quality: .observed,
                        note: "Latest completed trip report for the selected vehicle."
                    ),
                    evidence(
                        source: .rideDNA,
                        dates: [dna.generatedAt, dna.generatedAt],
                        count: max(dna.sampleCount, 1),
                        quality: .inferred,
                        note: "Ride DNA is descriptive and is not a mechanical fault diagnosis."
                    )
                ],
                generatedAt: now,
                expiresAt: rideExpiry,
                isActionable: false
            )
        )

        let reviewMarkers = dna.markers.filter {
            $0.severity >= 0.7 && [.highRPM, .strongImpact, .roughRoad].contains($0.kind)
        }
        guard let marker = reviewMarkers.max(by: { $0.severity < $1.severity }) else { return }
        insights.append(
            PTVehicleIntelligenceInsight(
                id: "ride.review.\(marker.kind.rawValue)",
                kind: .rideReview,
                titleKey: "ride_dna_title",
                severity: .observe,
                primaryValue: marker.value,
                secondaryValue: marker.severity,
                sampleCount: max(dna.sampleCount, 1),
                evidence: [evidence(
                    source: .rideDNA,
                    dates: [latest.startTime, latest.endTime],
                    count: max(dna.sampleCount, 1),
                    quality: .inferred,
                    note: "A high-severity descriptive ride marker needs human review before any conclusion."
                )],
                generatedAt: now,
                expiresAt: rideExpiry,
                isActionable: false
            )
        )
    }

    private static func appendRoadInsights(
        segments: [PTRoadSurfaceSegment],
        vehicleID: UUID,
        now: Date,
        insights: inout [PTVehicleIntelligenceInsight],
        suppressed: inout [String]
    ) {
        guard !segments.isEmpty else {
            suppressed.append("road.summary.no-real-segment")
            return
        }
        let summary = PTRoadSurfaceAnalyzer.summary(for: segments, vehicleID: vehicleID, now: now)
        guard summary.roughSegmentCount > 0 || summary.severeSegmentCount > 0 || (summary.maximumVerticalImpactG ?? 0) >= 1.25 else {
            return
        }
        let roadExpiry = (summary.latestSegmentAt ?? segments.last?.endedAt ?? now)
            .addingTimeInterval(24 * 60 * 60)
        insights.append(
            PTVehicleIntelligenceInsight(
                id: "road.latest-summary",
                kind: .roadSummary,
                titleKey: "road_surface_intelligence",
                severity: .observe,
                primaryValue: summary.maximumVerticalImpactG,
                secondaryValue: Double(summary.roughSegmentCount + summary.severeSegmentCount),
                sampleCount: summary.sampleCount,
                evidence: [evidence(
                    source: .roadSurface,
                    dates: segments.map(\.endedAt),
                    count: summary.sampleCount,
                    quality: .inferred,
                    note: "Road surface evidence describes ride comfort and is not a vehicle fault signal."
                )],
                generatedAt: now,
                expiresAt: roadExpiry,
                isActionable: false
            )
        )
    }

    private static func appendConfirmedSemanticInsights(
        twin: PTVehicleTwinSnapshot,
        now: Date,
        insights: inout [PTVehicleIntelligenceInsight],
        suppressed: inout [String]
    ) {
        guard let abs = twin.absState else {
            suppressed.append("semantic.abs.no-value")
            return
        }
        guard abs.source == .xp400BLE, abs.freshness == .fresh, !abs.isSynthetic else {
            if abs.value == .warning {
                suppressed.append("semantic.abs-warning.unconfirmed")
            }
            return
        }
        guard abs.value == .warning else { return }
        insights.append(
            PTVehicleIntelligenceInsight(
                id: "semantic.abs-warning",
                kind: .absWarning,
                titleKey: "vehicle_intelligence_abs_warning",
                severity: .attention,
                sampleCount: 1,
                evidence: [evidence(
                    source: .confirmedSemanticState,
                    dates: [abs.capturedAt],
                    count: 1,
                    quality: .confirmed,
                    note: "Fresh, non-synthetic ABS state from the confirmed XP400 BLE semantic projection."
                )],
                generatedAt: now,
                isActionable: false
            )
        )
    }

    private static func appendMaintenanceInsight(
        health: [PTVehicleHealthPoint],
        profile: PTMotorcycleProfile?,
        now: Date,
        insights: inout [PTVehicleIntelligenceInsight],
        suppressed: inout [String]
    ) -> Double? {
        let remaining: Double?
        if let dashboardDistance = profile?.dashboardMaintenanceDistanceKm {
            remaining = Double(dashboardDistance)
        } else if let profile {
            remaining = profile.maintenanceRecords
                .compactMap { record in
                    record.nextDueMileageKm.map { $0 - profile.odometerKm }
                }
                .min()
        } else {
            remaining = health.reversed().compactMap(\.maintenanceDistanceKm).first
        }
        guard let remaining, remaining.isFinite else {
            suppressed.append("maintenance.no-distance")
            return nil
        }
        let warning = profile?.maintenanceWarningDistanceKm ?? 500
        guard remaining <= warning else { return remaining }
        let date = profile?.updatedAt ?? health.last?.capturedAt ?? now
        insights.append(
            PTVehicleIntelligenceInsight(
                id: remaining <= 0 ? "maintenance.due" : "maintenance.due-soon",
                kind: .maintenance,
                titleKey: "garage_maintenance",
                severity: remaining <= 0 ? .attention : .observe,
                primaryValue: remaining,
                sampleCount: 1,
                evidence: [evidence(
                    source: .maintenance,
                    dates: [date],
                    count: 1,
                    quality: .observed,
                    note: "Maintenance distance comes from the selected vehicle garage record."
                )],
                generatedAt: now,
                isActionable: false
            )
        )
        return remaining
    }

    private static func deduplicated(
        _ insights: [PTVehicleIntelligenceInsight],
        now: Date
    ) -> [PTVehicleIntelligenceInsight] {
        var byID: [String: PTVehicleIntelligenceInsight] = [:]
        for insight in insights {
            if let expiresAt = insight.expiresAt, expiresAt <= now { continue }
            guard insight.evidence.contains(where: { $0.quality != .syntheticExcluded && $0.sampleCount > 0 }) else { continue }
            if let existing = byID[insight.id], existing.severity.rawValue > insight.severity.rawValue { continue }
            byID[insight.id] = insight
        }
        return byID.values.sorted {
            if $0.severity.rawValue != $1.severity.rawValue {
                return $0.severity.rawValue > $1.severity.rawValue
            }
            return $0.generatedAt > $1.generatedAt
        }
    }

    private static func evidence(
        source: PTVehicleIntelligenceEvidenceSource,
        dates: [Date],
        count: Int,
        quality: PTVehicleIntelligenceEvidenceQuality,
        note: String
    ) -> PTVehicleIntelligenceEvidence {
        let fallback = dates.first ?? .distantPast
        return PTVehicleIntelligenceEvidence(
            source: source,
            windowStart: dates.min() ?? fallback,
            windowEnd: dates.max() ?? fallback,
            sampleCount: count,
            quality: quality,
            note: note
        )
    }
}

nonisolated enum PTVehicleIntelligenceNotificationPolicy {
    static func eligibleInsights(from summary: PTVehicleIntelligenceSummary) -> [PTVehicleIntelligenceInsight] {
        summary.insights.filter { insight in
            guard insight.isActionable, !insight.isSynthetic else { return false }
            guard insight.kind != .maintenance else { return false }
            return insight.evidence.contains { $0.quality.mayNotify && $0.sampleCount > 0 }
        }
    }
}

// EN: The repository debounces only derived analysis; it never changes polling, pairing, or YMOBD sequencing.
// ES: El repositorio solo agrupa el análisis derivado; nunca cambia el sondeo, el emparejamiento ni la secuencia YMOBD.
// 中文：仓库只对派生分析做防抖，不改变轮询、配对或 YMOBD 时序。
@MainActor
final class PTVehicleIntelligenceRepository: NSObject {
    static let shared = PTVehicleIntelligenceRepository()
    static let didChange = Notification.Name("PTVehicleIntelligenceRepository.didChange")

    private(set) var lastSummary: PTVehicleIntelligenceSummary?
    private var summaries: [UUID: PTVehicleIntelligenceSummary] = [:]
    private var recomputeTask: Task<Void, Never>?
    private var didStart = false
    private var lastNotificationSignature = ""

    private override init() {
        super.init()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        PTVehicleHealthRepository.shared.start()
        PTRoadSurfaceRepository.shared.start()
        let names: [Notification.Name] = [
            PTVehicleHealthRepository.didChange,
            PTRoadSurfaceRepository.didChange,
            PTMotorcycleGarageStore.didChangeNotification,
            MotorcycleTripReportGenerated,
            PTBuild68DiagnosticCoordinator.didChange,
            PTVehicleConnectivityCoordinator.telemetryDidChange
        ]
        for name in names {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(sourceDidChange),
                name: name,
                object: nil
            )
        }
        scheduleRecompute()
    }

    func summary(for vehicleID: UUID) -> PTVehicleIntelligenceSummary? {
        if !didStart {
            start()
        }
        let now = Date()
        if let cached = summaries[vehicleID],
           !cached.insights.contains(where: { $0.expiresAt.map { $0 <= now } == true }) {
            return cached
        }
        let summary = makeSummary(for: vehicleID, now: now)
        summaries[vehicleID] = summary
        lastSummary = summary
        return summary
    }

    @objc private func sourceDidChange() {
        scheduleRecompute()
    }

    private func scheduleRecompute() {
        recomputeTask?.cancel()
        recomputeTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.recomputeCurrent()
        }
    }

    private func recomputeCurrent() {
        guard let vehicleID = PTVehicleConnectivityCoordinator.shared.dashboardGarageVehicleID
                ?? PTMotorcycleGarageStore.shared.selectedVehicleID else {
            lastSummary = nil
            return
        }
        let summary = makeSummary(for: vehicleID, now: Date())
        summaries[vehicleID] = summary
        lastSummary = summary
        scheduleNotifications(for: summary)
        NotificationCenter.default.post(
            name: Self.didChange,
            object: self,
            userInfo: ["vehicleID": vehicleID]
        )
    }

    private func makeSummary(for vehicleID: UUID, now: Date) -> PTVehicleIntelligenceSummary {
        let input = PTVehicleIntelligenceInput(
            vehicleID: vehicleID,
            healthPoints: PTVehicleHealthRepository.shared.points(for: vehicleID),
            roadSegments: PTRoadSurfaceRepository.shared.segments(for: vehicleID),
            tripReports: Array(PTTripManager.shared.tripHistory.prefix(48)),
            profile: PTMotorcycleGarageStore.shared.vehicle(id: vehicleID),
            twin: PTVehicleTwinStateMapper.makeCurrent(now: now),
            now: now
        )
        return PTVehicleIntelligenceAnalyzer.make(input: input)
    }

    private func scheduleNotifications(for summary: PTVehicleIntelligenceSummary) {
        let eligible = PTVehicleIntelligenceNotificationPolicy.eligibleInsights(from: summary)
        let signature = [summary.vehicleID.uuidString]
            + eligible.map { "\($0.id):\($0.severity.rawValue):\($0.primaryValue ?? 0)" }
        let notificationSignature = signature.joined(separator: "|")
        guard notificationSignature != lastNotificationSignature else { return }
        lastNotificationSignature = notificationSignature

        for insight in eligible {
            let title: String
            let body: String
            switch insight.kind {
            case .batteryTrend, .batteryLow:
                title = "⚠️" + PTDashboardConfig.languageFunc(text: "batt_warning_title")
                body = PTDashboardConfig.language(key: "batt_warning_msg", insight.primaryValue ?? 0)
            case .confirmedDTC, .pendingDTC:
                title = PTDashboardConfig.languageFunc(text: "obd_diagnostic_notification_title")
                body = PTDashboardConfig.languageFunc(text: "obd_diagnostic_notification_body")
            default:
                continue
            }
            PTNotificationCenter.schedule(
                PTNotificationRequest(
                    kind: .diagnostic,
                    title: title,
                    body: body,
                    identifier: "pt.notification.intelligence.\(summary.vehicleID.uuidString).\(insight.id)",
                    deduplicationKey: "vehicle-intelligence-\(summary.vehicleID.uuidString)-\(insight.id)",
                    cooldown: 24 * 60 * 60,
                    categoryIdentifier: PTNotificationCenter.diagnosticCategoryIdentifier,
                    userInfo: [
                        "pt_notification_kind": PTAppNotificationKind.diagnostic.rawValue,
                        "pt_vehicle_id": summary.vehicleID.uuidString,
                        "pt_insight_id": insight.id
                    ]
                )
            )
        }
    }
}
