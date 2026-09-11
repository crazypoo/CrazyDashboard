//
//  PTJieliOTAManager.swift
//  CrazyDashboard
//
//  P4 productized OTA coordinator built on the existing official Jieli SDK engine.
//  This file replaces the current Global/OBD/OTA/PTJieliOTAManager.swift.
//

@preconcurrency import CoreBluetooth
import Foundation

nonisolated public enum PTJieliOTAManagerError: Error, Equatable, LocalizedError, Sendable {
    case busy
    case developerAccessDenied
    case preflightFailed([String])
    case powerPreflightFailed([String])
    case explicitConfirmationRequired
    case invalidFirmware
    case firmwareDigestMismatch
    case disconnected
    case unsupportedTransport
    case busUnavailable
    case sdkUnavailable
    case cancelled
    case resumeUnavailable
    case resumePersistenceFailed(String)
    case versionVerificationFailed(expected: String, actual: String?)
    case transportFailed(String)
    case engineFailed(PTJieliOTAEngineError)

    public var errorDescription: String? {
        switch self {
        case .busy:
            return "Jieli OTA 正在执行"
        case .developerAccessDenied:
            return "开发者高风险开关未开启"
        case let .preflightFailed(blockers):
            return "OTA 前置检查未通过：" + blockers.joined(separator: ", ")
        case let .powerPreflightFailed(blockers):
            return "OTA 电源检查未通过：" + blockers.joined(separator: ", ")
        case .explicitConfirmationRequired:
            return "OTA 需要开发者明确确认"
        case .invalidFirmware:
            return "解密后的固件无效"
        case .firmwareDigestMismatch:
            return "解密固件摘要与只读报告不一致"
        case .disconnected:
            return "当前没有可交接的 ELM327 蓝牙连接"
        case .unsupportedTransport:
            return "当前连接不是可交接的 ELM327 蓝牙传输"
        case .busUnavailable:
            return "OBD 总线暂时被其他任务占用"
        case .sdkUnavailable:
            return "Jieli OTA SDK 不可用"
        case .cancelled:
            return "Jieli OTA 已取消"
        case .resumeUnavailable:
            return "没有可恢复的 OTA 会话"
        case let .resumePersistenceFailed(message):
            return "OTA 恢复点不可用：" + message
        case let .versionVerificationFailed(expected, actual):
            return "OTA 版本复核失败，目标 \(expected)，实际 \(actual ?? "未知")"
        case let .transportFailed(message):
            return "Jieli OTA 传输失败：" + message
        case let .engineFailed(error):
            return error.localizedDescription
        }
    }
}

@MainActor
public protocol PTJieliOTAManagerDelegate: AnyObject {
    func jieliOTAManager(
        _ manager: PTJieliOTAManager,
        didChange state: PTOTAState,
        progress: PTOTAProgress
    )
    func jieliOTAManager(
        _ manager: PTJieliOTAManager,
        didFinish result: PTOTAExecutionResult
    )
    func jieliOTAManager(
        _ manager: PTJieliOTAManager,
        didFail error: PTJieliOTAManagerError
    )
}

@MainActor
public extension PTJieliOTAManagerDelegate {
    func jieliOTAManager(
        _ manager: PTJieliOTAManager,
        didChange state: PTOTAState,
        progress: PTOTAProgress
    ) {}

    func jieliOTAManager(
        _ manager: PTJieliOTAManager,
        didFinish result: PTOTAExecutionResult
    ) {}

    func jieliOTAManager(
        _ manager: PTJieliOTAManager,
        didFail error: PTJieliOTAManagerError
    ) {}
}

@MainActor
public final class PTJieliOTAManager {
    public static let shared = PTJieliOTAManager()

    public weak var delegate: PTJieliOTAManagerDelegate?
    public private(set) var state: PTOTAState = .idle
    public private(set) var progress: PTOTAProgress = .zero
    public private(set) var currentSession: PTOTASession?
    public private(set) var lastError: PTJieliOTAManagerError?
    public private(set) var isRunning = false
    public private(set) var isMandatoryUpgrade = false
    public private(set) var reconnectCount = 0
    public private(set) var currentPowerReport: PTOTAPowerPreflightReport?
    public private(set) var currentConfiguration: PTOTAProductConfiguration = .default

    private let engine: PTJieliOTAEngine
    private let resumeStore: PTOTAResumeStore
    private let analyticsLogger: PTOTAAnalyticsLogger
    private var transport: PTJieliBLETransport?
    private var shouldRestoreOBD = false

