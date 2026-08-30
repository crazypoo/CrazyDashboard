//
//  PTXP400InstructionCatalog.swift
//  CrazyDashboard
//
//  EN: Evidence-gated XP400 instruction metadata; it never sends a command by itself.
//  ES: Metadatos de instrucciones del XP400 protegidos por evidencia; nunca envía comandos por sí mismo.
//  中文：按证据等级管理 XP400 指令元数据，本文件本身不会发送任何命令。
//

import Foundation

public enum PTXP400InstructionEvidenceLevel: String, Codable, Sendable {
    case confirmed
    case observed
    case devTest
    case hypothesis
    case rejected
}

public enum PTXP400InstructionKind: String, Codable, Sendable {
    case read
    case write
    case routine
    case firmware
}

public struct PTXP400InstructionEvidence: Codable, Equatable, Sendable {
    public let identifier: String
    public let kind: PTXP400InstructionKind
    public let service: String
    public let target: String?
    public let requestHex: String
    public let expectedPositiveResponse: String
    public let expectedNegativeResponse: String
    public let preconditions: [String]
    public let recovery: String
    public let level: PTXP400InstructionEvidenceLevel
    public let isReversible: Bool

    public init(
        identifier: String,
        kind: PTXP400InstructionKind,
        service: String,
        target: String?,
        requestHex: String,
        expectedPositiveResponse: String,
        expectedNegativeResponse: String,
        preconditions: [String],
        recovery: String,
        level: PTXP400InstructionEvidenceLevel,
        isReversible: Bool
    ) {
        self.identifier = identifier
        self.kind = kind
        self.service = service
        self.target = target
        self.requestHex = requestHex
        self.expectedPositiveResponse = expectedPositiveResponse
        self.expectedNegativeResponse = expectedNegativeResponse
        self.preconditions = preconditions
        self.recovery = recovery
        self.level = level
        self.isReversible = isReversible
    }
}

public enum PTXP400InstructionCatalog {
    /// EN: This is the only instruction currently allowed in the ordinary read-only UI.
    /// ES: Esta es la única instrucción permitida actualmente en la interfaz ordinaria de solo lectura.
    /// 中文：这是当前普通只读界面唯一允许使用的指令。
    nonisolated public static let confirmedReadOnly: [PTXP400InstructionEvidence] = [
        PTXP400InstructionEvidence(
            identifier: "dashboard.vin.f190",
            kind: .read,
            service: "22",
            target: "F190",
            requestHex: "22F190",
            expectedPositiveResponse: "62F190",
            expectedNegativeResponse: "7F22xx",
            preconditions: [
                "Vehicle stationary",
                "Target ECU identity recorded",
                "Read-only diagnostic session"
            ],
            recovery: "No write or reset step; leave the diagnostic session through the existing coordinator.",
            level: .confirmed,
            isReversible: true
        )
    ]

    /// EN: Keep unverified operations out of the catalog until captures and recovery evidence exist.
    /// ES: Mantiene fuera del catálogo las operaciones no verificadas hasta disponer de capturas y pruebas de recuperación.
    /// 中文：在获得抓包和恢复证据前，不把未验证操作加入目录。
    nonisolated public static let unverified: [PTXP400InstructionEvidence] = []

    nonisolated public static var confirmedDIDs: [String] {
        confirmedReadOnly.compactMap(\.target)
    }

    nonisolated public static func ordinaryUIEntries() -> [PTXP400InstructionEvidence] {
        confirmedReadOnly.filter {
            $0.level == .confirmed && $0.kind == .read && $0.isReversible
        }
    }

    nonisolated public static func entry(identifier: String) -> PTXP400InstructionEvidence? {
        (confirmedReadOnly + unverified).first { $0.identifier == identifier }
    }

    /// EN: Validate the catalog before a caller uses it to build a diagnostic request.
    /// ES: Valida el catálogo antes de que un llamador construya una solicitud de diagnóstico.
    /// 中文：调用方构造诊断请求前先校验目录，避免元数据污染只读边界。
    nonisolated public static func validateOrdinaryUIEntries() -> Bool {
        let entries = ordinaryUIEntries()
        guard Set(entries.map(\.identifier)).count == entries.count else { return false }
        return entries.allSatisfy { entry in
            entry.service == "22" &&
            entry.requestHex.hasPrefix("22") &&
            entry.expectedPositiveResponse.hasPrefix("62") &&
            entry.expectedNegativeResponse.hasPrefix("7F22") &&
            entry.target != nil
        }
    }
}
