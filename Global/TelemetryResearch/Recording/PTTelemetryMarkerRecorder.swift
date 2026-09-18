//
//  PTTelemetryMarkerRecorder.swift
//  PTSpeed
//

import Foundation

nonisolated public enum PTTelemetryMarkerKind: String, Codable, Sendable {
    case tcs
    case language
    case unit
    case color
    case dashboardSetting
    case ignition
    case researchTest
}

nonisolated public enum PTTelemetryMarkerRecorder {

    public static func record(
        _ kind: PTTelemetryMarkerKind,
        value: String
    ) async {
        await PTTelemetryRecorder.shared.recordMarker(
            kind: kind,
            value: value
        )
    }

    public static func tcs(
        _ value: String
    ) async {
        await record(
            .tcs,
            value: value
        )
    }

    public static func language(
        _ value: String
    ) async {
        await record(
            .language,
            value: value
        )
    }

    public static func unit(
        _ value: String
    ) async {
        await record(
            .unit,
            value: value
        )
    }

    public static func color(
        _ value: String
    ) async {
        await record(
            .color,
            value: value
        )
    }
}
