//
//  PTOTAState.swift
//  CrazyDashboard
//
//  EN: Shared state and progress values for the guarded Jieli OTA flow.
//  ES: Estados y valores de progreso compartidos para el flujo OTA Jieli protegido.
//  中文：受保护的 Jieli OTA 流程共用状态与进度模型。
//

import Foundation

nonisolated public enum PTOTAState: String, Codable, Equatable, Sendable {
    case idle
    case checking
    case downloading
    case decrypting
    case preparing
    case ready
    case verifying
    case upgrading
    case reconnecting
    case verifyingVersion
    case completed
    case failed
    case cancelled
}

nonisolated public enum PTOTAFailureReason: String, Codable, Equatable, Sendable {
    case developerAccessDenied
    case preflightFailed
    case explicitConfirmationRequired
    case invalidFirmware
    case disconnected
    case sdkUnavailable
    case transportFailed
    case authenticationFailed
    case transferFailed
    case reconnectTimeout
    case versionVerificationFailed
    case cancelled
}

nonisolated public enum PTJieliOTAEvent: String, Codable, Equatable, Sendable {
    case onInitCompleted
    case onOtaReady
    case onStartOTA
    case onProgress
    case onMandatoryUpgrade
    case onNeedReconnect
    case onStopOTA
    case onError
}

nonisolated public struct PTOTAProgress: Codable, Equatable, Sendable {
    public let phase: Int
    public let completedBytes: Int64
    public let totalBytes: Int64
    public let fractionCompleted: Double
    public let detail: String?

    public init(
        phase: Int,
        completedBytes: Int64,
        totalBytes: Int64,
        fractionCompleted: Double? = nil,
        detail: String? = nil
    ) {
        let boundedTotal = max(totalBytes, 0)
        let boundedCompleted = min(max(completedBytes, 0), boundedTotal == 0 ? Int64.max : boundedTotal)
        let calculatedFraction: Double
        if boundedTotal > 0 {
            calculatedFraction = Double(boundedCompleted) / Double(boundedTotal)
        } else {
            calculatedFraction = 0
        }

        self.phase = max(phase, 0)
        self.completedBytes = boundedCompleted
        self.totalBytes = boundedTotal
        self.fractionCompleted = min(max(fractionCompleted ?? calculatedFraction, 0), 1)
        self.detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static let zero = PTOTAProgress(
        phase: 0,
        completedBytes: 0,
        totalBytes: 0,
        fractionCompleted: 0
    )
}

// EN: The session is an in-memory transfer record; secure persistence belongs to the later resume phase.
// ES: La sesión es un registro de transferencia en memoria; la persistencia segura pertenece a la fase posterior de reanudación.
// 中文：会话只是内存中的传输记录；安全持久化留给后续恢复阶段。
nonisolated public struct PTOTASession: Codable, Equatable, Sendable {
    public let id: UUID
    public let deviceIdentifier: String
    public let deviceName: String
    public let oldFirmwareVersion: String
    public let targetFirmwareVersion: String
    public let firmwareFileUUID: String
    public let firmwareByteCount: Int
    public let firmwareSHA256: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        deviceIdentifier: String = "",
        deviceName: String = "",
        oldFirmwareVersion: String,
        targetFirmwareVersion: String,
        firmwareFileUUID: String,
        firmwareByteCount: Int,
        firmwareSHA256: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.deviceIdentifier = deviceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.deviceName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.oldFirmwareVersion = oldFirmwareVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.targetFirmwareVersion = targetFirmwareVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.firmwareFileUUID = firmwareFileUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.firmwareByteCount = max(firmwareByteCount, 0)
        self.firmwareSHA256 = firmwareSHA256.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.createdAt = createdAt
    }
}

nonisolated public struct PTOTAExecutionResult: Codable, Equatable, Sendable {
    public let session: PTOTASession
    public let finalState: PTOTAState
    public let versionVerified: Bool

    public init(
        session: PTOTASession,
        finalState: PTOTAState,
        versionVerified: Bool
    ) {
        self.session = session
        self.finalState = finalState
        self.versionVerified = versionVerified
    }
}
