//
//  PTXP400ReadOnlyDIDCatalog.swift
//  CrazyDashboard
//
//  EN: Describes explicitly approved read-only DID and ECU enumeration work.
//  ES: Describe los DID y el trabajo de enumeración ECU de solo lectura aprobados explícitamente.
//  中文：描述显式批准的只读 DID 与 ECU 枚举工作。
//

import Foundation

public nonisolated enum PTReadOnlyDIDStatus: String, Codable, CaseIterable, Sendable {
    case official
    case capturedRepeatable
    case candidate
    case disabled
}

// EN: A definition is metadata only; it never sends a request by itself.
// ES: Una definición solo contiene metadatos; nunca envía una solicitud por sí misma.
// 中文：定义只保存元数据，本身绝不会发送请求。
public nonisolated struct PTXP400ReadOnlyDIDDefinition: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let did: String
    public let title: String
    public let requestHex: String
    public let status: PTReadOnlyDIDStatus
    public let diagnosticAddress: PTOBDiagnosticAddress?
    public let fieldKeys: [PTVehicleIdentityFieldKey]
    public let evidenceIDs: [UUID]
    public let readOnly: Bool

    public init(
        id: String? = nil,
        did: String,
        title: String,
        status: PTReadOnlyDIDStatus,
        diagnosticAddress: PTOBDiagnosticAddress? = nil,
        fieldKeys: [PTVehicleIdentityFieldKey] = [],
        evidenceIDs: [UUID] = [],
        readOnly: Bool = true
    ) {
        let normalizedDID = Self.normalizeHex(did)
        self.id = String((id ?? normalizedDID).prefix(32))
        self.did = normalizedDID
        self.title = String(title.prefix(160))
        self.requestHex = normalizedDID.isEmpty ? "" : "22\(normalizedDID)"
        self.status = status
        self.diagnosticAddress = diagnosticAddress
        self.fieldKeys = Array(Set(fieldKeys)).sorted { $0.rawValue < $1.rawValue }
        self.evidenceIDs = Array(Set(evidenceIDs)).sorted { $0.uuidString < $1.uuidString }
        self.readOnly = readOnly
    }

    public var isValid: Bool {
        did.count == 4 && did.allSatisfy { "0123456789ABCDEF".contains($0) }
            && requestHex == "22\(did)"
    }

    private static func normalizeHex(_ value: String) -> String {
        value
            .uppercased()
            .filter { "0123456789ABCDEF".contains($0) }
    }
}

