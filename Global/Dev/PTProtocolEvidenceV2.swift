//
//  PTProtocolEvidenceV2.swift
//  CrazyDashboard
//
//  EN: Build 60 unifies passive protocol evidence without replacing any transport core.
//  ES: Build 60 unifica la evidencia pasiva del protocolo sin sustituir ningún núcleo de transporte.
//  中文：Build 60 统一被动协议证据，但不替换任何传输核心。
//

import Foundation

// EN: Domains prevent YMOBD adapter maintenance traffic from being mistaken for XP400 vehicle traffic.
// ES: Los dominios impiden confundir el mantenimiento del adaptador YMOBD con tráfico del vehículo XP400.
// 中文：域用于防止把 YMOBD 适配器维护流量误认为 XP400 车辆流量。
nonisolated public enum PTProtocolEvidenceDomain: String, Codable, CaseIterable, Sendable {
    case xp400BLE
    case obd
    case can
    case uds
    case ymobdVendorExtension
    case ymobdFirmwareOTA
    case firmwareResearch
}

nonisolated public enum PTProtocolEvidenceSource: String, Codable, CaseIterable, Sendable {
    case live
    case mock
    case replay
    case imported
    case migrated
    case system
    case unknown

    public init(discoverySource: PTProtocolDiscoverySource) {
        switch discoverySource {
        case .real: self = .live
        case .mock: self = .mock
        case .replay: self = .replay
        case .unknown: self = .unknown
        }
    }

    public init(traceSource: PTTraceSource) {
        switch traceSource {
        case .live: self = .live
        case .mock: self = .mock
        case .replay: self = .replay
        case .system: self = .system
        }
    }
}

nonisolated public enum PTProtocolEvidenceDirection: String, Codable, CaseIterable, Sendable {
    case tx
    case rx
    case state
    case marker
}

nonisolated public enum PTProtocolEvidenceKind: String, Codable, CaseIterable, Sendable {
    case frame
    case command
    case response
    case session
    case candidate
    case telemetry
    case marker
    case identity
    case adapterIdentity
    case firmwareOTA
    case research
}

// EN: Every record carries source, timestamp, and bounded confidence so a candidate never looks like a confirmed protocol fact.
// ES: Cada registro lleva fuente, tiempo y confianza limitada para que un candidato nunca parezca un hecho confirmado.
// 中文：每条记录都带来源、时间和有界置信度，候选结果不会伪装成已确认协议事实。
nonisolated public struct PTProtocolEvidenceRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let domain: PTProtocolEvidenceDomain
    public let kind: PTProtocolEvidenceKind
    public let direction: PTProtocolEvidenceDirection
    public let source: PTProtocolEvidenceSource
    public let timestamp: Date
    public let confidence: Double
    public let value: String
    public let request: String?
    public let response: String?
    public let fingerprint: String?
    public let vehicleID: UUID?
    public let referenceID: UUID?
    public let reference: String?
    public let note: String?

    public init(
        id: UUID = UUID(),
        domain: PTProtocolEvidenceDomain,
        kind: PTProtocolEvidenceKind,
        direction: PTProtocolEvidenceDirection = .state,
        source: PTProtocolEvidenceSource,
        timestamp: Date = Date(),
        confidence: Double,
        value: String,
        request: String? = nil,
        response: String? = nil,
        fingerprint: String? = nil,
        vehicleID: UUID? = nil,
        referenceID: UUID? = nil,
        reference: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.domain = domain
        self.kind = kind
        self.direction = direction
        self.source = source
        self.timestamp = timestamp
        self.confidence = confidence.isFinite ? min(max(confidence, 0), 1) : 0
        self.value = String(value.prefix(4_096))
        self.request = request.map { String($0.prefix(1_024)) }
        self.response = response.map { String($0.prefix(4_096)) }
        self.fingerprint = fingerprint.map { String($0.prefix(512)) }
        self.vehicleID = vehicleID
        self.referenceID = referenceID
        self.reference = reference.map { String($0.prefix(512)) }
        self.note = note.map { String($0.prefix(1_024)) }
    }
}

// EN: A CAN bit candidate is an observation for research only; it never creates an executable command.
// ES: Un candidato de bit CAN solo es una observación para investigación; nunca crea un comando ejecutable.
// 中文：CAN 位候选只是研究观察结果，绝不会创建可执行指令。
nonisolated public struct PTProtocolCANBitCandidate: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let captureID: UUID
    public let eventID: UUID
    public let header: String
    public let changedByteIndexes: [Int]
    public let changedBits: [Int]
    public let dominantBeforePayload: String?
    public let dominantAfterPayload: String?
    public let changedFrameCount: Int
    public let firstChangeRelativeTimestamp: TimeInterval?
    public let lastChangeRelativeTimestamp: TimeInterval?
    public let score: Int
    public let source: PTProtocolEvidenceSource
    public let timestamp: Date
    public let confidence: Double
    public let vehicleID: UUID?
    public let note: String

    public init(
        id: UUID = UUID(),
        captureID: UUID,
        eventID: UUID,
        header: String,
        changedByteIndexes: [Int],
        changedBits: [Int],
        dominantBeforePayload: String?,
        dominantAfterPayload: String?,
        changedFrameCount: Int,
        firstChangeRelativeTimestamp: TimeInterval?,
        lastChangeRelativeTimestamp: TimeInterval?,
        score: Int,
        source: PTProtocolEvidenceSource,
        timestamp: Date,
        confidence: Double,
        vehicleID: UUID? = nil,
        note: String = "candidate requires human confirmation"
    ) {
        self.id = id
        self.captureID = captureID
        self.eventID = eventID
        self.header = header.uppercased()
        self.changedByteIndexes = Array(Set(changedByteIndexes.filter { $0 >= 0 }).sorted().prefix(64))
        self.changedBits = Array(Set(changedBits.filter { $0 >= 0 && $0 < 8 }).sorted().prefix(64))
        self.dominantBeforePayload = dominantBeforePayload
        self.dominantAfterPayload = dominantAfterPayload
        self.changedFrameCount = max(changedFrameCount, 0)
        self.firstChangeRelativeTimestamp = firstChangeRelativeTimestamp
        self.lastChangeRelativeTimestamp = lastChangeRelativeTimestamp
        self.score = max(score, 0)
        self.source = source
        self.timestamp = timestamp
        self.confidence = confidence.isFinite ? min(max(confidence, 0), 1) : 0
        self.vehicleID = vehicleID
        self.note = String(note.prefix(512))
    }

    public var evidenceDomain: PTProtocolEvidenceDomain { .can }

    public var summary: String {
        let bytes = changedByteIndexes.map(String.init).joined(separator: ",")
        let bits = changedBits.map(String.init).joined(separator: ",")
        return "CAN \(header): bytes=[\(bytes)] bits=[\(bits)] score=\(score)"
    }
}

