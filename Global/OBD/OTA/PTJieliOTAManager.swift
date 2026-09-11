//
//  PTJieliOTAManager.swift
//  CrazyDashboard
//
//  EN: Owns the guarded handoff from the stable ELM327 session to Jieli OTA.
//  ES: Controla la transferencia protegida desde la sesión ELM327 estable hacia Jieli OTA.
//  中文：负责从稳定 ELM327 会话切换到 Jieli OTA 的受保护流程。
//

@preconcurrency import CoreBluetooth
import Foundation

nonisolated public enum PTJieliOTAManagerError: Error, Equatable, LocalizedError, Sendable {
    case busy
    case developerAccessDenied
    case preflightFailed([String])
    case explicitConfirmationRequired
    case invalidFirmware
    case firmwareDigestMismatch
    case disconnected
    case unsupportedTransport
    case busUnavailable
    case sdkUnavailable
    case cancelled
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

    private let engine: PTJieliOTAEngine
    private var transport: PTJieliBLETransport?
    private var shouldRestoreOBD = false

    public init() {
        self.engine = PTJieliSDKOTAEngine()
    }

    public init(engine: PTJieliOTAEngine) {
        self.engine = engine
    }

    /// EN: Starts only from the P2 decrypted artifact, never from encrypted server bytes.
    /// ES: Solo comienza con el artefacto descifrado de P2, nunca con bytes cifrados del servidor.
    /// 中文：只允许从 P2 解密后的固件开始，绝不直接使用服务器加密字节。
    public func start(
        readOnlyResult: PTYMOBDFirmwareReadOnlyResult,
        checklist: PTDeveloperTestChecklist,
        explicitlyConfirmed: Bool,
        deviceIdentifier: UUID? = nil,
        deviceName: String? = nil,
        characteristicMapping: PTJieliCharacteristicMapping = .automatic
    ) async throws -> PTOTAExecutionResult {
        guard !isRunning else {
            throw PTJieliOTAManagerError.busy
        }

        try validate(
            readOnlyResult: readOnlyResult,
            checklist: checklist,
            explicitlyConfirmed: explicitlyConfirmed
        )

        guard engine.isAvailable else {
            try reject(.sdkUnavailable)
        }

        let telemetry = PTMotoTelemetryManager.shared
        guard telemetry.isConnected else {
            try reject(.disconnected)
        }

        let obdConnector = PTHiddenOBDConnector.shared
        guard obdConnector.isUnlocked,
              let connectedPeripheral = obdConnector.obdPeripheral else {
            try reject(.disconnected)
        }

        let resolvedIdentifier = deviceIdentifier ?? connectedPeripheral.identifier
        let resolvedName = (deviceName ?? connectedPeripheral.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedName.isEmpty || deviceName == nil else {
            try reject(.disconnected)
        }

        let session = PTOTASession(
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
        transition(to: .checking, detail: "准备 Jieli OTA")

        var lease: PTOBDBusLeaseToken?
        let nextTransport = PTJieliBLETransport()
        transport = nextTransport

        do {
            lease = try await PTOBDBusLease.shared.acquire(
                kind: .developerWrite,
                timeout: 30
            )
            try Task.checkCancellation()

            // EN: Stop every normal ELM327 producer before changing the BLE service surface.
            // ES: Detiene todos los productores ELM327 normales antes de cambiar la superficie BLE.
            // 中文：切换 BLE 服务面之前，先停止所有普通 ELM327 数据生产者。
            telemetry.telemetryPollingTask?.cancel()
            telemetry.telemetryPollingTask = nil
            telemetry.stopKeepAliveHeartbeat()
            try? await Task.sleep(nanoseconds: 100_000_000)

            // EN: The stable connector still owns the normal ELM327 teardown; this manager only owns the OTA handoff.
            // ES: El conector estable sigue controlando el cierre ELM327 normal; este gestor solo controla la transferencia OTA.
            // 中文：普通 ELM327 的拆除仍由稳定连接器负责，本管理器只负责 OTA 交接。
            telemetry.disconnect()
            shouldRestoreOBD = true
            try Task.checkCancellation()

            transition(to: .preparing, detail: "连接 Jieli OTA 服务")
            let discovery = try await nextTransport.connect(
                identifier: resolvedIdentifier,
                name: resolvedName.isEmpty ? nil : resolvedName,
                mapping: characteristicMapping,
                timeout: 20
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
            transition(to: .verifyingVersion, detail: "等待重新读取 AT+VERSION")
            restoreNormalOBDConnection()

            let result = PTOTAExecutionResult(
                session: session,
                finalState: .verifyingVersion,
                versionVerified: false
            )
            finishSuccessfully(result)
            if let lease {
                await PTOBDBusLease.shared.release(lease)
            }
            return result
        } catch {
            nextTransport.disconnect()
            if shouldRestoreOBD {
                restoreNormalOBDConnection()
            }

            let mappedError = map(error)
            finishWithFailure(mappedError)
            if let lease {
                await PTOBDBusLease.shared.release(lease)
            }
            throw mappedError
        }
    }

    public func cancel() {
        guard isRunning else { return }
        engine.cancelOTA()
        transport?.disconnect()
    }
}

private extension PTJieliOTAManager {
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
            transition(to: .preparing, detail: "设备要求强制 OTA")
        case .onNeedReconnect:
            transition(to: .reconnecting, detail: "等待 OTA 重连")
        case .onStopOTA:
            transition(to: .verifying, detail: "设备已停止 OTA，等待版本复核")
        case .onError:
            transition(to: .failed, detail: "Jieli OTA SDK 报告错误")
        }
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
    }

    func notifyState() {
        delegate?.jieliOTAManager(self, didChange: state, progress: progress)
    }

    func finishSuccessfully(_ result: PTOTAExecutionResult) {
        isRunning = false
        shouldRestoreOBD = false
        transport = nil
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
        // EN: Re-enter the existing ELM327 path; no second polling engine is created here.
        // ES: Vuelve a la ruta ELM327 existente; aquí no se crea un segundo motor de sondeo.
        // 中文：重新进入现有 ELM327 路径，不在这里创建第二套轮询引擎。
        PTMotoTelemetryManager.shared.connectToMotorcycle(via: .bluetooth)
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
        if error is PTOBDBusLeaseError {
            return .busUnavailable
        }
        return .transportFailed(error.localizedDescription)
    }
}
