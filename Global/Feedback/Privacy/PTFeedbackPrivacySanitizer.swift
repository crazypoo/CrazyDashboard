//
//  PTFeedbackPrivacySanitizer.swift
//  CrazyDashboard
//

import Foundation

nonisolated public enum PTFeedbackPrivacySanitizer {
    public static let maximumTitleCharacters = 120
    public static let maximumBodyCharacters = 6_000

    /// Server and iOS both enforce a whitelist. Keep this intentionally small.
    public static let allowedDiagnosticKeys: Set<String> = [
        "lowPowerMode",
        "thermalState",
        "preferredLanguage",
        "interfaceIdiom",
        "dashboardConnectionState",
        "obdConnectionState",
        "lastVehicleErrorCategory",
        "musicAuthorizationState",
        "cloudAccountState"
    ]

    public static func sanitize(
        draft: PTFeedbackDraft,
        context: PTFeedbackContext,
        diagnostics: PTFeedbackDiagnosticsSnapshot?,
        telemetrySessionID: UUID?
    ) throws -> PTFeedbackUploadPayload {
        let title = normalized(
            PTFeedbackRedactor.redact(draft.title),
            maxCharacters: maximumTitleCharacters
        )

        let body = normalized(
            PTFeedbackRedactor.redact(draft.body),
            maxCharacters: maximumBodyCharacters
        )

        guard !title.isEmpty else {
            throw PTFeedbackError.invalidTitle
        }

        guard !body.isEmpty else {
            throw PTFeedbackError.invalidBody
        }

        let safeDiagnostics = diagnostics.map {
            sanitizeDiagnostics($0)
        }

        return .init(
            schemaVersion: PTFeedbackConfiguration.payloadSchemaVersion,
            feedbackID: draft.feedbackID,
            category: draft.category,
            module: draft.module,
            title: title,
            body: body,
            app: .init(
                version: normalized(context.appVersion, maxCharacters: 32),
                build: normalized(context.appBuild, maxCharacters: 32)
            ),
            environment: .init(
                osVersion: normalized(context.osVersion, maxCharacters: 32),
                deviceClass: normalized(context.deviceClass, maxCharacters: 32),
                localeIdentifier: normalized(
                    context.localeIdentifier,
                    maxCharacters: 64
                ),
                vehicleFamily: safeVehicleFamily(context.vehicleFamily)
            ),
            diagnostics: .init(
                included: draft.includeDiagnostics && safeDiagnostics != nil,
                summary: draft.includeDiagnostics
                    ? safeDiagnostics?.values ?? [:]
                    : [:]
            ),
            telemetry: .init(
                linked: draft.linkCurrentTelemetrySession
                    && telemetrySessionID != nil,
                sessionID: draft.linkCurrentTelemetrySession
                    ? telemetrySessionID
                    : nil
            )
        )
    }

    public static func safeVehicleFamily(
        _ value: String
    ) -> String {
        let sanitized = PTFeedbackRedactor.redact(value)

        // Vehicle family is a coarse model family only.
        // Reject long / identifier-looking values rather than trying to preserve them.
        guard sanitized.count <= 40,
              !sanitized.contains("[REDACTED_") else {
            return "unknown"
        }

        return normalized(
            sanitized,
            maxCharacters: 40
        )
    }

    private static func sanitizeDiagnostics(
        _ snapshot: PTFeedbackDiagnosticsSnapshot
    ) -> PTFeedbackDiagnosticsSnapshot {
        var output: [String: String] = [:]

        for (key, value) in snapshot.values {
            guard allowedDiagnosticKeys.contains(key) else {
                continue
            }

            let redacted = PTFeedbackRedactor.redact(value)
            output[key] = normalized(
                redacted,
                maxCharacters: 256
            )
        }

        return .init(values: output)
    }

    private static func normalized(
        _ value: String,
        maxCharacters: Int
    ) -> String {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard trimmed.count > maxCharacters else {
            return trimmed
        }

        return String(trimmed.prefix(maxCharacters))
    }
}