nonisolated public enum PTProtocolEvidenceCaptureTemplateID: String, Codable, CaseIterable, Sendable {
    case xp400BLEMenuChange
    case obdPIDObservation
    case canEventWindow
    case udsDIDRead
    case ymobdVersionCheck
}

// EN: Templates describe a safe observation workflow and contain no automatic device operation.
// ES: Las plantillas describen un flujo seguro de observación y no contienen operaciones automáticas del dispositivo.
// 中文：模板只描述安全观察流程，不包含任何自动设备操作。
nonisolated public struct PTProtocolEvidenceCaptureTemplate: Codable, Equatable, Identifiable, Sendable {
    public let id: PTProtocolEvidenceCaptureTemplateID
    public let title: String
    public let domain: PTProtocolEvidenceDomain
    public let purpose: String
    public let steps: [String]
    public let readOnly: Bool
    public let requiresUserMarker: Bool

    public init(
        id: PTProtocolEvidenceCaptureTemplateID,
        title: String,
        domain: PTProtocolEvidenceDomain,
        purpose: String,
        steps: [String],
        readOnly: Bool = true,
        requiresUserMarker: Bool
    ) {
        self.id = id
        self.title = title
        self.domain = domain
        self.purpose = purpose
        self.steps = Array(steps.prefix(12))
        self.readOnly = readOnly
        self.requiresUserMarker = requiresUserMarker
    }
}

nonisolated public enum PTProtocolEvidenceCaptureTemplateCatalog {
    public static let templates: [PTProtocolEvidenceCaptureTemplate] = [
        PTProtocolEvidenceCaptureTemplate(
            id: .xp400BLEMenuChange,
            title: "XP400 BLE menu change",
            domain: .xp400BLE,
            purpose: "Compare an existing dashboard setting change with passive BLE evidence.",
            steps: ["Start passive evidence", "Record baseline", "Change one setting in the official app", "Record the result", "Repeat the original value"],
            requiresUserMarker: true
        ),
        PTProtocolEvidenceCaptureTemplate(
            id: .obdPIDObservation,
            title: "OBD PID observation",
            domain: .obd,
            purpose: "Review standard ELM327 traffic without adding a second transport path.",
            steps: ["Connect the adapter", "Start passive evidence", "Observe normal polling", "Stop and export"],
            requiresUserMarker: false
        ),
        PTProtocolEvidenceCaptureTemplate(
            id: .canEventWindow,
            title: "CAN event window",
            domain: .can,
            purpose: "Use a user marker to rank byte and bit changes around one reversible event.",
            steps: ["Start CAN monitor", "Mark before the event", "Perform one reversible vehicle action", "Mark after the event", "Stop and review candidates"],
            requiresUserMarker: true
        ),
        PTProtocolEvidenceCaptureTemplate(
            id: .udsDIDRead,
            title: "UDS DID read",
            domain: .uds,
            purpose: "Store a confirmed read-only DID response with its ECU address and timestamp.",
            steps: ["Select a confirmed read-only DID", "Read the DID", "Review positive or negative response", "Export the redacted result"],
            requiresUserMarker: false
        ),
        PTProtocolEvidenceCaptureTemplate(
            id: .ymobdVersionCheck,
            title: "YMOBD AT+VERSION",
            domain: .ymobdVendorExtension,
            purpose: "Keep adapter version metadata separate from vehicle firmware evidence.",
            steps: ["Connect a YMOBD-compatible adapter", "Observe the existing version probe", "Review vendor metadata", "Do not label it as XP400 firmware"],
            requiresUserMarker: false
        )
    ]
}

nonisolated public enum PTProtocolEvidenceCorrelationSource: String, Codable, CaseIterable, Sendable {
    case xp400BLETelemetry
    case obdTelemetry
    case can
    case gps
    case motion
    case userMarker
}

nonisolated public struct PTProtocolEvidenceCorrelationEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let source: PTProtocolEvidenceCorrelationSource
    public let domain: PTProtocolEvidenceDomain?
    public let timestamp: Date
    public let confidence: Double
    public let summary: String
    public let evidenceID: UUID?

    public init(
        id: UUID = UUID(),
        source: PTProtocolEvidenceCorrelationSource,
        domain: PTProtocolEvidenceDomain?,
        timestamp: Date,
        confidence: Double,
        summary: String,
        evidenceID: UUID? = nil
    ) {
        self.id = id
        self.source = source
        self.domain = domain
        self.timestamp = timestamp
        self.confidence = confidence.isFinite ? min(max(confidence, 0), 1) : 0
        self.summary = String(summary.prefix(1_024))
        self.evidenceID = evidenceID
    }
}