// EN: The catalog starts with known evidence-backed definitions and accepts candidates only through explicit insertion.
// ES: El catálogo comienza con definiciones conocidas y solo acepta candidatos mediante inserción explícita.
// 中文：目录从已知定义开始，候选项只能通过显式插入加入，禁止宽范围扫描。
public nonisolated struct PTXP400ReadOnlyDIDCatalog: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public private(set) var definitions: [PTXP400ReadOnlyDIDDefinition]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        definitions: [PTXP400ReadOnlyDIDDefinition] = PTXP400ReadOnlyDIDCatalog.knownDefinitions
    ) {
        self.schemaVersion = schemaVersion
        self.definitions = Self.normalized(definitions)
    }

    // EN: F190 is the only built-in identity DID; an empty evidence list keeps it non-readable until evidence is attached.
    // ES: F190 es el único DID de identidad integrado; sin evidencia no se considera legible.
    // 中文：F190 是唯一内置身份 DID；没有证据绑定时不会被视为可读取。
    public static let knownDefinitions: [PTXP400ReadOnlyDIDDefinition] = [
        PTXP400ReadOnlyDIDDefinition(
            did: "F190",
            title: "Vehicle identification / VIN",
            status: .official,
            fieldKeys: [.vehicleVIN]
        )
    ]

    public var readableDefinitions: [PTXP400ReadOnlyDIDDefinition] {
        definitions.filter { canRead($0) }
    }

    public var candidateDefinitions: [PTXP400ReadOnlyDIDDefinition] {
        definitions.filter { $0.status == .candidate }
    }

    public func definition(for did: String) -> PTXP400ReadOnlyDIDDefinition? {
        let normalized = did.uppercased().filter { "0123456789ABCDEF".contains($0) }
        return definitions.first { $0.did == normalized }
    }

    public func canRead(
        did: String,
        explicitlySelected: Bool = false
    ) -> Bool {
        guard let definition = definition(for: did) else { return false }
        return canRead(definition, explicitlySelected: explicitlySelected)
    }

    public func canRead(
        _ definition: PTXP400ReadOnlyDIDDefinition,
        explicitlySelected: Bool = false
    ) -> Bool {
        guard definition.isValid, definition.readOnly, !definition.evidenceIDs.isEmpty else { return false }
        switch definition.status {
        case .official, .capturedRepeatable:
            return true
        case .candidate:
            return explicitlySelected
        case .disabled:
            return false
        }
    }

    public func explicitlySelectedDefinitions(for dids: [String]) -> [PTXP400ReadOnlyDIDDefinition] {
        dids.compactMap { definition(for: $0) }
            .filter { canRead($0, explicitlySelected: true) }
            .sorted { $0.did < $1.did }
    }

    public mutating func insertCandidate(
        did: String,
        title: String,
        diagnosticAddress: PTOBDiagnosticAddress? = nil,
        fieldKeys: [PTVehicleIdentityFieldKey] = [],
        evidenceIDs: [UUID]
    ) {
        let definition = PTXP400ReadOnlyDIDDefinition(
            did: did,
            title: title,
            status: .candidate,
            diagnosticAddress: diagnosticAddress,
            fieldKeys: fieldKeys,
            evidenceIDs: evidenceIDs
        )
        guard definition.isValid, !definition.evidenceIDs.isEmpty else { return }
        definitions.removeAll { $0.did == definition.did }
        definitions = Self.normalized(definitions + [definition])
    }

    @discardableResult
    public mutating func setStatus(
        _ status: PTReadOnlyDIDStatus,
        for did: String
    ) -> Bool {
        let normalized = did.uppercased().filter { "0123456789ABCDEF".contains($0) }
        guard let index = definitions.firstIndex(where: { $0.did == normalized }) else { return false }
        let old = definitions[index]
        definitions[index] = PTXP400ReadOnlyDIDDefinition(
            id: old.id,
            did: old.did,
            title: old.title,
            status: status,
            diagnosticAddress: old.diagnosticAddress,
            fieldKeys: old.fieldKeys,
            evidenceIDs: old.evidenceIDs,
            readOnly: old.readOnly
        )
        definitions = Self.normalized(definitions)
        return true
    }

    private static func normalized(_ definitions: [PTXP400ReadOnlyDIDDefinition]) -> [PTXP400ReadOnlyDIDDefinition] {
        var seen = Set<String>()
        return definitions
            .filter { $0.isValid && seen.insert($0.did).inserted }
            .sorted { $0.did < $1.did }
    }
}

public nonisolated enum PTReadOnlyECURequestKind: String, Codable, CaseIterable, Sendable {
    case readDID
    case testerPresent
    case forbiddenMutation
    case unknown
}

