//
//  PTELM327State.swift
//  PTSpeed
//
//  EN: Describes the ELM327 session only; adapter OTA is deliberately outside this enum.
//  ES: Describe únicamente la sesión ELM327; la OTA del adaptador queda fuera de este enum.
//  中文：只描述 ELM327 会话，适配器 OTA 明确不属于这个状态枚举。
//

import Foundation

nonisolated public enum PTELM327State: String, Codable, Equatable, CaseIterable, Sendable {
    case disconnected
    case transportConnected
    case initializing
    case ready
    case polling
    case monitoring
    case diagnosticExclusive
    case suspended
    case recovering
    case failed
}
