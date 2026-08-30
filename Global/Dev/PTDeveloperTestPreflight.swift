//
//  PTDeveloperTestPreflight.swift
//  CrazyDashboard
//
//  EN: Deterministic readiness checks for developer vehicle experiments.
//  ES: Comprobaciones deterministas de preparación para experimentos del vehículo del desarrollador.
//  中文：为开发者车辆实验提供确定性的执行前检查。
//

import Foundation

public enum PTDeveloperTestLevel: String, Codable, Sendable {
    case configurationWrite
    case securityAndRoutine
    case firmware
}

public struct PTDeveloperTestChecklist: Codable, Equatable, Sendable {
    public let vehicleStationary: Bool
    public let targetIdentityVerified: Bool
    public let originalBackupVerified: Bool
    public let protocolEvidenceAvailable: Bool
    public let adapterCapabilityVerified: Bool
    public let stablePowerAvailable: Bool
    public let recoveryPathAvailable: Bool
    public let firmwareCompatibilityVerified: Bool
    public let seedKeySourceAvailable: Bool

    public init(
        vehicleStationary: Bool,
        targetIdentityVerified: Bool,
        originalBackupVerified: Bool,
        protocolEvidenceAvailable: Bool,
        adapterCapabilityVerified: Bool,
        stablePowerAvailable: Bool,
        recoveryPathAvailable: Bool,
        firmwareCompatibilityVerified: Bool,
        seedKeySourceAvailable: Bool
    ) {
        self.vehicleStationary = vehicleStationary
        self.targetIdentityVerified = targetIdentityVerified
        self.originalBackupVerified = originalBackupVerified
        self.protocolEvidenceAvailable = protocolEvidenceAvailable
        self.adapterCapabilityVerified = adapterCapabilityVerified
        self.stablePowerAvailable = stablePowerAvailable
        self.recoveryPathAvailable = recoveryPathAvailable
        self.firmwareCompatibilityVerified = firmwareCompatibilityVerified
        self.seedKeySourceAvailable = seedKeySourceAvailable
    }

    nonisolated public static let empty = PTDeveloperTestChecklist(
        vehicleStationary: false,
        targetIdentityVerified: false,
        originalBackupVerified: false,
        protocolEvidenceAvailable: false,
        adapterCapabilityVerified: false,
        stablePowerAvailable: false,
        recoveryPathAvailable: false,
        firmwareCompatibilityVerified: false,
        seedKeySourceAvailable: false
    )
}

public struct PTDeveloperTestPreflightResult: Codable, Equatable, Sendable {
    public let level: PTDeveloperTestLevel
    public let isReady: Bool
    public let blockers: [String]

    nonisolated public init(level: PTDeveloperTestLevel, isReady: Bool, blockers: [String]) {
        self.level = level
        self.isReady = isReady
        self.blockers = blockers
    }
}

public enum PTDeveloperTestPreflight {
    /// EN: A missing prerequisite always blocks the operation; no level can bypass the checklist.
    /// ES: Cualquier requisito ausente bloquea la operación; ningún nivel puede saltarse la lista.
    /// 中文：任何前置条件缺失都会阻止操作，任何等级都不能绕过检查表。
    nonisolated public static func evaluate(
        level: PTDeveloperTestLevel,
        checklist: PTDeveloperTestChecklist
    ) -> PTDeveloperTestPreflightResult {
        var blockers: [String] = []

        if !checklist.vehicleStationary {
            blockers.append("vehicleNotStationary")
        }
        if !checklist.targetIdentityVerified {
            blockers.append("targetIdentityNotVerified")
        }
        if !checklist.protocolEvidenceAvailable {
            blockers.append("protocolEvidenceMissing")
        }
        if !checklist.adapterCapabilityVerified {
            blockers.append("adapterCapabilityNotVerified")
        }
        if !checklist.recoveryPathAvailable {
            blockers.append("recoveryPathMissing")
        }

        switch level {
        case .configurationWrite:
            if !checklist.originalBackupVerified {
                blockers.append("originalBackupNotVerified")
            }
        case .securityAndRoutine:
            if !checklist.stablePowerAvailable {
                blockers.append("stablePowerMissing")
            }
            if !checklist.seedKeySourceAvailable {
                blockers.append("seedKeySourceMissing")
            }
        case .firmware:
            if !checklist.originalBackupVerified {
                blockers.append("originalFirmwareNotVerified")
            }
            if !checklist.stablePowerAvailable {
                blockers.append("stablePowerMissing")
            }
            if !checklist.firmwareCompatibilityVerified {
                blockers.append("firmwareCompatibilityNotVerified")
            }
        }

        return PTDeveloperTestPreflightResult(
            level: level,
            isReady: blockers.isEmpty,
            blockers: blockers
        )
    }
}
