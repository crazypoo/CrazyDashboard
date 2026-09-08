//
//  PTRideAnalysis.swift
//  CrazyDashboard
//
//  EN: Deterministic ride analysis built from the existing persisted report.
//  ES: Análisis determinista de la ruta construido desde el informe persistido existente.
//  中文：基于现有持久化行程报告生成确定性的骑行分析。
//

import Foundation

// EN: A redacted, Codable snapshot is safe to render, compare and share without exposing route coordinates.
// ES: Un resumen Codable y anonimizado se puede mostrar, comparar y compartir sin exponer coordenadas.
// 中文：脱敏后的 Codable 快照可以用于展示、比较和分享，同时不暴露路线坐标。
nonisolated public struct PTRideAnalysisSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date

    public let durationSeconds: TimeInterval
    public let movingTimeSeconds: TimeInterval
    public let idleTimeSeconds: TimeInterval
    public let idleRatio: Double
    public let distanceKm: Double
    public let startOdoKm: Double
    public let endOdoKm: Double
    public let distanceSource: PTTripDistanceSource

    public let averageSpeedKmh: Double
    public let dashboardMaxSpeedKmh: Double
    public let gpsMinSpeedKmh: Double?
    public let gpsMaxSpeedKmh: Double?
    public let averageRpm: Double?
    public let maxRpm: Int
    public let averageConsumption: Double?
    public let best0To100Time: TimeInterval?

    public let maxLeanLeftDegrees: Double
    public let maxLeanRightDegrees: Double
    public let maxLeanDifferenceDegrees: Double
    public let maxAccelerationG: Double
    public let maxBrakingG: Double
    public let maxCorneringG: Double
    public let maxBumpG: Double
    public let maxPitchUpDegrees: Double
    public let maxPitchDownDegrees: Double

    public let altitudeGainMeters: Double
    public let altitudeLossMeters: Double
    public let altitudeMinMeters: Double?
    public let altitudeMaxMeters: Double?
    public let pressureMinHpa: Double?
    public let pressureMaxHpa: Double?

    public let maxSlipRatio: Double
    public let heavySlipCount: Int
    public let eventCount: Int
    public let offRoadEventCount: Int
    public let eventRatePer100Km: Double?
    public let eventBreakdown: [String: Int]
    public let events: [PTRideAnalysisEvent]
    public let comparisons: [PTRideAnalysisComparison]
    public let quality: PTRideAnalysisQuality

    nonisolated public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        durationSeconds: TimeInterval,
        movingTimeSeconds: TimeInterval,
        idleTimeSeconds: TimeInterval,
        idleRatio: Double,
        distanceKm: Double,
        startOdoKm: Double,
        endOdoKm: Double,
        distanceSource: PTTripDistanceSource,
        averageSpeedKmh: Double,
        dashboardMaxSpeedKmh: Double,
        gpsMinSpeedKmh: Double?,
        gpsMaxSpeedKmh: Double?,
        averageRpm: Double?,
        maxRpm: Int,
        averageConsumption: Double?,
        best0To100Time: TimeInterval?,
        maxLeanLeftDegrees: Double,
        maxLeanRightDegrees: Double,
        maxLeanDifferenceDegrees: Double,
        maxAccelerationG: Double,
        maxBrakingG: Double,
        maxCorneringG: Double,
        maxBumpG: Double,
        maxPitchUpDegrees: Double,
        maxPitchDownDegrees: Double,
        altitudeGainMeters: Double,
        altitudeLossMeters: Double,
        altitudeMinMeters: Double?,
        altitudeMaxMeters: Double?,
        pressureMinHpa: Double?,
        pressureMaxHpa: Double?,
        maxSlipRatio: Double,
        heavySlipCount: Int,
        eventCount: Int,
        offRoadEventCount: Int,
        eventRatePer100Km: Double?,
        eventBreakdown: [String: Int],
        events: [PTRideAnalysisEvent],
        comparisons: [PTRideAnalysisComparison],
        quality: PTRideAnalysisQuality
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.durationSeconds = max(durationSeconds.isFinite ? durationSeconds : 0, 0)
        self.movingTimeSeconds = max(movingTimeSeconds.isFinite ? movingTimeSeconds : 0, 0)
        self.idleTimeSeconds = max(idleTimeSeconds.isFinite ? idleTimeSeconds : 0, 0)
        self.idleRatio = min(max(idleRatio.isFinite ? idleRatio : 0, 0), 1)
        self.distanceKm = max(distanceKm.isFinite ? distanceKm : 0, 0)
        self.startOdoKm = max(startOdoKm.isFinite ? startOdoKm : 0, 0)
        self.endOdoKm = max(endOdoKm.isFinite ? endOdoKm : 0, 0)
        self.distanceSource = distanceSource
        self.averageSpeedKmh = max(averageSpeedKmh.isFinite ? averageSpeedKmh : 0, 0)
        self.dashboardMaxSpeedKmh = max(dashboardMaxSpeedKmh.isFinite ? dashboardMaxSpeedKmh : 0, 0)
        self.gpsMinSpeedKmh = Self.positiveOrNil(gpsMinSpeedKmh)
        self.gpsMaxSpeedKmh = Self.positiveOrNil(gpsMaxSpeedKmh)
        self.averageRpm = Self.positiveOrNil(averageRpm)
        self.maxRpm = max(maxRpm, 0)
        self.averageConsumption = Self.positiveOrNil(averageConsumption)
        self.best0To100Time = Self.positiveOrNil(best0To100Time)
        self.maxLeanLeftDegrees = max(maxLeanLeftDegrees.isFinite ? maxLeanLeftDegrees : 0, 0)
        self.maxLeanRightDegrees = max(maxLeanRightDegrees.isFinite ? maxLeanRightDegrees : 0, 0)
        self.maxLeanDifferenceDegrees = max(maxLeanDifferenceDegrees.isFinite ? maxLeanDifferenceDegrees : 0, 0)
        self.maxAccelerationG = max(maxAccelerationG.isFinite ? maxAccelerationG : 0, 0)
        self.maxBrakingG = max(maxBrakingG.isFinite ? maxBrakingG : 0, 0)
        self.maxCorneringG = max(maxCorneringG.isFinite ? maxCorneringG : 0, 0)
        self.maxBumpG = max(maxBumpG.isFinite ? maxBumpG : 0, 0)
        self.maxPitchUpDegrees = max(maxPitchUpDegrees.isFinite ? maxPitchUpDegrees : 0, 0)
        self.maxPitchDownDegrees = max(maxPitchDownDegrees.isFinite ? maxPitchDownDegrees : 0, 0)
        self.altitudeGainMeters = max(altitudeGainMeters.isFinite ? altitudeGainMeters : 0, 0)
        self.altitudeLossMeters = max(altitudeLossMeters.isFinite ? altitudeLossMeters : 0, 0)
        self.altitudeMinMeters = Self.finiteOrNil(altitudeMinMeters)
        self.altitudeMaxMeters = Self.finiteOrNil(altitudeMaxMeters)
        self.pressureMinHpa = Self.finiteOrNil(pressureMinHpa)
        self.pressureMaxHpa = Self.finiteOrNil(pressureMaxHpa)
        self.maxSlipRatio = max(maxSlipRatio.isFinite ? abs(maxSlipRatio) : 0, 0)
        self.heavySlipCount = max(heavySlipCount, 0)
        self.eventCount = max(eventCount, 0)
        self.offRoadEventCount = max(offRoadEventCount, 0)
        self.eventRatePer100Km = Self.positiveOrNil(eventRatePer100Km)
        self.eventBreakdown = eventBreakdown
        self.events = events.sorted { $0.timestamp < $1.timestamp }
        self.comparisons = comparisons
        self.quality = quality
    }

    private static func finiteOrNil(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func positiveOrNil(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}

nonisolated public struct PTRideAnalysisEvent: Codable, Equatable, Sendable {
    public let kind: String
    public let titleKey: String
    public let timestamp: Date
    public let offsetSeconds: TimeInterval
    public let peakValue: Double
    public let speedKmh: Double
    public let severity: Double

    nonisolated public init(
        kind: String,
        titleKey: String,
        timestamp: Date,
        offsetSeconds: TimeInterval,
        peakValue: Double,
        speedKmh: Double,
        severity: Double
    ) {
        self.kind = kind
        self.titleKey = titleKey
        self.timestamp = timestamp
        self.offsetSeconds = max(offsetSeconds.isFinite ? offsetSeconds : 0, 0)
        self.peakValue = peakValue.isFinite ? peakValue : 0
        self.speedKmh = max(speedKmh.isFinite ? speedKmh : 0, 0)
        self.severity = max(severity.isFinite ? severity : 0, 0)
    }
}

nonisolated public struct PTRideAnalysisComparison: Codable, Equatable, Sendable {
    public let metricKey: String
    public let currentValue: Double
    public let historicalAverage: Double
    public let delta: Double
    public let sampleCount: Int

    nonisolated public init(
        metricKey: String,
        currentValue: Double,
        historicalAverage: Double,
        delta: Double,
        sampleCount: Int
    ) {
        self.metricKey = metricKey
        self.currentValue = currentValue
        self.historicalAverage = historicalAverage
        self.delta = delta
        self.sampleCount = max(sampleCount, 0)
    }
}

nonisolated public struct PTRideAnalysisQuality: Codable, Equatable, Sendable {
    public let reportSchemaVersion: Int
    public let traceSampleCounts: [String: Int]
    public let commonTraceSampleCount: Int
    public let hasTraceLengthMismatch: Bool
    public let hasGPX: Bool
    public let hasVehicleBinding: Bool
    public let warnings: [String]

    nonisolated public init(
        reportSchemaVersion: Int,
        traceSampleCounts: [String: Int],
        commonTraceSampleCount: Int,
        hasTraceLengthMismatch: Bool,
        hasGPX: Bool,
        hasVehicleBinding: Bool,
        warnings: [String]
    ) {
        self.reportSchemaVersion = reportSchemaVersion
        self.traceSampleCounts = traceSampleCounts
        self.commonTraceSampleCount = max(commonTraceSampleCount, 0)
        self.hasTraceLengthMismatch = hasTraceLengthMismatch
        self.hasGPX = hasGPX
        self.hasVehicleBinding = hasVehicleBinding
        self.warnings = warnings
    }
}

// EN: These keys are stable export identifiers; the UI localizes them separately.
// ES: Estas claves son identificadores estables de exportación; la interfaz las localiza por separado.
// 中文：这些键是稳定的导出标识，界面会单独进行本地化。
nonisolated public enum PTRideAnalysisMetricKey {
    public static let distance = "distance"
    public static let averageSpeed = "averageSpeed"
    public static let maxSpeed = "maxSpeed"
    public static let idleRatio = "idleRatio"
    public static let eventRate = "eventRate"
    public static let maxLean = "maxLean"
}

nonisolated public enum PTRideAnalysisQualityWarning {
    public static let noTrace = "noTrace"
    public static let traceLengthMismatch = "traceLengthMismatch"
    public static let missingGPX = "missingGPX"
    public static let unboundVehicle = "unboundVehicle"
}

// EN: The builder only reads PTTripReport values and never sends transport commands.
// ES: El generador solo lee PTTripReport y nunca envía comandos de transporte.
// 中文：构建器只读取 PTTripReport，不会发送任何车辆通信指令。
nonisolated public enum PTRideAnalysisBuilder {
    public static func make(
        report: PTTripReport,
        comparisonPool: [PTTripReport]
    ) -> PTRideAnalysisSnapshot {
        let duration = rideDuration(for: report)
        let idle = min(max(finiteNonNegative(report.idleTimeSeconds), 0), duration)
        let moving = max(duration - idle, 0)
        let distance = finiteNonNegative(report.distanceKm)
        let averageSpeed = validPositive(report.gpsAvgSpeedKmh)
            ?? (duration > 0 ? finiteNonNegative(distance / (duration / 3_600)) : 0)
        let dashboardMaxSpeed = max(
            finiteNonNegative(report.maxSpeedKmh),
            finiteNonNegative(report.gpsMaxSpeedKmh)
        )
        let rpmValues = report.rpmTrace.filter { $0 > 0 }.map(Double.init)
        let averageRpm = average(rpmValues)
        let maxRpm = max(report.maxRpm, report.rpmTrace.max() ?? 0)
        let leftLean = abs(finiteValue(report.maxLeanAngleLeft))
        let rightLean = abs(finiteValue(report.maxLeanAngleRight))
        let elevation = elevationChange(report.relativeAltitudeTrace)
        let pressure = finiteRange(report.pressureTrace)
        let altitude = finiteRange(report.relativeAltitudeTrace)
        let allEvents = makeEvents(report: report)
        let eventCount = allEvents.count
        let eventRate = distance > 0 ? Double(eventCount) / distance * 100 : nil
        let comparisons = makeComparisons(report: report, comparisonPool: comparisonPool)
        let traceCounts = traceSampleCounts(report)
        let nonEmptyCounts = traceCounts.values.filter { $0 > 0 }
        let commonCount = nonEmptyCounts.min() ?? 0
        let hasMismatch = Set(nonEmptyCounts).count > 1
        var warnings: [String] = []
        if nonEmptyCounts.isEmpty {
            warnings.append(PTRideAnalysisQualityWarning.noTrace)
        }
        if hasMismatch {
            warnings.append(PTRideAnalysisQualityWarning.traceLengthMismatch)
        }
        if report.gpxFileName == nil {
            warnings.append(PTRideAnalysisQualityWarning.missingGPX)
        }
        if report.vehicleID == nil {
            warnings.append(PTRideAnalysisQualityWarning.unboundVehicle)
        }

        return PTRideAnalysisSnapshot(
            durationSeconds: duration,
            movingTimeSeconds: moving,
            idleTimeSeconds: idle,
            idleRatio: duration > 0 ? idle / duration : 0,
            distanceKm: distance,
            startOdoKm: finiteNonNegative(report.startOdoKm),
            endOdoKm: finiteNonNegative(report.endOdoKm),
            distanceSource: report.distanceSource,
            averageSpeedKmh: averageSpeed,
            dashboardMaxSpeedKmh: dashboardMaxSpeed,
            gpsMinSpeedKmh: finiteOptional(report.gpsMinSpeedKmh),
            gpsMaxSpeedKmh: finiteOptional(report.gpsMaxSpeedKmh),
            averageRpm: averageRpm,
            maxRpm: maxRpm,
            averageConsumption: finiteOptional(report.avgConsumption),
            best0To100Time: finiteOptional(report.best0To100Time),
            maxLeanLeftDegrees: leftLean,
            maxLeanRightDegrees: rightLean,
            maxLeanDifferenceDegrees: abs(leftLean - rightLean),
            maxAccelerationG: abs(finiteValue(report.maxAccelerationG)),
            maxBrakingG: abs(finiteValue(report.maxBrakingG)),
            maxCorneringG: abs(finiteValue(report.maxCorneringG)),
            maxBumpG: abs(finiteValue(report.maxBumpG)),
            maxPitchUpDegrees: abs(finiteValue(report.maxPitchUp)),
            maxPitchDownDegrees: abs(finiteValue(report.maxPitchDown)),
            altitudeGainMeters: elevation.gain,
            altitudeLossMeters: elevation.loss,
            altitudeMinMeters: altitude.min,
            altitudeMaxMeters: altitude.max,
            pressureMinHpa: pressure.min,
            pressureMaxHpa: pressure.max,
            maxSlipRatio: abs(finiteValue(report.maxSlipRatio)),
            heavySlipCount: max(report.heavySlipCount, 0),
            eventCount: eventCount,
            offRoadEventCount: report.offRoadEvents.count,
            eventRatePer100Km: eventRate,
            eventBreakdown: eventBreakdown(report: report),
            events: allEvents,
            comparisons: comparisons,
            quality: PTRideAnalysisQuality(
                reportSchemaVersion: report.schemaVersion,
                traceSampleCounts: traceCounts,
                commonTraceSampleCount: commonCount,
                hasTraceLengthMismatch: hasMismatch,
                hasGPX: report.gpxFileName != nil,
                hasVehicleBinding: report.vehicleID != nil,
                warnings: warnings
            )
        )
    }

    private static func rideDuration(for report: PTTripReport) -> TimeInterval {
        let timestampDuration = report.endTime.timeIntervalSince(report.startTime)
        if timestampDuration.isFinite, timestampDuration > 0 {
            return timestampDuration
        }
        return TimeInterval(max(report.durationMinutes, 0) * 60)
    }

    private static func makeEvents(report: PTTripReport) -> [PTRideAnalysisEvent] {
        let reviewEvents = report.reviewEvents.map { event in
            PTRideAnalysisEvent(
                kind: "review",
                titleKey: reviewTitleKey(event.type),
                timestamp: event.timestamp,
                offsetSeconds: event.timestamp.timeIntervalSince(report.startTime),
                peakValue: event.peakValue,
                speedKmh: event.speedKmh,
                severity: event.severity
            )
        }
        let offRoadEvents = report.offRoadEvents.map { event in
            PTRideAnalysisEvent(
                kind: "offRoad",
                titleKey: "ride_replay_event_offroad",
                timestamp: event.timestamp,
                offsetSeconds: event.timestamp.timeIntervalSince(report.startTime),
                peakValue: event.slipRatio,
                speedKmh: 0,
                severity: abs(event.slipRatio)
            )
        }
        return (reviewEvents + offRoadEvents).sorted { $0.timestamp < $1.timestamp }
    }

    private static func reviewTitleKey(_ type: PTRideReviewEventType) -> String {
        switch type {
        case .hardBraking: return "ride_replay_event_hard_braking"
        case .hardAcceleration: return "ride_replay_event_hard_acceleration"
        case .heavyBump: return "ride_replay_event_heavy_bump"
        case .highLean: return "ride_replay_event_high_lean"
        case .suspectedSlip: return "ride_replay_event_suspected_slip"
        }
    }

    private static func eventBreakdown(report: PTTripReport) -> [String: Int] {
        var result: [String: Int] = [:]
        for event in report.reviewEvents {
            result[event.type.rawValue, default: 0] += 1
        }
        if !report.offRoadEvents.isEmpty {
            result["offRoad", default: 0] += report.offRoadEvents.count
        }
        return result
    }

    private static func makeComparisons(
        report: PTTripReport,
        comparisonPool: [PTTripReport]
    ) -> [PTRideAnalysisComparison] {
        guard let vehicleID = report.vehicleID else { return [] }
        let history = comparisonPool
            .filter {
                $0.id != report.id &&
                $0.vehicleID == vehicleID &&
                $0.startTime < report.startTime &&
                isValidHistoryReport($0)
            }
            .sorted { $0.startTime > $1.startTime }
            .prefix(10)
        guard history.count >= 3 else { return [] }

        let current = metrics(for: report)
        let historyMetrics = history.map(metrics(for:))
        let keys = [
            PTRideAnalysisMetricKey.distance,
            PTRideAnalysisMetricKey.averageSpeed,
            PTRideAnalysisMetricKey.maxSpeed,
            PTRideAnalysisMetricKey.idleRatio,
            PTRideAnalysisMetricKey.eventRate,
            PTRideAnalysisMetricKey.maxLean
        ]

        return keys.compactMap { key in
            guard let currentValue = current[key] else { return nil }
            let values = historyMetrics.compactMap { $0[key] }
            guard !values.isEmpty else { return nil }
            let baseline = values.reduce(0, +) / Double(values.count)
            return PTRideAnalysisComparison(
                metricKey: key,
                currentValue: currentValue,
                historicalAverage: baseline,
                delta: currentValue - baseline,
                sampleCount: values.count
            )
        }
    }

    private static func isValidHistoryReport(_ report: PTTripReport) -> Bool {
        rideDuration(for: report) > 0 && finiteNonNegative(report.distanceKm) > 0
    }

    private static func metrics(for report: PTTripReport) -> [String: Double] {
        let duration = rideDuration(for: report)
        let distance = finiteNonNegative(report.distanceKm)
        let averageSpeed = validPositive(report.gpsAvgSpeedKmh)
            ?? (duration > 0 ? distance / (duration / 3_600) : 0)
        let maxSpeed = max(finiteNonNegative(report.maxSpeedKmh), finiteNonNegative(report.gpsMaxSpeedKmh))
        let idle = min(max(finiteNonNegative(report.idleTimeSeconds), 0), duration)
        let eventCount = report.reviewEvents.count + report.offRoadEvents.count
        return [
            PTRideAnalysisMetricKey.distance: distance,
            PTRideAnalysisMetricKey.averageSpeed: averageSpeed,
            PTRideAnalysisMetricKey.maxSpeed: maxSpeed,
            PTRideAnalysisMetricKey.idleRatio: duration > 0 ? idle / duration : 0,
            PTRideAnalysisMetricKey.eventRate: distance > 0 ? Double(eventCount) / distance * 100 : 0,
            PTRideAnalysisMetricKey.maxLean: max(abs(finiteValue(report.maxLeanAngleLeft)), abs(finiteValue(report.maxLeanAngleRight)))
        ]
    }

    private static func traceSampleCounts(_ report: PTTripReport) -> [String: Int] {
        [
            "speed": report.speedTrace.count,
            "rpm": report.rpmTrace.count,
            "lean": report.leanAngleTrace.count,
            "gForceX": report.gForceXTrace.count,
            "gForceY": report.gForceYTrace.count,
            "gForceZ": report.gForceZTrace.count,
            "pitch": report.pitchTrace.count,
            "altitude": report.relativeAltitudeTrace.count,
            "pressure": report.pressureTrace.count,
            "slipRatio": report.slipRatioTrace.count
        ]
    }

    private static func elevationChange(_ values: [Double]) -> (gain: Double, loss: Double) {
        guard values.count > 1 else { return (0, 0) }
        var gain = 0.0
        var loss = 0.0
        for (previous, current) in zip(values, values.dropFirst()) {
            guard previous.isFinite, current.isFinite else { continue }
            let delta = current - previous
            if delta > 0 {
                gain += delta
            } else {
                loss += abs(delta)
            }
        }
        return (max(gain, 0), max(loss, 0))
    }

    private static func finiteRange(_ values: [Double]) -> (min: Double?, max: Double?) {
        let finiteValues = values.filter(\.isFinite)
        guard let minValue = finiteValues.min(), let maxValue = finiteValues.max() else {
            return (nil, nil)
        }
        return (minValue, maxValue)
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let result = values.reduce(0, +) / Double(values.count)
        return result.isFinite && result > 0 ? result : nil
    }

    private static func finiteValue(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    private static func finiteNonNegative(_ value: Double) -> Double {
        max(finiteValue(value), 0)
    }

    private static func finiteOptional(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func validPositive(_ value: Double) -> Double? {
        finiteOptional(value)
    }
}

// EN: Shared indices keep multi-line charts visually aligned even when legacy traces have different lengths.
// ES: Los índices compartidos mantienen alineados los gráficos aunque las trazas antiguas tengan longitudes distintas.
// 中文：公共索引让多线图保持对齐，即使旧报告的轨迹长度不一致。
nonisolated public enum PTRideAnalysisDownsampler {
    public static func commonIndices(
        for series: [[Double]],
        maximumCount: Int = 600
    ) -> [Int] {
        guard maximumCount > 0 else { return [] }
        let referenceCount = series.map(\.count).max() ?? 0
        guard referenceCount > 0 else { return [] }
        let targetCount = min(referenceCount, maximumCount)
        guard referenceCount > targetCount else {
            return Array(0..<referenceCount)
        }

        var mandatory = Set([0, referenceCount - 1])
        for values in series {
            guard !values.isEmpty else { continue }
            let finiteIndices = values.indices.filter { values[$0].isFinite }
            if let minIndex = finiteIndices.min(by: { values[$0] < values[$1] }) {
                mandatory.insert(normalizedIndex(minIndex, sourceCount: values.count, referenceCount: referenceCount))
            }
            if let maxIndex = finiteIndices.max(by: { values[$0] < values[$1] }) {
                mandatory.insert(normalizedIndex(maxIndex, sourceCount: values.count, referenceCount: referenceCount))
            }
        }

        if mandatory.count >= targetCount {
            return mandatory.sorted().prefix(targetCount).map { $0 }
        }

        var result = mandatory
        for index in 0..<targetCount {
            if result.count >= targetCount { break }
            let normalized = Double(index) / Double(max(targetCount - 1, 1))
            result.insert(Int((normalized * Double(referenceCount - 1)).rounded()))
        }
        if result.count < targetCount {
            for index in 0..<referenceCount {
                if result.count >= targetCount { break }
                result.insert(index)
            }
        }
        return result.sorted()
    }

    public static func values(
        _ values: [Double],
        at referenceIndices: [Int],
        referenceCount: Int
    ) -> [Double] {
        guard !values.isEmpty, referenceCount > 0 else { return [] }
        if values.count == referenceCount {
            return referenceIndices.compactMap { index in
                guard values.indices.contains(index), values[index].isFinite else { return nil }
                return values[index]
            }
        }
        return referenceIndices.compactMap { referenceIndex in
            let normalized = referenceCount > 1
                ? Double(referenceIndex) / Double(referenceCount - 1)
                : 0
            let sourceIndex = Int((normalized * Double(values.count - 1)).rounded())
            guard values.indices.contains(sourceIndex), values[sourceIndex].isFinite else { return nil }
            return values[sourceIndex]
        }
    }

    private static func normalizedIndex(
        _ index: Int,
        sourceCount: Int,
        referenceCount: Int
    ) -> Int {
        guard sourceCount > 1, referenceCount > 1 else { return 0 }
        let normalized = Double(index) / Double(sourceCount - 1)
        return Int((normalized * Double(referenceCount - 1)).rounded())
    }
}
