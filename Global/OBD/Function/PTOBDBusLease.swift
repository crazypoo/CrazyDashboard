//
//  PTOBDBusLease.swift
//  PTSpeed
//
//  EN: One cancellable actor-owned lease serializes every advanced OBD bus user.
//  ES: Una única concesión controlada por actor serializa todos los usos avanzados del bus OBD.
//  中文：由 actor 管理的一份可取消租约，统一串行化所有高级 OBD 总线使用者。
//

import Foundation

// EN: Lease kinds describe intent for diagnostics and telemetry coordination.
// ES: Los tipos de concesión describen la intención para coordinar diagnóstico y telemetría.
// 中文：租约类型描述任务意图，用于协调诊断与遥测。
nonisolated public enum PTOBDBusLeaseKind: String, Codable, CaseIterable, Sendable {
    case telemetry
    case sniffer
    case diagnosticRead
    case developerWrite
}

// EN: Cancellation is explicit so queued work never waits forever for the vehicle bus.
// ES: La cancelación es explícita para que una tarea en cola nunca espere indefinidamente al bus.
// 中文：显式表达取消，避免排队任务无限等待车辆总线。
nonisolated public enum PTOBDBusLeaseError: Error, Equatable, Sendable {
    case cancelled
    case timedOut
    case disconnected
    case invalidToken
}

// EN: A token prevents a stale task from releasing a newer holder's lease.
// ES: El token evita que una tarea antigua libere la concesión de un propietario posterior.
// 中文：令牌防止旧任务释放后来持有者的租约。
nonisolated public struct PTOBDBusLeaseToken: Hashable, Sendable {
    public let id: UUID
    public let kind: PTOBDBusLeaseKind
    public let generation: UInt64
    public let expiresAt: Date

    fileprivate init(
        id: UUID = UUID(),
        kind: PTOBDBusLeaseKind,
        generation: UInt64,
        expiresAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.generation = generation
        self.expiresAt = expiresAt
    }
}

// ponytail: One actor and one token are enough for this phase; transport ownership stays in the stable managers.
// EN: This small actor is the single coordination point; transport ownership stays in the stable managers.
// ES: Un actor y un token bastan en esta fase; la propiedad del transporte sigue en los gestores estables.
// 中文：当前阶段一个 actor 和一个令牌即可；传输所有权仍保留在稳定管理器中。
public actor PTOBDBusLease {
    public static let shared = PTOBDBusLease()

    private struct Waiter {
        let id: UUID
        let kind: PTOBDBusLeaseKind
        let continuation: CheckedContinuation<PTOBDBusLeaseToken, Error>
    }

    private let waitTimeout: TimeInterval = 30
    private let leaseDuration: TimeInterval = 300
    private var generation: UInt64 = 0
    private var holder: PTOBDBusLeaseToken?
    private var waiters: [Waiter] = []

    // EN: Internal initialization lets tests exercise an isolated lease without touching the process-wide coordinator.
    // ES: La inicialización interna permite probar una concesión aislada sin tocar el coordinador del proceso.
    // 中文：内部初始化让测试可以使用独立租约，不干扰进程级协调器。
    init() {}

    var queuedCount: Int {
        waiters.count
    }

    public var currentKind: PTOBDBusLeaseKind? {
        holder?.kind
    }

    public func acquire(
        kind: PTOBDBusLeaseKind,
        timeout: TimeInterval? = nil
    ) async throws -> PTOBDBusLeaseToken {
        guard !Task.isCancelled else {
            throw PTOBDBusLeaseError.cancelled
        }

        if holder == nil {
            let token = makeToken(kind: kind)
            holder = token
            return token
        }

        let waiterID = UUID()
        let timeoutInterval = max(0.001, timeout ?? waitTimeout)
		let timeoutTask: Task<Void, Never> = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeoutInterval * 1_000_000_000))
                await self?.timeoutWaiter(id: waiterID)
            } catch {
                // EN: Cancellation is expected when the waiter is resumed before its deadline.
                // ES: La cancelación es esperada cuando el solicitante se reanuda antes de su plazo.
                // 中文：等待者在截止时间前被唤醒时，计时任务被取消是正常情况。
            }
        }
		let token = try await withTaskCancellationHandler(operation: {
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PTOBDBusLeaseToken, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: PTOBDBusLeaseError.cancelled)
                    return
                }
                // EN: The actor cannot re-enter between the holder check and this enqueue.
                // ES: El actor no puede reentrar entre la comprobación y esta espera en cola.
                // 中文：在检查持有者与入队之间 actor 不会重入，因此不会丢失唤醒。
                waiters.append(
                    Waiter(
                        id: waiterID,
                        kind: kind,
                        continuation: continuation
                    )
                )
            }
		}, onCancel: {
			let cancellationTask: Task<Void, Never> = Task { [weak self] in
				await self?.cancelWaiter(id: waiterID)
			}
			_ = cancellationTask
        })
        timeoutTask.cancel()

        guard !Task.isCancelled else {
            release(token)
            throw PTOBDBusLeaseError.cancelled
        }
        return token
    }

    public func release(_ token: PTOBDBusLeaseToken) {
        guard holder == token else {
            return
        }

        holder = nil
        while !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            let nextToken = makeToken(kind: waiter.kind)
            holder = nextToken
            waiter.continuation.resume(returning: nextToken)
            return
        }
    }

    // EN: A disconnect invalidates the current generation and wakes every queued operation.
    // ES: Una desconexión invalida la generación actual y despierta todas las operaciones en cola.
    // 中文：断开连接会使当前连接代次失效，并唤醒所有排队任务。
    public func invalidateForDisconnect() {
        generation &+= 1
        holder = nil
        let queued = waiters
        waiters.removeAll(keepingCapacity: false)
        queued.forEach { $0.continuation.resume(throwing: PTOBDBusLeaseError.disconnected) }
    }

    public func isCurrent(_ token: PTOBDBusLeaseToken) -> Bool {
        guard let holder,
              holder == token,
              token.generation == generation,
              token.expiresAt > Date() else {
            return false
        }
        return true
    }

    public func withLease<Value: Sendable>(
        kind: PTOBDBusLeaseKind,
        timeout: TimeInterval? = nil,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let token = try await acquire(kind: kind, timeout: timeout)
        defer { release(token) }
        return try await operation()
    }

    private func makeToken(kind: PTOBDBusLeaseKind) -> PTOBDBusLeaseToken {
        PTOBDBusLeaseToken(
            kind: kind,
            generation: generation,
            expiresAt: Date().addingTimeInterval(leaseDuration)
        )
    }

    private func timeoutWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }

        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: PTOBDBusLeaseError.timedOut)
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }

        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: PTOBDBusLeaseError.cancelled)
    }
}
