//
//  PTOBDMockTransport.swift
//  PTSpeed
//
//  EN: Provides a deterministic byte transport for offline ELM tests and UI development.
//  ES: Proporciona un transporte de bytes determinista para pruebas ELM sin vehículo y desarrollo de UI.
//  中文：为离线 ELM 测试和 UI 开发提供确定性的字节传输。
//

import Foundation

@MainActor
public final class PTOBDMockTransport: NSObject, PTOBDTransport {
    public typealias ResponseProvider = @Sendable (Data) -> Data?

    public private(set) var state: PTOBDTransportState = .disconnected

    private let responseProvider: ResponseProvider
    private var receiveHandler: (@Sendable (Data) -> Void)?

    public init(responseProvider: @escaping ResponseProvider = { _ in Data(">\r\n".utf8) }) {
        self.responseProvider = responseProvider
        super.init()
    }

    public convenience init(responses: [String: String]) {
        let normalized = Dictionary(uniqueKeysWithValues: responses.map {
            ($0.key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), Data($0.value.utf8))
        })
        self.init { data in
            guard let command = String(data: data, encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() else { return nil }
            return normalized[command]
        }
    }

    public func connect() async throws {
        guard state != .connecting else { throw PTOBDTransportError.busy }
        try Task.checkCancellation()
        state = .connected
    }

    public func disconnect() async {
        state = .disconnected
    }

    public func write(_ data: Data) async throws {
        guard state == .connected else { throw PTOBDTransportError.notConnected }
        try Task.checkCancellation()
        if let response = responseProvider(data) {
            receiveHandler?(response)
        }
    }

    public func setReceiveHandler(_ handler: @escaping @Sendable (Data) -> Void) {
        receiveHandler = handler
    }
}
