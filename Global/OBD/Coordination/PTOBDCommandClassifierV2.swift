//
//  PTOBDCommandClassifierV2.swift
//  PTSpeed
//
//  EN: Separates ELM configuration, reads, monitoring, vendor management, and unknown commands.
//  ES: Separa configuración ELM, lecturas, monitorización, gestión del proveedor y comandos desconocidos.
//  中文：区分 ELM 配置、读取、监听、厂商管理和未知指令。
//

import Foundation

nonisolated public enum PTOBDCommandKind: String, Codable, CaseIterable, Sendable {
    case elmConfiguration
    case telemetryRead
    case diagnosticRead
    case diagnosticMutation
    case canMonitor
    case vendorRead
    case vendorManagement
    case rawUnknown
}

nonisolated public struct PTOBDCommandClassificationV2: Codable, Equatable, Sendable {
    public let normalizedCommand: String
    public let kind: PTOBDCommandKind

    public init(normalizedCommand: String, kind: PTOBDCommandKind) {
        self.normalizedCommand = normalizedCommand
        self.kind = kind
    }

    public var rawValue: String { kind.rawValue }
}

nonisolated public enum PTAdapterMaintenanceOperation: String, Codable, CaseIterable, Sendable {
    case firmwareCheck
    case firmwareDownload
    case firmwareUpdate
}

nonisolated public enum PTOBDCommandClassifierV2 {
    public static func classify(_ rawCommand: String) -> PTOBDCommandClassificationV2 {
        let command = PTELM327Parser.normalize(rawCommand)
        guard !command.isEmpty else {
            return PTOBDCommandClassificationV2(normalizedCommand: command, kind: .rawUnknown)
        }

        if command.hasPrefix("AT") {
            let kind: PTOBDCommandKind
            switch command {
            case "ATMA", "ATMT":
                kind = .canMonitor
            case "AT+VERSION", "AT+CRYPT", "AT+SETCRYPT", "AT+DEBUG_FLG":
                kind = .vendorManagement
            case "ATI", "ATDP", "ATDPN", "ATRV":
                kind = .vendorRead
            case "ATZ", "ATE0", "ATE1", "ATL0", "ATL1", "ATH0", "ATH1", "ATS0", "ATS1",
                 "ATSP0", "ATD0", "ATD1", "ATCAF0", "ATCAF1", "ATCFC0", "ATCFC1", "ATAL":
                kind = .elmConfiguration
            default:
                kind = .rawUnknown
            }
            return PTOBDCommandClassificationV2(normalizedCommand: command, kind: kind)
        }

        guard command.count.isMultiple(of: 2), command.allSatisfy({ $0.isHexDigit }) else {
            return PTOBDCommandClassificationV2(normalizedCommand: command, kind: .rawUnknown)
        }

        let service = String(command.prefix(2))
        let kind: PTOBDCommandKind
        switch service {
        case "01":
            kind = .telemetryRead
        case "02", "03", "05", "06", "07", "09", "0A", "19", "22", "23":
            kind = .diagnosticRead
        case "04", "08", "10", "11", "14", "27", "31", "2E", "34", "36", "37", "3E":
            kind = .diagnosticMutation
        default:
            kind = .rawUnknown
        }
        return PTOBDCommandClassificationV2(normalizedCommand: command, kind: kind)
    }

    public static func busPurpose(for classification: PTOBDCommandClassificationV2) -> PTOBDBusPurpose {
        switch classification.kind {
        case .telemetryRead:
            return .telemetry
        case .diagnosticRead:
            return .diagnostics
        case .canMonitor:
            return .canMonitor
        case .vendorRead, .vendorManagement:
            return .adapterManagement
        case .elmConfiguration, .diagnosticMutation, .rawUnknown:
            return .research
        }
    }
}
