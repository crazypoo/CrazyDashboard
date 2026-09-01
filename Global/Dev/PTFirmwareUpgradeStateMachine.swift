//
//  PTFirmwareUpgradeStateMachine.swift
//  CrazyDashboard
//
//  EN: Developer-only firmware readiness state machine with no write transport.
//  ES: Máquina de estados de preparación de firmware solo para desarrolladores y sin transporte de escritura.
//  中文：仅限开发者的固件升级准备状态机，不包含写入传输。
//

import CryptoKit
import Foundation

public struct PTFirmwareUpgradeRequest: Codable, Equatable, Sendable {
    public let id: UUID
    public let targetAddress: PTOBDDiagnosticAddress
    public let firmwareIdentifier: String
    public let byteCount: Int
    public let sha256Hex: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        targetAddress: PTOBDDiagnosticAddress,
        firmwareIdentifier: String,
        byteCount: Int,
        sha256Hex: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.targetAddress = targetAddress
        self.firmwareIdentifier = firmwareIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.byteCount = max(byteCount, 0)
        self.sha256Hex = sha256Hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.createdAt = createdAt
    }

    // EN: Hash the payload once and keep only metadata in the state machine.
    // ES: Calcula el hash una vez y conserva solo metadatos en la máquina de estados.
    // 中文：只计算一次哈希，状态机仅保留元数据，不保留固件字节。
    public init(
        id: UUID = UUID(),
        targetAddress: PTOBDiagnosticAddress,
        firmwareIdentifier: String,
        firmwareData: Data,
        createdAt: Date = Date()
    ) {
        let digest = SHA256.hash(data: firmwareData)
        let hash = digest.map { String(format: "%02X", $0) }.joined()
        self.init(
            id: id,
            targetAddress: targetAddress,
            firmwareIdentifier: firmwareIdentifier,
            byteCount: firmwareData.count,
            sha256Hex: hash,
            createdAt: createdAt
        )
    }

    public var metadataBlockers: [String] {
        var blockers: [String] = []
        if firmwareIdentifier.isEmpty { blockers.append("firmwareIdentifierMissing") }
        if byteCount <= 0 { blockers.append("firmwarePayloadMissing") }
        if sha256Hex.count != 64 || !sha256Hex.allSatisfy({ "0123456789ABCDEF".contains($0) }) {
            blockers.append("firmwareSHA256Invalid")
        }
        return blockers
    }
}

public enum PTFirmwareUpgradeState: String, Codable, Sendable {
    case idle
    case preflighting
    case blocked
    case awaitingExplicitConfirmation
    case rejected
    case cancelled
}

public enum PTFirmwareUpgradeExecutionResult: String, Codable, Sendable {
    case confirmationRequired
    case protocolNotValidated
    case blocked
    case cancelled
}

public struct PTFirmwareUpgradeAuditEvent: Codable, Equatable, Sendable {
    public let state: PTFirmwareUpgradeState
    public let detail: String
    public let timestamp: Date

    public init(state: PTFirmwareUpgradeState, detail: String, timestamp: Date = Date()) {
        self.state = state
        self.detail = detail
        self.timestamp = timestamp
    }
}

// EN: Passing the developer gate only permits an explicit readiness review; it never authorizes an unverified write.
// ES: Pasar la puerta del desarrollador solo permite revisar la preparación; nunca autoriza una escritura no verificada.
// 中文：通过开发者门禁只允许明确检查准备状态，绝不代表可以执行未经验证的写入。
@MainActor
public final class PTFirmwareUpgradeStateMachine {
    public static let shared = PTFirmwareUpgradeStateMachine()

    public private(set) var state: PTFirmwareUpgradeState = .idle
    public private(set) var currentRequest: PTFirmwareUpgradeRequest?
    public private(set) var blockers: [String] = []
    public private(set) var auditEvents: [PTFirmwareUpgradeAuditEvent] = []

    private init() {}

    @discardableResult
    public func prepare(
        request: PTFirmwareUpgradeRequest,
        checklist: PTDeveloperTestChecklist
    ) -> PTFirmwareUpgradeState {
        currentRequest = request
        state = .preflighting
        blockers = request.metadataBlockers

        let preflight = PTDeveloperTestPreflight.evaluate(level: .firmware, checklist: checklist)
        blockers.append(contentsOf: preflight.blockers)

        let gateAllowed = PTDeveloperSafetyGate.shared.authorize(
            .firmwareFlash,
            protocolEvidenceAvailable: checklist.protocolEvidenceAvailable
        )
        if !gateAllowed {
            blockers.append("developerSafetyGateDenied")
        }

        if blockers.isEmpty {
            state = .awaitingExplicitConfirmation
            appendAudit("readinessPassedAwaitingConfirmation")
        } else {
            state = .blocked
            appendAudit("blocked:" + blockers.joined(separator: ","))
        }
        return state
    }

    @discardableResult
    public func attemptExecution(explicitlyConfirmed: Bool) -> PTFirmwareUpgradeExecutionResult {
        guard state == .awaitingExplicitConfirmation else {
            appendAudit("executionBlockedByState")
            return state == .cancelled ? .cancelled : .blocked
        }

        guard explicitlyConfirmed else {
            appendAudit("explicitConfirmationRequired")
            return .confirmationRequired
        }

        // EN: No verified XP400 bootloader, CRC, ACK, recovery or rollback transport exists yet.
        // ES: Aún no existe transporte verificado de bootloader, CRC, ACK, recuperación o reversión para XP400.
        // 中文：当前没有经过验证的 XP400 Bootloader、CRC、ACK、恢复或回滚传输协议。
        state = .rejected
        appendAudit("protocolNotValidatedNoBytesSent")
        return .protocolNotValidated
    }

    public func cancel() {
        guard state != .idle else { return }
        state = .cancelled
        appendAudit("cancelled")
    }

    public func reset() {
        state = .idle
        currentRequest = nil
        blockers.removeAll(keepingCapacity: true)
        appendAudit("reset")
    }
}

private extension PTFirmwareUpgradeStateMachine {
    func appendAudit(_ detail: String) {
        auditEvents.append(PTFirmwareUpgradeAuditEvent(state: state, detail: detail))
        if auditEvents.count > 100 {
            auditEvents.removeFirst(auditEvents.count - 100)
        }
    }
}
