//
//  PTOTAProductConfiguration.swift
//  CrazyDashboard
//
//  P4 product policy: mandatory update, battery/power checks and verification timeouts.
//

import Foundation
import UIKit

nonisolated public struct PTOTAProductConfiguration: Codable, Equatable, Sendable {
    public var isMandatoryUpdate: Bool
    public var minimumBatteryLevel: Float
    public var recommendsExternalPower: Bool
    public var blocksLowBattery: Bool
    public var allowsCancelWhenMandatory: Bool
    public var normalOBDReconnectTimeout: TimeInterval
    public var versionVerificationTimeout: TimeInterval
    public var keepResumeCheckpointOnFailure: Bool

    public init(
        isMandatoryUpdate: Bool = false,
        minimumBatteryLevel: Float = 0.50,
        recommendsExternalPower: Bool = true,
        blocksLowBattery: Bool = true,
        allowsCancelWhenMandatory: Bool = false,
        normalOBDReconnectTimeout: TimeInterval = 30,
        versionVerificationTimeout: TimeInterval = 45,
        keepResumeCheckpointOnFailure: Bool = true
    ) {
        self.isMandatoryUpdate = isMandatoryUpdate
        self.minimumBatteryLevel = min(max(minimumBatteryLevel, 0), 1)
        self.recommendsExternalPower = recommendsExternalPower
        self.blocksLowBattery = blocksLowBattery
        self.allowsCancelWhenMandatory = allowsCancelWhenMandatory
        self.normalOBDReconnectTimeout = max(normalOBDReconnectTimeout, 5)
        self.versionVerificationTimeout = max(versionVerificationTimeout, 5)
        self.keepResumeCheckpointOnFailure = keepResumeCheckpointOnFailure
    }

    public static let `default` = PTOTAProductConfiguration()
}

nonisolated public enum PTOTAPowerSource: String, Codable, Equatable, Sendable {
    case unknown
    case battery
    case charging
    case full

    public var isExternalPowerLikely: Bool {
        self == .charging || self == .full
    }
}

nonisolated public struct PTOTAPowerSnapshot: Codable, Equatable, Sendable {
    /// 0...1. nil means iOS did not provide a valid battery level.
    public let batteryLevel: Float?
    public let source: PTOTAPowerSource
    public let lowPowerModeEnabled: Bool
    public let capturedAt: Date

    public init(
        batteryLevel: Float?,
        source: PTOTAPowerSource,
        lowPowerModeEnabled: Bool,
        capturedAt: Date = Date()
    ) {
        self.batteryLevel = batteryLevel
        self.source = source
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.capturedAt = capturedAt
    }

    public var batteryPercentageText: String {
        guard let batteryLevel else { return "未知" }
        return "\(Int((batteryLevel * 100).rounded()))%"
    }
}

nonisolated public struct PTOTAPowerPreflightReport: Codable, Equatable, Sendable {
    public let snapshot: PTOTAPowerSnapshot
    public let blockers: [String]
    public let warnings: [String]

    public init(snapshot: PTOTAPowerSnapshot, blockers: [String], warnings: [String]) {
        self.snapshot = snapshot
        self.blockers = blockers
        self.warnings = warnings
    }

    public var canStartOTA: Bool { blockers.isEmpty }
}

@MainActor
public enum PTOTAPowerPreflight {
    public static func evaluate(
        configuration: PTOTAProductConfiguration = .default
    ) -> PTOTAPowerPreflightReport {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        let rawLevel = device.batteryLevel
        let level: Float? = (0...1).contains(rawLevel) ? rawLevel : nil
        let source: PTOTAPowerSource
        switch device.batteryState {
        case .unplugged:
            source = .battery
        case .charging:
            source = .charging
        case .full:
            source = .full
        case .unknown:
            source = .unknown
        @unknown default:
            source = .unknown
        }

        let snapshot = PTOTAPowerSnapshot(
            batteryLevel: level,
            source: source,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )

        var blockers: [String] = []
        var warnings: [String] = []

        if let level,
           level < configuration.minimumBatteryLevel,
           !source.isExternalPowerLikely {
            let threshold = Int((configuration.minimumBatteryLevel * 100).rounded())
            let message = "手机电量仅 \(snapshot.batteryPercentageText)，建议至少 \(threshold)% 或连接电源后再升级"
            if configuration.blocksLowBattery {
                blockers.append(message)
            } else {
                warnings.append(message)
            }
        }

        if level == nil {
            warnings.append("系统暂时无法读取手机电量，请确认手机电量充足")
        }

        if configuration.recommendsExternalPower && !source.isExternalPowerLikely {
            warnings.append("OTA 期间建议保持手机外接电源，避免升级过程中断电")
        }

        if snapshot.lowPowerModeEnabled {
            warnings.append("当前开启了低电量模式，建议关闭后再执行 OTA")
        }

        return PTOTAPowerPreflightReport(
            snapshot: snapshot,
            blockers: blockers,
            warnings: warnings
        )
    }
}