// EN: Only TesterPresent and ReadDataByIdentifier are allowed in the Build 64 enumeration policy.
// ES: La política de Build 64 solo permite TesterPresent y ReadDataByIdentifier.
// 中文：Build 64 枚举策略只允许 TesterPresent 和 ReadDataByIdentifier。
public nonisolated enum PTReadOnlyECUEnumerationPolicy {
    private static let forbiddenServices: Set<UInt8> = [
        0x11, // ECU Reset / Reinicio ECU / ECU 重置
        0x27, // Security Access / Acceso de seguridad / 安全访问
        0x2E, // WriteDataByIdentifier / Escritura DID / 写入 DID
        0x31, // Routine Control / Control de rutina / 例程控制
        0x34, // Request Download / Solicitud de descarga / 请求下载
        0x36, // Transfer Data / Transferencia / 传输数据
        0x37  // Request Transfer Exit / Fin de transferencia / 结束传输
    ]

    public static func classify(requestHex: String) -> PTReadOnlyECURequestKind {
        guard let service = firstByte(in: requestHex) else { return .unknown }
        if forbiddenServices.contains(service) { return .forbiddenMutation }
        switch service {
        case 0x22: return .readDID
        case 0x3E: return .testerPresent
        default: return .unknown
        }
    }

    public static func isReadOnly(requestHex: String) -> Bool {
        switch classify(requestHex: requestHex) {
        case .readDID, .testerPresent: return true
        case .forbiddenMutation, .unknown: return false
        }
    }

    // EN: Enumeration may read only the DIDs explicitly present in the target allow-list.
    // ES: La enumeración solo puede leer los DID incluidos explícitamente en la lista permitida del objetivo.
    // 中文：枚举只能读取目标白名单中明确列出的 DID。
    public static func isReadOnly(
        requestHex: String,
        allowedDIDs: Set<String>
    ) -> Bool {
        switch classify(requestHex: requestHex) {
        case .testerPresent:
            return true
        case .readDID:
            guard let bytes = bytes(in: requestHex), bytes.count == 3 else { return false }
            let did = String(format: "%02X%02X", bytes[1], bytes[2])
            return allowedDIDs.contains(did)
        case .forbiddenMutation, .unknown:
            return false
        }
    }

    public static func isPositiveResponse(
        requestHex: String,
        responseHex: String
    ) -> Bool {
        guard let requestService = firstByte(in: requestHex),
              let responseService = firstByte(in: responseHex) else { return false }
        return responseService == requestService &+ 0x40
    }

    public static func isNegativeResponse(responseHex: String) -> Bool {
        firstByte(in: responseHex) == 0x7F
    }

    private static func firstByte(in value: String) -> UInt8? {
        bytes(in: value)?.first
    }

    private static func bytes(in value: String) -> [UInt8]? {
        let hex = value
            .uppercased()
            .replacingOccurrences(of: "0X", with: "")
            .filter { "0123456789ABCDEF".contains($0) }
        guard hex.count >= 2, hex.count.isMultiple(of: 2) else { return nil }
        return stride(from: 0, to: hex.count, by: 2).compactMap { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start..<end], radix: 16)
        }
    }
}

// EN: A probe plan is an auditable list of read-only requests, not an executor.
// ES: Un plan de sondeo es una lista auditable de solicitudes de solo lectura, no un ejecutor.
// 中文：探测计划是可审计的只读请求清单，不是执行器。
public nonisolated struct PTReadOnlyECUProbeTarget: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let role: PTECURole
    public let diagnosticAddress: PTOBDiagnosticAddress
    public let dids: [String]

    public init(
        id: UUID? = nil,
        role: PTECURole,
        diagnosticAddress: PTOBDiagnosticAddress,
        dids: [String]
    ) {
        let normalizedDIDs = Array(Set(dids.map { $0.uppercased().filter { "0123456789ABCDEF".contains($0) } }))
            .filter { $0.count == 4 }
            .sorted()
        self.id = id ?? PTVehicleIdentityStableID.make("probe:\(role.rawValue):\(diagnosticAddress.tx)->\(diagnosticAddress.rx)")
        self.role = role
        self.diagnosticAddress = diagnosticAddress
        self.dids = normalizedDIDs
    }
}

public nonisolated struct PTReadOnlyECUEnumerationPlan: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let targets: [PTReadOnlyECUProbeTarget]
    public let readOnly: Bool

    public init(
        schemaVersion: Int = currentSchemaVersion,
        targets: [PTReadOnlyECUProbeTarget]
    ) {
        self.schemaVersion = schemaVersion
        self.targets = targets.sorted { $0.id.uuidString < $1.id.uuidString }
        self.readOnly = true
    }

    public func requests(
        using catalog: PTXP400ReadOnlyDIDCatalog,
        explicitlySelectedDIDs: Set<String> = []
    ) -> [(targetID: UUID, address: PTOBDiagnosticAddress, requestHex: String)] {
        let selectedDIDs = Set(explicitlySelectedDIDs.map {
            $0.uppercased().filter { "0123456789ABCDEF".contains($0) }
        })
        return targets.flatMap { target in
            let testerPresent = [(target.id, target.diagnosticAddress, "3E")]
            let didRequests = target.dids.compactMap { did -> (UUID, PTOBDiagnosticAddress, String)? in
                guard catalog.canRead(did: did, explicitlySelected: selectedDIDs.contains(did)) else { return nil }
                return (target.id, target.diagnosticAddress, "22\(did)")
            }
            return testerPresent + didRequests
        }
    }
}

