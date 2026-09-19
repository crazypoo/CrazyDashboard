//
//  PTFeedbackAttachmentManager.swift
//  CrazyDashboard
//

import Foundation

public actor PTFeedbackAttachmentManager {
    public static let shared = PTFeedbackAttachmentManager()

    private let queue = PTFeedbackAttachmentQueue.shared
    private let repository = PTFeedbackAttachmentRepository.shared
    private var configuration: PTFeedbackConfiguration?
    private var flushing = false

    private init() {}

    public func configure(_ configuration: PTFeedbackConfiguration) {
        self.configuration = configuration
    }

    public func submit(
        feedbackID: UUID,
        drafts: [PTFeedbackAttachmentDraft]
    ) async {
        guard let configuration, !drafts.isEmpty else { return }
        for draft in drafts.prefix(3) {
            do {
                let envelope = try PTFeedbackAttachmentEncryptor.encrypt(
                    draft,
                    feedbackID: feedbackID,
                    configuration: configuration
                )
                defer { try? FileManager.default.removeItem(at: envelope.payloadFileURL) }
                try await queue.enqueue(envelope)
            } catch {
                continue
            }
        }
        await flushPendingUploads()
    }

    public func flushPendingUploads() async {
        guard let configuration, !flushing else { return }
        flushing = true
        defer { flushing = false }
        for envelope in await queue.pending(limit: 8) {
            do {
                try await repository.upload(envelope, configuration: configuration)
                await queue.remove(attachmentID: envelope.attachmentID)
            } catch {
                break
            }
        }
    }

    public func pendingCount() async -> Int {
        await queue.pendingCount()
    }
}