    public init() {
        self.engine = PTJieliSDKOTAEngine()
        self.resumeStore = .shared
        self.analyticsLogger = .shared
    }

    public init(
        engine: PTJieliOTAEngine,
        resumeStore: PTOTAResumeStore = .shared,
        analyticsLogger: PTOTAAnalyticsLogger = .shared
    ) {
        self.engine = engine
        self.resumeStore = resumeStore
        self.analyticsLogger = analyticsLogger
    }

    /// Starts from the decrypted artifact produced by the existing P2 read-only flow.
    /// Existing call sites remain source-compatible because the P4 configuration has a default value.
    public func start(
        readOnlyResult: PTYMOBDFirmwareReadOnlyResult,
        checklist: PTDeveloperTestChecklist,
        explicitlyConfirmed: Bool,
        deviceIdentifier: UUID? = nil,
        deviceName: String? = nil,
        characteristicMapping: PTJieliCharacteristicMapping = .automatic,
        productConfiguration: PTOTAProductConfiguration = .default
    ) async throws -> PTOTAExecutionResult {
        try await performStart(
            readOnlyResult: readOnlyResult,
            checklist: checklist,
            explicitlyConfirmed: explicitlyConfirmed,
            deviceIdentifier: deviceIdentifier,
            deviceName: deviceName,
            characteristicMapping: characteristicMapping,
            productConfiguration: productConfiguration,
            existingSession: nil,
            isProcessRecovery: false
        )
    }

    /// Returns a persisted interrupted session, if P4 previously reached the OTA handoff.
    public func pendingResumeCheckpoint() async -> PTOTAResumeCheckpoint? {
        try? await resumeStore.load()
    }

    /// Process-recovery entry point. JL_OTALib still owns true in-session offset resume through
    /// cmdOtaDataIIResult; this method restores the prepared firmware/session after an app restart.
    public func resumeInterruptedUpgrade(
        checklist: PTDeveloperTestChecklist,
        explicitlyConfirmed: Bool,
        characteristicMapping: PTJieliCharacteristicMapping = .automatic
    ) async throws -> PTOTAExecutionResult {
        guard !isRunning else { throw PTJieliOTAManagerError.busy }
        guard let checkpoint = try await resumeStore.load() else {
            throw PTJieliOTAManagerError.resumeUnavailable
        }

        let firmware: Data
        do {
            firmware = try await resumeStore.loadFirmware(for: checkpoint)
        } catch {
            throw PTJieliOTAManagerError.resumePersistenceFailed(error.localizedDescription)
        }

        let readOnlyResult = checkpoint.makeReadOnlyResult(decryptedFirmware: firmware)
        let identifier = UUID(uuidString: checkpoint.session.deviceIdentifier)
        return try await performStart(
            readOnlyResult: readOnlyResult,
            checklist: checklist,
            explicitlyConfirmed: explicitlyConfirmed,
            deviceIdentifier: identifier,
            deviceName: checkpoint.session.deviceName.isEmpty ? nil : checkpoint.session.deviceName,
            characteristicMapping: characteristicMapping,
            productConfiguration: checkpoint.configuration,
            existingSession: checkpoint.session,
            isProcessRecovery: true
        )
    }

    public func discardInterruptedUpgrade() async {
        try? await resumeStore.clear(deleteFirmware: true)
    }

    public func exportCurrentLogURL() async throws -> URL {
        guard let currentSession else {
            throw PTOTAAnalyticsLoggerError.sessionUnavailable
        }
        return try await analyticsLogger.exportURL(for: currentSession.id)
    }

    public func exportLogURL(for sessionID: UUID) async throws -> URL {
        try await analyticsLogger.exportURL(for: sessionID)
    }

    public func cancel() {
        guard isRunning else { return }
        if isMandatoryUpgrade && !currentConfiguration.allowsCancelWhenMandatory {
            logEvent(name: "cancel_blocked", message: "Mandatory OTA blocks user cancellation")
            return
        }
        logEvent(name: "cancel_requested", message: "User requested OTA cancellation")
        engine.cancelOTA()
        transport?.disconnect()
    }
}

