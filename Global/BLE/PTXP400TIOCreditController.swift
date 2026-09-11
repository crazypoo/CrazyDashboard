//
//  PTXP400TIOCreditController.swift
//  CrazyDashboard
//
//  EN: Owns the bounded TIO credit accounting used by the existing transport.
//  ES: Posee la contabilidad acotada de créditos TIO usada por el transporte existente.
//  中文：负责现有传输使用的有界 TIO Credits 计数。
//

import Foundation

/// EN: Pure credit accounting prevents malformed writes and arithmetic from leaking into transport code.
/// ES: La contabilidad pura evita que escrituras malformadas y aritmética inválida entren en el transporte.
/// 中文：纯 Credits 计数避免格式错误写入和算术边界泄漏到传输层。
nonisolated public struct PTXP400TIOCreditController: Sendable, Equatable {
    public private(set) var sendCredits: Int
    public private(set) var localCredits: Int

    public init(sendCredits: Int = 0, localCredits: Int = 0) {
        self.sendCredits = min(max(0, sendCredits), PTXP400BLEProtocol.maxCredits)
        self.localCredits = min(max(0, localCredits), PTXP400BLEProtocol.maxCredits)
    }

    @discardableResult
    public mutating func acceptRemoteCredits(_ data: Data?) -> PTXP400BLEWriteValidationResult {
        let result = PTXP400BLEWriteValidator.validateRemoteCredits(
            data,
            currentCredits: sendCredits
        )
        if case .accepted(let amount) = result {
            sendCredits += amount
        }
        return result
    }

    @discardableResult
    public mutating func consumeRemoteCredit() -> Bool {
        guard sendCredits > 0 else { return false }
        sendCredits -= 1
        return true
    }

    @discardableResult
    public mutating func consumeLocalCredit() -> Bool {
        guard localCredits > 0 else { return false }
        localCredits -= 1
        return true
    }

    /// EN: Refill the local receive window to the confirmed per-session maximum.
    /// ES: Repone la ventana de recepción local al máximo confirmado por sesión.
    /// 中文：把本地接收窗口补充到已确认的会话最大值。
    @discardableResult
    public mutating func refillLocalCredits() -> Int {
        let refill = PTXP400BLEProtocol.maxCredits - localCredits
        guard refill > 0 else { return 0 }
        localCredits += refill
        return refill
    }

    public mutating func reset() {
        sendCredits = 0
        localCredits = 0
    }
}
