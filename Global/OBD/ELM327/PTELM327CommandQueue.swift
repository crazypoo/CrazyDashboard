//
//  PTELM327CommandQueue.swift
//  PTSpeed
//
//  EN: Serializes ELM requests, applies deadlines, and flushes stale work safely.
//  ES: Serializa solicitudes ELM, aplica plazos y vacía el trabajo obsoleto de forma segura.
//  中文：串行化 ELM 请求、应用超时期限，并安全清理过期任务。
//

import Foundation

nonisolated public enum PTOBDCommandPriority: Int, Codable, Comparable, Sendable {
    case low = 10
    case normal = 50
    case high = 100
    case critical = 200

    public static func < (lhs: PTOBDCommandPriority, rhs: PTOBDCommandPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated public struct PTELM327Request: Sendable {
    public let id: UUID
    public let command: String
    public let timeout: Duration
    public let priority: PTOBDCommandPriority
    public let classification: PTOBDCommandClassificationV2
    public let extensionIdentifier: String?

    public init(
        id: UUID = UUID(),
        command: String,
        timeout: Duration = .seconds(20),
        priority: PTOBDCommandPriority = .normal,
        classification: PTOBDCommandClassificationV2? = nil,
        extensionIdentifier: String? = nil
    ) {
        self.id = id
        self.command = PTELM327Parser.normalize(command)
        self.timeout = timeout
        self.priority = priority
        self.classification = classification ?? PTOBDCommandClassifierV2.classify(command)
        self.extensionIdentifier = extensionIdentifier
    }
}

nonisolated public enum PTELM327CommandQueueError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case flushed
    case timedOut(UUID)
    case invalidRequest

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "ELM327 command was cancelled."
        case .flushed:
            return "ELM327 command queue was flushed."
        case let .timedOut(id):
            return "ELM327 command timed out: \(id.uuidString)"
        case .invalidRequest:
            return "ELM327 command is empty."
        }
    }
}

public actor PTELM327CommandQueue {
    private struct Item {
        let sequence: UInt64
        let request: PTELM327Request
        let operation: @Sendable () async throws -> PTELM327Response
        let continuation: CheckedContinuation<PTELM327Response, Error>
    }

    private var pending: [Item] = []
    private var sequence: UInt64 = 0
    private var worker: Task<Void, Never>?
    private var currentRequestID: UUID?
    private var currentOperation: Task<PTELM327Response, Error>?

    public init() {}

    public var pendingCount: Int {
        pending.count + (currentRequestID == nil ? 0 : 1)
    }

    public var isIdle: Bool {
        pending.isEmpty && currentRequestID == nil
    }

    public func enqueue(
        _ request: PTELM327Request,
        operation: @escaping @Sendable () async throws -> PTELM327Response
    ) async throws -> PTELM327Response {
        guard !request.command.isEmpty else {
            throw PTELM327CommandQueueError.invalidRequest
        }
        try Task.checkCancellation()

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let item = Item(
                    sequence: sequence,
                    request: request,
                    operation: operation,
                    continuation: continuation
                )
                sequence &+= 1
                pending.append(item)
                startWorkerIfNeeded()
            }
        }, onCancel: { [weak self] in
            Task { await self?.cancel(requestID: request.id) }
        })
    }

    public func cancel(requestID: UUID) {
        if let index = pending.firstIndex(where: { $0.request.id == requestID }) {
            let item = pending.remove(at: index)
            item.continuation.resume(throwing: PTELM327CommandQueueError.cancelled)
            return
        }
        if currentRequestID == requestID {
            currentOperation?.cancel()
        }
    }

    public func flush() {
        let items = pending
        pending.removeAll(keepingCapacity: false)
        items.forEach { $0.continuation.resume(throwing: PTELM327CommandQueueError.flushed) }
        currentOperation?.cancel()
    }
}

private extension PTELM327CommandQueue {
    func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    func drain() async {
        while !pending.isEmpty {
            pending.sort {
                if $0.request.priority == $1.request.priority {
                    return $0.sequence < $1.sequence
                }
                return $0.request.priority > $1.request.priority
            }
            let item = pending.removeFirst()
            currentRequestID = item.request.id

            let operationTask = Task { try await item.operation() }
            currentOperation = operationTask
            do {
                let response = try await withThrowingTaskGroup(of: PTELM327Response.self) { group in
                    group.addTask { try await operationTask.value }
                    group.addTask {
                        try await Task.sleep(for: item.request.timeout)
                        // EN: Cancel the external operation before the race scope waits for its child to finish.
                        // ES: Cancela la operación externa antes de que el alcance de la carrera espere a su hijo.
                        // 中文：在竞争作用域等待子任务结束前，先取消外部操作。
                        operationTask.cancel()
                        throw PTELM327CommandQueueError.timedOut(item.request.id)
                    }
                    defer { group.cancelAll() }
                    guard let first = try await group.next() else {
                        throw PTELM327CommandQueueError.cancelled
                    }
                    return first
                }
                item.continuation.resume(returning: response)
            } catch {
                // EN: A timeout or cancellation must stop the underlying request before the next command starts.
                // ES: Un tiempo límite o una cancelación debe detener la solicitud subyacente antes del siguiente comando.
                // 中文：超时或取消时必须先停止底层请求，再开始下一条指令。
                operationTask.cancel()
                item.continuation.resume(throwing: error)
            }

            currentOperation = nil
            currentRequestID = nil
        }

        worker = nil
        if !pending.isEmpty {
            startWorkerIfNeeded()
        }
    }
}
