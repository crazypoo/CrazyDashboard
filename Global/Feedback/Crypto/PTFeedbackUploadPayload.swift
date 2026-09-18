//
//  PTFeedbackUploadPayload.swift
//  CrazyDashboard
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
