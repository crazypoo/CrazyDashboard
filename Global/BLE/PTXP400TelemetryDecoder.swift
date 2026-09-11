//
//  PTXP400TelemetryDecoder.swift
//  CrazyDashboard
//
//  EN: Validates the XP400 dashboard envelope before the existing field decoder runs.
//  ES: Valida la envoltura del tablero XP400 antes de ejecutar el decodificador de campos existente.
//  中文：在现有字段解码器运行前，先校验 XP400 仪表盘帧包络。
//

import Foundation

nonisolated struct PTXP400TelemetryFrame: Equatable, Sendable {
    let id: UInt8
    let payload: Data
}

nonisolated enum PTXP400TelemetryFrameKind: Equatable, Sendable {
    case connection
    case data1
    case data2
    case data3
    case control
    case abs
    case configuration
    case unknown
}

/// EN: This adapter owns only envelope validation and frame classification, not field semantics.
/// ES: Este adaptador solo posee la validación y clasificación de la trama, no la semántica de campos.
/// 中文：该适配器只负责包络校验和帧分类，不负责字段语义。
nonisolated enum PTXP400TelemetryDecoder {
    static func decode(_ data: Data) -> PTXP400TelemetryFrame? {
        guard data.count >= 3,
              data.first == PTXP400BLEProtocol.preamble,
              data.last == PTXP400BLEProtocol.terminator else {
            return nil
        }

        return PTXP400TelemetryFrame(
            id: data[1],
            payload: Data(data.dropFirst(2).dropLast())
        )
    }

    static func kind(for id: UInt8) -> PTXP400TelemetryFrameKind {
        switch id {
        case PTXP400BLEProtocol.connectionFrameID:
            return .connection
        case PTXP400BLEProtocol.data1FrameID:
            return .data1
        case PTXP400BLEProtocol.data2FrameID:
            return .data2
        case PTXP400BLEProtocol.data3FrameID:
            return .data3
        case PTXP400BLEProtocol.controlFrameID:
            return .control
        case PTXP400BLEProtocol.absFrameID:
            return .abs
        case PTXP400BLEProtocol.configurationFrameID:
            return .configuration
        default:
            return .unknown
        }
    }
}