nonisolated public struct PTProtocolEvidenceCorrelationReport: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let vehicleID: UUID?
    public let startedAt: Date
    public let endedAt: Date
    public let entries: [PTProtocolEvidenceCorrelationEntry]
    public let excludedDomains: [PTProtocolEvidenceDomain]

    public init(
        id: UUID = UUID(),
        vehicleID: UUID?,
        startedAt: Date,
        endedAt: Date,
        entries: [PTProtocolEvidenceCorrelationEntry],
        excludedDomains: [PTProtocolEvidenceDomain] = [.ymobdFirmwareOTA]
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.entries = entries.sorted { $0.timestamp < $1.timestamp }
        self.excludedDomains = excludedDomains
    }

    public var sources: [PTProtocolEvidenceCorrelationSource] {
        var result: [PTProtocolEvidenceCorrelationSource] = []
        for source in entries.map(\.source) where !result.contains(source) {
            result.append(source)
        }
        return result
    }
}

// EN: Passport fields are evidence-bearing values, not inferred factory specifications.
// ES: Los campos del pasaporte son valores con evidencia, no especificaciones de fábrica inferidas.
// 中文：Passport 字段都是带证据的值，不是推测出来的厂家规格。
nonisolated public struct PTVehiclePassportField: Codable, Equatable, Sendable {
    public let key: String
    public let value: String?
    public let source: PTProtocolEvidenceSource
    public let timestamp: Date
    public let confidence: Double

    public init(
        key: String,
        value: String?,
        source: PTProtocolEvidenceSource,
        timestamp: Date,
        confidence: Double
    ) {
        self.key = String(key.prefix(128))
        self.value = value.map { String($0.prefix(512)) }
        self.source = source
        self.timestamp = timestamp
        self.confidence = confidence.isFinite ? min(max(confidence, 0), 1) : 0
    }

    public var displayValue: String { value?.isEmpty == false ? value! : "—" }
}

nonisolated public struct PTVehiclePassport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let generatedAt: Date
    public let vehicleID: UUID?
    public let vehicleFields: [PTVehiclePassportField]
    public let adapterFields: [PTVehiclePassportField]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        generatedAt: Date = Date(),
        vehicleID: UUID?,
        vehicleFields: [PTVehiclePassportField],
        adapterFields: [PTVehiclePassportField]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.vehicleID = vehicleID
        self.vehicleFields = vehicleFields
        self.adapterFields = adapterFields
    }

    public func field(for key: String, inAdapter: Bool = false) -> PTVehiclePassportField? {
        (inAdapter ? adapterFields : vehicleFields).first { $0.key == key }
    }
}

nonisolated public struct PTProtocolEvidenceV2Document: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let generatedAt: Date
    public let records: [PTProtocolEvidenceRecord]
    public let canCandidates: [PTProtocolCANBitCandidate]
    public let correlations: [PTProtocolEvidenceCorrelationReport]
    public let passport: PTVehiclePassport
    public let captureTemplates: [PTProtocolEvidenceCaptureTemplate]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        generatedAt: Date = Date(),
        records: [PTProtocolEvidenceRecord],
        canCandidates: [PTProtocolCANBitCandidate],
        correlations: [PTProtocolEvidenceCorrelationReport],
        passport: PTVehiclePassport,
        captureTemplates: [PTProtocolEvidenceCaptureTemplate] = PTProtocolEvidenceCaptureTemplateCatalog.templates
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.records = records
        self.canCandidates = canCandidates
        self.correlations = correlations
        self.passport = passport
        self.captureTemplates = captureTemplates
    }
}

// EN: CAN discovery consumes only a capture and user event markers; OTA state cannot influence the result.
// ES: El descubrimiento CAN solo consume una captura y marcas del usuario; el estado OTA no puede influir.
// 中文：CAN Discovery 只使用抓包和用户事件标记，OTA 状态不会参与结果。
nonisolated public enum PTProtocolEvidenceV2CANDiscovery {
    public static func discover(
        in session: PTCANCaptureSession,
        source: PTProtocolEvidenceSource = .live,
        vehicleID: UUID? = nil,
        before: TimeInterval = 2,
        after: TimeInterval = 2,
        maximumResults: Int = 100
    ) -> [PTProtocolCANBitCandidate] {
        PTProtocolCANDiscoveryEngine.discover(
            in: session,
            source: source,
            vehicleID: vehicleID,
            before: before,
            after: after,
            maximumResults: maximumResults
        )
    }

    public static func evidenceRecord(
        from candidate: PTProtocolCANBitCandidate
    ) -> PTProtocolEvidenceRecord {
        PTProtocolEvidenceRecord(
            id: candidate.id,
            domain: .can,
            kind: .candidate,
            direction: .state,
            source: candidate.source,
            timestamp: candidate.timestamp,
            confidence: candidate.confidence,
            value: candidate.summary,
            fingerprint: "can:\(candidate.header):\(candidate.changedByteIndexes.map(String.init).joined(separator: ","))",
            vehicleID: candidate.vehicleID,
            referenceID: candidate.eventID,
            reference: "capture:\(candidate.captureID.uuidString)",
            note: candidate.note
        )
    }
}

