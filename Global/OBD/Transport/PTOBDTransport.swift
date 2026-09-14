//
//  PTOBDTransport.swift
//  PTSpeed
//
//  EN: Defines the byte-only OBD transport boundary.
//  ES: Define el límite de transporte OBD basado únicamente en bytes.
//  中文：定义只负责字节通道的 OBD 传输边界。
//

import Foundation

nonisolated public enum PTOBDTransportState: String, Codable, Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed
}

nonisolated public enum PTOBDTransportError: Error, Equatable, LocalizedError, Sendable {
    case busy
    case cancelled
    case notConnected
    case invalidPayload
    case connectionFailed(String)
    case writeFailed(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .busy:
            return "OBD transport is busy."
        case .cancelled:
            return "OBD transport was cancelled."
        case .notConnected:
            return "OBD transport is not connected."
        case .invalidPayload:
            return "OBD transport payload is not valid ASCII."
        case let .connectionFailed(message):
            return "OBD transport connection failed: \(message)"
        case let .writeFailed(message):
            return "OBD transport write failed: \(message)"
        case .timeout:
            return "OBD transport operation timed out."
        }
    }
}

// EN: Main-actor isolation matches CoreBluetooth and the existing stable connector lifecycle.
// ES: El aislamiento en el actor principal coincide con CoreBluetooth y el ciclo de vida del conector estable.
// 中文：主线程 actor 隔离与 CoreBluetooth 及现有稳定连接器的生命周期保持一致。
@MainActor
public protocol PTOBDTransport: AnyObject, Sendable {
    var state: PTOBDTransportState { get }

    func connect() async throws

    func disconnect() async

    func write(_ data: Data) async throws

    func setReceiveHandler(_ handler: @escaping @Sendable (Data) -> Void)
}

// EN: ELM command conversion is kept at the legacy compatibility edge, never in the byte-only protocol.
// ES: La conversión de comandos ELM queda en el borde de compatibilidad heredado, nunca en el protocolo de bytes.
// 中文：ELM 指令转换只存在于旧连接器兼容边界，不进入纯字节协议。
@MainActor
internal func ptOBDASCIICommand(from data: Data) throws -> String {
    guard let value = String(data: data, encoding: .ascii) else {
        throw PTOBDTransportError.invalidPayload
    }

    let command = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
    guard !command.isEmpty else {
        throw PTOBDTransportError.invalidPayload
    }
    return command
}

// EN: Legacy ELM connectors return a complete response without exposing the prompt byte.
// ES: Los conectores ELM heredados devuelven una respuesta completa sin exponer el byte prompt.
// 中文：旧 ELM 连接器返回完整响应，但不会把 prompt 字节暴露给上层。
@MainActor
internal func ptELMResponseData(from response: String) -> Data {
    let framedResponse = response.contains(">") ? response : response + "\r\n>"
    return Data(framedResponse.utf8)
}
