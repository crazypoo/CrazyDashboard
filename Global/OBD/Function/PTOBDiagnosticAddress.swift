//
//  PTOBDiagnosticAddress.swift
//  CrazyDashboard
//
//  只读 UDS 诊断地址模型。
//  Modelo de dirección para diagnóstico UDS de solo lectura.
//

import Foundation

/// ECU 的发送与接收 CAN Header；统一在边界处规范化。
/// Header CAN de transmisión y recepción del ECU; se normaliza en el límite.
public struct PTOBDiagnosticAddress: Codable, Hashable, Sendable {
    public let tx: String
    public let rx: String

    public init?(tx: String, rx: String) {
        let normalizedTX = Self.normalizeHeader(tx)
        let normalizedRX = Self.normalizeHeader(rx)

        guard let normalizedTX, let normalizedRX else {
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

        return normalized
    }
}

/// 兼容早期实现中的双 D 拼写；新代码请使用 `PTOBDiagnosticAddress`。
/// Compatibilidad con la grafía antigua con dos D; el código nuevo debe usar `PTOBDiagnosticAddress`.
public typealias PTOBDDiagnosticAddress = PTOBDiagnosticAddress
