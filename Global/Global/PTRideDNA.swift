//
//  PTRideDNA.swift
//  CrazyDashboard
//
//  EN: Deterministic Ride DNA features derived from the persisted trip report.
//  ES: Características deterministas del ADN de la ruta derivadas del informe persistido.
//  中文：基于持久化行程报告生成确定性的 Ride DNA 特征。
//

import Foundation

// EN: Coverage is intentionally evidence-based; missing source metadata is never presented as confirmed.
// ES: La cobertura se basa intencionadamente en evidencias; la falta de metadatos nunca se presenta como confirmada.
// 中文：覆盖率严格基于证据，缺失来源元数据时不会伪装成已确认。
public nonisolated enum PTRideDNACoverageState: String, Codable, CaseIterable, Equatable, Sendable {
    case confirmed
    case inferred
    case unavailable
}

public nonisolated struct PTRideDNAHistogramBucket: Codable, Equatable, Sendable {
    public let label: String
    public let lowerBound: Double
    public let upperBound: Double?
    public let count: Int
    public let fraction: Double

    public init(label: String,
                lowerBound: Double,
                upperBound: Double?,
                count: Int,
                fraction: Double) {
        self.label = label
        self.lowerBound = lowerBound.isFinite ? lowerBound : 0
        self.upperBound = upperBound?.isFinite == true ? upperBound : nil
        self.count = max(count, 0)
        self.fraction = min(max(fraction.isFinite ? fraction : 0, 0), 1)
    }
}

public nonisolated struct PTRideDNAPace: Codable, Equatable, Sendable {
    public let movingDurationSeconds: TimeInterval
    public let stopDurationSeconds: TimeInterval
    public let averageMovingSpeedKmh: Double
    public let cruiseRatio: Double

    public init(movingDurationSeconds: TimeInterval,
                stopDurationSeconds: TimeInterval,
                averageMovingSpeedKmh: Double,
                cruiseRatio: Double) {
        self.movingDurationSeconds = max(movingDurationSeconds.isFinite ? movingDurationSeconds : 0, 0)
        self.stopDurationSeconds = max(stopDurationSeconds.isFinite ? stopDurationSeconds : 0, 0)
        self.averageMovingSpeedKmh = max(averageMovingSpeedKmh.isFinite ? averageMovingSpeedKmh : 0, 0)
        self.cruiseRatio = min(max(cruiseRatio.isFinite ? cruiseRatio : 0, 0), 1)
    }
}

public nonisolated struct PTRideDNAEngine: Codable, Equatable, Sendable {
    public let rpmHistogram: [PTRideDNAHistogramBucket]
    public let idleRatio: Double
    public let highRPMDurationSeconds: TimeInterval
    public let averageRPM: Double?
    public let maximumRPM: Int

    public init(rpmHistogram: [PTRideDNAHistogramBucket],
                idleRatio: Double,
                highRPMDurationSeconds: TimeInterval,
                averageRPM: Double?,
                maximumRPM: Int) {
        self.rpmHistogram = rpmHistogram
        self.idleRatio = min(max(idleRatio.isFinite ? idleRatio : 0, 0), 1)
        self.highRPMDurationSeconds = max(highRPMDurationSeconds.isFinite ? highRPMDurationSeconds : 0, 0)
        if let averageRPM, averageRPM.isFinite, averageRPM > 0 {
            self.averageRPM = averageRPM
        } else {
            self.averageRPM = nil
        }
        self.maximumRPM = max(maximumRPM, 0)
    }
}

public nonisolated struct PTRideDNAMotion: Codable, Equatable, Sendable {
    public let leanDistribution: [PTRideDNAHistogramBucket]
    public let decelerationEventCount: Int
    public let gDistribution: [PTRideDNAHistogramBucket]
    public let maximumLeanDegrees: Double

    public init(leanDistribution: [PTRideDNAHistogramBucket],
                decelerationEventCount: Int,
                gDistribution: [PTRideDNAHistogramBucket],
                maximumLeanDegrees: Double) {
        self.leanDistribution = leanDistribution
        self.decelerationEventCount = max(decelerationEventCount, 0)
        self.gDistribution = gDistribution
        self.maximumLeanDegrees = max(maximumLeanDegrees.isFinite ? maximumLeanDegrees : 0, 0)
    }
}