public nonisolated enum PTReadOnlyECUObservationOutcome: String, Codable, CaseIterable, Sendable {
    case positive
    case negative
    case unknown
}

public nonisolated struct PTReadOnlyECUObservation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let targetID: UUID
    public let role: PTECURole
    public let diagnosticAddress: PTOBDDiagnosticAddress
    public let requestHex: String
    public let responseHex: String?
    public let outcome: PTReadOnlyECUObservationOutcome
    public let evidenceID: UUID
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        targetID: UUID,
        role: PTECURole,
        diagnosticAddress: PTOBDDiagnosticAddress,
        requestHex: String,
        responseHex: String?,
        outcome: PTReadOnlyECUObservationOutcome,
        evidenceID: UUID,
        timestamp: Date
    ) {
        self.id = id
        self.targetID = targetID
        self.role = role
        self.diagnosticAddress = diagnosticAddress
        self.requestHex = requestHex
        self.responseHex = responseHex
        self.outcome = outcome
        self.evidenceID = evidenceID
        self.timestamp = timestamp
    }
}

public nonisolated struct PTReadOnlyECUEnumerationReport: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let observations: [PTReadOnlyECUObservation]
    public let ignoredEvidenceIDs: [UUID]
    public let readOnly: Bool

    public init(
        generatedAt: Date = Date(),
        observations: [PTReadOnlyECUObservation],
        ignoredEvidenceIDs: [UUID] = []
    ) {
        self.generatedAt = generatedAt
        self.observations = observations.sorted { $0.timestamp < $1.timestamp }
        self.ignoredEvidenceIDs = Array(Set(ignoredEvidenceIDs)).sorted { $0.uuidString < $1.uuidString }
        self.readOnly = true
    }
}

// EN: Evaluation consumes saved evidence only; it never calls a connector or sends a diagnostic request.
// ES: La evaluación solo consume evidencia guardada; nunca llama a un conector ni envía solicitudes.
// 中文：评估只消费已保存证据，绝不调用连接器或发送诊断请求。
public nonisolated enum PTReadOnlyECUEnumerationEvaluator {
    public static func evaluate(
        records: [PTProtocolEvidenceRecord],
        targets: [PTReadOnlyECUProbeTarget],
        at date: Date = Date()
    ) -> PTReadOnlyECUEnumerationReport {
        let targetByAddress = Dictionary(
            targets.map { (addressKey($0.diagnosticAddress), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var observations: [PTReadOnlyECUObservation] = []
        var ignored: [UUID] = []

        for record in records {
            guard record.domain == .obd || record.domain == .uds || record.domain == .can,
                  record.kind == .response || record.kind == .identity,
                  let request = record.request,
                  let address = addressKey(from: record.reference),
                  let target = targetByAddress[address],
                  PTReadOnlyECUEnumerationPolicy.isReadOnly(
                      requestHex: request,
                      allowedDIDs: Set(target.dids)
                  ) else {
                ignored.append(record.id)
                continue
            }

            let response = record.response
            let outcome: PTReadOnlyECUObservationOutcome
            if let response, PTReadOnlyECUEnumerationPolicy.isPositiveResponse(requestHex: request, responseHex: response) {
                outcome = .positive
            } else if let response, PTReadOnlyECUEnumerationPolicy.isNegativeResponse(responseHex: response) {
                outcome = .negative
            } else {
                outcome = .unknown
            }

            observations.append(
                PTReadOnlyECUObservation(
                    targetID: target.id,
                    role: target.role,
                    diagnosticAddress: target.diagnosticAddress,
                    requestHex: request,
                    responseHex: response,
                    outcome: outcome,
                    evidenceID: record.id,
                    timestamp: record.timestamp
                )
            )
        }

        return PTReadOnlyECUEnumerationReport(
            generatedAt: date,
            observations: observations,
            ignoredEvidenceIDs: ignored
        )
    }

    private static func addressKey(_ address: PTOBDiagnosticAddress) -> String {
        "\(address.tx)->\(address.rx)"
    }

    private static func addressKey(from reference: String?) -> String? {
        guard let reference else { return nil }
        let normalized = reference.uppercased().replacingOccurrences(of: " ", with: "")
        let parts = normalized.components(separatedBy: "->")
        guard parts.count == 2 else { return nil }
        return "\(parts[0])->\(parts[1])"
    }
}
