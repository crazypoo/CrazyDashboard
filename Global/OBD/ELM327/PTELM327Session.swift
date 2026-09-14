//
//  PTELM327Session.swift
//  PTSpeed
//
//  EN: Owns ELM response correlation while leaving physical bytes to PTOBDTransport.
//  ES: Posee la correlación de respuestas ELM y deja los bytes físicos a PTOBDTransport.
//  中文：负责 ELM 响应关联，但把物理字节传输交给 PTOBDTransport。
//

import Foundation

nonisolated public enum PTELM327SessionError: Error, Equatable, LocalizedError, Sendable {
    case invalidState(PTELM327State)
    case responseAlreadyPending
    case disconnected

    public var errorDescription: String? {
        switch self {
        case let .invalidState(state):
            return "ELM327 session is not ready for this operation: \(state.rawValue)"
        case .responseAlreadyPending:
            return "An ELM327 response is already pending."
        case .disconnected:
            return "ELM327 session is disconnected."
        }
    }
}

public actor PTELM327Session {
    public static let maximumCommandLength = 512

    public private(set) var state: PTELM327State = .disconnected
    public private(set) var capabilities: PTELM327Capabilities
    public private(set) var sessionIdentifiers: PTOBDSessionIdentifiers?

    private let transport: any PTOBDTransport
    private let queue = PTELM327CommandQueue()
    private let monitor = PTELM327Monitor()
    private var parser = PTELM327Parser()
    private var pendingRequestID: UUID?
    private var pendingCommand: String?
    private var pendingContinuation: CheckedContinuation<PTELM327Response, Error>?
    private var pendingWriteTask: Task<Void, Never>?
    private var isMonitoring = false

    public init(
        transport: any PTOBDTransport,
        transportKind: PTOBDTransportKind = .unknown
    ) {
        self.transport = transport
        self.capabilities = PTELM327Capabilities(transportKind: transportKind)
    }

    public func connect() async throws {
        guard state == .disconnected || state == .failed else { return }
        state = .recovering
        await transport.setReceiveHandler { [weak self] data in
            Task { await self?.receive(data) }
        }

        do {
            try await transport.connect()
            state = .transportConnected
            sessionIdentifiers = await PTOBDSessionTrace.shared.begin()
            await PTOBDSessionTrace.shared.record(
                name: "elm_transport_connected",
                metadata: ["transport": capabilities.transportKind.rawValue]
            )
        } catch {
            state = .failed
            await PTOBDSessionTrace.shared.record(
                name: "elm_transport_connect_failed",
                metadata: ["error": error.localizedDescription]
            )
            throw error
        }
    }

    public func disconnect() async {
        pendingWriteTask?.cancel()
        pendingWriteTask = nil
        if let continuation = pendingContinuation {
            pendingContinuation = nil
            pendingRequestID = nil
            pendingCommand = nil
            continuation.resume(throwing: PTELM327SessionError.disconnected)
        }
        await queue.flush()
        await monitor.stop()
        await transport.disconnect()
        parser.reset()
        isMonitoring = false
        state = .disconnected
        await PTOBDSessionTrace.shared.record(name: "elm_disconnected")
    }

    public func markReady() {
        guard state == .transportConnected || state == .initializing || state == .recovering else { return }
        state = .ready
    }

    public func beginInitialization() {
        guard state == .transportConnected || state == .recovering else { return }
        state = .initializing
    }

    public func markPolling() {
        guard state == .ready || state == .polling else { return }
        state = .polling
    }

    public func stopPolling() {
        guard state == .polling else { return }
        state = .ready
    }

    public func beginDiagnosticExclusive() throws {
        guard state == .ready || state == .polling || state == .monitoring else {
            throw PTELM327SessionError.invalidState(state)
        }
        state = .diagnosticExclusive
    }

    public func endDiagnosticExclusive() {
        guard state == .diagnosticExclusive else { return }
        state = .ready
    }

    public func suspend() {
        guard state != .disconnected else { return }
        state = .suspended
    }

    public func recover() {
        guard state == .suspended || state == .failed else { return }
        state = .recovering
    }

    public func setVendorCapabilities(_ vendor: PTYMOBDCapabilities?) {
        capabilities.vendor = vendor
    }

    public func execute(
        _ command: String,
        timeout: Duration = .seconds(20),
        priority: PTOBDCommandPriority = .normal,
        classification: PTOBDCommandClassificationV2? = nil,
        extensionIdentifier: String? = nil
    ) async throws -> PTELM327Response {
        guard canExecute else { throw PTELM327SessionError.invalidState(state) }
        let normalizedCommand = PTELM327Parser.normalize(command)
        guard !normalizedCommand.isEmpty,
              normalizedCommand.count <= Self.maximumCommandLength else {
            throw PTELM327CommandQueueError.invalidRequest
        }
        let request = PTELM327Request(
            command: normalizedCommand,
            timeout: timeout,
            priority: priority,
            classification: classification,
            extensionIdentifier: extensionIdentifier
        )
        await PTOBDSessionTrace.shared.record(
            name: "elm_command_queued",
            metadata: [
                "command": request.command,
                "classification": request.classification.rawValue
            ]
        )

        do {
            let response = try await queue.enqueue(request) { [weak self] in
                guard let self else { throw PTELM327SessionError.disconnected }
                return try await self.transmit(request: request)
            }
            await PTOBDSessionTrace.shared.record(
                name: "elm_command_completed",
                metadata: ["command": request.command, "status": response.status.rawValue]
            )
            return response
        } catch {
            await PTOBDSessionTrace.shared.record(
                name: "elm_command_failed",
                metadata: ["command": request.command, "error": error.localizedDescription]
            )
            throw error
        }
    }

    public func startMonitoring() async -> AsyncStream<PTELM327Response> {
        isMonitoring = true
        state = .monitoring
        return await monitor.start()
    }

    public func stopMonitoring() async {
        isMonitoring = false
        await monitor.stop()
        if state == .monitoring { state = .ready }
    }
}

