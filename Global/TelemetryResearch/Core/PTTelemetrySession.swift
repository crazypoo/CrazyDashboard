//
//  PTTelemetrySession.swift
//  PTSpeed
//

import Foundation

nonisolated public struct PTTelemetryAppContext: Codable, Equatable, Sendable {
    public let version: String
    public let build: String

    public init(
        version: String,
        build: String
    ) {
        self.version = version
        self.build = build
    }

    public static func current(
        bundle: Bundle = .main
    ) -> Self {
        Self(
            version: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0",
            build: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "0"
        )
    }
}

nonisolated public struct PTTelemetryVehicleContext: Codable, Equatable, Sendable {

    public let family: String
    public let dashboardFirmware: String?
    public let ecuSoftware: String?

    public init(
        family: String = "unknown",
        dashboardFirmware: String? = nil,
        ecuSoftware: String? = nil
    ) {
        let normalizedFamily = family
            .trimmingCharacters(in: .whitespacesAndNewlines)

        self.family = normalizedFamily.isEmpty
            ? "unknown"
            : normalizedFamily

        self.dashboardFirmware = dashboardFirmware?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        self.ecuSoftware = ecuSoftware?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static let unknown = Self()
}

nonisolated public struct PTTelemetrySession: Codable, Equatable, Sendable {

    public static let schemaVersion = 1

    public let id: UUID

    /// Local diagnostics only. This absolute timestamp is never included in upload payloads.
    public let startedAt: Date

    /// Used to derive anonymous relative offsets for uploaded events.
    public let startedMonotonicNanoseconds: UInt64

    public let app: PTTelemetryAppContext
    public let vehicle: PTTelemetryVehicleContext

    public var events: [PTTelemetryEvent]
    public var droppedEventCount: Int

    public init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        startedMonotonicNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds,
        app: PTTelemetryAppContext = .current(),
        vehicle: PTTelemetryVehicleContext = .unknown,
        events: [PTTelemetryEvent] = [],
        droppedEventCount: Int = 0
    ) {
        self.id = id
        self.startedAt = startedAt
        self.startedMonotonicNanoseconds = startedMonotonicNanoseconds
        self.app = app
        self.vehicle = vehicle
        self.events = events
        self.droppedEventCount = max(0, droppedEventCount)
    }

    public var eventCount: Int {
        events.count
    }

    public var sourceMask: PTTelemetrySourceMask {
        .make(from: events)
    }
}
