//
//  PTCloudKitConfiguration.swift
//  CrazyDashboard
//
//  Shared CloudKit transport configuration.
//  Domain-specific crypto / record logic remains in TelemetryResearch / Feedback.
//

import Foundation

nonisolated public struct PTCloudKitConfiguration: Sendable, Equatable {
    public let containerIdentifier: String

    public init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    public static func feedbackFromInfoPlist(
        bundle: Bundle = .main
    ) throws -> PTCloudKitConfiguration {
        let feedbackKey = "PTFeedbackCloudKitContainerIdentifier"
        let telemetryKey = "PTTelemetryCloudKitContainerIdentifier"

        let explicit = bundle.object(
            forInfoDictionaryKey: feedbackKey
        ) as? String

        let fallback = bundle.object(
            forInfoDictionaryKey: telemetryKey
        ) as? String

        guard let identifier = [explicit, fallback]
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else {
            throw PTFeedbackError.missingConfiguration(
                "Info.plist 缺少 \(feedbackKey)，且没有可复用的 \(telemetryKey)。"
            )
        }

        return .init(containerIdentifier: identifier)
    }
}
