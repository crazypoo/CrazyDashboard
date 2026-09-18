//
//  PTFeedbackManager.swift
//  CrazyDashboard
//
//  High-level Feedback orchestration.
//  No UIKit / BLE / OBD / CAN command logic belongs here.
//

import Foundation

public actor PTFeedbackManager {
    public static let shared = PTFeedbackManager()

    private let queue: PTFeedbackUploadQueue
    private let statusStore: PTFeedbackStatusStore
    private let repository: PTCloudKitFeedbackRepository
    private let subscriptionManager: PTFeedbackSubscriptionManager
    private let defaults: UserDefaults

    private var configuration: PTFeedbackConfiguration?
    private var uploadInProgress = false
    private var uploadRequestedWhileBusy = false

    public init(
        queue: PTFeedbackUploadQueue = .shared,
        statusStore: PTFeedbackStatusStore = .shared,
        repository: PTCloudKitFeedbackRepository = .shared,
        subscriptionManager: PTFeedbackSubscriptionManager = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.queue = queue
        self.statusStore = statusStore
        self.repository = repository
        self.subscriptionManager = subscriptionManager
        self.defaults = defaults
    }

    public func configure(
        _ configuration: PTFeedbackConfiguration
    ) {
        self.configuration = configuration
    }

    public func isFeedbackEnabled() -> Bool {
        defaults.object(
            forKey: PTFeedbackConfiguration.consentDefaultsKey
        ) == nil
            ? true
            : defaults.bool(
                forKey: PTFeedbackConfiguration.consentDefaultsKey
            )
    }

    public func setFeedbackEnabled(
        _ enabled: Bool,
        purgePendingDataWhenDisabled: Bool = false
    ) async {
        defaults.set(
            enabled,
            forKey: PTFeedbackConfiguration.consentDefaultsKey
        )

        if !enabled && purgePendingDataWhenDisabled {
            await queue.purgeAll()
        }
    }

    @discardableResult
    public func submit(
        draft: PTFeedbackDraft,
        context: PTFeedbackContext,
        diagnostics: PTFeedbackDiagnosticsSnapshot?,
        telemetrySessionID: UUID?
    ) async throws -> PTFeedbackSubmissionResult {
        guard let configuration else {
            throw PTFeedbackError.missingConfiguration(
                "PTFeedbackManager 尚未 configure。"
            )
        }

        guard isFeedbackEnabled() else {
            throw PTFeedbackError.missingConfiguration(
                "用户已关闭 Feedback Cloud 提交。"
            )
        }

        let payload = try PTFeedbackPrivacySanitizer.sanitize(
            draft: draft,
            context: context,
            diagnostics: diagnostics,
            telemetrySessionID: telemetrySessionID
        )

        let envelope = try PTFeedbackEncryptor.encrypt(
            payload,
            configuration: configuration
        )

        defer {
            try? FileManager.default.removeItem(
                at: envelope.payloadFileURL
            )
        }

        try await queue.enqueue(envelope)

        let preview = String(
            payload.body.prefix(160)
        )

        try await statusStore.upsert(
            .init(
                feedbackID: draft.feedbackID,
                category: draft.category,
                module: draft.module,
                title: payload.title,
                bodyPreview: preview
            )
        )

        var uploadedImmediately = false

        if configuration.autoFlushAfterSubmit {
            uploadedImmediately = await flushPendingUploads(
                targetFeedbackID: draft.feedbackID
            )
        }

        return .init(
            feedbackID: draft.feedbackID,
            uploadedImmediately: uploadedImmediately
        )
    }

    @discardableResult
    public func flushPendingUploads(
        targetFeedbackID: UUID? = nil
    ) async -> Bool {
        guard let configuration,
              isFeedbackEnabled() else {
            return false
        }

        if uploadInProgress {
            uploadRequestedWhileBusy = true
            return false
        }

        uploadInProgress = true
        defer {
            uploadInProgress = false
        }

        var uploadedTarget = false
        var shouldStop = false

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

                    try await repository.upload(
                        envelope,
                        configuration: configuration
                    )

                    await queue.markUploaded(
                        feedbackID: envelope.feedbackID
                    )

                    // A push is only a signal. Failing to create the
                    // subscription must never turn a successful submission
                    // into a failed submission.
                    try? await subscriptionManager.ensureSubscription(
                        feedbackID: envelope.feedbackID,
                        configuration: configuration
                    )

                    if envelope.feedbackID == targetFeedbackID {
                        uploadedTarget = true
                    }
                } catch is CancellationError {
                    shouldStop = true
                    break
                } catch {
                    await queue.markFailed(
                        feedbackID: envelope.feedbackID,
                        error: error
                    )

                    // Avoid a retry storm when iCloud/network is unavailable.
                    shouldStop = true
                    break
                }
            }

            if shouldStop {
                break
            }
        } while uploadRequestedWhileBusy

        return uploadedTarget
    }

    public func feedbackRecords() async throws -> [PTFeedbackLocalRecord] {
        try await statusStore.records()
    }

    @discardableResult
    public func refreshStatuses() async throws -> [PTFeedbackLocalRecord] {
        guard let configuration else {
            throw PTFeedbackError.missingConfiguration(
                "PTFeedbackManager 尚未 configure。"
            )
        }

        let ids = try await statusStore.feedbackIDs()

        let remote = try await repository.fetchStatuses(
            feedbackIDs: ids,
            configuration: configuration
        )

        try await statusStore.apply(remote)

        return try await statusStore.records()
    }

    public func pendingUploadCount() async -> Int {
        await queue.pendingCount()
    }

    public func purgePendingEncryptedFeedback() async {
        await queue.purgeAll()
    }

    public func purgeLocalFeedbackHistory() async {
        await statusStore.removeAll()
    }
}
