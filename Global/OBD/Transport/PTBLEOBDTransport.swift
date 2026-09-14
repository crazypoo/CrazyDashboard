//
//  PTBLEOBDTransport.swift
//  PTSpeed
//
//  EN: Bridges the stable generic ELM327 BLE connector to PTOBDTransport.
//  ES: Conecta el conector BLE ELM327 genérico estable con PTOBDTransport.
//  中文：把稳定的通用 ELM327 蓝牙连接器桥接到 PTOBDTransport。
//

@preconcurrency import CoreBluetooth
import Foundation

@MainActor
public final class PTBLEOBDTransport: NSObject, PTOBDTransport {
    public private(set) var state: PTOBDTransportState = .disconnected

    private let connector: PTHiddenOBDConnector
    private var receiveHandler: (@Sendable (Data) -> Void)?
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var previousIceBroken: (() -> Void)?
    private var previousDisconnected: ((Error?) -> Void)?
    private var callbacksInstalled = false

    public init(connector: PTHiddenOBDConnector = .shared) {
        self.connector = connector
        super.init()
    }

    public func connect() async throws {
        guard state != .connecting else {
            throw PTOBDTransportError.busy
        }
        if connector.isUnlocked {
            state = .connected
            return
        }

        state = .connecting
        installCallbacks()

        do {
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    connectionContinuation = continuation
                    connector.startIcebreakerConnection()
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
            // EN: The frozen connector remains the only physical ELM327 writer during migration.
            // ES: El conector congelado sigue siendo el único escritor físico ELM327 durante la migración.
            // 中文：迁移期间仍由冻结连接器作为唯一的物理 ELM327 写入者。
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

private extension PTBLEOBDTransport {
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
                self.connectionContinuation?.resume(throwing: PTOBDTransportError.connectionFailed("BLE disconnected"))
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
