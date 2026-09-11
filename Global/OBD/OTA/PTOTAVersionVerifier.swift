//
//  PTOTAVersionVerifier.swift
//  CrazyDashboard
//
//  P4 final success gate: reconnect the normal YMOBD path, read AT+VERSION and verify target version.
//

import Foundation

nonisolated public struct PTOTAVersionVerificationResult: Equatable, Sendable {
    public let expectedVersion: String
    public let actualVersion: String
    public let rawResponse: String

    public init(expectedVersion: String, actualVersion: String, rawResponse: String) {
        self.expectedVersion = expectedVersion
        self.actualVersion = actualVersion
        self.rawResponse = rawResponse
    }
}

nonisolated public enum PTOTAVersionVerificationError: Error, Equatable, LocalizedError, Sendable {
    case reconnectTimeout
    case emptyVersionResponse
    case mismatch(expected: String, actual: String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .reconnectTimeout:
            return "OTA 后普通 YMOBD 连接恢复超时"
        case .emptyVersionResponse:
            return "OTA 后 AT+VERSION 未返回有效固件版本"
        case let .mismatch(expected, actual):
            return "OTA 版本复核失败，目标 \(expected)，实际 \(actual)"
        case let .commandFailed(message):
            return "OTA 后 AT+VERSION 读取失败：\(message)"
        }
    }
}

@MainActor
public enum PTOTAVersionVerifier {
    public static func verify(
        targetVersion: String,
        reconnectTimeout: TimeInterval = 30,
        commandTimeout: TimeInterval = 45
    ) async throws -> PTOTAVersionVerificationResult {
        let reconnectDeadline = Date().addingTimeInterval(max(reconnectTimeout, 5))
        while Date() < reconnectDeadline {
            try Task.checkCancellation()
            if PTMotoTelemetryManager.shared.isConnected,
               PTHiddenOBDConnector.shared.isUnlocked {
                break
            }
            try await Task.sleep(nanoseconds: 400_000_000)
        }

        guard PTMotoTelemetryManager.shared.isConnected,
              PTHiddenOBDConnector.shared.isUnlocked else {
            throw PTOTAVersionVerificationError.reconnectTimeout
        }

        let response: String
        do {
            // sendRawCommandAsync 本身已经由现有 OBD 层负责 command watchdog。
            // P4 不再额外并发一条 timeout task，避免 timeout 后旧 ELM command 继续占用 BLE 总线。
            _ = commandTimeout
            response = try await PTAdvancedOBDCoordinator.shared.executeReadOnly {
                try await PTMotoTelemetryManager.shared.sendRawCommandAsync("AT+VERSION")
            }
        } catch {
            throw PTOTAVersionVerificationError.commandFailed(error.localizedDescription)
        }

        let info = PTYMOBDVersionParser().parse(response)
        let actual = info.version.trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = targetVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !actual.isEmpty else {
            throw PTOTAVersionVerificationError.emptyVersionResponse
        }
        guard versionsEquivalent(actual, expected) else {
            throw PTOTAVersionVerificationError.mismatch(expected: expected, actual: actual)
        }

        return PTOTAVersionVerificationResult(
            expectedVersion: expected,
            actualVersion: actual,
            rawResponse: response
        )
    }

    private static func versionsEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        if lhs.caseInsensitiveCompare(rhs) == .orderedSame { return true }
        return !PTYMOBDFirmwareVersionComparator.isNewer(lhs, than: rhs)
            && !PTYMOBDFirmwareVersionComparator.isNewer(rhs, than: lhs)
    }
}
