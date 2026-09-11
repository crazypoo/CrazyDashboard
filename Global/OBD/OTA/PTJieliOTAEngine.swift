//
//  PTJieliOTAEngine.swift
//  CrazyDashboard
//
//  EN: Bridges the official Jieli OTA SDK to the app-owned CoreBluetooth transport.
//  ES: Conecta el SDK OTA oficial de Jieli con el transporte CoreBluetooth de la app.
//  中文：把官方 Jieli OTA SDK 接入应用自有的 CoreBluetooth 传输适配器。
//

@preconcurrency import Foundation
import JL_OTALib
import OSLog

public typealias PTJieliOTAProgressHandler = @MainActor @Sendable (PTOTAProgress) -> Void
public typealias PTJieliOTAEventHandler = @MainActor @Sendable (PTJieliOTAEvent) -> Void
public typealias PTJieliOTAReconnectHandler = @MainActor @Sendable () async throws -> PTJieliBLETransportDiscovery

nonisolated public enum PTJieliOTAEngineError: Error, Equatable, LocalizedError, Sendable {
    case sdkUnavailable
    case invalidFirmware
    case invalidState
    case cancelled
    case featureTimeout
    case transferTimeout
    case authenticationFailed
    case transferFailed
    case reconnectFailed
    case sdkResult(UInt16)
    case transportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return "Jieli OTA SDK 不可用"
        case .invalidFirmware:
            return "固件数据为空或超过允许大小"
        case .invalidState:
            return "Jieli OTA 当前状态不允许执行此操作"
        case .cancelled:
            return "Jieli OTA 已取消"
        case .featureTimeout:
            return "Jieli OTA 设备能力查询超时"
        case .transferTimeout:
            return "Jieli OTA 传输超时"
        case .authenticationFailed:
            return "Jieli OTA 认证失败"
        case .transferFailed:
            return "Jieli OTA 固件传输失败"
        case .reconnectFailed:
            return "Jieli OTA 重连失败"
        case let .sdkResult(code):
            return "Jieli OTA 返回错误码 " + String(format: "0x%02X", code)
        case let .transportFailed(message):
            return "Jieli OTA 传输失败：" + message
        }
    }
}

@MainActor
public protocol PTJieliOTAEngine: AnyObject {
    var isAvailable: Bool { get }

    func startOTA(
        firmwareData: Data,
        transport: PTJieliBLETransport,
        discovery: PTJieliBLETransportDiscovery,
        progress: @escaping PTJieliOTAProgressHandler,
        event: @escaping PTJieliOTAEventHandler,
        reconnect: @escaping PTJieliOTAReconnectHandler
    ) async throws

    func cancelOTA()
}

// EN: This adapter deliberately uses JL_OTAManager as the only RCSP/OTA implementation.
// ES: Este adaptador usa deliberadamente JL_OTAManager como única implementación RCSP/OTA.
// 中文：这个适配器明确只使用 JL_OTAManager 实现 RCSP/OTA，不重复实现协议。
@MainActor
public final class PTJieliSDKOTAEngine: NSObject, PTJieliOTAEngine, @preconcurrency JL_OTAManagerDelegate {
    public let isAvailable = true

    private let sdkManager: JL_OTAManager
    private weak var transport: PTJieliBLETransport?
    private var notificationTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var featureTimeoutTask: Task<Void, Never>?
    private var transferTimeoutTask: Task<Void, Never>?
    private var featureContinuation: CheckedContinuation<Void, Error>?
    private var transferContinuation: CheckedContinuation<Void, Error>?
    private var progressHandler: PTJieliOTAProgressHandler?
    private var eventHandler: PTJieliOTAEventHandler?
    private var reconnectHandler: PTJieliOTAReconnectHandler?
    private var isRunning = false
    private var isCancelling = false
    private var isReconnecting = false
    private var didEmitReady = false
    private var didEmitStart = false

    private let featureTimeout: TimeInterval = 12
    private let transferTimeout: TimeInterval = 20 * 60
    private let maximumReconnectAttempts = 3
    private static let maximumFirmwareBytes = 64 * 1024 * 1024
    private let logger = Logger(subsystem: "com.yd.PTSpeed", category: "Jieli.OTA")

    public init(sdkManager: JL_OTAManager = .getOTAManager()) {
        self.sdkManager = sdkManager
        super.init()
    }

    deinit {
        notificationTask?.cancel()
        reconnectTask?.cancel()
        featureTimeoutTask?.cancel()
        transferTimeoutTask?.cancel()
    }