// EN: Migration is intentionally one-way and additive; old stores remain the compatibility source of truth.
// ES: La migración es unidireccional y aditiva; los almacenes antiguos siguen siendo la fuente compatible.
// 中文：迁移只做单向追加，旧存储仍然保留为兼容数据源。
nonisolated public enum PTProtocolEvidenceV2Migration {
    public static func from(_ record: PTXP400EvidenceRecord) -> PTProtocolEvidenceRecord {
        let source = sourceFromLegacy(record.source)
        let redactedResponse = record.did.uppercased() == "F190"
            ? "<VIN response redacted>"
            : record.rawResponse
        let value = [
            "DID=\(record.did)",
            "status=\(record.status.rawValue)",
            "response=\(redactedResponse)",
            record.payloadHex.map { "payload=\($0)" },
            record.decodedText.map { "text=\($0)" }
        ].compactMap { $0 }.joined(separator: " | ")
        return PTProtocolEvidenceRecord(
            id: record.id,
            domain: .uds,
            kind: .response,
            direction: .rx,
            source: source,
            timestamp: record.capturedAt,
            confidence: confidence(for: record.evidenceLevel),
            value: value,
            request: record.requestHex,
            response: redactedResponse,
            fingerprint: "uds:\(record.address.tx):\(record.did)",
            vehicleID: record.vehicleID,
            reference: "\(record.address.tx)->\(record.address.rx)"
        )
    }

    public static func from(
        _ frame: PTXP400BLEEvidenceFrame,
        session: PTXP400BLEEvidenceSession,
        vehicleModel: String,
        importedAt: Date
    ) -> PTProtocolEvidenceRecord {
        let timestamp = frame.timestamp.isFinite
            ? session.capturedAt.addingTimeInterval(frame.timestamp)
            : importedAt
        let direction: PTProtocolEvidenceDirection
        switch frame.direction {
        case .tx: direction = .tx
        case .rx: direction = .rx
        case .unknown: direction = .state
        }
        return PTProtocolEvidenceRecord(
            id: frame.id,
            domain: .xp400BLE,
            kind: .frame,
            direction: direction,
            source: .imported,
            timestamp: timestamp,
            confidence: frame.rawHex.isEmpty ? 0 : 0.8,
            value: frame.rawHex,
            request: frame.direction == .tx ? frame.rawHex : nil,
            response: frame.direction == .rx ? frame.rawHex : nil,
            fingerprint: "ble:\(frame.characteristicUUID ?? "unknown"):\(frame.rawHex.prefix(24))",
            referenceID: session.id,
            reference: vehicleModel,
            note: frame.note
        )
    }

    public static func from(_ summary: PTProtocolDiscoverySessionSummary) -> PTProtocolEvidenceRecord {
        let domain: PTProtocolEvidenceDomain = summary.channel == .dashboardBLE ? .xp400BLE : .obd
        let confidence = summary.eventCount > 0 ? 0.75 : 0.35
        let value = "\(summary.channel.rawValue) session: events=\(summary.eventCount), candidates=\(summary.candidateCount), anomalies=\(summary.anomalyCount), transport=\(summary.transport)"
        return PTProtocolEvidenceRecord(
            id: summary.id,
            domain: domain,
            kind: .session,
            direction: .state,
            source: PTProtocolEvidenceSource(discoverySource: summary.source),
            timestamp: summary.startedAt,
            confidence: confidence,
            value: value,
            fingerprint: "session:\(summary.channel.rawValue):\(summary.id.uuidString)",
            vehicleID: summary.vehicleID,
            referenceID: summary.id,
            reference: summary.fileName,
            note: summary.endedAt == nil ? "session was not finalized" : nil
        )
    }

    public static func from(_ report: PTProtocolExperimentReport) -> PTProtocolEvidenceRecord {
        PTProtocolEvidenceRecord(
            id: report.id,
            domain: .firmwareResearch,
            kind: .research,
            direction: .marker,
            source: .migrated,
            timestamp: report.endedAt,
            confidence: Double(report.candidateScore) / 100,
            value: "setting=\(report.setting.rawValue), status=\(report.candidateStatus.rawValue), operations=\(report.operationHitCount), data3Confirmations=\(report.data3ConfirmationCount)",
            referenceID: report.id,
            note: "research candidate only; not an executable protocol"
        )
    }

    public static func from(_ event: PTCrazyTraceEvent) -> PTProtocolEvidenceRecord? {
        guard let domain = domain(for: event.domain) else { return nil }
        let value: String
        let kind: PTProtocolEvidenceKind
        let direction = direction(for: event.direction)
        var reference: String?

        switch event.payload {
        case .protocolMessage(let payload):
            value = payload.raw
            kind = payload.command == nil ? .frame : .command
            reference = payload.command
        case .adapter(let payload):
            value = "vendor=\(payload.vendor ?? "—"), model=\(payload.model ?? "—"), firmware=\(payload.firmwareVersion ?? "—"), transport=\(payload.transport.rawValue)"
            kind = domain == .ymobdFirmwareOTA ? .firmwareOTA : .adapterIdentity
        default:
            return nil
        }

        let normalizedCommand = reference?.replacingOccurrences(of: " ", with: "").uppercased()
        let resolvedDomain: PTProtocolEvidenceDomain = normalizedCommand == "AT+VERSION"
            ? .ymobdVendorExtension
            : domain == .obd && (normalizedCommand?.hasPrefix("22") == true ? true : false) ? .uds : domain
        return PTProtocolEvidenceRecord(
            id: event.id,
            domain: resolvedDomain,
            kind: kind,
            direction: direction,
            source: PTProtocolEvidenceSource(traceSource: event.source),
            timestamp: event.timestamp,
            confidence: event.isDomainConsistent ? 0.85 : 0.35,
            value: value,
            request: payloadCommand(from: event.payload, direction: event.direction),
            response: payloadResponse(from: event.payload, direction: event.direction),
            fingerprint: "trace:\(event.domain.rawValue):\(event.sequence)",
            reference: reference,
            note: event.isDomainConsistent ? nil : "trace domain and payload domain disagree"
        )
    }

    public static func adapterEvidence(
        snapshot: PTOBDAdapterSnapshot,
        source: PTProtocolEvidenceSource,
        timestamp: Date = Date(),
        vehicleID: UUID? = nil
    ) -> PTProtocolEvidenceRecord? {
        guard snapshot.vendor != nil || snapshot.model != nil || snapshot.firmwareVersion != nil else { return nil }
        return PTProtocolEvidenceRecord(
            domain: .ymobdVendorExtension,
            kind: .adapterIdentity,
            direction: .state,
            source: source,
            timestamp: timestamp,
            confidence: snapshot.isOfficialYMOBD ? 1 : 0.65,
            value: "AT+VERSION metadata: vendor=\(snapshot.vendor ?? "—"), model=\(snapshot.model ?? "—"), version=\(snapshot.firmwareVersion ?? "—")",
            fingerprint: "ymobd:version:\(snapshot.vendor ?? "unknown"):\(snapshot.model ?? "unknown")",
            vehicleID: vehicleID,
            reference: "AT+VERSION",
            note: "adapter metadata; not XP400 vehicle firmware"
        )
    }

    public static func otaEvidence(
        snapshot: PTCrazyDashboardOTAMetrics,
        source: PTProtocolEvidenceSource,
        timestamp: Date = Date(),
        vehicleID: UUID? = nil
    ) -> PTProtocolEvidenceRecord? {
        guard snapshot.isVisible else { return nil }
        return PTProtocolEvidenceRecord(
            domain: .ymobdFirmwareOTA,
            kind: .firmwareOTA,
            direction: .state,
            source: source,
            timestamp: timestamp,
            confidence: snapshot.error == nil ? 0.9 : 0.5,
            value: "Jieli adapter OTA state=\(snapshot.state), progress=\(Int(snapshot.progress * 100))%, current=\(snapshot.currentFirmwareVersion ?? "—"), target=\(snapshot.targetFirmwareVersion ?? "—")",
            fingerprint: "ymobd-ota:\(snapshot.state)",
            vehicleID: vehicleID,
            note: "adapter maintenance timeline; not a vehicle signal"
        )
    }

    public static func sourceFromLegacy(_ value: String) -> PTProtocolEvidenceSource {
        let lowercased = value.lowercased()
        if lowercased.contains("mock") { return .mock }
        if lowercased.contains("replay") { return .replay }
        if lowercased.contains("import") { return .imported }
        if lowercased.contains("system") { return .system }
        return .live
    }

    private static func confidence(for level: PTXP400InstructionEvidenceLevel) -> Double {
        switch level {
        case .confirmed: return 1
        case .observed: return 0.8
        case .devTest: return 0.6
        case .hypothesis: return 0.3
        case .rejected: return 0.05
        }
    }

    private static func domain(for traceDomain: PTTraceDomain) -> PTProtocolEvidenceDomain? {
        switch traceDomain {
        case .xp400BLE: return .xp400BLE
        case .obd: return .obd
        case .ymobdAdapter: return .ymobdVendorExtension
        case .adapterOTA: return .ymobdFirmwareOTA
        case .vehicleTelemetry, .location, .motion, .navigation, .system: return nil
        }
    }

    private static func direction(for traceDirection: PTTraceDirection) -> PTProtocolEvidenceDirection {
        switch traceDirection {
        case .input: return .rx
        case .output: return .tx
        case .state: return .state
        case .marker: return .marker
        }
    }

    private static func payloadCommand(from payload: PTTracePayload, direction: PTTraceDirection) -> String? {
        guard case .protocolMessage(let message) = payload else { return nil }
        if direction == .output, message.command == nil {
            return message.raw
        }
        return message.command
    }

    private static func payloadResponse(from payload: PTTracePayload, direction: PTTraceDirection) -> String? {
        guard case .protocolMessage(let message) = payload else { return nil }
        return direction == .input ? message.raw : nil
    }
}

