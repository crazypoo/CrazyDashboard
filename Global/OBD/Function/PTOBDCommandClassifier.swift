//
//  PTOBDCommandClassifier.swift
//  PTSpeed
//
//  EN: Classifies raw OBD/UDS commands before an app-owned gateway can send them.
//  ES: Clasifica comandos OBD/UDS sin procesar antes de que la puerta de la app los envíe.
//  中文：在应用自有网关发送裸 OBD/UDS 指令前先进行风险分级。
//

import Foundation

// EN: The safest default is unknown; callers must opt into a developer operation for it.
// ES: El valor predeterminado más seguro es desconocido; requiere una operación de desarrollador.
// 中文：最安全的默认值是未知，必须显式进入开发者操作才能发送。
nonisolated public enum PTOBDCommandRisk: String, Codable, CaseIterable, Sendable {
    case passive
    case readOnly
    case stateChanging
    case write
    case programming
    case unknown
}

nonisolated public struct PTOBDCommandClassification: Codable, Equatable, Sendable {
    public let normalizedCommand: String
    public let risk: PTOBDCommandRisk

    public init(normalizedCommand: String, risk: PTOBDCommandRisk) {
        self.normalizedCommand = normalizedCommand
        self.risk = risk
    }
}

// EN: Explicit contexts make accidental raw-command calls visible at the call site.
// ES: Los contextos explícitos hacen visibles las llamadas accidentales de comandos sin procesar.
// 中文：显式上下文让所有裸指令调用都在调用点可见。
nonisolated public enum PTOBDCommandExecutionContext: Sendable {
    case ordinary
    case developer(PTDeveloperSafetyOperation)
    case recovery
}

nonisolated public enum PTOBDCommandGatewayError: Error, Equatable, Sendable {
    case invalidCommand
    case commandTooLong
    case readNotAllowed
    case disconnected
    case leaseUnavailable
    case denied(PTOBDCommandRisk)
}

extension PTOBDCommandGatewayError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCommand:
            return "OBD command is empty or malformed."
        case .commandTooLong:
            return "OBD command exceeds the permitted length."
        case .readNotAllowed:
            return "This private read requires an explicit developer operation."
        case .disconnected:
            return "OBD is not connected."
        case .leaseUnavailable:
            return "The OBD bus is no longer available for this operation."
        case let .denied(risk):
            return "OBD command denied by safety policy: \(risk.rawValue)."
        }
    }
}

