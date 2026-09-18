//
//  PTTelemetryResearchManager.swift
//  PTSpeed
//
//  High-level orchestration.
//  No UIKit and no vehicle command/transport code belongs here.
//

import Foundation

nonisolated public enum PTTelemetryResearchError: Error, LocalizedError, Sendable {
    case notConfigured
    case consentRequired
    case sessionAlreadyRunning
    case noActiveSession

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Telemetry Research 尚未配置。"
        case .consentRequired:
            return "用户尚未开启匿名协议研究数据贡献。"
        case .sessionAlreadyRunning:
            return "Telemetry Research Session 已经在录制。"
        case .noActiveSession:
            return "当前没有正在录制的 Telemetry Research Session。"
        }
    }
}

nonisolated public enum PTTelemetryResearchState: Sendable, Equatable {
    case idle
    case recording(UUID)
    case preparingUpload(UUID)
    case uploading
}

public actor PTTelemetryResearchManager {

    public static let shared = PTTelemetryResearchManager()

    private var configuration: PTTelemetryConfiguration?
    private var state: PTTelemetryResearchState = .idle

    private let recorder: PTTelemetryRecorder
    private let queue: PTTelemetryUploadQueue
    private let uploader: PTCloudKitTelemetryUploader
    private let defaults: UserDefaults

    // MARK: - Automatic vehicle connection lifecycle

    /// 至少有一个真实 Dashboard / OBD 已经连接。
    private var lifecycleHasConnectedLink = false

    /// 至少有一个真实 Dashboard / OBD 正在 connecting / connected。
    /// 用它避免一边断开、另一边正在连接时提前结束 Session。
    private var lifecycleHasActiveLink = false

    /// 当前 Session 使用的匿名车辆上下文。
    private var lifecycleVehicleContext: PTTelemetryVehicleContext = .unknown

    /// CloudKit 上传和 Recording 是两个不同维度，不能让上传状态覆盖新 Session。
    private var uploadInProgress = false

    /// 如果上传期间又产生了一个需要上传的新 Session，
    //// 当前批次完成后再跑一轮。
    private var uploadRequestedWhileBusy = false
    
    public init(
        recorder: PTTelemetryRecorder = .shared,
        queue: PTTelemetryUploadQueue = .shared,
        uploader: PTCloudKitTelemetryUploader = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.recorder = recorder
        self.queue = queue
        self.uploader = uploader
        self.defaults = defaults
    }

    public func configure(
        _ configuration: PTTelemetryConfiguration
    ) async {
        self.configuration = configuration

        // 如果 Coordinator 比配置更早收到连接状态，
        // 配置完成后立即补一次生命周期校正。
        await reconcileVehicleLinkLifecycle()
    }

    public func currentState() -> PTTelemetryResearchState {
        state
    }

    public func isResearchEnabled() -> Bool {
        defaults.bool(
            forKey:
                PTTelemetryConfiguration
                    .consentDefaultsKey
        )
    }

    public func setResearchEnabled(
        _ enabled: Bool,
        purgePendingDataWhenDisabled: Bool = false
    ) async {

        defaults.set(
            enabled,
            forKey: PTTelemetryConfiguration.consentDefaultsKey
        )

        if enabled {
            // 用户开启研究贡献时，如果车已经连接，
            // 不必等待下一次 connection callback。
            await reconcileVehicleLinkLifecycle()
            return
        }

        await recorder.cancel()
        state = .idle

        if purgePendingDataWhenDisabled {
            await queue.purgeAll()
        }
    }
    
    public func synchronizeVehicleLinks(
        hasConnectedLink: Bool,
        hasActiveLink: Bool,
        vehicle: PTTelemetryVehicleContext
    ) async {

        // 即使研究功能暂时没开启，也先保存最新连接状态。
        // 这样用户开启开关时可以立即开始。
        lifecycleHasConnectedLink = hasConnectedLink
        lifecycleHasActiveLink = hasActiveLink
        lifecycleVehicleContext = vehicle

        await reconcileVehicleLinkLifecycle()
    }

    private func reconcileVehicleLinkLifecycle() async {

        guard configuration != nil,
              isResearchEnabled() else {
            return
        }

        switch state {

        case .idle, .uploading:

            // 真正有一个连接成功之后才开始。
            guard lifecycleHasConnectedLink else {
                return
            }

            do {
                _ = try await startSession(
                    vehicle: lifecycleVehicleContext
                )
            } catch {
                // 自动生命周期不能影响正常车辆连接。
            }

        case .recording:

            // connecting / connected 任意一个还存在，都继续当前 Session。
            guard !lifecycleHasActiveLink else {
                return
            }

            // Dashboard + OBD 都真正结束，才结束并上传。
            do {
                _ = try await finishSession(
                    uploadIfPossible: true
                )
            } catch {
                // 无有效事件等情况不能影响正常车辆连接。
            }

            // finish/encrypt/upload 是可重入 async。
            // 如果这段时间车辆又连接回来了，补开下一 Session。
            if lifecycleHasConnectedLink {
                await reconcileVehicleLinkLifecycle()
            }

        case .preparingUpload:
            // finishSession 正在生成加密 Envelope。
            // synchronizeVehicleLinks 已经保存最新状态，
            // 完成后上面的 reconcile 会再次检查。
            return
        }
    }

    @discardableResult
    public func startSession(
        vehicle: PTTelemetryVehicleContext = .unknown
    ) async throws -> UUID {

        guard let configuration else {
            throw PTTelemetryResearchError
                .notConfigured
        }

        guard isResearchEnabled() else {
            throw PTTelemetryResearchError
                .consentRequired
        }

        switch state {
        case .idle, .uploading:
            break
        case .recording, .preparingUpload:
            throw PTTelemetryResearchError
                .sessionAlreadyRunning
        }

        let sessionID = await recorder.start(
            vehicle: vehicle,
            configuration: configuration
        )

        state = .recording(
            sessionID
        )

        return sessionID
    }

    @discardableResult
    public func finishSession(
        uploadIfPossible: Bool? = nil
    ) async throws -> UUID {

        guard let configuration else {
            throw PTTelemetryResearchError
                .notConfigured
        }

        guard case .recording(
            let sessionID
        ) = state else {
            throw PTTelemetryResearchError
                .noActiveSession
        }

        guard let session = await recorder.stop() else {
            state = .idle
            throw PTTelemetryResearchError
                .noActiveSession
        }

        state = .preparingUpload(
            sessionID
        )

        do {
            let payload =
                try PTTelemetryPrivacySanitizer
                    .makeUploadPayload(
                        from: session
                    )

            let envelope =
                try PTTelemetryEncryptor
                    .encrypt(
                        payload,
                        configuration:
                            configuration
                    )

            defer {
                try? FileManager
                    .default
                    .removeItem(
                        at:
                            envelope
                                .payloadFileURL
                    )
            }

            _ = try await queue.enqueue(
                envelope
            )

            state = .idle

            let shouldUpload =
                uploadIfPossible
                ?? configuration
                    .autoUploadOnFinish

            if shouldUpload {
                await flushPendingUploads()
            }

            return sessionID

        } catch {
            state = .idle
            throw error
        }
    }

    public func cancelSession() async {
        await recorder.cancel()
        state = .idle
    }

    public func flushPendingUploads() async {

        guard let configuration,
              isResearchEnabled() else {
            return
        }

        if uploadInProgress {
            uploadRequestedWhileBusy = true
            return
        }

        uploadInProgress = true

        let shouldExposeUploadingState: Bool

        if case .idle = state {
            state = .uploading
            shouldExposeUploadingState = true
        } else {
            // 如果正在 recording，后台上传旧 Session
            // 不允许覆盖 recording 状态。
            shouldExposeUploadingState = false
        }

        defer {
            uploadInProgress = false

            if shouldExposeUploadingState,
               case .uploading = state {
                state = .idle
            }
        }

        var shouldStopUploading = false

        repeat {
            uploadRequestedWhileBusy = false

            let pending = await queue.pending(
                limit: configuration.uploadBatchSize
            )

            guard !pending.isEmpty else {
                break
            }

            for envelope in pending {
                do {
                    try Task.checkCancellation()

                    try await uploader.upload(
                        envelope,
                        containerIdentifier:
                            configuration.cloudKitContainerIdentifier
                    )

                    await queue.markUploaded(
                        sessionID: envelope.sessionID
                    )

                } catch is CancellationError {
                    shouldStopUploading = true
                    break

                } catch {
                    await queue.markFailed(
                        sessionID: envelope.sessionID,
                        error: error
                    )

                    // CloudKit 当前不可用时不要疯狂重试。
                    shouldStopUploading = true
                    break
                }
            }

            if shouldStopUploading {
                break
            }

        } while uploadRequestedWhileBusy
    }
    
    public func pendingUploadCount() async -> Int {
        await queue.pendingCount()
    }

    public func deletePendingUploadData() async {
        await queue.purgeAll()
    }

    /// End-to-end smoke test without connecting to the scooter or OBD.
    ///
    /// Preconditions:
    /// - configure() has been called
    /// - user consent is enabled
    @discardableResult
    public func runUploadSmokeTest(
        uploadIfPossible: Bool = true
    ) async throws -> UUID {

        _ = try await startSession(
            vehicle: .init(
                family:
                    "XP400-research-test"
            )
        )

        await PTTelemetryMarkerRecorder.record(
            .researchTest,
            value:
                "cloudkit-ingest-v1"
        )

        do {
            return try await finishSession(
                uploadIfPossible:
                    uploadIfPossible
            )
        } catch {
            await recorder.cancel()
            state = .idle
            throw error
        }
    }
}