// EN: This builder keeps vehicle identity and adapter identity physically separate in the exported passport.
// ES: Este constructor mantiene separadas físicamente la identidad del vehículo y la del adaptador.
// 中文：该构建器在导出 Passport 中物理分离车辆身份和适配器身份。
@MainActor
public enum PTVehiclePassportBuilder {
    public static func build(at date: Date = Date()) -> PTVehiclePassport {
        let connectivity = PTVehicleConnectivityCoordinator.shared
        let vehicle = PTMotorcycleGarageStore.shared.currentVehicle
        let selectedVehicleID = vehicle?.id
        let linkSnapshot = connectivity.snapshot
        let telemetryBridge = PTVehicleTelemetryBridge.shared
        let obdInfo = PTMotoTelemetryManager.shared.obdInfo
        let adapter = telemetryBridge.adapterSnapshot
        let obdSource = evidenceSource(for: linkSnapshot.obd.transport, isConnected: linkSnapshot.obd.state == .connected)
        let dashboardSource = evidenceSource(for: linkSnapshot.dashboard.transport, isConnected: linkSnapshot.dashboard.state == .connected)
        let dashboardReference = connectivity.dashboardConnectionIdentity?.reportedSerialNumber
            ?? vehicle?.dashboardSerialNumber
            ?? connectivity.dashboardConnectionIdentity?.centralIdentifier.map { String($0.uuidString.suffix(8)).uppercased() }
        let ecuAddress = vehicle?.preferredDiagnosticAddress.map { "\($0.tx)->\($0.rx)" }
        let vehicleFields = PTVehicleIdentityResolver.resolve(
            PTVehicleIdentityResolutionInput(
                name: vehicle?.name,
                brand: vehicle?.brand,
                model: vehicle?.model,
                year: vehicle?.year,
                vin: vehicle?.vin,
                dashboardReference: dashboardReference,
                dashboardSource: dashboardSource,
                vehicleTimestamp: vehicle?.updatedAt ?? date,
                ecuAddress: ecuAddress,
                ecuSource: ecuAddress == nil ? .unknown : .system,
                ecuTimestamp: vehicle?.updatedAt ?? date,
                ecuCalibration: nonEmpty(obdInfo.ecuVersion),
                ecuCalibrationSource: nonEmpty(obdInfo.ecuVersion) == nil ? .unknown : obdSource,
                dashboardTimestamp: date,
                ecuComponentTimestamp: date
            )
        )

        let vendor = adapter.vendor ?? nonEmpty(obdInfo.moudleInfo.company)
        let adapterModel = adapter.model ?? nonEmpty(obdInfo.moudleInfo.deviceType) ?? nonEmpty(obdInfo.moudleInfo.deviceName)
        let firmware = adapter.firmwareVersion ?? nonEmpty(obdInfo.moudleInfo.version)
        let officialYMOBD = adapter.isOfficialYMOBD || vendor?.localizedCaseInsensitiveContains("YMOBD") == true
        let adapterSource = adapter.vendor != nil || adapter.model != nil || adapter.firmwareVersion != nil
            ? (adapter.transport == .mock ? .mock : .live)
            : obdSource
        let transport = adapter.transport == .unknown ? linkSnapshot.obd.transport?.rawValue : adapter.transport.rawValue
        let capabilityCount = PTMotoTelemetryManager.shared.obdInfo.supportCommand.count
        let otaSupported = officialYMOBD && (adapter.isOfficialYMOBD || adapter.mode != .disconnected)
        let adapterIdentifier = nonEmpty(obdInfo.moudleInfo.deviceMac)
        let adapterFields = PTDiagnosticAdapterIdentityResolver.resolve(
            PTDiagnosticAdapterIdentityResolutionInput(
                vendor: vendor,
                model: adapterModel,
                firmware: firmware,
                transport: transport,
                supportedCommandCount: capabilityCount,
                isOfficialYMOBD: officialYMOBD,
                identifier: adapterIdentifier,
                source: adapterSource,
                timestamp: date,
                otaSupported: otaSupported
            )
        )

        return PTVehiclePassport(
            vehicleID: selectedVehicleID,
            vehicleFields: vehicleFields,
            adapterFields: adapterFields
        )
    }

