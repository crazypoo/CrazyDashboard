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

// EN: The inspector accepts a developer-supplied artifact but stores only bounded metadata, never firmware bytes.
// ES: El inspector acepta un archivo del desarrollador, pero solo guarda metadatos limitados y nunca los bytes del firmware.
// 中文：文件检查器允许开发者选择固件文件，但只保存有界元数据，绝不保存固件字节。
public enum PTFirmwareArtifactFormat: String, Codable, Sendable {
    case intelHex
    case motorolaSRecord
    case elf
    case windowsPE
    case zip
    case appleImage
    case rawBinary
    case unknown
}

nonisolated public struct PTFirmwareInspectionReport: Codable, Equatable, Sendable {
    public let fileName: String
    public let byteCount: Int
    public let sha256Hex: String
    public let format: PTFirmwareArtifactFormat
    public let headerHex: String
    public let printableStrings: [String]
    public let inspectedAt: Date

    public init(
        fileName: String,
        byteCount: Int,
        sha256Hex: String,
        format: PTFirmwareArtifactFormat,
        headerHex: String,
        printableStrings: [String],
        inspectedAt: Date = Date()
    ) {
        self.fileName = fileName
        self.byteCount = byteCount
        self.sha256Hex = sha256Hex
        self.format = format
        self.headerHex = headerHex
        self.printableStrings = printableStrings
        self.inspectedAt = inspectedAt
    }
}

nonisolated public enum PTFirmwareInspectionError: Error, Equatable, LocalizedError, Sendable {
    case emptyFile
    case fileTooLarge(maximumBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "固件文件为空"
        case let .fileTooLarge(maximumBytes):
            return "固件文件超过大小限制（\(maximumBytes) bytes）"
        }
    }
}

// EN: This is a format and integrity preflight only; it deliberately makes no claim about XP400 bootloader compatibility.
// ES: Solo comprueba formato e integridad; deliberadamente no afirma compatibilidad con el bootloader del XP400.
// 中文：这里只检查格式和完整性，不会声称文件兼容 XP400 Bootloader。
public enum PTFirmwareArtifactInspector {
    public static let maximumFileSize = 64 * 1024 * 1024

    public static func inspect(data: Data, fileName: String) throws -> PTFirmwareInspectionReport {
        guard !data.isEmpty else { throw PTFirmwareInspectionError.emptyFile }
        guard data.count <= maximumFileSize else {
            throw PTFirmwareInspectionError.fileTooLarge(maximumBytes: maximumFileSize)
        }

        let digest = SHA256.hash(data: data)
        let sha256Hex = digest.map { String(format: "%02X", $0) }.joined()
        let header = data.prefix(16)
        let headerHex = header.map { String(format: "%02X", $0) }.joined(separator: " ")
        let format = detectFormat(data: data, fileName: fileName)

        return PTFirmwareInspectionReport(
            fileName: fileName,
            byteCount: data.count,
            sha256Hex: sha256Hex,
            format: format,
            headerHex: headerHex,
            printableStrings: printableStrings(in: data)
        )
    }

    private static func detectFormat(data: Data, fileName: String) -> PTFirmwareArtifactFormat {
        let name = fileName.lowercased()
        if name.hasSuffix(".hex") { return .intelHex }
        if name.hasSuffix(".s19") || name.hasSuffix(".srec") { return .motorolaSRecord }

        let bytes = Array(data.prefix(4))
        if bytes == [0x7F, 0x45, 0x4C, 0x46] { return .elf }
        if bytes.starts(with: [0x4D, 0x5A]) { return .windowsPE }
        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return .zip }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) || bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return .appleImage
        }
        return .rawBinary
    }

    private static func printableStrings(in data: Data) -> [String] {
        let maximumCount = 12
        let maximumLength = 64
        var values: [String] = []
        var buffer: [UInt8] = []

        func flush() {
            guard buffer.count >= 4, values.count < maximumCount else {
                buffer.removeAll(keepingCapacity: true)
                return
            }
            values.append(String(decoding: buffer.prefix(maximumLength), as: UTF8.self))
            buffer.removeAll(keepingCapacity: true)
        }

        for byte in data {
            if (0x20...0x7E).contains(byte) {
                buffer.append(byte)
                if buffer.count == maximumLength {
                    flush()
                }
            } else {
                flush()
            }
            if values.count == maximumCount { break }
        }
        flush()
        return values
    }
}

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
