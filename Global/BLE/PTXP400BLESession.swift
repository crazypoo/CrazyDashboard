//
//  PTXP400BLESession.swift
//  CrazyDashboard
//
//  EN: Owns the value-typed identity of one XP400 BLE connection generation.
//  ES: Posee la identidad tipada por valor de una generación de conexión BLE del XP400.
//  中文：负责一个 XP400 BLE 连接代次的值类型身份。
//

import Foundation

/// EN: A session identity changes whenever a central or mock connection starts.
/// ES: La identidad cambia cada vez que comienza una conexión central o simulada.
/// 中文：每次真实 Central 或 Mock 连接开始时，Session 身份都会变化。
nonisolated public struct PTXP400BLESession: Codable, Equatable, Sendable {
    public private(set) var token: PTXP400BLESessionToken
    public private(set) var centralIdentifier: UUID?
    public private(set) var isActive: Bool

    public init(
        token: PTXP400BLESessionToken = PTXP400BLESessionToken(),
        centralIdentifier: UUID? = nil,
        isActive: Bool = false
    ) {
        self.token = token
        self.centralIdentifier = centralIdentifier
        self.isActive = isActive
    }

    @discardableResult
    public mutating func begin(centralIdentifier: UUID? = nil) -> PTXP400BLESessionToken {
        token = token.next()
        self.centralIdentifier = centralIdentifier
        isActive = true
        return token
    }

    public mutating func end() {
        isActive = false
        centralIdentifier = nil
    }

    public func accepts(_ candidate: PTXP400BLESessionToken) -> Bool {
        isActive && token == candidate
    }
}
