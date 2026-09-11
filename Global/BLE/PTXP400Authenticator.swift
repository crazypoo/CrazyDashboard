//
//  PTXP400Authenticator.swift
//  CrazyDashboard
//
//  EN: Provides a narrow authentication boundary while reusing the confirmed algorithm.
//  ES: Proporciona un límite estrecho de autenticación reutilizando el algoritmo confirmado.
//  中文：建立窄化的认证边界，同时继续复用已经确认的算法。
//

import Foundation

/// EN: Compatibility adapter; the established PTScooterAuth implementation remains the source of truth.
/// ES: Adaptador de compatibilidad; PTScooterAuth sigue siendo la fuente de verdad establecida.
/// 中文：兼容适配器；既有 PTScooterAuth 仍然是认证算法的唯一事实来源。
final class PTXP400Authenticator {
    private let implementation: PTScooterAuth

    init(implementation: PTScooterAuth = PTScooterAuth()) {
        self.implementation = implementation
    }

    func createChallenge() -> [UInt16] {
        implementation.createChallenge()
    }

    func checkAuthMsg(scooterResponse: Data) -> Bool {
        implementation.checkAuthMsg(scooterResponse: scooterResponse)
    }

    func createAuthenticationMessage(r: [UInt16]) -> Data {
        implementation.createAuthenticationMessage(r: r)
    }

    func getScooterKeyId() -> Data {
        implementation.getScooterKeyId()
    }
}
