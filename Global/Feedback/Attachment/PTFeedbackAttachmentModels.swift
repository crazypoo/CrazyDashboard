//
//  PTFeedbackAttachmentModels.swift
//  CrazyDashboard
//

import Foundation

nonisolated public enum PTFeedbackAttachmentKind: String, Codable, Sendable {
    case screenshot
    case diagnostics
    case sanitizedLog
}

nonisolated public struct PTFeedbackAttachmentDraft: Sendable, Equatable {
    public let attachmentID: UUID
    public let kind: PTFeedbackAttachmentKind
    public let mimeType: String
    public let data: Data

    public init(
        attachmentID: UUID = UUID(),
        kind: PTFeedbackAttachmentKind,
        mimeType: String,
        data: Data
    ) {
        self.attachmentID = attachmentID
        self.kind = kind
        self.mimeType = mimeType
        self.data = data
    }
}

nonisolated public struct PTFeedbackAttachmentEnvelope: Sendable, Equatable {
    public let attachmentID: UUID
    public let feedbackID: UUID
    public let kind: PTFeedbackAttachmentKind
    public let mimeType: String
    public let cryptoVersion: Int
    public let ephemeralPublicKey: Data
    public let nonce: Data
    public let tag: Data
    public let payloadHash: String
    public let payloadByteCount: Int
    public let payloadFileURL: URL
}