private extension PTELM327Session {
    var canExecute: Bool {
        switch state {
        case .transportConnected, .initializing, .ready, .polling, .monitoring, .diagnosticExclusive:
            return true
        case .disconnected, .suspended, .recovering, .failed:
            return false
        }
    }

    func transmit(request: PTELM327Request) async throws -> PTELM327Response {
        guard pendingContinuation == nil else {
            throw PTELM327SessionError.responseAlreadyPending
        }

        let data = Data((request.command + "\r").utf8)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                pendingRequestID = request.id
                pendingCommand = request.command
                pendingContinuation = continuation
                pendingWriteTask = Task { [weak self] in
                    await self?.write(data, for: request.id)
                }
            }
        }, onCancel: { [weak self] in
            Task { await self?.cancelPending(requestID: request.id) }
        })
    }

    func write(_ data: Data, for requestID: UUID) async {
        do {
            try await transport.write(data)
        } catch {
            finishPending(requestID: requestID, result: .failure(error))
        }
    }

    func receive(_ data: Data) {
        let responses = parser.append(data)
        for response in responses {
            if pendingRequestID != nil,
               let continuation = pendingContinuation {
                pendingRequestID = nil
                let command = pendingCommand
                pendingCommand = nil
                pendingContinuation = nil
                pendingWriteTask = nil
                continuation.resume(returning: PTELM327Parser.parse(
                    raw: response.raw,
                    command: command,
                    promptTerminated: response.isPromptTerminated
                ))
            } else if isMonitoring {
                Task { await monitor.yield(response) }
            }
        }
    }

    func cancelPending(requestID: UUID) {
        guard pendingRequestID == requestID else { return }
        pendingWriteTask?.cancel()
        pendingWriteTask = nil
        pendingRequestID = nil
        pendingCommand = nil
        if let continuation = pendingContinuation {
            pendingContinuation = nil
            continuation.resume(throwing: PTELM327CommandQueueError.cancelled)
        }
    }

    func finishPending(
        requestID: UUID,
        result: Result<PTELM327Response, Error>
    ) {
        guard pendingRequestID == requestID, let continuation = pendingContinuation else { return }
        pendingRequestID = nil
        pendingCommand = nil
        pendingContinuation = nil
        pendingWriteTask = nil
        continuation.resume(with: result)
    }
}