    private static func evidenceSource(for transport: PTVehicleTransport?, isConnected: Bool) -> PTProtocolEvidenceSource {
        guard isConnected else { return .unknown }
        switch transport {
        case .dashboardMock, .obdMock: return .mock
        case .dashboardBluetooth, .obdBluetooth, .obdWiFi: return .live
        case nil: return .unknown
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : String(normalized.prefix(256))
    }

}

// EN: The store is bounded and additive; it never forwards migrated data to CoreBluetooth or an OBD transport.
// ES: El almacén está limitado y es aditivo; nunca reenvía datos migrados a CoreBluetooth ni al transporte OBD.
// 中文：证据库有界且只追加，绝不会把迁移数据转发给 CoreBluetooth 或 OBD 传输层。
@MainActor
public final class PTProtocolEvidenceV2Store {
    public static let shared = PTProtocolEvidenceV2Store()
    public static let storageKey = PTProtocolEvidenceStorageKeys.legacyState
    public static let maximumRecordCount = 2_000
    public static let maximumCandidateCount = 500
    public static let maximumCorrelationCount = 50

    public private(set) var records: [PTProtocolEvidenceRecord]
    public private(set) var canCandidates: [PTProtocolCANBitCandidate]
    public private(set) var databaseStatus: PTProtocolEvidenceDatabaseStatus
    private let defaults: UserDefaults
    private let repository: PTProtocolEvidenceRepository?
    private var isRefreshing = false

    public init(defaults: UserDefaults = .standard, databaseURL: URL? = nil) {
        self.defaults = defaults
        let legacyState = defaults.data(forKey: Self.storageKey).flatMap { try? PTProtocolEvidenceV2StateCodec.decode($0) }
        var openedRepository: PTProtocolEvidenceRepository?
        var loadedRecords: [PTProtocolEvidenceRecord] = []
        var loadedCandidates: [PTProtocolCANBitCandidate] = []
        var status = PTProtocolEvidenceDatabaseStatus(state: .unavailable, message: "数据库不可用")

        do {
            let repository = try PTProtocolEvidenceRepository(databaseURL: databaseURL ?? PTProtocolEvidenceDatabase.defaultURL)
            openedRepository = repository
            _ = try PTProtocolEvidenceMigrationCoordinator(defaults: defaults, repository: repository).migrateIfNeeded()
            loadedRecords = try repository.records(limit: Self.maximumRecordCount)
            loadedCandidates = try repository.candidates(limit: Self.maximumCandidateCount)
            status = PTProtocolEvidenceDatabaseStatus(
                state: .database,
                schemaVersion: repository.database.schemaVersion,
                migrationCompleted: defaults.bool(forKey: PTProtocolEvidenceMigrationCoordinator.completionKey)
            )
        } catch {
            defaults.set(error.localizedDescription, forKey: PTProtocolEvidenceMigrationCoordinator.failureKey)
            status = PTProtocolEvidenceDatabaseStatus(
                state: .legacyFallback,
                schemaVersion: nil,
                migrationCompleted: false,
                message: error.localizedDescription
            )
        }

        self.repository = openedRepository
        self.databaseStatus = status
        if loadedRecords.isEmpty, let legacyState {
            self.records = Array(legacyState.records.sorted { $0.timestamp > $1.timestamp }.prefix(Self.maximumRecordCount))
        } else {
            self.records = loadedRecords
        }
        if loadedCandidates.isEmpty, let legacyState {
            self.canCandidates = Array(legacyState.canCandidates.sorted { $0.timestamp > $1.timestamp }.prefix(Self.maximumCandidateCount))
        } else {
            self.canCandidates = loadedCandidates
        }
    }

    @discardableResult
    public func merge(_ newRecords: [PTProtocolEvidenceRecord]) -> Int {
        guard !newRecords.isEmpty else { return 0 }
        var inserted = 0
        for record in newRecords {
            guard !records.contains(where: { sameEvidence($0, record) }) else { continue }
            records.append(record)
            inserted += 1
        }
        guard inserted > 0 else { return 0 }
        records.sort { $0.timestamp > $1.timestamp }
        records = Array(records.prefix(Self.maximumRecordCount))
        do {
            _ = try repository?.insert(records: newRecords)
        } catch {
            databaseStatus = PTProtocolEvidenceDatabaseStatus(
                state: .legacyFallback,
                schemaVersion: repository?.database.schemaVersion,
                migrationCompleted: false,
                message: error.localizedDescription
            )
        }
        persist()
        return inserted
    }

    @discardableResult
    public func ingestCapture(
        _ session: PTCANCaptureSession,
        source: PTProtocolEvidenceSource = .live,
        vehicleID: UUID? = nil
    ) -> Int {
        let candidates = PTProtocolEvidenceV2CANDiscovery.discover(
            in: session,
            source: source,
            vehicleID: vehicleID
        )
        return mergeCANCandidates(candidates)
    }

