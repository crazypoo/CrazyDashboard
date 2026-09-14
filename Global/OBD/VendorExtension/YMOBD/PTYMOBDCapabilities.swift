//
//  PTYMOBDCapabilities.swift
//  PTSpeed
//
//  EN: Describes optional YMOBD capabilities without replacing generic ELM state.
//  ES: Describe capacidades YMOBD opcionales sin reemplazar el estado ELM genérico.
//  中文：描述可选 YMOBD 能力，不替换通用 ELM 状态。
//

import Foundation

nonisolated public struct PTYMOBDCapabilities: Codable, Equatable, Sendable {
    public let isOfficial: Bool
    public let deviceType: String?
    public let supportsFirmwareCheck: Bool
    public let supportsFirmwareDownload: Bool
    public let supportsJieliOTA: Bool

    public init(
        isOfficial: Bool,
        deviceType: String?,
        supportsFirmwareCheck: Bool,
        supportsFirmwareDownload: Bool,
        supportsJieliOTA: Bool
    ) {
        self.isOfficial = isOfficial
        self.deviceType = deviceType
        self.supportsFirmwareCheck = supportsFirmwareCheck
        self.supportsFirmwareDownload = supportsFirmwareDownload
        self.supportsJieliOTA = supportsJieliOTA
    }

    public static let unavailable = PTYMOBDCapabilities(
        isOfficial: false,
        deviceType: nil,
        supportsFirmwareCheck: false,
        supportsFirmwareDownload: false,
        supportsJieliOTA: false
    )
}
