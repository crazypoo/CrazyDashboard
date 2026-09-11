//
//  PTXP400BLEState.swift
//  CrazyDashboard
//
//  EN: Stores the mutable, session-scoped BLE facts without owning CoreBluetooth.
//  ES: Guarda los hechos BLE mutables de una sesión sin apropiarse de CoreBluetooth.
//  中文：保存会话范围内可变的 BLE 状态事实，但不接管 CoreBluetooth。
//

import Foundation

/// EN: Pure state keeps authentication, subscriptions, and credits together for safe reset.
/// ES: El estado puro mantiene autenticación, suscripciones y créditos juntos para reinicios seguros.
/// 中文：纯状态模型把认证、订阅和 Credits 集中管理，便于安全重置。
nonisolated public struct PTXP400BLEState: Codable, Equatable, Sendable {
    public var isAuthenticated: Bool
    public var isTIOSubscribed: Bool
    public var isCreditsSubscribed: Bool
    public var sendCredits: Int
    public var localCredits: Int

    public init(
        isAuthenticated: Bool = false,
        isTIOSubscribed: Bool = false,
        isCreditsSubscribed: Bool = false,
        sendCredits: Int = 0,
        localCredits: Int = 0
    ) {
        self.isAuthenticated = isAuthenticated
        self.isTIOSubscribed = isTIOSubscribed
        self.isCreditsSubscribed = isCreditsSubscribed
        self.sendCredits = max(0, sendCredits)
        self.localCredits = max(0, localCredits)
    }

    /// EN: Reset only the state owned by the current dashboard session.
    /// ES: Reinicia solo el estado perteneciente a la sesión actual del tablero.
    /// 中文：只重置当前仪表盘会话拥有的状态。
    public mutating func resetSession() {
        isAuthenticated = false
        isTIOSubscribed = false
        isCreditsSubscribed = false
        sendCredits = 0
        localCredits = 0
    }
}
