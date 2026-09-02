//
//  PTOBDiagnosticAddress.swift
//  CrazyDashboard
//
//  只读 UDS 诊断地址模型。
//  Modelo de dirección para diagnóstico UDS de solo lectura.
//  EN: Read-only UDS diagnostic address model.
//

import Foundation

/// ECU 的发送与接收 CAN Header；统一在边界处规范化。
/// Header CAN de transmisión y recepción del ECU; se normaliza en el límite.
nonisolated public struct PTOBDiagnosticAddress: Codable, Hashable, Sendable {
    public let tx: String
    public let rx: String

    public init?(tx: String, rx: String) {
        let normalizedTX = Self.normalizeHeader(tx)
        let normalizedRX = Self.normalizeHeader(rx)

        guard let normalizedTX, let normalizedRX,
              normalizedTX.count == normalizedRX.count else {
            return nil
        }

        self.tx = normalizedTX
        self.rx = normalizedRX
    }

    private static func normalizeHeader(_ value: String) -> String? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard normalized.count == 3 || normalized.count == 8,
              normalized.allSatisfy({ "0123456789ABCDEF".contains($0) }) else {
            return nil
        }

        // EN: Reject IDs outside the physical 11-bit or 29-bit CAN range.
        // ES: Rechaza identificadores fuera del rango CAN físico de 11 o 29 bits.
        // 中文：拒绝超出 11-bit 或 29-bit CAN 物理范围的 ID。
        guard let numericValue = UInt32(normalized, radix: 16) else {
            return nil
        }

        let maximum = normalized.count == 3 ? 0x7FF : 0x1FFF_FFFF
        guard numericValue <= maximum else {
            return nil
        }

        return normalized
    }
}

/// 兼容早期实现中的双 D 拼写；新代码请使用 `PTOBDiagnosticAddress`。
/// Compatibilidad con la grafía antigua con dos D; el código nuevo debe usar `PTOBDiagnosticAddress`.
public typealias PTOBDDiagnosticAddress = PTOBDiagnosticAddress
