//
//  PTTelemetryConfiguration.swift
//  PTSpeed
//
//  CrazyDashboard anonymous protocol research configuration.
//

import Foundation

nonisolated public struct PTTelemetryConfiguration: Sendable, Equatable {

    public enum ConfigurationError: Error, LocalizedError, Sendable {
        case missingCloudKitContainerIdentifier
        case missingServerPublicKey
        case invalidServerPublicKey

        public var errorDescription: String? {
            switch self {
            case .missingCloudKitContainerIdentifier:
                return "缺少 CloudKit Container Identifier。"
            case .missingServerPublicKey:
                return "缺少 Telemetry X25519 Server Public Key。"
            case .invalidServerPublicKey:
                return "Telemetry X25519 Server Public Key 必须是 Base64 编码的 32-byte Curve25519 公钥。"
            }
        }
    }

    public static let cloudKitRecordType = "TelemetryEnvelope"
    public static let payloadSchemaVersion = 1
    public static let cryptoVersion = 1

    /// Must stay byte-for-byte compatible with CrazyDashboard-Telemetry ingest V1.
    public static let hkdfSalt = "CrazyDashboardTelemetry-v1"

    /// Research contribution is opt-in. UserDefaults contains only the user's local preference.
    public static let consentDefaultsKey = "PTTelemetryResearch.enabled.v1"

    public let cloudKitContainerIdentifier: String
    public let serverPublicKeyBase64: String

    public let maximumEventsPerSession: Int
    public let maximumEventValueLength: Int
    public let uploadBatchSize: Int
    public let autoUploadOnFinish: Bool

    public init(
        cloudKitContainerIdentifier: String,
        serverPublicKeyBase64: String,
        maximumEventsPerSession: Int = 50_000,
        maximumEventValueLength: Int = 4_096,
        uploadBatchSize: Int = 20,
        autoUploadOnFinish: Bool = true
    ) throws {
        let container = cloudKitContainerIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !container.isEmpty else {
            throw ConfigurationError.missingCloudKitContainerIdentifier
        }

        let publicKey = serverPublicKeyBase64
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !publicKey.isEmpty else {
            throw ConfigurationError.missingServerPublicKey
        }

        guard let keyData = Data(base64Encoded: publicKey),
              keyData.count == 32 else {
            throw ConfigurationError.invalidServerPublicKey
        }

        self.cloudKitContainerIdentifier = container
        self.serverPublicKeyBase64 = publicKey
        self.maximumEventsPerSession = max(1, maximumEventsPerSession)
        self.maximumEventValueLength = max(64, maximumEventValueLength)
        self.uploadBatchSize = max(1, uploadBatchSize)
        self.autoUploadOnFinish = autoUploadOnFinish
    }

    /// Optional convenience if you prefer keeping the two non-secret settings in Info.plist.
    ///
    /// Required keys:
    /// - `PTTelemetryCloudKitContainerIdentifier`
    /// - `PTTelemetryServerPublicKeyBase64`
    public static func fromInfoPlist(
        bundle: Bundle = .main
    ) throws -> PTTelemetryConfiguration {
        let container = bundle.object(
            forInfoDictionaryKey: "PTTelemetryCloudKitContainerIdentifier"
        ) as? String ?? ""

        let publicKey = bundle.object(
            forInfoDictionaryKey: "PTTelemetryServerPublicKeyBase64"
        ) as? String ?? ""

        return try PTTelemetryConfiguration(
            cloudKitContainerIdentifier: container,
            serverPublicKeyBase64: publicKey
        )
    }
}
