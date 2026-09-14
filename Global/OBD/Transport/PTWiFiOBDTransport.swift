//
//  PTWiFiOBDTransport.swift
//  PTSpeed
//
//  EN: Bridges the stable Wi-Fi ELM327 connector to PTOBDTransport.
//  ES: Conecta el conector Wi-Fi ELM327 estable con PTOBDTransport.
//  中文：把稳定的 Wi-Fi ELM327 连接器桥接到 PTOBDTransport。
//

import Foundation

@MainActor
public final class PTWiFiOBDTransport: NSObject, PTOBDTransport {
    public private(set) var state: PTOBDTransportState = .disconnected

    private let connector: PTWifiOBDConnector
    private let host: String
    private let port: UInt16
    private var receiveHandler: (@Sendable (Data) -> Void)?
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var previousIceBroken: (() -> Void)?
    private var previousDisconnected: ((Error?) -> Void)?
    private var callbacksInstalled = false

    public init(
        host: String = "192.168.0.10",
        port: UInt16 = 35000,
        connector: PTWifiOBDConnector = .shared
    ) {
        self.host = host
        self.port = port
        self.connector = connector
        super.init()
    }

    public func connect() async throws {
        guard state != .connecting else { throw PTOBDTransportError.busy }
        if connector.isUnlocked {
            state = .connected
            return
        }

        state = .connecting
        installCallbacks()
        connector.targetIP = host
        connector.targetPort = port

        do {
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    connectionContinuation = continuation
                    connector.startConnection()
                }
            }, onCancel: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.cancelPendingConnection()
                }
            })
            state = .connected
        } catch {
            state = error is CancellationError ? .disconnected : .failed
            throw error
        }
    }

    public func disconnect() async {
        cancelPendingConnection()
        connector.disconnect()
        restoreCallbacks()
        state = .disconnected
    }

    public func write(_ data: Data) async throws {
        guard state == .connected, connector.isUnlocked else {
            throw PTOBDTransportError.notConnected
        }
        let command = try ptOBDASCIICommand(from: data)
        do {
            let response = try await connector.sendOBDCommandAsync(command)
            // EN: Re-add the prompt expected by PTELM327Session because the legacy async API strips it.
            // ES: Vuelve a añadir el prompt esperado por PTELM327Session porque la API heredada lo elimina.
            // 中文：旧异步 API 会移除 prompt，因此在交给 PTELM327Session 前补回它。
            receiveHandler?(ptELMResponseData(from: response))
        } catch {
            throw PTOBDTransportError.writeFailed(error.localizedDescription)
        }
    }

    public func setReceiveHandler(_ handler: @escaping @Sendable (Data) -> Void) {
        receiveHandler = handler
    }
}

private extension PTWiFiOBDTransport {
    func installCallbacks() {
        guard !callbacksInstalled else { return }
        callbacksInstalled = true
        previousIceBroken = connector.onIceBroken
        previousDisconnected = connector.onDisconnected

        connector.onIceBroken = { [weak self] in
            self?.previousIceBroken?()
            guard let self else { return }
            self.state = .connected
            self.connectionContinuation?.resume(returning: ())
            self.connectionContinuation = nil
        }
        connector.onDisconnected = { [weak self] error in
            self?.previousDisconnected?(error)
            guard let self else { return }
            self.state = .disconnected
            if let error {
                self.connectionContinuation?.resume(throwing: error)
            } else {
                self.connectionContinuation?.resume(throwing: PTOBDTransportError.connectionFailed("Wi-Fi disconnected"))
            }
            self.connectionContinuation = nil
        }
    }

    func restoreCallbacks() {
        guard callbacksInstalled else { return }
        connector.onIceBroken = previousIceBroken
        connector.onDisconnected = previousDisconnected
        previousIceBroken = nil
        previousDisconnected = nil
        callbacksInstalled = false
    }

    func cancelPendingConnection() {
        guard connectionContinuation != nil else { return }
        connector.disconnect()
        connectionContinuation?.resume(throwing: PTOBDTransportError.cancelled)
        connectionContinuation = nil
        state = .disconnected
    }
}