public nonisolated struct PTRideDNARoad: Codable, Equatable, Sendable {
    public let roughDurationSeconds: TimeInterval
    public let impactCount: Int
    public let roughSampleCount: Int
    public let maximumImpactG: Double

    public init(roughDurationSeconds: TimeInterval,
                impactCount: Int,
                roughSampleCount: Int,
                maximumImpactG: Double) {
        self.roughDurationSeconds = max(roughDurationSeconds.isFinite ? roughDurationSeconds : 0, 0)
        self.impactCount = max(impactCount, 0)
        self.roughSampleCount = max(roughSampleCount, 0)
        self.maximumImpactG = abs(maximumImpactG.isFinite ? maximumImpactG : 0)
    }
}

public nonisolated struct PTRideDNAEfficiency: Codable, Equatable, Sendable {
    public let consumptionLPer100Km: Double?
    public let distanceKm: Double
    public let distancePerMovingHourKm: Double
    public let idlePenaltyRatio: Double

    public init(consumptionLPer100Km: Double?,
                distanceKm: Double,
                distancePerMovingHourKm: Double,
                idlePenaltyRatio: Double) {
        if let consumptionLPer100Km, consumptionLPer100Km.isFinite, consumptionLPer100Km > 0 {
            self.consumptionLPer100Km = consumptionLPer100Km
        } else {
            self.consumptionLPer100Km = nil
        }
        self.distanceKm = max(distanceKm.isFinite ? distanceKm : 0, 0)
        self.distancePerMovingHourKm = max(distancePerMovingHourKm.isFinite ? distancePerMovingHourKm : 0, 0)
        self.idlePenaltyRatio = min(max(idlePenaltyRatio.isFinite ? idlePenaltyRatio : 0, 0), 1)
    }
}

public nonisolated struct PTRideDNACoverage: Codable, Equatable, Sendable {
    public let xp400: PTRideDNACoverageState
    public let obd: PTRideDNACoverageState
    public let gps: PTRideDNACoverageState
    public let motion: PTRideDNACoverageState
    public let evidenceNotes: [String]

    public init(xp400: PTRideDNACoverageState,
                obd: PTRideDNACoverageState,
                gps: PTRideDNACoverageState,
                motion: PTRideDNACoverageState,
                evidenceNotes: [String] = []) {
        self.xp400 = xp400
        self.obd = obd
        self.gps = gps
        self.motion = motion
        self.evidenceNotes = evidenceNotes
    }
}

public nonisolated struct PTRideDNAHistoryComparison: Codable, Equatable, Sendable {
    public let metricKey: String
    public let currentValue: Double
    public let historicalAverage: Double
    public let delta: Double
    public let sampleCount: Int

    public init(metricKey: String,
                currentValue: Double,
                historicalAverage: Double,
                delta: Double,
                sampleCount: Int) {
        self.metricKey = metricKey
        self.currentValue = currentValue.isFinite ? currentValue : 0
        self.historicalAverage = historicalAverage.isFinite ? historicalAverage : 0
        self.delta = delta.isFinite ? delta : 0
        self.sampleCount = max(sampleCount, 0)
    }
}

public nonisolated enum PTRideDNAMarkerKind: String, Codable, CaseIterable, Sendable {
    case highRPM
    case strongImpact
    case largestLean
    case longestIdle
    case roughRoad
}

public nonisolated struct PTRideDNATimelineMarker: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: PTRideDNAMarkerKind
    public let titleKey: String
    public let offsetSeconds: TimeInterval
    public let value: Double
    public let severity: Double

    public init(id: String,
                kind: PTRideDNAMarkerKind,
                titleKey: String,
                offsetSeconds: TimeInterval,
                value: Double,
                severity: Double) {
        self.id = id
        self.kind = kind
        self.titleKey = titleKey
        self.offsetSeconds = max(offsetSeconds.isFinite ? offsetSeconds : 0, 0)
        self.value = value.isFinite ? value : 0
        self.severity = min(max(severity.isFinite ? severity : 0, 0), 1)
    }
}