    // EN: Candidate analysis stays pure and bounded; only the final merge touches the main-actor store.
    // ES: El análisis de candidatos es puro y acotado; solo la combinación final toca el almacén del actor principal.
    // 中文：候选分析保持纯函数且有界，只有最终合并会访问主线程证据库。
    @discardableResult
    private func mergeCANCandidates(_ candidates: [PTProtocolCANBitCandidate]) -> Int {
        guard !candidates.isEmpty else { return 0 }
        for candidate in candidates where !canCandidates.contains(where: { sameCandidate($0, candidate) }) {
            canCandidates.append(candidate)
        }
        canCandidates.sort { $0.timestamp > $1.timestamp }
        canCandidates = Array(canCandidates.prefix(Self.maximumCandidateCount))
        do {
            _ = try repository?.insert(candidates: candidates)
        } catch {
            databaseStatus = PTProtocolEvidenceDatabaseStatus(
                state: .legacyFallback,
                schemaVersion: repository?.database.schemaVersion,
                migrationCompleted: false,
                message: error.localizedDescription
            )
        }
        let count = merge(candidates.map(PTProtocolEvidenceV2CANDiscovery.evidenceRecord(from:)))
        persist()
        return count
    }

    public func records(for domain: PTProtocolEvidenceDomain) -> [PTProtocolEvidenceRecord] {
        records.filter { $0.domain == domain }
    }

    // EN: Importing existing stores is idempotent, so opening the page repeatedly cannot multiply evidence.
    // ES: La importación de almacenes existentes es idempotente y abrir la página no duplica la evidencia.
    // 中文：迁移旧存储具备幂等性，反复打开页面也不会复制证据。
    @discardableResult
    public func refresh() async -> Int {
        guard !isRefreshing else { return 0 }
        isRefreshing = true
        defer { isRefreshing = false }

        var migrated: [PTProtocolEvidenceRecord] = []
        migrated.append(contentsOf: PTXP400InstructionEvidenceStore.shared.records.map(PTProtocolEvidenceV2Migration.from))
        migrated.append(contentsOf: PTProtocolExperimentStore.shared.reports.map(PTProtocolEvidenceV2Migration.from))

        for report in PTXP400BLEEvidenceStore.shared.reports {
            for session in report.sessions {
                for frame in session.frames {
                    migrated.append(
                        PTProtocolEvidenceV2Migration.from(
                            frame.frame,
                            session: PTXP400BLEEvidenceSession(
                                id: session.id,
                                capturedAt: session.capturedAt,
                                centralUUID: session.centralUUID,
                                deviceName: session.deviceName,
                                frames: session.frames.map(\.frame),
                                conclusion: session.conclusion
                            ),
                            vehicleModel: report.vehicleModel,
                            importedAt: report.importedAt
                        )
                    )
                }
            }
        }

        let summaries = await PTProtocolDiscoveryRecorder.shared.sessionSummaries(limit: 50)
        migrated.append(contentsOf: summaries.map(PTProtocolEvidenceV2Migration.from))

        // EN: Load completed CAN history off the main actor and keep one session per file stem.
        // ES: Carga el historial CAN terminado fuera del actor principal y conserva una sesión por cada nombre base de archivo.
        // 中文：将已完成的 CAN 历史抓包移出主线程读取，并按文件主体名去重会话。
        let captureURLs = Array(
            PTCANCaptureStore.shared
                .allCaptureFiles()
                .filter { ["json", "jsonl"].contains($0.pathExtension.lowercased()) }
                .prefix(50)
        )
        let historicalCaptures = await Task.detached(priority: .utility) {
            var sessions: [PTCANCaptureSession] = []
            var stems = Set<String>()
            for url in captureURLs {
                let stem = url.deletingPathExtension().path
                guard stems.insert(stem).inserted else { continue }
                let session: PTCANCaptureSession?
                switch url.pathExtension.lowercased() {
                case "json":
                    session = try? PTCANCaptureStore.shared.loadJSON(from: url)
                case "jsonl":
                    session = try? PTCANCaptureStore.shared.loadJSONL(from: url)
                default:
                    session = nil
                }
                if let session { sessions.append(session) }
            }
            return sessions
        }.value
        let currentVehicleID = PTMotorcycleGarageStore.shared.currentVehicle?.id
        let historicalCandidates = await Task.detached(priority: .utility) {
            historicalCaptures.flatMap { capture in
                PTProtocolEvidenceV2CANDiscovery.discover(
                    in: capture,
                    source: .imported,
                    // EN: A historical capture has no immutable vehicle link; keep it unassigned.
                    // ES: Una captura histórica no tiene un vínculo inmutable con el vehículo; se mantiene sin asignar.
                    // 中文：历史抓包没有不可变车辆关联，不能猜测归属到当前车辆。
                    vehicleID: nil
                )
            }
        }.value
        _ = mergeCANCandidates(historicalCandidates)

        if let document = PTCrazyTraceRecorder.shared.lastDocument {
            migrated.append(contentsOf: document.events.compactMap(PTProtocolEvidenceV2Migration.from))
        }

        let connectivity = PTVehicleConnectivityCoordinator.shared
        let adapterSnapshot = PTVehicleTelemetryBridge.shared.adapterSnapshot
        let adapterSource: PTProtocolEvidenceSource = adapterSnapshot.mode == .disconnected ? .unknown : (adapterSnapshot.transport == .mock ? .mock : .live)
        if let adapterRecord = PTProtocolEvidenceV2Migration.adapterEvidence(
            snapshot: adapterSnapshot,
            source: adapterSource,
            vehicleID: currentVehicleID
        ) {
            migrated.append(adapterRecord)
        }

        let instruments = PTCrazyDashboardInstrumentsStore.shared.snapshot
        if let otaRecord = PTProtocolEvidenceV2Migration.otaEvidence(
            snapshot: instruments.adapterOTA,
            source: adapterSource,
            vehicleID: currentVehicleID
        ) {
            migrated.append(otaRecord)
        }

        if let capture = PTCANRecorder.shared.snapshot() {
            _ = ingestCapture(
                capture,
                source: connectivity.snapshot.obd.transport == .obdMock ? .mock : .live,
                vehicleID: currentVehicleID
            )
        }

        return merge(migrated)
    }

