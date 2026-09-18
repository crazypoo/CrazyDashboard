//
//  PTFeedbackContext.swift
//  CrazyDashboard
//

import Foundation

nonisolated public struct PTFeedbackContext: Codable, Sendable, Equatable {
    public let appVersion: String
    public let appBuild: String
    public let osVersion: String
    public let deviceClass: String
    public let localeIdentifier: String
    public let vehicleFamily: String

    public init(
        appVersion: String,
        appBuild: String,
        osVersion: String,
        deviceClass: String,
        localeIdentifier: String,
        vehicleFamily: String
    ) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.osVersion = osVersion
        self.deviceClass = deviceClass
        self.localeIdentifier = localeIdentifier
        self.vehicleFamily = vehicleFamily
    }
}
