//
//  PTXP400BLEProtocolContract.swift
//  CrazyDashboard
//
//  EN: Documents the confirmed XP400 BLE boundary without owning transport state.
//  ES: Documenta el límite BLE confirmado del XP400 sin apropiarse del estado de transporte.
//  中文：固化已确认的 XP400 BLE 协议边界，但不接管传输状态。
//

import Foundation

/// EN: Pure protocol facts and validators shared by navigation adapters and tests.
/// ES: Hechos y validadores puros del protocolo compartidos por adaptadores y pruebas.
/// 中文：供导航适配层和测试复用的纯协议事实与校验器。
public enum PTXP400BLEProtocol {
    public static let preamble: UInt8 = 0x16
    public static let terminator: UInt8 = 0x00
    public static let maxTIOChunkLength = 20
    public static let maxCredits = 25
    public static let creditRefillThreshold = 4
    // EN: Keep every confirmed logical packet size explicit for state-aware ingress reassembly.
    // ES: Mantén explícito el tamaño de cada paquete lógico confirmado para el reensamblado de entrada consciente del estado.
    // 中文：为按状态进行的入站重组明确保留每种已确认逻辑数据包的长度。
    public static let vehicleStatusFrameLength = 11
    public static let authenticationKeyConfigurationFrameLength = 15
    public static let authenticationChallengeLength = 20
    public static let connectionFrameLength = 15
    public static let authenticationKeyID: UInt32 = 0x0000_2236

    // EN: Keep the confirmed authentication prefix and credit bounds in one pure contract.
    // ES: Mantén el prefijo de autenticación confirmado y los límites de créditos en un contrato puro.
    // 中文：把已确认的认证前缀和 Credits 边界集中在纯协议契约中。
    private static let authenticationKeyPrefix = Data([0x00, 0x00, 0x22, 0x36])

    public static let tioServiceUUID = "FEFB"
    public static let uartRXUUID = "00000001-0000-1000-8000-008025000000"
    public static let uartTXUUID = "00000002-0000-1000-8000-008025000000"
    public static let uartRXCreditsUUID = "00000003-0000-1000-8000-008025000000"
    public static let uartTXCreditsUUID = "00000004-0000-1000-8000-008025000000"

    public static let navigationFrameID: UInt8 = 0x01
    public static let connectionFrameID: UInt8 = 0x01
    public static let data1FrameID: UInt8 = 0x02
    public static let data2FrameID: UInt8 = 0x03
    public static let data3FrameID: UInt8 = 0x04
    public static let controlFrameID: UInt8 = 0x05
    public static let absFrameID: UInt8 = 0x06
    public static let configurationFrameID: UInt8 = 0x07

    public static let returnToRouteManeuverCode: UInt8 = 0x2E
    public static let noValidActionManeuverCode: UInt8 = 0x2F

    private static let documentedManeuverCodes: Set<UInt8> = [
        0x01, 0x02, 0x03, 0x05, 0x06, 0x07, 0x08,
        0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
        0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A,
        0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22,
        0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A,
        0x2B, 0x2C, 0x2E, 0x2F
    ]

    /// EN: Keep only maneuver codes documented by the protocol; unknown values become straight.
    /// ES: Conserva solo códigos documentados por el protocolo; los valores desconocidos se vuelven recto.
    /// 中文：只保留协议文档确认的动作码，未知值安全回退为直行。
    public static func normalizedManeuverCode(_ code: UInt8) -> UInt8 {
        documentedManeuverCodes.contains(code) ? code : 0x01
    }

    /// EN: Validate the variable-length phone-to-dashboard envelope.
    /// ES: Valida la envoltura de longitud variable del teléfono al tablero.
    /// 中文：校验手机发送给仪表的可变长度帧封装。
    public static func isValidOutboundFrame(_ data: Data) -> Bool {
        guard data.count >= 5,
              data.first == preamble,
              data.last == terminator else {
            return false
        }

        let payloadLength = (Int(data[2]) << 8) | Int(data[3])
        return data.count == payloadLength + 5
    }

