//
//  PTFeedbackUploadPayload.swift
//  CrazyDashboard
//
//  Feedback payload V2 adds only an anonymous relative telemetry offset.
//  It does not add wall-clock time, GPS, VIN or device identifiers.
//

import Foundation

nonisolated public struct PTFeedbackUploadPayload: Codable, Sendable, Equatable {
    public struct App: Codable, Sendable, Equatable {
        public let version: String
        public let build: String
    }

    public struct Environment: Codable, Sendable, Equatable {
        public let osVersion: String
        public let deviceClass: String
        public let localeIdentifier: String
        public let vehicleFamily: String
    }

    public struct Diagnostics: Codable, Sendable, Equatable {
        public let included: Bool
        public let summary: [String: String]
    }

    public struct Telemetry: Codable, Sendable, Equatable {
        public let linked: Bool
        public let sessionID: UUID?

        /// Monotonic elapsed time inside the anonymous TelemetryResearch
        /// session. This is intentionally not a wall-clock timestamp.
        public let sessionOffsetMilliseconds: Int64?

        public init(
            linked: Bool,
            sessionID: UUID?,
            sessionOffsetMilliseconds: Int64?
        ) {
            self.linked = linked
            self.sessionID = sessionID
            self.sessionOffsetMilliseconds = sessionOffsetMilliseconds
        }
    }

    public let schemaVersion: Int
    public let feedbackID: UUID
    public let category: PTFeedbackCategory
    public let module: PTFeedbackModule
    public let title: String
    public let body: String
    public let app: App
    public let environment: Environment
    public let diagnostics: Diagnostics
    public let telemetry: Telemetry
}
