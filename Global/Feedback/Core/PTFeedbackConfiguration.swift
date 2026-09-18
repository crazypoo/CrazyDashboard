//
//  PTFeedbackConfiguration.swift
//  CrazyDashboard
//

import Foundation

nonisolated public struct PTFeedbackConfiguration: Sendable, Equatable {
    public static let consentDefaultsKey = "CrazyDashboard.Feedback.Consent"
    public static let recordType = "FeedbackEnvelope"
    public static let envelopeSchemaVersion = 1
    public static let payloadSchemaVersion = 1
    public static let cryptoVersion = 1
    public static let hkdfSalt = "CrazyDashboardFeedback-v1"

    public let cloudKit: PTCloudKitConfiguration
    public let serverPublicKeyBase64: String
    public let uploadBatchSize: Int
    public let maximumPayloadBytes: Int
    public let autoFlushAfterSubmit: Bool

    public init(
        cloudKit: PTCloudKitConfiguration,
        serverPublicKeyBase64: String,
        uploadBatchSize: Int = 8,
        maximumPayloadBytes: Int = 128 * 1024,
        autoFlushAfterSubmit: Bool = true
    ) {
        self.cloudKit = cloudKit
        self.serverPublicKeyBase64 = serverPublicKeyBase64
        self.uploadBatchSize = max(1, uploadBatchSize)
        self.maximumPayloadBytes = max(16 * 1024, maximumPayloadBytes)
        self.autoFlushAfterSubmit = autoFlushAfterSubmit
    }

    public static func fromInfoPlist(
        bundle: Bundle = .main
    ) throws -> PTFeedbackConfiguration {
        let cloudKit = try PTCloudKitConfiguration.feedbackFromInfoPlist(
            bundle: bundle
        )

        guard let key = bundle.object(
            forInfoDictionaryKey: "PTFeedbackServerPublicKeyBase64"
        ) as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PTFeedbackError.missingConfiguration(
                "Info.plist 缺少 PTFeedbackServerPublicKeyBase64。"
            )
        }

        return .init(
            cloudKit: cloudKit,
            serverPublicKeyBase64: key
        )
    }
}
