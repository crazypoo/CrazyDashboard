//
//  PTOTAResumeStore.swift
//  CrazyDashboard
//
//  Persists the P4 OTA checkpoint and the already-decrypted Jieli firmware artifact.
//  Live offset resume is still owned by JL_OTALib; this store provides process-recovery context.
//

import Foundation

nonisolated public enum PTOTAResumeStoreError: Error, Equatable, LocalizedError, Sendable {
    case checkpointMissing
    case firmwareMissing
    case firmwareDigestMismatch
    case persistenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .checkpointMissing:
            return "没有可恢复的 OTA 会话"
        case .firmwareMissing:
            return "OTA 恢复所需的本地固件不存在"
        case .firmwareDigestMismatch:
            return "OTA 恢复固件摘要校验失败"
        case let .persistenceFailed(message):
            return "OTA 恢复点保存失败：\(message)"
        }
    }
}

nonisolated public struct PTOTAResumeCheckpoint: Codable, Equatable, Sendable {
    public var session: PTOTASession
    public var request: PTYMOBDFirmwareCheckRequest
    public var metadata: PTYMOBDFirmwareMetadata
    /// EN: The temporary download secret is intentionally memory-only and is never encoded into the checkpoint JSON.
    /// ES: El secreto temporal de descarga solo vive en memoria y nunca se codifica en el JSON del punto de reanudación.
    /// 中文：临时下载密钥只存在于内存中，绝不会编码进恢复点 JSON。
    public var secret: PTYMOBDFirmwareSecret?
    public var report: PTYMOBDFirmwareTransferReport
    public var configuration: PTOTAProductConfiguration
    public var state: PTOTAState
    public var progress: PTOTAProgress
    public var firmwareFileName: String
    public var reconnectCount: Int
    public var updatedAt: Date

    public init(
        session: PTOTASession,
        request: PTYMOBDFirmwareCheckRequest,
        metadata: PTYMOBDFirmwareMetadata,
        secret: PTYMOBDFirmwareSecret? = nil,
        report: PTYMOBDFirmwareTransferReport,
        configuration: PTOTAProductConfiguration,
        state: PTOTAState,
        progress: PTOTAProgress,
        firmwareFileName: String,
        reconnectCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.session = session
        self.request = request
        self.metadata = metadata
        self.secret = secret
        self.report = report
        self.configuration = configuration
        self.state = state
        self.progress = progress
        self.firmwareFileName = firmwareFileName
        self.reconnectCount = max(reconnectCount, 0)
        self.updatedAt = updatedAt
    }

    public func makeReadOnlyResult(decryptedFirmware: Data) -> PTYMOBDFirmwareReadOnlyResult {
        PTYMOBDFirmwareReadOnlyResult(
            checkResult: PTYMOBDFirmwareCheckResult(request: request, metadata: metadata),
            secret: secret,
            decryptedFirmware: decryptedFirmware,
            report: report
        )
    }

    private enum CodingKeys: String, CodingKey {
        case session
        case request
        case metadata
        case report
        case configuration
        case state
        case progress
        case firmwareFileName
        case reconnectCount
        case updatedAt
    }

    // EN: Decode old checkpoints but deliberately discard any legacy secret that may have been persisted by an earlier build.
    // ES: Decodifica puntos antiguos, pero descarta deliberadamente cualquier secreto guardado por una versión anterior.
    // 中文：兼容读取旧恢复点，但会主动丢弃旧版本可能写入的临时密钥。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            session: try container.decode(PTOTASession.self, forKey: .session),
            request: try container.decode(PTYMOBDFirmwareCheckRequest.self, forKey: .request),
            metadata: try container.decode(PTYMOBDFirmwareMetadata.self, forKey: .metadata),
            secret: nil,
            report: try container.decode(PTYMOBDFirmwareTransferReport.self, forKey: .report),
            configuration: try container.decode(PTOTAProductConfiguration.self, forKey: .configuration),
            state: try container.decode(PTOTAState.self, forKey: .state),
            progress: try container.decode(PTOTAProgress.self, forKey: .progress),
            firmwareFileName: try container.decode(String.self, forKey: .firmwareFileName),
            reconnectCount: try container.decode(Int.self, forKey: .reconnectCount),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt)
        )
    }

    // EN: Encode only restart-safe metadata; firmware bytes and temporary secrets stay outside the JSON document.
    // ES: Codifica solo metadatos seguros para reinicio; los bytes y secretos temporales quedan fuera del documento JSON.
    // 中文：只编码可安全恢复的元数据；固件字节和临时密钥不写入 JSON 文档。
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(session, forKey: .session)
        try container.encode(request, forKey: .request)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(report, forKey: .report)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(state, forKey: .state)
        try container.encode(progress, forKey: .progress)
        try container.encode(firmwareFileName, forKey: .firmwareFileName)
        try container.encode(reconnectCount, forKey: .reconnectCount)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public actor PTOTAResumeStore {
    public static let shared = PTOTAResumeStore()

    private let fileManager: FileManager
    private let directoryURL: URL
    private let checkpointURL: URL

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directoryURL = root
            .appendingPathComponent("CrazyDashboard", isDirectory: true)
            .appendingPathComponent("OTA", isDirectory: true)
        self.checkpointURL = directoryURL.appendingPathComponent("resume_checkpoint.json")
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    @discardableResult
    public func saveInitial(
        session: PTOTASession,
        readOnlyResult: PTYMOBDFirmwareReadOnlyResult,
        configuration: PTOTAProductConfiguration,
        state: PTOTAState,
        progress: PTOTAProgress
    ) throws -> PTOTAResumeCheckpoint {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let fileName = "firmware_\(session.id.uuidString.lowercased()).bin"
            let firmwareURL = directoryURL.appendingPathComponent(fileName)
            try readOnlyResult.decryptedFirmware.write(to: firmwareURL, options: [.atomic])
            protectFile(at: firmwareURL)

            let checkpoint = PTOTAResumeCheckpoint(
                session: session,
                request: readOnlyResult.checkResult.request,
                metadata: readOnlyResult.checkResult.metadata,
                secret: readOnlyResult.secret,
                report: readOnlyResult.report,
                configuration: configuration,
                state: state,
                progress: progress,
                firmwareFileName: fileName
            )
            try write(checkpoint)
            return checkpoint
        } catch let error as PTOTAResumeStoreError {
            throw error
        } catch {
            throw PTOTAResumeStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    public func update(
        state: PTOTAState,
        progress: PTOTAProgress,
        reconnectCount: Int
    ) throws {
        guard var checkpoint = try load() else {
            throw PTOTAResumeStoreError.checkpointMissing
        }
        checkpoint.state = state
        checkpoint.progress = progress
        checkpoint.reconnectCount = max(reconnectCount, 0)
        checkpoint.updatedAt = Date()
        try write(checkpoint)
    }

    public func load() throws -> PTOTAResumeCheckpoint? {
        guard fileManager.fileExists(atPath: checkpointURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: checkpointURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let checkpoint = try decoder.decode(PTOTAResumeCheckpoint.self, from: data)
            // EN: Rewrite a legacy checkpoint once so an old persisted secret is removed from disk.
            // ES: Reescribe una vez el punto antiguo para eliminar del disco un secreto persistido previamente.
            // 中文：首次读取旧恢复点时立即重写，清除磁盘上旧版本遗留的临时密钥。
            if data.range(of: Data("\"secret\"".utf8)) != nil {
                try write(checkpoint)
            }
            return checkpoint
        } catch {
            throw PTOTAResumeStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    public func loadFirmware(for checkpoint: PTOTAResumeCheckpoint) throws -> Data {
        let safeName = URL(fileURLWithPath: checkpoint.firmwareFileName).lastPathComponent
        guard safeName == checkpoint.firmwareFileName else {
            throw PTOTAResumeStoreError.firmwareMissing
        }
        let firmwareURL = directoryURL.appendingPathComponent(safeName)
        guard fileManager.fileExists(atPath: firmwareURL.path) else {
            throw PTOTAResumeStoreError.firmwareMissing
        }
        let data = try Data(contentsOf: firmwareURL)
        guard !data.isEmpty else { throw PTOTAResumeStoreError.firmwareMissing }
        let digest = PTYMOBDFirmwareCrypto.sha256Hex(data)
        guard digest.caseInsensitiveCompare(checkpoint.session.firmwareSHA256) == .orderedSame else {
            throw PTOTAResumeStoreError.firmwareDigestMismatch
        }
        return data
    }

    public func clear(deleteFirmware: Bool = true) throws {
        let checkpoint = try? load()
        if deleteFirmware, let checkpoint {
            let fileName = URL(fileURLWithPath: checkpoint.firmwareFileName).lastPathComponent
            let firmwareURL = directoryURL.appendingPathComponent(fileName)
            try? fileManager.removeItem(at: firmwareURL)
        }
        if fileManager.fileExists(atPath: checkpointURL.path) {
            try fileManager.removeItem(at: checkpointURL)
        }
    }

    private func write(_ checkpoint: PTOTAResumeCheckpoint) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(checkpoint)
            try data.write(to: checkpointURL, options: [.atomic])
            protectFile(at: checkpointURL)
        } catch {
            throw PTOTAResumeStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    private func protectFile(at url: URL) {
        #if os(iOS)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
