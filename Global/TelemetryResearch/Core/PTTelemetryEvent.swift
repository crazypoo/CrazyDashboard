//
//  PTTelemetryEvent.swift
//  PTSpeed
//

import Foundation

nonisolated public enum PTTelemetrySource: String, Codable, Sendable, CaseIterable {
    case dashboardBLE
    case obd
    case can
    case marker
}

nonisolated public enum PTTelemetryEventKind: String, Codable, Sendable {
    case frame = "frame"
    case frameRX = "frameRx"
    case frameTX = "frameTx"
    case command = "command"
    case response = "response"
    case marker = "marker"
    case timeout = "timeout"
    case transportError = "transportError"
}

nonisolated public struct PTTelemetryEvent: Codable, Equatable, Sendable {

    public let monotonicNanoseconds: UInt64
    public let source: PTTelemetrySource
    public let kind: PTTelemetryEventKind
    public let value: String

    public init(
        monotonicNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds,
        source: PTTelemetrySource,
        kind: PTTelemetryEventKind,
        value: String
    ) {
        self.monotonicNanoseconds = monotonicNanoseconds
        self.source = source
        self.kind = kind
        self.value = value
    }
}

nonisolated public struct PTTelemetrySourceMask: OptionSet, Sendable, Equatable {

    public let rawValue: Int64

    public init(rawValue: Int64) {
        self.rawValue = rawValue
    }

    public static let dashboardBLE = Self(rawValue: 1 << 0)
    public static let obd = Self(rawValue: 1 << 1)
    public static let can = Self(rawValue: 1 << 2)
    public static let marker = Self(rawValue: 1 << 3)

    public static func make(
        from events: [PTTelemetryEvent]
    ) -> Self {
        events.reduce(into: Self()) { result, event in
            switch event.source {
            case .dashboardBLE:
                result.insert(.dashboardBLE)
            case .obd:
                result.insert(.obd)
            case .can:
                result.insert(.can)
            case .marker:
                result.insert(.marker)
            }
        }
    }
}