// EN: Pure classification is intentionally independent from Bluetooth, Wi-Fi, and ELM327 state.
// ES: La clasificación pura es independiente del estado de Bluetooth, Wi-Fi y ELM327.
// 中文：纯分类逻辑故意与蓝牙、Wi-Fi 和 ELM327 状态解耦。
nonisolated public enum PTOBDCommandClassifier {
    public static let maximumCommandLength = 512

    public static func classify(_ rawCommand: String) -> PTOBDCommandClassification {
        let normalized = normalize(rawCommand)
        guard !normalized.isEmpty else {
            return PTOBDCommandClassification(normalizedCommand: normalized, risk: .unknown)
        }

        if normalized.hasPrefix("AT") {
            let risk: PTOBDCommandRisk
            switch normalized {
            case "ATMA", "ATMT":
                risk = .passive
            case "ATI", "ATDP", "ATDPN", "ATRV":
                risk = .readOnly
            default:
                risk = .stateChanging
            }
            return PTOBDCommandClassification(normalizedCommand: normalized, risk: risk)
        }

        guard normalized.count >= 2,
              normalized.count.isMultiple(of: 2),
              normalized.allSatisfy({ $0.isHexDigit }) else {
            return PTOBDCommandClassification(normalizedCommand: normalized, risk: .unknown)
        }

        let service = String(normalized.prefix(2))
        let risk: PTOBDCommandRisk
        switch service {
        case "01", "02", "03", "05", "06", "07", "09", "0A", "19", "22", "23":
            risk = .readOnly
        case "04", "08", "10", "11", "14", "27", "31", "3E":
            risk = .stateChanging
        case "2E":
            risk = .write
        case "34", "36", "37":
            risk = .programming
        default:
            risk = .unknown
        }
        return PTOBDCommandClassification(normalizedCommand: normalized, risk: risk)
    }

    public static func normalize(_ rawCommand: String) -> String {
        let compact = rawCommand
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { !$0.isWhitespace && $0 != "\r" && $0 != "\n" }
        return compact.hasPrefix("$") ? String(compact.dropFirst()) : compact
    }

    // EN: Only adapter reset commands used by cleanup may bypass the developer switch.
    // ES: Solo los comandos de restablecimiento del adaptador usados al limpiar pueden omitir el interruptor.
    // 中文：只有清理流程使用的适配器复位指令可以绕过开发者开关。
    public static func isSafeRecoveryCommand(_ normalizedCommand: String) -> Bool {
        ["ATD", "ATE0", "ATL0", "ATH1", "ATS0"].contains(normalizedCommand)
    }

    // EN: Ordinary reads stay narrow; private DID and memory reads require a developer operation.
    // ES: Las lecturas ordinarias son estrictas; los DID privados y la memoria requieren una operación de desarrollador.
    // 中文：普通读取保持严格范围，私有 DID 和内存读取必须经过开发者操作。
    public static func isOrdinaryReadAllowed(_ normalizedCommand: String) -> Bool {
        let command = normalize(normalizedCommand)
        guard command.count >= 2 else { return false }

        if command.hasPrefix("AT") {
            return ["ATI", "ATDP", "ATDPN", "ATRV"].contains(command)
        }

        let service = String(command.prefix(2))
        if service == "22" {
            guard command.count == 6 else { return false }
            return confirmedReadDIDs().contains(String(command.dropFirst(2)).uppercased())
        }
        return ["01", "02", "03", "05", "06", "07", "09", "0A", "19"].contains(service)
    }

    public static func confirmedReadDIDs() -> Set<String> {
        Set(PTXP400InstructionCatalog.confirmedDIDs.map { $0.uppercased() })
    }

    // EN: Adapter setup is allowed only for the capture workflow; it must never become an ordinary raw-command path.
    // ES: La configuración del adaptador solo se permite durante la captura; nunca debe ser un comando ordinario.
    // 中文：适配器配置只允许出现在抓包流程中，不能成为普通裸指令入口。
    public static func isCaptureAdapterCommand(_ normalizedCommand: String) -> Bool {
        let command = normalize(normalizedCommand)
        let prefixes = [
            "ATCRA", "ATE0", "ATH0", "ATH1", "ATS0", "ATS1", "ATD0", "ATD1",
            "ATCAF", "ATCSM", "ATCFC", "ATFCS", "ATST", "ATAL"
        ]
        return prefixes.contains { command.hasPrefix($0) }
    }

    public static func leaseKind(
        for classification: PTOBDCommandClassification,
        context: PTOBDCommandExecutionContext
    ) -> PTOBDBusLeaseKind {
        switch context {
        case .developer(let operation):
            if operation.rawValue == PTDeveloperSafetyOperation.canCapture.rawValue {
                return .sniffer
            }
            return .developerWrite
        case .recovery:
            return .developerWrite
        case .ordinary:
            return classification.risk == .readOnly ? .diagnosticRead : .telemetry
        }
    }
}

// EN: The gateway is a compatibility boundary; stable transport and polling code remain untouched.
// ES: La puerta es un límite de compatibilidad; el transporte y el sondeo estables no se modifican.
// 中文：网关是兼容边界，稳定传输与轮询代码保持不变。
@MainActor
public final class PTOBDCommandGateway {
    public static let shared = PTOBDCommandGateway()

    private init() {}