public nonisolated struct PTRideDNA: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let reportID: String
    public let vehicleID: UUID?
    public let generatedAt: Date
    public let pace: PTRideDNAPace
    public let engine: PTRideDNAEngine
    public let motion: PTRideDNAMotion
    public let road: PTRideDNARoad
    public let efficiency: PTRideDNAEfficiency
    public let coverage: PTRideDNACoverage
    public let historyComparisons: [PTRideDNAHistoryComparison]
    public let markers: [PTRideDNATimelineMarker]
    public let sampleCount: Int
    public let qualityWarning: String?

    public init(schemaVersion: Int = 1,
                reportID: String,
                vehicleID: UUID?,
                generatedAt: Date = Date(),
                pace: PTRideDNAPace,
                engine: PTRideDNAEngine,
                motion: PTRideDNAMotion,
                road: PTRideDNARoad,
                efficiency: PTRideDNAEfficiency,
                coverage: PTRideDNACoverage,
                historyComparisons: [PTRideDNAHistoryComparison],
                markers: [PTRideDNATimelineMarker],
                sampleCount: Int,
                qualityWarning: String? = nil) {
        self.schemaVersion = max(schemaVersion, 1)
        self.reportID = reportID
        self.vehicleID = vehicleID
        self.generatedAt = generatedAt
        self.pace = pace
        self.engine = engine
        self.motion = motion
        self.road = road
        self.efficiency = efficiency
        self.coverage = coverage
        self.historyComparisons = historyComparisons
        self.markers = markers.sorted { $0.offsetSeconds < $1.offsetSeconds }
        self.sampleCount = max(sampleCount, 0)
        self.qualityWarning = qualityWarning
    }
}

// EN: The export document keeps the legacy analysis snapshot and the new DNA schema together.
// ES: El documento de exportación conserva juntos el resumen heredado y el nuevo esquema de ADN.
// 中文：导出文档同时保留旧分析快照与新的 DNA 结构，兼容现有分享流程。
public nonisolated struct PTRideAnalysisExportDocument: Codable, Sendable {
    public let analysis: PTRideAnalysisSnapshot
    public let dna: PTRideDNA

    public init(analysis: PTRideAnalysisSnapshot, dna: PTRideDNA) {
        self.analysis = analysis
        self.dna = dna
    }
}

