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
    ) {
        self.configuration =
            configuration
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
            forKey:
                PTTelemetryConfiguration
                    .consentDefaultsKey
        )

        if !enabled {
            await recorder.cancel()
            state = .idle

            if purgePendingDataWhenDisabled {
                await queue.purgeAll()
            }
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

        guard case .idle = state else {
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

        state = .uploading

        let pending = await queue.pending(
            limit:
                configuration
                    .uploadBatchSize
        )

        for envelope in pending {
            do {
                try Task.checkCancellation()

                try await uploader.upload(
                    envelope,
                    containerIdentifier:
                        configuration
                            .cloudKitContainerIdentifier
                )

                await queue.markUploaded(
                    sessionID:
                        envelope.sessionID
                )

            } catch is CancellationError {
                break

            } catch {
                await queue.markFailed(
                    sessionID:
                        envelope.sessionID,
                    error:
                        error
                )

                // CloudKit/iCloud failures generally affect the entire batch.
                // Keep the remaining encrypted files queued and retry later.
                break
            }
        }

        state = .idle
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
