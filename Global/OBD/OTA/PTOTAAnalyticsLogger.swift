//
//  PTOTAAnalyticsLogger.swift
//  CrazyDashboard
//
//  Local structured OTA analytics + exportable protocol/product log.
//  Never records account tokens or server credentials.
//

import Foundation

nonisolated public struct PTOTAAnalyticsEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let sessionID: UUID
    public let name: String
    public let state: PTOTAState
    public let phase: Int
    public let progress: Double
    public let completedBytes: Int64
    public let totalBytes: Int64
    public let deviceIdentifier: String
    public let deviceName: String
    public let oldFirmwareVersion: String
    public let targetFirmwareVersion: String
    public let firmwareFileUUID: String
    public let firmwareSize: Int
    public let reconnectCount: Int
    public let message: String?
    public let metadata: [String: String]
}

nonisolated public enum PTOTAAnalyticsLoggerError: Error, LocalizedError, Sendable {
    case sessionUnavailable
    case exportUnavailable

    public var errorDescription: String? {
        switch self {
        case .sessionUnavailable:
            return "OTA 日志缺少 session"
        case .exportUnavailable:
            return "OTA 日志文件尚不可导出"
        }
    }
}

public actor PTOTAAnalyticsLogger {
    public static let shared = PTOTAAnalyticsLogger()

    private let fileManager: FileManager
    private let directoryURL: URL

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directoryURL = root
            .appendingPathComponent("CrazyDashboard", isDirectory: true)
            .appendingPathComponent("OTALogs", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    public func start(
        session: PTOTASession,
        mandatory: Bool,
        power: PTOTAPowerSnapshot
    ) {
        let metadata: [String: String] = [
            "mandatory": mandatory ? "true" : "false",
            "battery": power.batteryPercentageText,
            "powerSource": power.source.rawValue,
            "lowPowerMode": power.lowPowerModeEnabled ? "true" : "false"
        ]
        record(
            session: session,
            name: "session_start",
            state: .checking,
            progress: .zero,
            reconnectCount: 0,
            message: "P4 OTA session started",
            metadata: metadata
        )
    }

    public func record(
        session: PTOTASession,
        name: String,
        state: PTOTAState,
        progress: PTOTAProgress,
        reconnectCount: Int,
        message: String? = nil,
        metadata: [String: String] = [:]
    ) {
        let event = PTOTAAnalyticsEvent(
            timestamp: Date(),
            sessionID: session.id,
            name: name,
            state: state,
            phase: progress.phase,
            progress: progress.fractionCompleted,
            completedBytes: progress.completedBytes,
            totalBytes: progress.totalBytes,
            deviceIdentifier: session.deviceIdentifier,
            deviceName: session.deviceName,
            oldFirmwareVersion: session.oldFirmwareVersion,
            targetFirmwareVersion: session.targetFirmwareVersion,
            firmwareFileUUID: session.firmwareFileUUID,
            firmwareSize: session.firmwareByteCount,
            reconnectCount: max(reconnectCount, 0),
            message: message,
            metadata: sanitize(metadata)
        )
        append(event)
    }

    public func exportURL(for sessionID: UUID) throws -> URL {
        let url = logURL(for: sessionID)
        guard fileManager.fileExists(atPath: url.path) else {
            throw PTOTAAnalyticsLoggerError.exportUnavailable
        }
        return url
    }

    public func removeLog(for sessionID: UUID) {
        try? fileManager.removeItem(at: logURL(for: sessionID))
    }

    private func append(_ event: PTOTAAnalyticsEvent) {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            var data = try encoder.encode(event)
            data.append(0x0A)

            let url = logURL(for: event.sessionID)
            if !fileManager.fileExists(atPath: url.path) {
                fileManager.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Logging must never crash or interrupt the OTA transport.
        }
    }

    private func logURL(for sessionID: UUID) -> URL {
        directoryURL.appendingPathComponent(
            "CrazyDashboard_OBD_OTA_Session_\(sessionID.uuidString.lowercased()).log"
        )
    }

    private func sanitize(_ metadata: [String: String]) -> [String: String] {
        let deniedFragments = ["token", "authorization", "cookie", "password", "secret", "credential"]
        return metadata.reduce(into: [:]) { result, pair in
            let key = pair.key.lowercased()
            guard !deniedFragments.contains(where: key.contains) else { return }
            result[pair.key] = String(pair.value.prefix(512))
        }
    }
}
