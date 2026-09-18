//
//  PTFeedbackDiagnosticsBuilder.swift
//  CrazyDashboard
//

import Foundation
import UIKit

@MainActor
public enum PTFeedbackDiagnosticsBuilder {
    public static func make(
        extra: [String: String] = [:]
    ) -> PTFeedbackDiagnosticsSnapshot {
        let processInfo = ProcessInfo.processInfo

        var values: [String: String] = [
            "lowPowerMode": processInfo.isLowPowerModeEnabled ? "true" : "false",
            "thermalState": String(processInfo.thermalState.rawValue),
            "preferredLanguage": Locale.preferredLanguages.first ?? "unknown",
            "interfaceIdiom": interfaceIdiomName()
        ]

        for (key, value) in extra {
            guard PTFeedbackPrivacySanitizer.allowedDiagnosticKeys.contains(key) else {
                continue
            }
            values[key] = PTFeedbackRedactor.redact(value)
        }

        return .init(values: values)
    }

    private static func interfaceIdiomName() -> String {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: return "phone"
        case .pad: return "pad"
        case .carPlay: return "carPlay"
        default: return "other"
        }
    }
}
