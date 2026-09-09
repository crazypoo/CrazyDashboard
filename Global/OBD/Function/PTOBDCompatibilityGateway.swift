//
//  PTOBDCompatibilityGateway.swift
//  PTSpeed
//
//  ponytail: Keep the compatibility layer small: one actor delegates lease ownership and one transport call.
//  EN: The gateway coordinates callers around the frozen OBD transport without duplicating its protocol logic.
//  ES: La puerta coordina a los llamadores alrededor del transporte OBD congelado sin duplicar su protocolo.
//  中文：网关围绕冻结的 OBD 传输层协调调用者，不复制其中的协议逻辑。
//

import Foundation

nonisolated public enum PTOBDCompatibilityGatewayError: Error, Equatable, Sendable {
    case leaseUnavailable
    case disconnected
}

// EN: This actor is the app-owned coordination boundary; the stable transport still performs every byte transfer.
// ES: Este actor es el límite de coordinación de la app; el transporte estable sigue transfiriendo cada byte.
// 中文：这个 actor 是应用自有的协调边界，所有字节传输仍由稳定传输层完成。
public actor PTOBDCompatibilityGateway {
    public static let shared = PTOBDCompatibilityGateway()

    private init() {}

    public func withLease<Value: Sendable>(
        kind: PTOBDBusLeaseKind,
        timeout: TimeInterval? = nil,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await PTOBDBusLease.shared.withLease(
            kind: kind,
            timeout: timeout,
            operation: operation
        )
    }

    public func execute(
        normalizedCommand: String,
        requiresPause: Bool,
        leaseKind: PTOBDBusLeaseKind,
        leaseToken: PTOBDBusLeaseToken? = nil
    ) async throws -> String {
        let send = {
            await PTMotoTelemetryManager.shared.injectRawHexCommand(
                normalizedCommand,
                requiresPause: requiresPause
            )
        }

        if let leaseToken {
            // EN: A caller-owned token already identifies the lease; the command context still controls risk.
            // ES: Un token propio del llamador ya identifica la concesión; el contexto sigue controlando el riesgo.
            // 中文：调用方持有的令牌已经标识了租约，指令上下文仍然负责风险控制。
            guard await PTOBDBusLease.shared.isCurrent(leaseToken) else {
                throw PTOBDCompatibilityGatewayError.leaseUnavailable
            }
            return await send()
        }

        return try await PTOBDBusLease.shared.withLease(kind: leaseKind) {
            await send()
        }
    }

    // EN: Disconnect invalidates both active and queued work before a stale operation can reuse the bus.
    // ES: La desconexión invalida el trabajo activo y en cola antes de que una operación obsoleta reutilice el bus.
    // 中文：断开连接会先使当前和排队任务失效，避免过期任务再次使用总线。
    public func invalidateForDisconnect() async {
        await PTOBDBusLease.shared.invalidateForDisconnect()
    }
}