// EN: B80-01 through B80-05 are pure calculations, so they can run off the main actor and in strict-concurrency tests.
// ES: B80-01 a B80-05 son cálculos puros y pueden ejecutarse fuera del actor principal y en pruebas de concurrencia estricta.
// 中文：B80-01 至 B80-05 是纯计算，可在主 actor 外执行，也能在严格并发测试中复用。
public nonisolated enum PTRideDNABuilder {
    private struct Sample: Sendable {
        let offset: TimeInterval
        let speed: Double
        let rpm: Double
        let lean: Double
        let gX: Double
        let gY: Double
        let gZ: Double
    }

    private struct Run {
        let start: Int
        let end: Int

        var length: Int { end - start + 1 }
        var midpoint: Int { start + (length / 2) }
    }

    public static func make(report: PTTripReport,
                            comparisonPool: [PTTripReport] = [],
                            generatedAt: Date = Date()) -> PTRideDNA {
        let duration = rideDuration(for: report)
        let samples = makeSamples(report: report, duration: duration)
        let pace = makePace(report: report, samples: samples, duration: duration)
        let engine = makeEngine(report: report, samples: samples, duration: duration)
        let motion = makeMotion(report: report, samples: samples)
        let road = makeRoad(report: report, samples: samples, duration: duration)
        let efficiency = makeEfficiency(report: report, pace: pace)
        let coverage = makeCoverage(report: report)
        let comparisons = makeComparisons(report: report, comparisonPool: comparisonPool)
        let markers = makeMarkers(report: report, samples: samples, duration: duration, engine: engine, road: road)
        let hasSamples = !samples.isEmpty

        return PTRideDNA(
            reportID: report.id,
            vehicleID: report.vehicleID,
            generatedAt: generatedAt,
            pace: pace,
            engine: engine,
            motion: motion,
            road: road,
            efficiency: efficiency,
            coverage: coverage,
            historyComparisons: comparisons,
            markers: markers,
            sampleCount: samples.count,
            qualityWarning: hasSamples ? nil : "ride_dna_no_data"
        )
    }

    private static func makeSamples(report: PTTripReport, duration: TimeInterval) -> [Sample] {
        let count = [
            report.speedTrace.count,
            report.rpmTrace.count,
            report.leanAngleTrace.count,
            report.gForceXTrace.count,
            report.gForceYTrace.count,
            report.gForceZTrace.count
        ].max() ?? 0
        guard count > 0 else { return [] }

        return (0..<count).map { index in
            let fraction = count > 1 ? Double(index) / Double(count - 1) : 0
            return Sample(
                offset: duration * fraction,
                speed: max(value(report.speedTrace, index: index, count: count), 0),
                rpm: max(value(report.rpmTrace.map(Double.init), index: index, count: count), 0),
                lean: value(report.leanAngleTrace, index: index, count: count),
                gX: value(report.gForceXTrace, index: index, count: count),
                gY: value(report.gForceYTrace, index: index, count: count),
                gZ: value(report.gForceZTrace, index: index, count: count)
            )
        }
    }

    private static func makePace(report: PTTripReport,
                                 samples: [Sample],
                                 duration: TimeInterval) -> PTRideDNAPace {
        guard !samples.isEmpty else {
            let idle = min(max(finiteNonNegative(report.idleTimeSeconds), 0), duration)
            return PTRideDNAPace(movingDurationSeconds: max(duration - idle, 0),
                                 stopDurationSeconds: idle,
                                 averageMovingSpeedKmh: validPositive(report.gpsAvgSpeedKmh) ?? 0,
                                 cruiseRatio: 0)
        }

        let moving = samples.filter { $0.speed > 2 }
        let cruise = moving.filter { (30...90).contains($0.speed) }.count
        let inferredStop = duration * Double(samples.count - moving.count) / Double(samples.count)
        let storedIdle = min(max(finiteNonNegative(report.idleTimeSeconds), 0), duration)
        let stop = min(max(max(inferredStop, storedIdle), 0), duration)
        let movingDuration = max(duration - stop, 0)
        let averageMovingSpeed = average(moving.map(\.speed)) ?? 0
        return PTRideDNAPace(movingDurationSeconds: movingDuration,
                             stopDurationSeconds: stop,
                             averageMovingSpeedKmh: averageMovingSpeed,
                             cruiseRatio: moving.isEmpty ? 0 : Double(cruise) / Double(moving.count))
    }

    private static func makeEngine(report: PTTripReport,
                                   samples: [Sample],
                                   duration: TimeInterval) -> PTRideDNAEngine {
        let rpmValues = samples.map(\.rpm).filter { $0.isFinite && $0 >= 0 }
        let histogram = makeHistogram(
            values: rpmValues,
            buckets: [
                ("0–1k", 0, 1_000.0),
                ("1–3k", 1_000, 3_000),
                ("3–5k", 3_000, 5_000),
                ("5–7k", 5_000, 7_000),
                ("7k+", 7_000, nil)
            ]
        )
        let maximum = max(report.maxRpm, Int(rpmValues.max() ?? 0))
        let threshold = maximum >= 5_000 ? max(5_000.0, Double(maximum) * 0.8) : .infinity
        let highCount = samples.filter { $0.rpm >= threshold }.count
        let idle = min(max(finiteNonNegative(report.idleTimeSeconds), 0), duration)
        return PTRideDNAEngine(
            rpmHistogram: histogram,
            idleRatio: duration > 0 ? idle / duration : 0,
            highRPMDurationSeconds: samples.isEmpty ? 0 : duration * Double(highCount) / Double(samples.count),
            averageRPM: average(rpmValues),
            maximumRPM: maximum
        )
    }

    private static func makeMotion(report: PTTripReport,
                                   samples: [Sample]) -> PTRideDNAMotion {
        let leanValues = samples.map { abs($0.lean) }.filter(\.isFinite)
        let leanHistogram = makeHistogram(
            values: leanValues,
            buckets: [
                ("0–5°", 0, 5),
                ("5–15°", 5, 15),
                ("15–30°", 15, 30),
                ("30°+", 30, nil)
            ]
        )
        let gValues = samples.map { sqrt($0.gX * $0.gX + $0.gY * $0.gY + $0.gZ * $0.gZ) }
        let gHistogram = makeHistogram(
            values: gValues,
            buckets: [
                ("<0.10G", 0, 0.10),
                ("0.10–0.25G", 0.10, 0.25),
                ("0.25–0.50G", 0.25, 0.50),
                ("0.50G+", 0.50, nil)
            ]
        )
        return PTRideDNAMotion(
            leanDistribution: leanHistogram,
            decelerationEventCount: countThresholdEvents(samples.map(\.gY), threshold: -0.35, direction: .below),
            gDistribution: gHistogram,
            maximumLeanDegrees: max(
                max(abs(finite(report.maxLeanAngleLeft)), abs(finite(report.maxLeanAngleRight))),
                leanValues.max() ?? 0
            )
        )
    }

    private static func makeRoad(report: PTTripReport,
                                 samples: [Sample],
                                 duration: TimeInterval) -> PTRideDNARoad {
        let rough = samples.map { abs($0.gZ) >= 0.18 || abs($0.gX) >= 0.25 || abs($0.gY) >= 0.35 }
        let impactCandidates = countImpactEvents(samples.map(\.gZ))
        let reviewImpacts = report.reviewEvents.filter { $0.type == .heavyBump }.count
        let maximumImpact = max(samples.map { abs($0.gZ) }.max() ?? 0, abs(finite(report.maxBumpG)))
        return PTRideDNARoad(
            roughDurationSeconds: samples.isEmpty ? 0 : duration * Double(rough.filter { $0 }.count) / Double(samples.count),
            impactCount: max(reviewImpacts, impactCandidates),
            roughSampleCount: rough.filter { $0 }.count,
            maximumImpactG: maximumImpact
        )
    }

    private static func makeEfficiency(report: PTTripReport,
                                       pace: PTRideDNAPace) -> PTRideDNAEfficiency {
        let distance = finiteNonNegative(report.distanceKm)
        let movingHours = pace.movingDurationSeconds / 3_600
        return PTRideDNAEfficiency(
            consumptionLPer100Km: report.avgConsumption,
            distanceKm: distance,
            distancePerMovingHourKm: movingHours > 0 ? distance / movingHours : 0,
            idlePenaltyRatio: pace.movingDurationSeconds + pace.stopDurationSeconds > 0
                ? pace.stopDurationSeconds / (pace.movingDurationSeconds + pace.stopDurationSeconds)
                : 0
        )
    }

    private static func makeCoverage(report: PTTripReport) -> PTRideDNACoverage {
        let hasGPS = report.gpxFileName != nil || report.gpsAvgSpeedKmh > 0 || report.gpsMaxSpeedKmh > 0
        let hasMotion = !report.leanAngleTrace.isEmpty || !report.gForceXTrace.isEmpty
            || !report.gForceYTrace.isEmpty || !report.gForceZTrace.isEmpty || !report.pitchTrace.isEmpty
        let hasOdometer = report.distanceSource == .odometer && (report.endOdoKm > 0 || report.startOdoKm > 0)
        let hasRPM = !report.rpmTrace.isEmpty || report.maxRpm > 0
        var notes: [String] = []
        if hasOdometer { notes.append("odometer_source") }
        if hasRPM { notes.append("rpm_trace_source_not_persisted") }
        if hasGPS { notes.append("gpx_or_gps_speed") }
        if hasMotion { notes.append("motion_trace") }

        return PTRideDNACoverage(
            xp400: hasOdometer ? .inferred : .unavailable,
            obd: hasRPM ? .inferred : .unavailable,
            gps: hasGPS ? .confirmed : .unavailable,
            motion: hasMotion ? .confirmed : .unavailable,
            evidenceNotes: notes
        )
    }

    private static func makeComparisons(report: PTTripReport,
                                        comparisonPool: [PTTripReport]) -> [PTRideDNAHistoryComparison] {
        guard let vehicleID = report.vehicleID else { return [] }
        let history = comparisonPool
            .filter {
                $0.id != report.id && $0.vehicleID == vehicleID && $0.startTime < report.startTime
                    && rideDuration(for: $0) > 0 && finiteNonNegative($0.distanceKm) > 0
            }
            .sorted { $0.startTime > $1.startTime }
            .prefix(10)
        guard history.count >= 3 else { return [] }

        let current = historyMetrics(report)
        let historical = history.map(historyMetrics)
        let keys = [
            "averageMovingSpeed",
            "idleRatio",
            "highRPMDuration",
            "roughDuration",
            "impactCount",
            "consumption"
        ]
        return keys.compactMap { key in
            guard let currentValue = current[key] else { return nil }
            let values = historical.compactMap { $0[key] }
            guard !values.isEmpty else { return nil }
            let baseline = values.reduce(0, +) / Double(values.count)
            return PTRideDNAHistoryComparison(metricKey: key,
                                              currentValue: currentValue,
                                              historicalAverage: baseline,
                                              delta: currentValue - baseline,
                                              sampleCount: values.count)
        }
    }

    private static func historyMetrics(_ report: PTTripReport) -> [String: Double] {
        let duration = rideDuration(for: report)
        let samples = makeSamples(report: report, duration: duration)
        let pace = makePace(report: report, samples: samples, duration: duration)
        let engine = makeEngine(report: report, samples: samples, duration: duration)
        let road = makeRoad(report: report, samples: samples, duration: duration)
        var result: [String: Double] = [
            "averageMovingSpeed": pace.averageMovingSpeedKmh,
            "idleRatio": engine.idleRatio,
            "highRPMDuration": engine.highRPMDurationSeconds,
            "roughDuration": road.roughDurationSeconds,
            "impactCount": Double(road.impactCount)
        ]
        if report.avgConsumption.isFinite, report.avgConsumption > 0 {
            let consumption = report.avgConsumption
            result["consumption"] = consumption
        }
        return result
    }

    private static func makeMarkers(report: PTTripReport,
                                    samples: [Sample],
                                    duration: TimeInterval,
                                    engine: PTRideDNAEngine,
                                    road: PTRideDNARoad) -> [PTRideDNATimelineMarker] {
        guard !samples.isEmpty else { return [] }
        var markers: [PTRideDNATimelineMarker] = []
        let threshold = engine.maximumRPM >= 5_000 ? max(5_000.0, Double(engine.maximumRPM) * 0.8) : .infinity

        if let run = longestRun(in: samples, matching: { $0.rpm >= threshold }) {
            markers.append(marker(report: report, kind: .highRPM, offset: samples[run.midpoint].offset,
                                   value: samples[run.start...run.end].map(\.rpm).max() ?? 0,
                                   severity: min(max(engine.highRPMDurationSeconds / max(duration, 1), 0), 1)))
        }

        if let impactIndex = samples.indices.max(by: { abs(samples[$0].gZ) < abs(samples[$1].gZ) }),
           max(abs(samples[impactIndex].gZ), road.maximumImpactG) >= 0.8 {
            let value = max(abs(samples[impactIndex].gZ), road.maximumImpactG)
            markers.append(marker(report: report, kind: .strongImpact, offset: samples[impactIndex].offset,
                                   value: value, severity: min(value / 2, 1)))
        } else if let event = report.reviewEvents.first(where: { $0.type == .heavyBump }) {
            markers.append(marker(report: report, kind: .strongImpact,
                                  offset: boundedOffset(event.timestamp.timeIntervalSince(report.startTime), duration),
                                  value: abs(event.peakValue), severity: min(max(event.severity, 0), 1)))
        }

        if let index = samples.indices.max(by: { abs(samples[$0].lean) < abs(samples[$1].lean) }),
           abs(samples[index].lean) > 0 {
            markers.append(marker(report: report, kind: .largestLean, offset: samples[index].offset,
                                  value: abs(samples[index].lean), severity: min(abs(samples[index].lean) / 60, 1)))
        }

        if let run = longestRun(in: samples, matching: { $0.speed <= 2 }), run.length > 1 {
            let idleDuration = duration * Double(run.length) / Double(samples.count)
            markers.append(marker(report: report, kind: .longestIdle, offset: samples[run.midpoint].offset,
                                  value: idleDuration, severity: min(idleDuration / 120, 1)))
        } else if report.idleTimeSeconds > 0 {
            let idle = min(max(report.idleTimeSeconds, 0), duration)
            markers.append(marker(report: report, kind: .longestIdle,
                                  offset: max(duration - idle / 2, 0), value: idle,
                                  severity: min(idle / 120, 1)))
        }

        if let run = longestRun(in: samples, matching: { abs($0.gZ) >= 0.18 || abs($0.gX) >= 0.25 || abs($0.gY) >= 0.35 }) {
            let roughDuration = duration * Double(run.length) / Double(samples.count)
            markers.append(marker(report: report, kind: .roughRoad, offset: samples[run.midpoint].offset,
                                  value: roughDuration, severity: min(roughDuration / 60, 1)))
        }
        return markers
    }

    private static func marker(report: PTTripReport,
                               kind: PTRideDNAMarkerKind,
                               offset: TimeInterval,
                               value: Double,
                               severity: Double) -> PTRideDNATimelineMarker {
        PTRideDNATimelineMarker(
            id: "(report.id)-(kind.rawValue)",
            kind: kind,
            titleKey: titleKey(for: kind),
            offsetSeconds: max(offset, 0),
            value: value,
            severity: severity
        )
    }

    private static func titleKey(for kind: PTRideDNAMarkerKind) -> String {
        switch kind {
        case .highRPM: return "ride_dna_marker_high_rpm"
        case .strongImpact: return "ride_dna_marker_strong_impact"
        case .largestLean: return "ride_dna_marker_largest_lean"
        case .longestIdle: return "ride_dna_marker_longest_idle"
        case .roughRoad: return "ride_dna_marker_rough_road"
        }
    }

    private static func longestRun(in samples: [Sample], matching predicate: (Sample) -> Bool) -> Run? {
        var best: Run?
        var start: Int?
        for index in samples.indices {
            if predicate(samples[index]) {
                start = start ?? index
            } else if let currentStart = start {
                let candidate = Run(start: currentStart, end: index - 1)
                if best == nil || candidate.length > best!.length { best = candidate }
                start = nil
            }
        }
        if let currentStart = start {
            let candidate = Run(start: currentStart, end: samples.count - 1)
            if best == nil || candidate.length > best!.length { best = candidate }
        }
        return best
    }

    private enum ThresholdDirection { case below, above }

    private static func countThresholdEvents(_ values: [Double],
                                             threshold: Double,
                                             direction: ThresholdDirection) -> Int {
        var count = 0
        var active = false
        for value in values where value.isFinite {
            let matches = direction == .below ? value <= threshold : value >= threshold
            if matches && !active { count += 1 }
            active = matches
        }
        return count
    }

    private static func countImpactEvents(_ values: [Double]) -> Int {
        countThresholdEvents(values.map(abs), threshold: 0.8, direction: .above)
    }

    private static func makeHistogram(values: [Double],
                                      buckets: [(String, Double, Double?)]) -> [PTRideDNAHistogramBucket] {
        let finiteValues = values.filter { $0.isFinite && $0 >= 0 }
        guard !finiteValues.isEmpty else {
            return buckets.map { PTRideDNAHistogramBucket(label: $0.0, lowerBound: $0.1, upperBound: $0.2, count: 0, fraction: 0) }
        }
        return buckets.map { bucket in
            let count = finiteValues.filter { value in
                value >= bucket.1 && (bucket.2 == nil ? true : value < bucket.2!)
            }.count
            return PTRideDNAHistogramBucket(label: bucket.0,
                                            lowerBound: bucket.1,
                                            upperBound: bucket.2,
                                            count: count,
                                            fraction: Double(count) / Double(finiteValues.count))
        }
    }

    private static func rideDuration(for report: PTTripReport) -> TimeInterval {
        let duration = report.endTime.timeIntervalSince(report.startTime)
        return duration.isFinite && duration > 0 ? duration : TimeInterval(max(report.durationMinutes, 0) * 60)
    }

    private static func value<T: BinaryFloatingPoint>(_ values: [T], index: Int, count: Int) -> Double {
        guard !values.isEmpty, count > 0 else { return 0 }
        let sourceIndex = values.count == 1 || count == 1
            ? 0
            : Int((Double(index) / Double(count - 1) * Double(values.count - 1)).rounded())
        guard values.indices.contains(sourceIndex) else { return 0 }
        let value = Double(values[sourceIndex])
        return value.isFinite ? value : 0
    }

    private static func average(_ values: [Double]) -> Double? {
        let finite = values.filter { $0.isFinite && $0 > 0 }
        guard !finite.isEmpty else { return nil }
        let result = finite.reduce(0, +) / Double(finite.count)
        return result.isFinite ? result : nil
    }

    private static func validPositive(_ value: Double) -> Double? {
        value.isFinite && value > 0 ? value : nil
    }

    private static func finite(_ value: Double) -> Double { value.isFinite ? value : 0 }
    private static func finiteNonNegative(_ value: Double) -> Double { max(finite(value), 0) }

    private static func boundedOffset(_ value: TimeInterval, _ duration: TimeInterval) -> TimeInterval {
        min(max(value.isFinite ? value : 0, 0), max(duration, 0))
    }
}
