//
//  PTELM327Capabilities.swift
//  PTSpeed
//
//  EN: Holds capabilities shared by generic ELM327 and optional vendor extensions.
//  ES: Contiene capacidades compartidas por ELM327 genérico y extensiones opcionales.
//  中文：保存通用 ELM327 与可选厂商扩展共享的能力信息。
//

import Foundation

nonisolated public enum PTOBDTransportKind: String, Codable, Equatable, Sendable {
    case bluetooth
    case wifi
    case mock
    case unknown
}

nonisolated public struct PTELM327Capabilities: Codable, Equatable, Sendable {
    public var transportKind: PTOBDTransportKind
    public var supportedCommands: Set<String>
    public var vendor: PTYMOBDCapabilities?

    public init(
        transportKind: PTOBDTransportKind = .unknown,
        supportedCommands: Set<String> = [],
        vendor: PTYMOBDCapabilities? = nil
    ) {
        self.transportKind = transportKind
        self.supportedCommands = supportedCommands
        self.vendor = vendor
    }
}