    /// EN: Split a validated TIO payload into the confirmed 20-byte transport chunks.
    /// ES: Divide una carga TIO validada en fragmentos de transporte confirmados de 20 bytes.
    /// 中文：将已校验的 TIO 数据拆成协议确认的 20 字节传输分片。
    public static func tioChunks(_ data: Data) -> [Data] {
        guard !data.isEmpty else { return [] }

        return stride(from: 0, to: data.count, by: maxTIOChunkLength).map { offset in
            let end = min(offset + maxTIOChunkLength, data.count)
            return data.subdata(in: offset..<end)
        }
    }

    /// EN: Accept exactly one positive credit byte within the protocol limit.
    /// ES: Acepta exactamente un byte de crédito positivo dentro del límite del protocolo.
    /// 中文：只接受一个处于协议上限内的正 Credits 字节。
    public static func validatedRemoteCreditValue(in data: Data) -> Int? {
        guard data.count == 1,
              let rawValue = data.first,
              rawValue > 0,
              Int(rawValue) <= maxCredits else {
            return nil
        }
        return Int(rawValue)
    }

    /// EN: Prevent a valid credit increment from overflowing the per-session balance.
    /// ES: Evita que un incremento válido desborde el saldo de créditos de la sesión.
    /// 中文：防止合法的 Credits 增量让当前会话余额超过上限。
    public static func canAcceptRemoteCredits(current: Int, adding amount: Int) -> Bool {
        guard current >= 0,
              current <= maxCredits,
              amount > 0,
              amount <= maxCredits else {
            return false
        }
        return current <= maxCredits - amount
    }

    /// EN: Validate the complete fixed-size vehicle key/configuration envelope.
    /// ES: Valida la envoltura completa y de tamaño fijo de clave/configuración del vehículo.
    /// 中文：校验完整且固定长度的车辆 Key/Configuration 包络。
    public static func isValidAuthenticationKeyConfiguration(_ data: Data) -> Bool {
        data.count == authenticationKeyConfigurationFrameLength
            && data.prefix(authenticationKeyPrefix.count).elementsEqual(authenticationKeyPrefix)
    }

    /// EN: Both raw authentication challenges use an exact 20-byte boundary.
    /// ES: Ambos desafíos de autenticación sin envoltura usan exactamente 20 bytes.
    /// 中文：两种无包络认证挑战都必须严格使用 20 字节边界。
    public static func isValidAuthenticationChallenge(_ data: Data) -> Bool {
        data.count == authenticationChallengeLength
    }

    /// EN: Vehicle status frames are fixed-size frames for IDs 0x02 through 0x06.
    /// ES: Las tramas de estado del vehículo tienen tamaño fijo para los IDs 0x02 a 0x06.
    /// 中文：车辆状态帧对 0x02 至 0x06 使用固定长度格式。
    public static func isVehicleStatusFrame(_ data: Data) -> Bool {
        guard data.count == vehicleStatusFrameLength,
              data.first == preamble,
              data.last == terminator else {
            return false
        }

        return (data[1] >= data1FrameID && data[1] <= absFrameID)
    }

    /// EN: Return the 12-character hexadecimal Connectivity Box identity from the auth frame.
    /// ES: Devuelve la identidad hexadecimal de 12 caracteres del Connectivity Box.
    /// 中文：从认证连接帧中提取 12 位十六进制 Connectivity Box 身份。
    public static func connectionSerial(in data: Data) -> String? {
        guard data.count == connectionFrameLength,
              data[0] == preamble,
              data[1] == connectionFrameID,
              data.last == terminator else {
            return nil
        }

        let serialData = data.subdata(in: 2..<14)
        guard serialData.count == 12,
              serialData.allSatisfy(Self.isHexASCII) else {
            return nil
        }

        return String(decoding: serialData, as: UTF8.self)
    }

    private static func isHexASCII(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) ||
        (0x41...0x46).contains(byte) ||
        (0x61...0x66).contains(byte)
    }
}