    public func startOTA(
        firmwareData: Data,
        transport: PTJieliBLETransport,
        discovery: PTJieliBLETransportDiscovery,
        progress: @escaping PTJieliOTAProgressHandler,
        event: @escaping PTJieliOTAEventHandler,
        reconnect: @escaping PTJieliOTAReconnectHandler
    ) async throws {
        guard isAvailable else { throw PTJieliOTAEngineError.sdkUnavailable }
        guard !isRunning else { throw PTJieliOTAEngineError.invalidState }
        guard !firmwareData.isEmpty,
              firmwareData.count <= Self.maximumFirmwareBytes else {
            throw PTJieliOTAEngineError.invalidFirmware
        }
        guard transport.isReady else { throw PTJieliBLETransportError.notConnected }
        try Task.checkCancellation()

        isRunning = true
        isCancelling = false
        isReconnecting = false
        didEmitReady = false
        didEmitStart = false
        self.transport = transport
        progressHandler = progress
        eventHandler = event
        reconnectHandler = reconnect

        configureSDK(for: discovery)

        // EN: Subscribe before feature discovery so the first authenticated RCSP response cannot be lost.
        // ES: Se suscribe antes de descubrir capacidades para no perder la primera respuesta RCSP autenticada.
        // 中文：在能力发现前先订阅通知，避免丢失第一条经过认证的 RCSP 响应。
        let notificationStream = transport.makeNotificationStream()
        notificationTask = Task { @MainActor [weak self] in
            for await data in notificationStream {
                guard let self, self.isRunning else { return }
                self.sdkManager.cmdOtaDataReceive(data)
            }
        }

        do {
            try await waitForFeature()
            emit(.onInitCompleted)
            emit(.onOtaReady)
            try Task.checkCancellation()
            try await beginTransfer(firmwareData)
        } catch {
            cleanupSDK()
            throw normalize(error)
        }

        cleanupSDK()
    }

    public func cancelOTA() {
        guard isRunning else { return }
        isCancelling = true

        // EN: Let the SDK produce its official cancel frame before tearing down the transport.
        // ES: Deja que el SDK produzca su trama oficial de cancelación antes de cerrar el transporte.
        // 中文：先让 SDK 生成官方取消帧，再拆除传输连接。
        if transferContinuation != nil {
            sdkManager.cmdOTACancelResult { [weak self] _, _, _ in
                Task { @MainActor [weak self] in
                    self?.resumeTransfer(.failure(PTJieliOTAEngineError.cancelled))
                }
            }
        }

        resumeFeature(.failure(PTJieliOTAEngineError.cancelled))
        resumeTransfer(.failure(PTJieliOTAEngineError.cancelled))
        cleanupSDK()
    }

    // MARK: - JL_OTAManagerDelegate

    public func otaDataSend(_ data: Data) {
        guard isRunning, !isCancelling else { return }
        guard let transport else {
            fail(.transportFailed("传输适配器已释放"))
            return
        }

        do {
            // EN: JL_OTAManager calls this synchronously; do not suspend before submitting the SDK frame.
            // ES: JL_OTAManager llama de forma síncrona; no suspendas antes de enviar la trama del SDK.
            // 中文：JL_OTAManager 会同步调用这里，不能在提交 SDK 数据帧前挂起任务。
            try transport.writeImmediately(data)
        } catch {
            fail(.transportFailed(error.localizedDescription))
        }
    }

    public func otaFeatureResult(_ manager: JL_OTAManager) {
        guard manager === sdkManager else { return }
        resumeFeature(.success(()))
    }

    public func otaUpgradeResult(_ result: JL_OTAResult, progress: Float) {
        handleSDKResult(result, progress: progress)
    }

    public func otaCancel() {
        resumeTransfer(.failure(PTJieliOTAEngineError.cancelled))
    }
}

private extension PTJieliSDKOTAEngine {
    func configureSDK(for discovery: PTJieliBLETransportDiscovery) {
        sdkManager.delegate = self
        sdkManager.bleOnly = true
        sdkManager.mBLE_UUID = discovery.peripheralIdentifier.uuidString
        sdkManager.mBLE_NAME = discovery.peripheralName
        sdkManager.otaStatus = .normal
        sdkManager.otaReconnectType = .UUID
        sdkManager.otaSourceMode = .sourcesExtendModeFirmwareOnly
        sdkManager.logSendData(false)
        sdkManager.maxLostCount(10)
        sdkManager.cmdTimeOut(5)

        // EN: cmdTargetFeature performs the SDK-owned RCSP authentication handshake; the YMOBD AES key is never reused here.
        // ES: cmdTargetFeature realiza el handshake RCSP del SDK; la clave AES de YMOBD nunca se reutiliza aquí.
        // 中文：cmdTargetFeature 负责 SDK 内部的 RCSP 认证握手，绝不复用 YMOBD 的 AES 密钥。
        logger.info("Jieli OTA SDK 已配置，service=\(discovery.serviceUUID, privacy: .public), write=\(discovery.selection.writeUUID, privacy: .public), notify=\(discovery.selection.notifyUUID, privacy: .public)")
    }

