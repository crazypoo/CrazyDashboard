//
//  PTTelemetryUploadPayload.swift
//  PTSpeed
//
//  Exact plaintext contract consumed by CrazyDashboard-Telemetry ingest V1.
//

import Foundation

nonisolated public struct PTTelemetryUploadPayload: Codable, Equatable, Sendable {

    public static let schemaVersion = 1

    nonisolated public struct AppInfo: Codable, Equatable, Sendable {
        public let version: String
        public let build: String

        public init(
            version: String,
            build: String
        ) {
            self.version = version
            self.build = build
        }
    }

    nonisolated public struct VehicleInfo: Codable, Equatable, Sendable {
        /// Required by the GitHub schema. Use "unknown" instead of omitting the key.
        public let family: String
        public let dashboardFirmware: String?
        public let ecuSoftware: String?

        public init(
            family: String,
            dashboardFirmware: String?,
            ecuSoftware: String?
        ) {
            self.family = family
            self.dashboardFirmware = dashboardFirmware
            self.ecuSoftware = ecuSoftware
        }
    }

    nonisolated public struct Event: Codable, Equatable, Sendable {
        public let offset: TimeInterval
        public let source: PTTelemetrySource
        public let kind: String
        public let value: String

        public init(
            offset: TimeInterval,
            source: PTTelemetrySource,
            kind: String,
            value: String
        ) {
            self.offset = offset
            self.source = source
            self.kind = kind
            self.value = value
        }
    }

    public let schemaVersion: Int
    public let sessionID: UUID
    public let app: AppInfo
    public let vehicle: VehicleInfo
    public let events: [Event]

    public init(
        sessionID: UUID,
        app: AppInfo,
        vehicle: VehicleInfo,
        events: [Event]
    ) {
        self.schemaVersion = Self.schemaVersion
        self.sessionID = sessionID
        self.app = app
        self.vehicle = vehicle
        self.events = events
    }

    public var sourceMask: PTTelemetrySourceMask {
        events.reduce(
            into: PTTelemetrySourceMask()
        ) { result, event in
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
