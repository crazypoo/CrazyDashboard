//
//  PTYMOBDAdapterModeCoordinator.swift
//  PTSpeed
//
//  EN: Coordinates the safe handoff between ordinary ELM mode and adapter OTA mode.
//  ES: Coordina el cambio seguro entre el modo ELM normal y el modo OTA del adaptador.
//  中文：协调普通 ELM 模式与适配器 OTA 模式之间的安全交接。
//

import Foundation

nonisolated public enum PTYMOBDAdapterMode: String, Codable, Equatable, CaseIterable, Sendable {
    case disconnected
    case elm
    case preparingOTA
    case relinquishingELM
    case jieliOTA
    case rebooting
    case restoringELM
    case failed
}

nonisolated public enum PTYMOBDAdapterModeError: Error, Equatable, LocalizedError, Sendable {
    case invalidState(PTYMOBDAdapterMode)
    case confirmationRequired
    case developerAccessDenied
    case verificationFailed
    case recoveryFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidState(mode):
            return "YMOBD adapter mode does not allow this operation: \(mode.rawValue)"
        case .confirmationRequired:
            return "Developer confirmation is required before adapter OTA."
        case .developerAccessDenied:
            return "Developer firmware access is disabled."
        case .verificationFailed:
            return "The adapter returned to ELM mode but version verification failed."
        case let .recoveryFailed(message):
            return "The adapter could not be recovered to ELM mode: \(message)"
        }
    }
}

nonisolated public struct PTYMOBDAdapterModeHooks: Sendable {
    public let stopPolling: @Sendable () async -> Void
    public let flushELMQueue: @Sendable () async -> Void
    public let stopMonitor: @Sendable () async -> Void
    public let relinquishELM: @Sendable () async -> Void
    public let startJieliOTA: @Sendable () async throws -> Void
    public let restoreELM: @Sendable () async throws -> Void
    public let verifyELM: @Sendable () async throws -> Bool

    public init(
        stopPolling: @escaping @Sendable () async -> Void = {},
        flushELMQueue: @escaping @Sendable () async -> Void = {},
        stopMonitor: @escaping @Sendable () async -> Void = {},
        relinquishELM: @escaping @Sendable () async -> Void = {},
        startJieliOTA: @escaping @Sendable () async throws -> Void,
        restoreELM: @escaping @Sendable () async throws -> Void,
        verifyELM: @escaping @Sendable () async throws -> Bool
    ) {
        self.stopPolling = stopPolling
        self.flushELMQueue = flushELMQueue
        self.stopMonitor = stopMonitor
        self.relinquishELM = relinquishELM
        self.startJieliOTA = startJieliOTA
        self.restoreELM = restoreELM
        self.verifyELM = verifyELM
    }
}

public actor PTYMOBDAdapterModeCoordinator {
    public static let shared = PTYMOBDAdapterModeCoordinator()

    public private(set) var mode: PTYMOBDAdapterMode = .disconnected
    public private(set) var lastRecoveryMessage: String?

    private let busCoordinator: PTOBDBusCoordinator
    private let trace: PTOBDSessionTrace

    public init(
        busCoordinator: PTOBDBusCoordinator = .shared,
        trace: PTOBDSessionTrace = .shared
    ) {
        self.busCoordinator = busCoordinator
        self.trace = trace
    }

    public func markELMConnected() {
        mode = .elm
        lastRecoveryMessage = nil
    }

    public func markDisconnected() {
        mode = .disconnected
    }

    public func reset() {
        mode = .disconnected
        lastRecoveryMessage = nil
    }

    public func performOTA(
        explicitlyConfirmed: Bool,
        hooks: PTYMOBDAdapterModeHooks
    ) async throws {
        guard mode == .elm else {
            throw PTYMOBDAdapterModeError.invalidState(mode)
        }
        guard explicitlyConfirmed else {
            throw PTYMOBDAdapterModeError.confirmationRequired
        }
        let developerAccess = await MainActor.run {
            PTDeveloperSafetyGate.shared.authorize(.firmwareFlash)
        }
        guard developerAccess else {
            throw PTYMOBDAdapterModeError.developerAccessDenied
        }

        let lease = try await busCoordinator.acquire(purpose: .adapterManagement)
        await trace.attachOTAIdentifier()

        var elmRestored = false
        do {
            mode = .preparingOTA
            await hooks.stopPolling()
            await hooks.flushELMQueue()
            await hooks.stopMonitor()

            mode = .relinquishingELM
            await hooks.relinquishELM()

            mode = .jieliOTA
            try Task.checkCancellation()
            try await hooks.startJieliOTA()

            mode = .rebooting
            mode = .restoringELM
            try await hooks.restoreELM()
            elmRestored = true

            guard try await hooks.verifyELM() else {
                throw PTYMOBDAdapterModeError.verificationFailed
            }
            mode = .elm
            lastRecoveryMessage = nil
            await trace.record(name: "adapter_ota_recovered_to_elm")
            await busCoordinator.release(lease)
        } catch {
            // EN: Recovery is part of failure handling, not an optional cleanup detail.
            // ES: La recuperación forma parte del fallo, no es un detalle opcional de limpieza.
            // 中文：恢复是失败处理的一部分，不是可有可无的清理细节。
            mode = .failed
            if !elmRestored {
                do {
                    mode = .restoringELM
                    try await hooks.restoreELM()
                    elmRestored = true
                } catch {
                    lastRecoveryMessage = error.localizedDescription
                    mode = .failed
                    await busCoordinator.release(lease)
                    throw PTYMOBDAdapterModeError.recoveryFailed(error.localizedDescription)
                }
            }
            if elmRestored {
                mode = .elm
                lastRecoveryMessage = "OTA 失败，已恢复普通 ELM；请检查适配器版本后再决定是否重试。"
            }
            await trace.record(
                name: "adapter_ota_failed",
                metadata: ["error": error.localizedDescription, "mode": mode.rawValue]
            )
            await busCoordinator.release(lease)
            throw error
        }
    }
}
