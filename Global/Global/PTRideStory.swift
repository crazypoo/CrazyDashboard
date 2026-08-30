//
//  PTRideStory.swift
//  CrazyDashboard
//
//  EN: Deterministic summaries for completed rides and safe offline review.
//  ES: Resúmenes deterministas para rutas terminadas y revisión local segura.
//  中文：为已完成行程提供确定性的本地复盘摘要。
//

import Foundation

public struct PTRideStorySummary: Codable, Equatable, Sendable {
    public let startTime: Date
    public let endTime: Date
    public let durationMinutes: Int
    public let distanceKm: Double
    public let averageSpeedKmh: Double
    public let maxSpeedKmh: Double
    public let maximumLeanAngle: Double
    public let elevationGainMeters: Double
    public let elevationLossMeters: Double
    public let idleTimeSeconds: TimeInterval
    public let best0To100Time: TimeInterval?
    public let eventCount: Int
    public let offRoadEventCount: Int
    public let eventBreakdown: [String: Int]
    public let hasGPX: Bool

    public init(
        startTime: Date,
        endTime: Date,
        durationMinutes: Int,
        distanceKm: Double,
        averageSpeedKmh: Double,
        maxSpeedKmh: Double,
        maximumLeanAngle: Double,
        elevationGainMeters: Double,
        elevationLossMeters: Double,
        idleTimeSeconds: TimeInterval,
        best0To100Time: TimeInterval?,
        eventCount: Int,
        offRoadEventCount: Int,
        eventBreakdown: [String: Int],
        hasGPX: Bool
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.durationMinutes = max(durationMinutes, 0)
        self.distanceKm = max(distanceKm.isFinite ? distanceKm : 0, 0)
        self.averageSpeedKmh = max(averageSpeedKmh.isFinite ? averageSpeedKmh : 0, 0)
        self.maxSpeedKmh = max(maxSpeedKmh.isFinite ? maxSpeedKmh : 0, 0)
        self.maximumLeanAngle = max(maximumLeanAngle.isFinite ? maximumLeanAngle : 0, 0)
        self.elevationGainMeters = max(elevationGainMeters.isFinite ? elevationGainMeters : 0, 0)
        self.elevationLossMeters = max(elevationLossMeters.isFinite ? elevationLossMeters : 0, 0)
        self.idleTimeSeconds = max(idleTimeSeconds.isFinite ? idleTimeSeconds : 0, 0)
        self.best0To100Time = best0To100Time?.isFinite == true ? best0To100Time : nil
        self.eventCount = max(eventCount, 0)
        self.offRoadEventCount = max(offRoadEventCount, 0)
        self.eventBreakdown = eventBreakdown
        self.hasGPX = hasGPX
    }
}

public enum PTRideStoryBuilder {
    /// EN: Summarize existing report fields without inventing vehicle-specific metrics.
    /// ES: Resume los campos existentes sin inventar métricas específicas del vehículo.
    /// 中文：只汇总报告已有字段，不猜测车型专属指标。
    public static func make(from report: PTTripReport) -> PTRideStorySummary {
        let averageSpeed = report.gpsAvgSpeedKmh > 0
            ? report.gpsAvgSpeedKmh
            : (report.durationMinutes > 0 ? report.distanceKm / (Double(report.durationMinutes) / 60) : 0)
        let elevation = elevationChange(from: report.relativeAltitudeTrace)
        let allEvents = report.reviewEvents.map(\.type.rawValue)
        var breakdown: [String: Int] = [:]
        for eventType in allEvents {
            breakdown[eventType, default: 0] += 1
        }

        return PTRideStorySummary(
            startTime: report.startTime,
            endTime: report.endTime,
            durationMinutes: report.durationMinutes,
            distanceKm: report.distanceKm,
            averageSpeedKmh: averageSpeed,
            maxSpeedKmh: max(report.maxSpeedKmh, report.gpsMaxSpeedKmh),
            maximumLeanAngle: max(abs(report.maxLeanAngleLeft), abs(report.maxLeanAngleRight)),
            elevationGainMeters: elevation.gain,
            elevationLossMeters: elevation.loss,
            idleTimeSeconds: report.idleTimeSeconds,
            best0To100Time: report.best0To100Time,
            eventCount: report.reviewEvents.count + report.offRoadEvents.count,
            offRoadEventCount: report.offRoadEvents.count,
            eventBreakdown: breakdown,
            hasGPX: report.gpxFileName != nil
        )
    }

    private static func elevationChange(from trace: [Double]) -> (gain: Double, loss: Double) {
        guard trace.count > 1 else { return (0, 0) }
        var gain = 0.0
        var loss = 0.0
        for (previous, current) in zip(trace, trace.dropFirst()) {
            guard previous.isFinite, current.isFinite else { continue }
            let delta = current - previous
            if delta > 0 {
                gain += delta
            } else {
                loss += abs(delta)
            }
        }
        return (gain, loss)
    }
}
