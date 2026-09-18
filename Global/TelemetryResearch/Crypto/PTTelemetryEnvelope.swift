//
//  PTTelemetryEnvelope.swift
//  PTSpeed
//

import Foundation

nonisolated public struct PTTelemetryEnvelope: Sendable, Equatable {

    public let schemaVersion: Int
    public let cryptoVersion: Int

    public let sessionID: UUID

    public let appVersion: String
    public let appBuild: String

    public let vehicleFamily: String
    public let ecuSoftware: String?
    public let dashboardFirmware: String?

    public let sourceMask: Int64
    public let eventCount: Int

    public let ephemeralPublicKey: Data
    public let nonce: Data
    public let tag: Data

    /// AES-GCM ciphertext only. Authentication tag is stored separately.
    public let payloadFileURL: URL

    /// SHA-256 of ciphertext only, lower-case hexadecimal.
    public let payloadHash: String
    public let payloadByteCount: Int64

    public init(
        schemaVersion: Int = PTTelemetryConfiguration.payloadSchemaVersion,
        cryptoVersion: Int = PTTelemetryConfiguration.cryptoVersion,
        sessionID: UUID,
        appVersion: String,
        appBuild: String,
        vehicleFamily: String,
        ecuSoftware: String?,
        dashboardFirmware: String?,
        sourceMask: Int64,
        eventCount: Int,
        ephemeralPublicKey: Data,
        nonce: Data,
        tag: Data,
        payloadFileURL: URL,
        payloadHash: String,
        payloadByteCount: Int64
    ) {
        self.schemaVersion = schemaVersion
        self.cryptoVersion = cryptoVersion
        self.sessionID = sessionID
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.vehicleFamily = vehicleFamily
        self.ecuSoftware = ecuSoftware
        self.dashboardFirmware = dashboardFirmware
        self.sourceMask = sourceMask
        self.eventCount = max(0, eventCount)
        self.ephemeralPublicKey = ephemeralPublicKey
        self.nonce = nonce
        self.tag = tag
        self.payloadFileURL = payloadFileURL
        self.payloadHash = payloadHash
        self.payloadByteCount = max(0, payloadByteCount)
    }
}
