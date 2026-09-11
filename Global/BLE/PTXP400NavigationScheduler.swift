//
//  PTXP400NavigationScheduler.swift
//  CrazyDashboard
//
//  EN: Encapsulates navigation deduplication and the conservative send interval.
//  ES: Encapsula la deduplicación de navegación y el intervalo conservador de envío.
//  中文：封装导航去重和保守的发送间隔控制。
//

import Foundation

nonisolated struct PTXP400NavigationFingerprint: Equatable, Sendable {
    let maneuver: UInt8
    let nextRoad: String
    let currentRoad: String
    let speedLimit: UInt8
    let nextDistanceBucket: UInt32
    let destinationDistanceBucket: UInt32
    let etaBucket: Int

    init(info: PTNavigationInfo) {
        maneuver = info.nextManeuver
        nextRoad = info.nameNextRoad
        currentRoad = info.nameCurrentRoad
        speedLimit = info.currentSpeedLimit
        nextDistanceBucket = info.metersToNextManeuver / 10
        destinationDistanceBucket = info.distanceToDestination / 50
        etaBucket = max(info.estimatedTimeToDestinationSec, 0) / 30
    }
}

/// EN: Pure scheduler state keeps map callbacks deterministic and testable.
/// ES: El estado puro del planificador hace deterministas y comprobables los callbacks del mapa.
/// 中文：纯调度器状态让地图回调变得确定且可测试。
nonisolated struct PTXP400NavigationScheduler: Sendable {
    let minimumSendInterval: TimeInterval
    private(set) var lastFingerprint: PTXP400NavigationFingerprint?
    private(set) var lastSentAt: Date?

    init(minimumSendInterval: TimeInterval = 0.5) {
        self.minimumSendInterval = max(0, minimumSendInterval)
    }

    func isDuplicate(_ fingerprint: PTXP400NavigationFingerprint) -> Bool {
        lastFingerprint == fingerprint
    }

    func remainingDelay(at date: Date) -> TimeInterval {
        guard let lastSentAt else { return 0 }
        return max(0, minimumSendInterval - date.timeIntervalSince(lastSentAt))
    }

    mutating func recordSent(_ fingerprint: PTXP400NavigationFingerprint, at date: Date = Date()) {
        lastFingerprint = fingerprint
        lastSentAt = date
    }

    mutating func reset() {
        lastFingerprint = nil
        lastSentAt = nil
    }
}
