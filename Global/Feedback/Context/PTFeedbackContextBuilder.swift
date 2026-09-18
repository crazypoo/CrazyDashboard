//
//  PTFeedbackContextBuilder.swift
//  CrazyDashboard
//

import Foundation
import UIKit

@MainActor
public enum PTFeedbackContextBuilder {
    public static func make(
        vehicleFamily: String = "unknown",
        bundle: Bundle = .main
    ) -> PTFeedbackContext {
        let info = bundle.infoDictionary ?? [:]

        let version = (
            info["CFBundleShortVersionString"] as? String
        ) ?? "unknown"

        let build = (
            info["CFBundleVersion"] as? String
        ) ?? "unknown"

        let idiom: String
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            idiom = "iPhone"
        case .pad:
            idiom = "iPad"
        case .carPlay:
            idiom = "CarPlay"
        default:
            idiom = "other"
        }

        return .init(
            appVersion: version,
            appBuild: build,
            osVersion: UIDevice.current.systemVersion,
            deviceClass: idiom,
            localeIdentifier: Locale.current.identifier,
            vehicleFamily: PTFeedbackPrivacySanitizer.safeVehicleFamily(
                vehicleFamily
            )
        )
    }
}
