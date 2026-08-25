//
//  PTRideReviewAnalyzer.swift
//  CrazyDashboard
//
//  中文：行程结束后分析已有遥测数据，提供本地骑行复盘参考。
//  Español: Analiza la telemetría existente al finalizar la ruta para ofrecer una revisión local.
//

import Foundation

public enum PTRideReviewAnalyzer {
    private static let eventCooldown: TimeInterval = 5

    public static func analyze(points: [PTRoutePoint]) -> [PTRideReviewEvent] {
        var lastEventTime: [PTRideReviewEventType: Date] = [:]
        var events: [PTRideReviewEvent] = []
        events.reserveCapacity(min(points.count, 32))

        for point in points {
            let candidates: [(PTRideReviewEventType, Double, Double, Bool)] = [
                (.hardBraking, point.gForceY, 0.45, point.gForceY <= -0.45),
                (.hardAcceleration, point.gForceY, 0.40, point.gForceY >= 0.40),
                (.heavyBump, abs(point.gForceZ), 1.20, abs(point.gForceZ) >= 1.20),
                (.highLean, abs(point.leanAngle), 40.0, abs(point.leanAngle) >= 40.0 && point.speed >= 30),
                (.suspectedSlip, abs(point.slipRatio), 35.0, abs(point.slipRatio) >= 35.0 && point.speed > 5)
            ]

            for (type, value, threshold, isTriggered) in candidates where isTriggered {
                if let last = lastEventTime[type], point.timestamp.timeIntervalSince(last) < eventCooldown {
                    continue
                }

                lastEventTime[type] = point.timestamp
                events.append(
                    PTRideReviewEvent(
                        type: type,
                        timestamp: point.timestamp,
                        latitude: point.lat,
                        longitude: point.lon,
                        peakValue: value,
                        speedKmh: max(0, point.speed),
                        severity: min(max(abs(value) / threshold, 1), 3)
                    )
                )
            }
        }

        return events.sorted { $0.timestamp < $1.timestamp }
    }
}
