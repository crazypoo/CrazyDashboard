//
//  PTOBDBusCoordinator.swift
//  PTSpeed
//
//  EN: Maps high-level OBD purposes onto the existing cancellable bus lease.
//  ES: Mapea propósitos OBD de alto nivel a la concesión de bus cancelable existente.
//  中文：把高级 OBD 任务映射到现有的可取消总线租约。
//

import Foundation

nonisolated public enum PTOBDBusPurpose: String, Codable, CaseIterable, Sendable {
    case telemetry
    case diagnostics
    case canMonitor
    case research
    case adapterManagement
}

public actor PTOBDBusCoordinator {
    public static let shared = PTOBDBusCoordinator()

    public init() {}

    public func acquire(
        purpose: PTOBDBusPurpose,
        timeout: TimeInterval = 30
    ) async throws -> PTOBDBusLeaseToken {
        try await PTOBDBusLease.shared.acquire(
            kind: leaseKind(for: purpose),
            timeout: timeout
        )
    }

    public func release(_ token: PTOBDBusLeaseToken) async {
        await PTOBDBusLease.shared.release(token)
    }

    public func withBus<Value: Sendable>(
        purpose: PTOBDBusPurpose,
        timeout: TimeInterval = 30,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let token = try await acquire(purpose: purpose, timeout: timeout)
        do {
            let value = try await operation()
            await release(token)
            return value
        } catch {
            await release(token)
            throw error
        }
    }

    public func invalidateForDisconnect() async {
        await PTOBDBusLease.shared.invalidateForDisconnect()
    }
}

private extension PTOBDBusCoordinator {
    func leaseKind(for purpose: PTOBDBusPurpose) -> PTOBDBusLeaseKind {
        switch purpose {
        case .telemetry:
            return .telemetry
        case .diagnostics, .adapterManagement:
            return .diagnosticRead
        case .canMonitor:
            return .sniffer
        case .research:
            return .developerWrite
        }
    }
}