private extension PTJieliOTAManager {
    func performStart(
        readOnlyResult: PTYMOBDFirmwareReadOnlyResult,
        checklist: PTDeveloperTestChecklist,
        explicitlyConfirmed: Bool,
        deviceIdentifier: UUID?,
        deviceName: String?,
        characteristicMapping: PTJieliCharacteristicMapping,
        productConfiguration: PTOTAProductConfiguration,
        existingSession: PTOTASession?,
        isProcessRecovery: Bool
    ) async throws -> PTOTAExecutionResult {
        guard !isRunning else { throw PTJieliOTAManagerError.busy }

        try validate(
            readOnlyResult: readOnlyResult,
            checklist: checklist,
            explicitlyConfirmed: explicitlyConfirmed
        )
        guard engine.isAvailable else { try reject(.sdkUnavailable) }

        currentConfiguration = productConfiguration
        isMandatoryUpgrade = productConfiguration.isMandatoryUpdate
        reconnectCount = 0
        currentPowerReport = PTOTAPowerPreflight.evaluate(configuration: productConfiguration)
        if let blockers = currentPowerReport?.blockers, !blockers.isEmpty {
            try reject(.powerPreflightFailed(blockers))
        }

        let telemetry = PTMotoTelemetryManager.shared
        let obdConnector = PTHiddenOBDConnector.shared
        let connectedPeripheral = (telemetry.isConnected && obdConnector.isUnlocked)
            ? obdConnector.obdPeripheral
            : nil

        // 首次升级必须由已解锁的普通 YMOBD session 交接。
        // 进程恢复允许设备已经停留在 Jieli OTA 模式，此时普通 FFF0 session 可能暂时不存在。
        if !isProcessRecovery {
            guard telemetry.isConnected, connectedPeripheral != nil else {
                try reject(.disconnected)
            }
        }

        guard let resolvedIdentifier = deviceIdentifier ?? connectedPeripheral?.identifier else {
            try reject(.disconnected)
        }
        let resolvedName = (deviceName ?? connectedPeripheral?.name ?? existingSession?.deviceName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedName.isEmpty || deviceName == nil else {
            try reject(.disconnected)
        }

        let session = existingSession ?? PTOTASession(
            deviceIdentifier: resolvedIdentifier.uuidString,
            deviceName: resolvedName,
            oldFirmwareVersion: readOnlyResult.checkResult.request.obdFirmwareVersion,
            targetFirmwareVersion: readOnlyResult.checkResult.metadata.firmwareVersion,
            firmwareFileUUID: readOnlyResult.checkResult.metadata.firmwareFileUUID,
            firmwareByteCount: readOnlyResult.decryptedFirmware.count,
            firmwareSHA256: readOnlyResult.report.decryptedSHA256
        )

        currentSession = session
        lastError = nil
        isRunning = true
        shouldRestoreOBD = false
        progress = .zero
        transition(
            to: .checking,
            detail: isProcessRecovery ? "恢复未完成的 Jieli OTA" : "准备 Jieli OTA"
        )

        do {
            if isProcessRecovery {
                try await resumeStore.update(
                    state: state,
                    progress: progress,
                    reconnectCount: reconnectCount
                )
                await analyticsLogger.record(
                    session: session,
                    name: "process_resume",
                    state: state,
                    progress: progress,
                    reconnectCount: reconnectCount,
                    message: "Recovered persisted P4 OTA session"
                )
            } else {
                _ = try await resumeStore.saveInitial(
                    session: session,
                    readOnlyResult: readOnlyResult,
                    configuration: productConfiguration,
                    state: state,
                    progress: progress
                )
                if let currentPowerReport {
                    await analyticsLogger.start(
                        session: session,
                        mandatory: isMandatoryUpgrade,
                        power: currentPowerReport.snapshot
                    )
                }
            }
        } catch {
            isRunning = false
            throw PTJieliOTAManagerError.resumePersistenceFailed(error.localizedDescription)
        }

        var lease: PTOBDBusLeaseToken?
        let nextTransport = PTJieliBLETransport()
        transport = nextTransport

        do {
            lease = try await PTOBDBusLease.shared.acquire(
                kind: .developerWrite,
                timeout: 30
            )
            try Task.checkCancellation()

            if telemetry.isConnected {
                telemetry.telemetryPollingTask?.cancel()
                telemetry.telemetryPollingTask = nil
                telemetry.stopKeepAliveHeartbeat()
                try? await Task.sleep(nanoseconds: 100_000_000)
                telemetry.disconnect()
            }
            // OTA 结束后始终恢复普通 FFF0/YMOBD，用 AT+VERSION 作为最终成功门槛。
            shouldRestoreOBD = true
            try Task.checkCancellation()

            transition(to: .preparing, detail: "连接 Jieli OTA 服务")
            let discovery = try await nextTransport.connect(
                identifier: resolvedIdentifier,
                name: resolvedName.isEmpty ? nil : resolvedName,
                mapping: characteristicMapping,
                timeout: 20
            )
            logEvent(
                name: "ota_transport_ready",
                message: "service=\(discovery.serviceUUID), write=\(discovery.selection.writeUUID), notify=\(discovery.selection.notifyUUID)"
            )

            try await engine.startOTA(
                firmwareData: readOnlyResult.decryptedFirmware,
                transport: nextTransport,
                discovery: discovery,
                progress: { [weak self] value in
                    self?.updateProgress(value)
                },
                event: { [weak self] event in
                    self?.handle(event: event)
                },
                reconnect: { @MainActor [weak nextTransport] in
                    guard let nextTransport else {
                        throw PTJieliOTAEngineError.reconnectFailed
                    }
                    return try await nextTransport.reconnect(timeout: 20)
                }
            )

            nextTransport.disconnect()
            transport = nil

            // Release the developer-write bus lease before bringing the normal ELM/YMOBD path back.
            if let currentLease = lease {
                await PTOBDBusLease.shared.release(currentLease)
                lease = nil
            }

            transition(to: .verifyingVersion, detail: "OTA 已停止，重新连接普通 YMOBD 并读取 AT+VERSION")
            restoreNormalOBDConnection()

            let verification = try await PTOTAVersionVerifier.verify(
                targetVersion: session.targetFirmwareVersion,
                reconnectTimeout: productConfiguration.normalOBDReconnectTimeout,
                commandTimeout: productConfiguration.versionVerificationTimeout
            )

            transition(
                to: .completed,
                detail: "版本已确认：\(verification.actualVersion)"
            )
            let result = PTOTAExecutionResult(
                session: session,
                finalState: .completed,
                versionVerified: true
            )

            await analyticsLogger.record(
                session: session,
                name: "version_verified",
                state: .completed,
                progress: progress,
                reconnectCount: reconnectCount,
                message: "AT+VERSION verified",
                metadata: [
                    "expectedVersion": verification.expectedVersion,
                    "actualVersion": verification.actualVersion
                ]
            )
            try? await resumeStore.clear(deleteFirmware: true)
            finishSuccessfully(result)
            return result
        } catch {
            nextTransport.disconnect()
            transport = nil

            if let currentLease = lease {
                await PTOBDBusLease.shared.release(currentLease)
                lease = nil
            }
            if shouldRestoreOBD {
                restoreNormalOBDConnection()
            }

            let mappedError = map(error)
            let failureState: PTOTAState = mappedError == .cancelled ? .cancelled : .failed
            state = failureState

            if mappedError == .cancelled || !productConfiguration.keepResumeCheckpointOnFailure {
                try? await resumeStore.clear(deleteFirmware: true)
            } else {
                try? await resumeStore.update(
                    state: failureState,
                    progress: progress,
                    reconnectCount: reconnectCount
                )
            }

            await analyticsLogger.record(
                session: session,
                name: mappedError == .cancelled ? "cancelled" : "failed",
                state: failureState,
                progress: progress,
                reconnectCount: reconnectCount,
                message: mappedError.localizedDescription
            )
            finishWithFailure(mappedError)
            throw mappedError
        }
    }

    func validate(
        readOnlyResult: PTYMOBDFirmwareReadOnlyResult,
        checklist: PTDeveloperTestChecklist,
        explicitlyConfirmed: Bool
    ) throws {
        let preflight = PTDeveloperTestPreflight.evaluate(
            level: .firmware,
            checklist: checklist
        )
        guard preflight.isReady else {
            try reject(.preflightFailed(preflight.blockers))
        }
        guard PTDeveloperSafetyGate.shared.authorize(
            .firmwareFlash,
            protocolEvidenceAvailable: checklist.protocolEvidenceAvailable
        ) else {
            try reject(.developerAccessDenied)
        }

        guard explicitlyConfirmed else {
            state = .ready
            lastError = .explicitConfirmationRequired
            notifyState()
            throw PTJieliOTAManagerError.explicitConfirmationRequired
        }

        let firmware = readOnlyResult.decryptedFirmware
        guard !firmware.isEmpty,
              firmware.count <= PTFirmwareArtifactInspector.maximumFileSize,
              !readOnlyResult.checkResult.metadata.firmwareVersion.isEmpty,
              !readOnlyResult.checkResult.metadata.firmwareFileUUID.isEmpty else {
            try reject(.invalidFirmware)
        }

        let actualDigest = PTYMOBDFirmwareCrypto.sha256Hex(firmware)
        guard actualDigest.caseInsensitiveCompare(readOnlyResult.report.decryptedSHA256) == .orderedSame else {
            try reject(.firmwareDigestMismatch)
        }
    }

    func reject(_ error: PTJieliOTAManagerError) throws -> Never {
        finishWithFailure(error)
        throw error
    }

    func updateProgress(_ value: PTOTAProgress) {
        progress = value
        delegate?.jieliOTAManager(self, didChange: state, progress: value)
        persistCheckpoint()
        logEvent(name: "progress", message: value.detail)
    }

    func handle(event: PTJieliOTAEvent) {
        switch event {
        case .onInitCompleted:
            transition(to: .preparing, detail: "Jieli OTA SDK 已初始化")
        case .onOtaReady:
            transition(to: .ready, detail: "设备已通过 OTA 能力查询")
        case .onStartOTA, .onProgress:
            transition(to: .upgrading, detail: "正在传输固件")
        case .onMandatoryUpgrade:
            isMandatoryUpgrade = true
            transition(to: .preparing, detail: "设备要求强制 OTA")
        case .onNeedReconnect:
            reconnectCount += 1
            transition(to: .reconnecting, detail: "等待 OTA 重连（第 \(reconnectCount) 次）")
        case .onStopOTA:
            transition(to: .verifying, detail: "设备已停止 OTA，等待版本复核")
        case .onError:
            transition(to: .failed, detail: "Jieli OTA SDK 报告错误")
        }
        logEvent(name: event.rawValue, message: progress.detail)
    }

    func transition(to nextState: PTOTAState, detail: String?) {
        state = nextState
        if let detail {
            progress = PTOTAProgress(
                phase: progress.phase,
                completedBytes: progress.completedBytes,
                totalBytes: progress.totalBytes,
                fractionCompleted: progress.fractionCompleted,
                detail: detail
            )
        }
        notifyState()
        persistCheckpoint()
    }

    func notifyState() {
        delegate?.jieliOTAManager(self, didChange: state, progress: progress)
    }

    func finishSuccessfully(_ result: PTOTAExecutionResult) {
        isRunning = false
        shouldRestoreOBD = false
        transport = nil
        lastError = nil
        delegate?.jieliOTAManager(self, didFinish: result)
    }

    func finishWithFailure(_ error: PTJieliOTAManagerError) {
        isRunning = false
        lastError = error
        state = error == .cancelled ? .cancelled : .failed
        shouldRestoreOBD = false
        transport = nil
        notifyState()
        delegate?.jieliOTAManager(self, didFail: error)
    }

    func restoreNormalOBDConnection() {
        guard shouldRestoreOBD else { return }
        shouldRestoreOBD = false
        PTMotoTelemetryManager.shared.connectToMotorcycle(via: .bluetooth)
    }

    func persistCheckpoint() {
        let state = state
        let progress = progress
        let reconnectCount = reconnectCount
        Task {
            try? await resumeStore.update(
                state: state,
                progress: progress,
                reconnectCount: reconnectCount
            )
        }
    }

    func logEvent(name: String, message: String? = nil) {
        guard let session = currentSession else { return }
        let state = state
        let progress = progress
        let reconnectCount = reconnectCount
        Task {
            await analyticsLogger.record(
                session: session,
                name: name,
                state: state,
                progress: progress,
                reconnectCount: reconnectCount,
                message: message
            )
        }
    }

    func map(_ error: Error) -> PTJieliOTAManagerError {
        if let error = error as? PTJieliOTAManagerError {
            return error
        }
        if error is CancellationError {
            return .cancelled
        }
        if let error = error as? PTJieliOTAEngineError {
            return error == .cancelled ? .cancelled : .engineFailed(error)
        }
        if let error = error as? PTJieliBLETransportError {
            return error == .cancelled ? .cancelled : .transportFailed(error.localizedDescription)
        }
        if let error = error as? PTOTAVersionVerificationError {
            switch error {
            case let .mismatch(expected, actual):
                return .versionVerificationFailed(expected: expected, actual: actual)
            case .emptyVersionResponse, .reconnectTimeout, .commandFailed:
                return .versionVerificationFailed(
                    expected: currentSession?.targetFirmwareVersion ?? "未知",
                    actual: nil
                )
            }
        }
        if let error = error as? PTOTAResumeStoreError {
            return .resumePersistenceFailed(error.localizedDescription)
        }
        if error is PTOBDBusLeaseError {
            return .busUnavailable
        }
        return .transportFailed(error.localizedDescription)
    }
}
