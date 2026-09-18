//
//  PTFeedbackEnvelope.swift
//  CrazyDashboard
//

import Foundation

nonisolated public struct PTFeedbackEnvelope: Sendable, Equatable {
    public let schemaVersion: Int
    public let feedbackID: UUID
    public let appBuild: String
    public let cryptoVersion: Int
    public let ephemeralPublicKey: Data
    public let nonce: Data
    public let tag: Data
    public let payloadHash: String
    public let payloadByteCount: Int
    public let payloadFileURL: URL

    public init(
        schemaVersion: Int,
        feedbackID: UUID,
        appBuild: String,
        cryptoVersion: Int,
        ephemeralPublicKey: Data,
        nonce: Data,
        tag: Data,
        payloadHash: String,
        payloadByteCount: Int,
        payloadFileURL: URL
    ) {
        self.schemaVersion = schemaVersion
        self.feedbackID = feedbackID
        self.appBuild = appBuild
        self.cryptoVersion = cryptoVersion
        self.ephemeralPublicKey = ephemeralPublicKey
        self.nonce = nonce
        self.tag = tag
        self.payloadHash = payloadHash
        self.payloadByteCount = payloadByteCount
        self.payloadFileURL = payloadFileURL
    }
}