    public func execute(
        _ rawCommand: String,
        requiresPause: Bool,
        context: PTOBDCommandExecutionContext = .ordinary,
        leaseToken: PTOBDBusLeaseToken? = nil
    ) async throws -> String {
        let classification = PTOBDCommandClassifier.classify(rawCommand)
        guard !classification.normalizedCommand.isEmpty else {
            throw PTOBDCommandGatewayError.invalidCommand
        }

        guard classification.normalizedCommand.count <= PTOBDCommandClassifier.maximumCommandLength else {
            throw PTOBDCommandGatewayError.commandTooLong
        }

        if !classification.normalizedCommand.hasPrefix("AT"),
           (!classification.normalizedCommand.count.isMultiple(of: 2) ||
            !classification.normalizedCommand.allSatisfy({ $0.isHexDigit })) {
            throw PTOBDCommandGatewayError.invalidCommand
        }

        if classification.risk == .readOnly,
           case .ordinary = context,
           !PTOBDCommandClassifier.isOrdinaryReadAllowed(classification.normalizedCommand) {
            throw PTOBDCommandGatewayError.readNotAllowed
        }

        guard isPermitted(classification: classification, context: context) else {
            throw PTOBDCommandGatewayError.denied(classification.risk)
        }

        guard PTMotoTelemetryManager.shared.isConnected else {
            throw PTOBDCommandGatewayError.disconnected
        }

        do {
            return try await PTOBDCompatibilityGateway.shared.execute(
                normalizedCommand: classification.normalizedCommand,
                requiresPause: requiresPause,
                leaseKind: PTOBDCommandClassifier.leaseKind(
                    for: classification,
                    context: context
                ),
                leaseToken: leaseToken
            )
        } catch is PTOBDCompatibilityGatewayError {
            throw PTOBDCommandGatewayError.leaseUnavailable
        }
    }

    private func isPermitted(
        classification: PTOBDCommandClassification,
        context: PTOBDCommandExecutionContext
    ) -> Bool {
        switch classification.risk {
        case .passive:
            guard case .developer(let operation) = context else { return false }
            return operation.rawValue == PTDeveloperSafetyOperation.canCapture.rawValue
                && classification.normalizedCommand == "ATMA"
        case .readOnly:
            switch context {
            case .ordinary:
                return PTOBDCommandClassifier.isOrdinaryReadAllowed(classification.normalizedCommand)
            case .developer(let operation):
                let isCaptureRead = operation.rawValue == PTDeveloperSafetyOperation.canCapture.rawValue
                    && ["ATDP", "ATDPN"].contains(classification.normalizedCommand)
                let isDeveloperRead = [
                    PTDeveloperSafetyOperation.didFuzz.rawValue,
                    PTDeveloperSafetyOperation.memoryRead.rawValue,
                    PTDeveloperSafetyOperation.rawCommand.rawValue
                ].contains(operation.rawValue)
                guard isCaptureRead || isDeveloperRead else { return false }
                return PTDeveloperSafetyGate.shared.authorize(operation)
            case .recovery:
                return false
            }
        case .stateChanging:
            switch context {
            case .developer(let operation):
                let isCaptureSetup = operation.rawValue == PTDeveloperSafetyOperation.canCapture.rawValue
                    && PTOBDCommandClassifier.isCaptureAdapterCommand(classification.normalizedCommand)
                let isRawDeveloperOperation = operation.rawValue == PTDeveloperSafetyOperation.rawCommand.rawValue
                let isSupportedDiagnosticOperation = [
                    PTDeveloperSafetyOperation.didFuzz.rawValue,
                    PTDeveloperSafetyOperation.securityAccess.rawValue,
                    PTDeveloperSafetyOperation.routineControl.rawValue,
                    PTDeveloperSafetyOperation.lifecycle.rawValue
                ].contains(operation.rawValue)
                guard isCaptureSetup || isRawDeveloperOperation || isSupportedDiagnosticOperation else {
                    return false
                }
                return PTDeveloperSafetyGate.shared.authorize(operation)
            case .recovery:
                return PTOBDCommandClassifier.isSafeRecoveryCommand(classification.normalizedCommand)
            case .ordinary:
                return false
            }
        case .write:
            return developerAuthorization(
                context: context,
                operations: [.dashboardWrite, .rawCommand]
            )
        case .programming:
            return developerAuthorization(
                context: context,
                operations: [.firmwareFlash, .bootLogoExperiment, .rawCommand]
            )
        case .unknown:
            return developerAuthorization(context: context, operations: [.rawCommand])
        }
    }

    private func developerAuthorization(
        context: PTOBDCommandExecutionContext,
        operations: [PTDeveloperSafetyOperation]
    ) -> Bool {
        guard case .developer(let operation) = context,
              operations.contains(where: { $0.rawValue == operation.rawValue }) else {
            return false
        }
        return PTDeveloperSafetyGate.shared.authorize(operation)
    }
}