    public func correlation(
        window: TimeInterval = 30,
        at date: Date = Date()
    ) -> PTProtocolEvidenceCorrelationReport {
        PTProtocolEvidenceCorrelationBuilder.build(
            snapshot: PTVehicleTelemetryConsumerHub.shared.latestSnapshot,
            records: records,
            capture: PTCANRecorder.shared.snapshot(),
            vehicleID: PTMotorcycleGarageStore.shared.currentVehicle?.id,
            window: window,
            at: date
        )
    }

    public func passport(at date: Date = Date()) -> PTVehiclePassport {
        PTVehiclePassportBuilder.build(at: date)
    }

    public func exportJSONData(at date: Date = Date()) throws -> Data {
        let document = PTProtocolEvidenceV2Document(
            generatedAt: date,
            records: records,
            canCandidates: canCandidates,
            correlations: [correlation(at: date)],
            passport: passport(at: date)
        )
        return try PTProtocolEvidenceV2Exporter.jsonData(for: document)
    }

    public func exportJSONURL(at date: Date = Date()) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "crazydashboard-protocol-evidence-v2-\(Int(date.timeIntervalSince1970)).json"
        )
        try exportJSONData(at: date).write(to: url, options: .atomic)
        return url
    }

    public func exportCSVData() -> Data {
        PTProtocolEvidenceV2Exporter.csvData(for: records)
    }

    public func exportCSVURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "crazydashboard-protocol-evidence-v2-\(Int(Date().timeIntervalSince1970)).csv"
        )
        try exportCSVData().write(to: url, options: .atomic)
        return url
    }

    public var databaseURL: URL? {
        repository?.database.url
    }

    public func storageUsage() -> PTProtocolEvidenceStorageUsage {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let canCaptureDirectory = PTCANCaptureStore.shared.directoryURL
        return PTProtocolEvidenceStorageReporter.usage(
            databaseURL: repository?.database.url ?? PTProtocolEvidenceDatabase.defaultURL,
            traceDirectoryURL: documents,
            canCaptureDirectoryURL: canCaptureDirectory,
            instrumentExportDirectoryURL: nil,
            excludedDirectoryURLs: [canCaptureDirectory]
        )
    }

    @discardableResult
    public func maintainStorage(
        policy: PTProtocolEvidenceRetentionPolicy = PTProtocolEvidenceRetentionPolicy(),
        now: Date = Date()
    ) -> Int {
        guard let repository else { return 0 }
        do {
            let deleted = try PTProtocolEvidenceRetentionCoordinator(repository: repository).maintain(policy: policy, now: now)
            if deleted > 0 {
                records = (try? repository.records(limit: Self.maximumRecordCount)) ?? records
            }
            return deleted
        } catch {
            databaseStatus = PTProtocolEvidenceDatabaseStatus(
                state: .legacyFallback,
                schemaVersion: repository.database.schemaVersion,
                migrationCompleted: false,
                message: error.localizedDescription
            )
            return 0
        }
    }

    /// EN: Capture-file cleanup requires an explicit directory so a settings screen cannot delete an inferred production path.
    /// ES: La limpieza de capturas requiere un directorio explícito para que la pantalla de ajustes no borre una ruta de producción inferida.
    /// 中文：抓包文件清理必须显式传入目录，避免设置页误删猜测出的生产路径。
    public func maintainStorage(
        policy: PTProtocolEvidenceRetentionPolicy = PTProtocolEvidenceRetentionPolicy(),
        now: Date = Date(),
        captureDirectoryURL: URL
    ) -> PTProtocolEvidenceRetentionResult? {
        guard let repository else { return nil }
        do {
            let result = try PTProtocolEvidenceRetentionCoordinator(repository: repository).maintain(
                policy: policy,
                now: now,
                captureDirectoryURL: captureDirectoryURL
            )
            if result.deletedLowValueRecords > 0 {
                records = (try? repository.records(limit: Self.maximumRecordCount)) ?? records
            }
            return result
        } catch {
            databaseStatus = PTProtocolEvidenceDatabaseStatus(
                state: .legacyFallback,
                schemaVersion: repository.database.schemaVersion,
                migrationCompleted: false,
                message: error.localizedDescription
            )
            return nil
        }
    }
}

private extension PTProtocolEvidenceV2Store {
    func persist() {
        let state = PTProtocolEvidenceV2PersistedState(
            schemaVersion: PTProtocolEvidenceV2Document.currentSchemaVersion,
            records: records,
            canCandidates: canCandidates
        )
        guard let data = try? PTProtocolEvidenceV2StateCodec.encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func sameEvidence(_ lhs: PTProtocolEvidenceRecord, _ rhs: PTProtocolEvidenceRecord) -> Bool {
        if lhs.id == rhs.id { return true }
        return lhs.domain == rhs.domain
            && lhs.kind == rhs.kind
            && lhs.direction == rhs.direction
            && lhs.source == rhs.source
            && lhs.vehicleID == rhs.vehicleID
            && lhs.referenceID == rhs.referenceID
            && lhs.value == rhs.value
            && lhs.request == rhs.request
            && lhs.response == rhs.response
            && lhs.fingerprint == rhs.fingerprint
            && lhs.reference == rhs.reference
    }

    func sameCandidate(_ lhs: PTProtocolCANBitCandidate, _ rhs: PTProtocolCANBitCandidate) -> Bool {
        lhs.captureID == rhs.captureID
            && lhs.eventID == rhs.eventID
            && lhs.header == rhs.header
            && lhs.changedByteIndexes == rhs.changedByteIndexes
            && lhs.changedBits == rhs.changedBits
    }

}