    func waitForFeature() async throws {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                featureContinuation = continuation
                featureTimeoutTask?.cancel()
                featureTimeoutTask = Task { @MainActor [weak self] in
                    do {
                        let timeout = self?.featureTimeout ?? 12
                        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        self?.resumeFeature(.failure(PTJieliOTAEngineError.featureTimeout))
                    } catch {
                        // EN: The watchdog is cancelled after the SDK reports its feature response or teardown begins.
                        // ES: El vigilante se cancela después de la respuesta de capacidades o al iniciar el cierre.
                        // 中文：SDK 返回能力结果或开始清理后，会取消这个看门狗。
                    }
                }
                sdkManager.noteEntityConnected()
                sdkManager.cmdTargetFeature()
            }
        }, onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.resumeFeature(.failure(PTJieliOTAEngineError.cancelled))
            }
        })
    }

    func beginTransfer(_ firmwareData: Data) async throws {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                transferContinuation = continuation
                transferTimeoutTask?.cancel()
                transferTimeoutTask = Task { @MainActor [weak self] in
                    do {
                        let timeout = self?.transferTimeout ?? 20 * 60
                        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        self?.resumeTransfer(.failure(PTJieliOTAEngineError.transferTimeout))
                    } catch {
                        // EN: The transfer watchdog is expected to be cancelled on completion or failure.
                        // ES: El vigilante de transferencia se cancela normalmente al completar o fallar.
                        // 中文：传输完成或失败时取消传输看门狗是正常流程。
                    }
                }
                sdkManager.cmdOTAData(firmwareData, result: nil)
            }
        }, onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelOTA()
            }
        })
    }

    func handleSDKResult(_ result: JL_OTAResult, progress: Float) {
        guard isRunning, !isCancelling else { return }

        switch result {
        case .preparing:
            emitProgress(result: result, phase: 0, progress: progress, detail: "准备 OTA")
        case .prepared:
            if !didEmitReady {
                didEmitReady = true
                emit(.onOtaReady)
            }
            emitProgress(result: result, phase: 0, progress: progress, detail: "OTA 准备完成")
        case .upgrading:
            if !didEmitStart {
                didEmitStart = true
                emit(.onStartOTA)
            }
            emitProgress(result: result, phase: 1, progress: progress, detail: "传输固件")
        case .reconnect, .reconnectWithMacAddr, .reconnectUpdateSource:
            emitProgress(result: result, phase: 1, progress: progress, detail: "等待 OTA 重连")
            startReconnect()
        case .reboot:
            emitProgress(result: result, phase: 1, progress: progress, detail: "设备准备重启")
        case .success:
            let total = max(sdkManager.otaLength, 0)
            progressHandler?(PTOTAProgress(
                phase: 1,
                completedBytes: total,
                totalBytes: total,
                fractionCompleted: 1,
                detail: "Jieli OTA 已完成"
            ))
            emit(.onStopOTA)
            resumeTransfer(.success(()))
        case .cancel:
            resumeTransfer(.failure(PTJieliOTAEngineError.cancelled))
        case .failKey:
            fail(.authenticationFailed)
        case .failVerification, .failCompletely, .failErrorFile, .failUboot,
             .failLenght, .failFlash, .failCmdTimeout, .failSameVersion,
             .failSameSN, .lowPower, .enterFail, .commandFail, .dataIsNull,
             .seekFail, .infoFail, .failedConnectMore, .failTWSDisconnect,
             .failNotInBin, .disconnect, .fail, .statusIsUpdating, .unknown:
            fail(errorForSDKResult(result))
        @unknown default:
            fail(.sdkResult(result.rawValue))
        }
    }

    func startReconnect() {
        guard !isReconnecting else { return }
        guard let reconnectHandler else {
            fail(.reconnectFailed)
            return
        }

        isReconnecting = true
        emit(.onNeedReconnect)
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastError: Error?

            for attempt in 0..<self.maximumReconnectAttempts {
                guard self.isRunning, !self.isCancelling else { return }
                do {
                    let discovery = try await reconnectHandler()
                    guard self.isRunning, !self.isCancelling else { return }
                    self.sdkManager.mBLE_UUID = discovery.peripheralIdentifier.uuidString
                    self.sdkManager.mBLE_NAME = discovery.peripheralName
                    self.sdkManager.noteEntityConnected()
                    self.isReconnecting = false

                    // EN: The SDK's second-step API resumes a single-backup OTA after the app-owned reconnect.
                    // ES: La API de segundo paso del SDK reanuda una OTA de copia única tras la reconexión de la app.
                    // 中文：应用完成重连后，使用 SDK 的第二阶段接口继续单备份 OTA。
                    self.sdkManager.cmdOtaDataIIResult { [weak self] result, progress in
                        Task { @MainActor [weak self] in
                            self?.handleSDKResult(result, progress: progress)
                        }
                    }
                    return
                } catch {
                    lastError = error
                    guard attempt + 1 < self.maximumReconnectAttempts else { break }
                    do {
                        try await Task.sleep(nanoseconds: UInt64((attempt + 1) * 500_000_000))
                    } catch {
                        return
                    }
                }
            }

            self.isReconnecting = false
            let detail = lastError?.localizedDescription ?? "未知重连错误"
            logger.error("Jieli OTA 重连失败: \(detail, privacy: .public)")
            self.fail(.reconnectFailed)
        }
    }

    func emit(_ event: PTJieliOTAEvent) {
        eventHandler?(event)
    }

    func emitProgress(result: JL_OTAResult, phase: Int, progress: Float, detail: String) {
        let fraction = normalizedFraction(progress)
        let total = max(sdkManager.otaLength, 0)
        let completed: Int64
        if total > 0 {
            completed = min(total, max(0, Int64((Double(total) * fraction).rounded(.down))))
        } else {
            completed = Int64(sdkManager.otaSent)
        }

        progressHandler?(PTOTAProgress(
            phase: phase,
            completedBytes: completed,
            totalBytes: total,
            fractionCompleted: fraction,
            detail: "\(detail)（0x\(String(format: "%02X", result.rawValue))）"
        ))
    }

    func normalizedFraction(_ progress: Float) -> Double {
        let value = Double(progress)
        guard value.isFinite else { return 0 }
        return min(max(value > 1 ? value / 100 : value, 0), 1)
    }

    func errorForSDKResult(_ result: JL_OTAResult) -> PTJieliOTAEngineError {
        switch result {
        case .failKey:
            return .authenticationFailed
        case .reconnect, .reconnectWithMacAddr, .reconnectUpdateSource:
            return .reconnectFailed
        default:
            return .sdkResult(result.rawValue)
        }
    }

    func fail(_ error: PTJieliOTAEngineError) {
        guard isRunning else { return }
        emit(.onError)
        resumeFeature(.failure(error))
        resumeTransfer(.failure(error))
        logger.error("Jieli OTA 失败: \(error.localizedDescription, privacy: .public)")
    }

    func normalize(_ error: Error) -> Error {
        if error is CancellationError {
            return PTJieliOTAEngineError.cancelled
        }
        if let error = error as? PTJieliOTAEngineError, error == .cancelled {
            return PTJieliOTAEngineError.cancelled
        }
        return error
    }

    func resumeFeature(_ result: Result<Void, Error>) {
        featureTimeoutTask?.cancel()
        featureTimeoutTask = nil
        guard let continuation = featureContinuation else { return }
        featureContinuation = nil
        switch result {
        case .success:
            continuation.resume()
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }

    func resumeTransfer(_ result: Result<Void, Error>) {
        transferTimeoutTask?.cancel()
        transferTimeoutTask = nil
        guard let continuation = transferContinuation else { return }
        transferContinuation = nil
        switch result {
        case .success:
            continuation.resume()
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }

    func cleanupSDK() {
        featureTimeoutTask?.cancel()
        featureTimeoutTask = nil
        transferTimeoutTask?.cancel()
        transferTimeoutTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        notificationTask?.cancel()
        notificationTask = nil
        sdkManager.noteEntityDisconnected()
        sdkManager.delegate = nil
        sdkManager.resetOTAManager()
        transport = nil
        progressHandler = nil
        eventHandler = nil
        reconnectHandler = nil
        isRunning = false
        isCancelling = false
        isReconnecting = false
    }
}
