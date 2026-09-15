//
//  PTProtocolEvidenceArchitecture.swift
//  CrazyDashboard
//
//  EN: Isolates protocol evidence scoring, correlation, export, persistence codecs, and passport resolvers.
//  ES: Aísla la puntuación, correlación, exportación, codificación y resolución del pasaporte de evidencia.
//  中文：隔离协议证据评分、关联、导出、持久化编解码以及 Vehicle Passport 解析职责。
//

import Foundation

public nonisolated enum PTProtocolEvidenceConfidence {
    public static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    public static func forCANScore(_ score: Int) -> Double {
        min(0.95, max(0.1, Double(max(score, 0)) / 100))
    }
}

public nonisolated enum PTProtocolCANDiscoveryScorer {
    public static func score(_ summary: PTCANEventIDSummary) -> (score: Int, confidence: Double) {
        let score = max(summary.score, 0)
        return (score, PTProtocolEvidenceConfidence.forCANScore(score))
    }
}

// EN: The engine only reads a capture and produces research candidates; it cannot create executable commands.
// ES: El motor solo lee una captura y produce candidatos de investigación; no puede crear comandos ejecutables.
// 中文：Engine 只读取抓包并生成研究候选，不具备创建可执行指令的能力。
public nonisolated enum PTProtocolCANDiscoveryEngine {
    public static func discover(
        in session: PTCANCaptureSession,
        source: PTProtocolEvidenceSource = .live,
        vehicleID: UUID? = nil,
        before: TimeInterval = 2,
        after: TimeInterval = 2,
        maximumResults: Int = 100
    ) -> [PTProtocolCANBitCandidate] {
        guard before >= 0, after >= 0, maximumResults > 0 else { return [] }

        var candidates: [PTProtocolCANBitCandidate] = []
        for event in session.events {
            guard event.timestamp.isFinite else { continue }
            let analysis = PTCANEventAnalyzer.analyze(
                session: session,
                eventTimestamp: event.timestamp,
                before: before,
                after: after
            )
            for summary in analysis.interestingIDs {
                let scoring = PTProtocolCANDiscoveryScorer.score(summary)
                let timestamp = event.timestamp > 0
                    ? Date(timeIntervalSince1970: event.timestamp)
                    : session.startedAt
                candidates.append(
                    PTProtocolCANBitCandidate(
                        captureID: session.id,
                        eventID: event.id,
                        header: summary.header,
                        changedByteIndexes: summary.changedByteIndexes,
                        changedBits: summary.changedBits,
                        dominantBeforePayload: summary.dominantBeforePayload,
                        dominantAfterPayload: summary.dominantAfterPayload,
                        changedFrameCount: summary.changedFrameCount,
                        firstChangeRelativeTimestamp: summary.firstChangeRelativeTimestamp,
                        lastChangeRelativeTimestamp: summary.lastChangeRelativeTimestamp,
                        score: scoring.score,
                        source: source,
                        timestamp: timestamp,
                        confidence: scoring.confidence,
                        vehicleID: vehicleID
                    )
                )
            }
        }

        return Array(
            candidates
                .sorted {
                    if $0.score != $1.score { return $0.score > $1.score }
                    return $0.timestamp < $1.timestamp
                }
                .prefix(maximumResults)
        )
    }
}

public nonisolated struct PTProtocolCANExperimentMarker: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let timestamp: Date
    public let metadata: [String: String]

    public init(id: UUID = UUID(), name: String, timestamp: Date = Date(), metadata: [String: String] = [:]) {
        self.id = id
        self.name = String(name.prefix(160))
        self.timestamp = timestamp
        self.metadata = metadata.prefix(32).reduce(into: [:]) { result, item in
            result[String(item.key.prefix(80))] = String(item.value.prefix(256))
        }
    }
}

public nonisolated enum PTProtocolEvidenceCorrelationBuilder {
    public static func build(
        snapshot: PTUnifiedVehicleTelemetrySnapshot,
        records: [PTProtocolEvidenceRecord],
        capture: PTCANCaptureSession?,
        vehicleID: UUID?,
        window: TimeInterval = 30,
        at date: Date = Date()
    ) -> PTProtocolEvidenceCorrelationReport {
        let safeWindow = max(window, 1)
        let start = date.addingTimeInterval(-safeWindow)
        var entries: [PTProtocolEvidenceCorrelationEntry] = []

        for value in snapshot.values where value.capturedAt >= start && value.capturedAt <= date {
            let source: PTProtocolEvidenceCorrelationSource
            let domain: PTProtocolEvidenceDomain?
            switch value.source.domain {
            case .xp400BLE:
                source = .xp400BLETelemetry
                domain = .xp400BLE
            case .obd:
                source = .obdTelemetry
                domain = .obd
            case .gps:
                source = .gps
                domain = nil
            case .motion:
                source = .motion
                domain = nil
            case .calculated, .replay, .unknown:
                continue
            }
            entries.append(
                PTProtocolEvidenceCorrelationEntry(
                    source: source,
                    domain: domain,
                    timestamp: value.capturedAt,
                    confidence: value.confidence,
                    summary: "\(value.signal.rawValue)=\(describe(value.value))"
                )
            )
        }

        for record in records where record.timestamp >= start && record.timestamp <= date {
            guard record.domain != .ymobdFirmwareOTA else { continue }
            let source: PTProtocolEvidenceCorrelationSource?
            switch record.domain {
            case .xp400BLE: source = .xp400BLETelemetry
            case .obd, .uds: source = .obdTelemetry
            case .can: source = .can
            case .ymobdVendorExtension, .ymobdFirmwareOTA, .firmwareResearch: source = nil
            }
            guard let source else { continue }
            entries.append(
                PTProtocolEvidenceCorrelationEntry(
                    source: source,
                    domain: record.domain,
                    timestamp: record.timestamp,
                    confidence: record.confidence,
                    summary: record.value,
                    evidenceID: record.id
                )
            )
        }

        if let capture {
            for marker in capture.events {
                let timestamp = marker.timestamp > 0
                    ? Date(timeIntervalSince1970: marker.timestamp)
                    : capture.startedAt
                guard timestamp >= start && timestamp <= date else { continue }
                entries.append(
                    PTProtocolEvidenceCorrelationEntry(
                        source: .userMarker,
                        domain: .can,
                        timestamp: timestamp,
                        confidence: 1,
                        summary: marker.name
                    )
                )
            }
        }

        return PTProtocolEvidenceCorrelationReport(
            vehicleID: vehicleID,
            startedAt: start,
            endedAt: date,
            entries: Array(entries.sorted { $0.timestamp < $1.timestamp }.suffix(250))
        )
    }

    private static func describe(_ value: PTVehicleTelemetryValue) -> String {
        switch value {
        case .double(let value): return String(format: "%.2f", value)
        case .integer(let value): return String(value)
        case .boolean(let value): return value ? "true" : "false"
        case .location(let latitude, let longitude, _): return String(format: "%.5f,%.5f", latitude, longitude)
        }
    }
}

public nonisolated enum PTProtocolEvidenceV2Exporter {
    public static func jsonData(
        for document: PTProtocolEvidenceV2Document,
        privacyLevel: String = "redacted"
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let exportDocument = privacyLevel.caseInsensitiveCompare("redacted") == .orderedSame
            ? redacted(document)
            : document
        return try encoder.encode(exportDocument)
    }

    public static func csvData(
        for records: [PTProtocolEvidenceRecord],
        privacyLevel: String = "redacted"
    ) -> Data {
        let exportRecords = privacyLevel.caseInsensitiveCompare("redacted") == .orderedSame
            ? records.map(redacted)
            : records
        var rows = ["id,domain,kind,direction,source,timestamp,confidence,value,fingerprint,vehicleID,referenceID,reference,note"]
        let formatter = ISO8601DateFormatter()
        rows.append(contentsOf: exportRecords.map { record in
            [
                record.id.uuidString,
                record.domain.rawValue,
                record.kind.rawValue,
                record.direction.rawValue,
                record.source.rawValue,
                formatter.string(from: record.timestamp),
                String(format: "%.3f", record.confidence),
                record.value,
                record.fingerprint ?? "",
                record.vehicleID?.uuidString ?? "",
                record.referenceID?.uuidString ?? "",
                record.reference ?? "",
                record.note ?? ""
            ].map(csvField).joined(separator: ",")
        })
        return Data(rows.joined(separator: "\n").utf8)
    }

    private static func redacted(_ document: PTProtocolEvidenceV2Document) -> PTProtocolEvidenceV2Document {
        PTProtocolEvidenceV2Document(
            schemaVersion: document.schemaVersion,
            generatedAt: document.generatedAt,
            records: document.records.map(redacted),
            canCandidates: document.canCandidates.map(redacted),
            correlations: document.correlations.map(redacted),
            passport: redacted(document.passport),
            captureTemplates: document.captureTemplates
        )
    }

    private static func redacted(_ record: PTProtocolEvidenceRecord) -> PTProtocolEvidenceRecord {
        PTProtocolEvidenceRecord(
            id: record.id,
            domain: record.domain,
            kind: record.kind,
            direction: record.direction,
            source: record.source,
            timestamp: record.timestamp,
            confidence: record.confidence,
            value: PTBuild65PrivacyPolicy.redactExportText(record.value),
            request: record.request.map(PTBuild65PrivacyPolicy.redactExportText),
            response: record.response.map(PTBuild65PrivacyPolicy.redactExportText),
            fingerprint: record.fingerprint.map(PTBuild65PrivacyPolicy.redactExportText),
            vehicleID: nil,
            referenceID: record.referenceID,
            reference: record.reference.map(PTBuild65PrivacyPolicy.redactExportText),
            note: record.note.map(PTBuild65PrivacyPolicy.redactExportText)
        )
    }

    private static func redacted(_ candidate: PTProtocolCANBitCandidate) -> PTProtocolCANBitCandidate {
        PTProtocolCANBitCandidate(
            id: candidate.id,
            captureID: candidate.captureID,
            eventID: candidate.eventID,
            header: candidate.header,
            changedByteIndexes: candidate.changedByteIndexes,
            changedBits: candidate.changedBits,
            dominantBeforePayload: candidate.dominantBeforePayload.map(PTBuild65PrivacyPolicy.redactExportText),
            dominantAfterPayload: candidate.dominantAfterPayload.map(PTBuild65PrivacyPolicy.redactExportText),
            changedFrameCount: candidate.changedFrameCount,
            firstChangeRelativeTimestamp: candidate.firstChangeRelativeTimestamp,
            lastChangeRelativeTimestamp: candidate.lastChangeRelativeTimestamp,
            score: candidate.score,
            source: candidate.source,
            timestamp: candidate.timestamp,
            confidence: candidate.confidence,
            vehicleID: nil,
            note: PTBuild65PrivacyPolicy.redactExportText(candidate.note)
        )
    }

    private static func redacted(_ report: PTProtocolEvidenceCorrelationReport) -> PTProtocolEvidenceCorrelationReport {
        PTProtocolEvidenceCorrelationReport(
            id: report.id,
            vehicleID: nil,
            startedAt: report.startedAt,
            endedAt: report.endedAt,
            entries: report.entries.map { entry in
                PTProtocolEvidenceCorrelationEntry(
                    id: entry.id,
                    source: entry.source,
                    domain: entry.domain,
                    timestamp: entry.timestamp,
                    confidence: entry.confidence,
                    summary: PTBuild65PrivacyPolicy.redactExportText(entry.summary),
                    evidenceID: entry.evidenceID
                )
            },
            excludedDomains: report.excludedDomains
        )
    }

    private static func redacted(_ passport: PTVehiclePassport) -> PTVehiclePassport {
        func redactField(_ field: PTVehiclePassportField) -> PTVehiclePassportField {
            let value = PTBuild65PrivacyPolicy.isSensitiveKey(field.key)
                ? nil
                : field.value.map(PTBuild65PrivacyPolicy.redactExportText)
            return PTVehiclePassportField(
                key: field.key,
                value: value,
                source: field.source,
                timestamp: field.timestamp,
                confidence: field.confidence,
                evidenceIDs: field.evidenceIDs
            )
        }

        return PTVehiclePassport(
            schemaVersion: passport.schemaVersion,
            generatedAt: passport.generatedAt,
            vehicleID: nil,
            vehicleFields: passport.vehicleFields.map(redactField),
            adapterFields: passport.adapterFields.map(redactField)
        )
    }

    private static func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

public nonisolated struct PTProtocolEvidenceV2PersistedState: Codable, Sendable {
    public let schemaVersion: Int
    public let records: [PTProtocolEvidenceRecord]
    public let canCandidates: [PTProtocolCANBitCandidate]

    public init(
        schemaVersion: Int,
        records: [PTProtocolEvidenceRecord],
        canCandidates: [PTProtocolCANBitCandidate]
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
        self.canCandidates = canCandidates
    }
}

public nonisolated enum PTProtocolEvidenceV2StateCodec {
    public static func decode(_ data: Data) throws -> PTProtocolEvidenceV2PersistedState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PTProtocolEvidenceV2PersistedState.self, from: data)
    }

    public static func encode(_ state: PTProtocolEvidenceV2PersistedState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(state)
    }
}

public nonisolated struct PTVehicleIdentityResolutionInput: Sendable {
    public let name: String?
    public let brand: String?
    public let model: String?
    public let year: Int?
    public let vin: String?
    public let dashboardReference: String?
    public let dashboardSource: PTProtocolEvidenceSource
    public let vehicleTimestamp: Date
    public let ecuAddress: String?
    public let ecuSource: PTProtocolEvidenceSource
    public let ecuTimestamp: Date
    public let ecuCalibration: String?
    public let ecuCalibrationSource: PTProtocolEvidenceSource
    public let dashboardTimestamp: Date?
    public let ecuComponentTimestamp: Date?

    public init(
        name: String?,
        brand: String?,
        model: String?,
        year: Int?,
        vin: String?,
        dashboardReference: String?,
        dashboardSource: PTProtocolEvidenceSource,
        vehicleTimestamp: Date,
        ecuAddress: String?,
        ecuSource: PTProtocolEvidenceSource,
        ecuTimestamp: Date,
        ecuCalibration: String?,
        ecuCalibrationSource: PTProtocolEvidenceSource,
        dashboardTimestamp: Date? = nil,
        ecuComponentTimestamp: Date? = nil
    ) {
        self.name = name
        self.brand = brand
        self.model = model
        self.year = year
        self.vin = vin
        self.dashboardReference = dashboardReference
        self.dashboardSource = dashboardSource
        self.vehicleTimestamp = vehicleTimestamp
        self.ecuAddress = ecuAddress
        self.ecuSource = ecuSource
        self.ecuTimestamp = ecuTimestamp
        self.ecuCalibration = ecuCalibration
        self.ecuCalibrationSource = ecuCalibrationSource
        self.dashboardTimestamp = dashboardTimestamp
        self.ecuComponentTimestamp = ecuComponentTimestamp
    }
}

public nonisolated enum PTVehicleIdentityResolver {
    public static func resolve(_ input: PTVehicleIdentityResolutionInput) -> [PTVehiclePassportField] {
        var fields: [PTVehiclePassportField] = []
        fields.append(field("vehicle.name", input.name, source: .system, timestamp: input.vehicleTimestamp, confidence: input.name == nil ? 0 : 0.8))
        fields.append(field("vehicle.brand", input.brand, source: .system, timestamp: input.vehicleTimestamp, confidence: input.brand == nil ? 0 : 0.8))
        fields.append(field("vehicle.model", input.model, source: .system, timestamp: input.vehicleTimestamp, confidence: input.model == nil ? 0 : 0.8))
        fields.append(field("vehicle.year", input.year.map(String.init), source: .system, timestamp: input.vehicleTimestamp, confidence: input.year == nil ? 0 : 0.8))
        let vin = nonEmpty(input.vin)
        fields.append(field("vehicle.vin", redactedVIN(vin), source: .system, timestamp: input.vehicleTimestamp, confidence: vin == nil ? 0 : 0.85))

        let dashboardTimestamp = input.dashboardTimestamp ?? input.vehicleTimestamp
        let dashboardReference = redactedIdentifier(input.dashboardReference)
        fields.append(
            field(
                "dashboard.reference",
                dashboardReference,
                source: dashboardReference == nil ? .unknown : input.dashboardSource,
                timestamp: dashboardTimestamp,
                confidence: dashboardReference == nil ? 0 : (input.dashboardSource == .live ? 1 : 0.6)
            )
        )
        for key in [
            "dashboard.hardware", "dashboard.software", "dashboard.boot",
            "connectivityBox.hardware", "connectivityBox.software", "connectivityBox.boot", "connectivityBox.reference"
        ] {
            fields.append(field(key, nil, source: .unknown, timestamp: dashboardTimestamp, confidence: 0))
        }

        let ecuComponentTimestamp = input.ecuComponentTimestamp ?? input.ecuTimestamp
        let ecuAddress = nonEmpty(input.ecuAddress)
        fields.append(field("ecu.address", ecuAddress, source: ecuAddress == nil ? .unknown : input.ecuSource, timestamp: input.ecuTimestamp, confidence: ecuAddress == nil ? 0 : 0.8))
        fields.append(field("ecu.hardware", nil, source: .unknown, timestamp: ecuComponentTimestamp, confidence: 0))
        fields.append(field("ecu.software", nil, source: .unknown, timestamp: ecuComponentTimestamp, confidence: 0))
        let calibration = nonEmpty(input.ecuCalibration)
        fields.append(
            field(
                "ecu.calibration",
                calibration,
                source: calibration == nil ? .unknown : input.ecuCalibrationSource,
                timestamp: ecuComponentTimestamp,
                confidence: calibration == nil ? 0 : (input.ecuCalibrationSource == .live ? 0.9 : 0.6)
            )
        )
        return fields
    }

    private static func field(_ key: String, _ value: String?, source: PTProtocolEvidenceSource, timestamp: Date, confidence: Double) -> PTVehiclePassportField {
        PTVehiclePassportField(key: key, value: value, source: source, timestamp: timestamp, confidence: confidence)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : String(normalized.prefix(256))
    }

    private static func redactedVIN(_ value: String?) -> String? {
        guard let value = nonEmpty(value) else { return nil }
        guard value.count > 6 else { return "***" }
        return "\(value.prefix(3))***\(value.suffix(3))"
    }

    private static func redactedIdentifier(_ value: String?) -> String? {
        guard let value = nonEmpty(value) else { return nil }
        return String(value.suffix(8)).uppercased()
    }
}

public nonisolated struct PTDiagnosticAdapterIdentityResolutionInput: Sendable {
    public let vendor: String?
    public let model: String?
    public let firmware: String?
    public let transport: String?
    public let supportedCommandCount: Int
    public let isOfficialYMOBD: Bool
    public let identifier: String?
    public let source: PTProtocolEvidenceSource
    public let timestamp: Date
    public let otaSupported: Bool

    public init(
        vendor: String?,
        model: String?,
        firmware: String?,
        transport: String?,
        supportedCommandCount: Int,
        isOfficialYMOBD: Bool,
        identifier: String?,
        source: PTProtocolEvidenceSource,
        timestamp: Date,
        otaSupported: Bool
    ) {
        self.vendor = vendor
        self.model = model
        self.firmware = firmware
        self.transport = transport
        self.supportedCommandCount = supportedCommandCount
        self.isOfficialYMOBD = isOfficialYMOBD
        self.identifier = identifier
        self.source = source
        self.timestamp = timestamp
        self.otaSupported = otaSupported
    }
}

public nonisolated enum PTDiagnosticAdapterIdentityResolver {
    public static func resolve(_ input: PTDiagnosticAdapterIdentityResolutionInput) -> [PTVehiclePassportField] {
        let vendor = nonEmpty(input.vendor)
        let model = nonEmpty(input.model)
        let firmware = nonEmpty(input.firmware)
        let transport = nonEmpty(input.transport)
        let identifier = nonEmpty(input.identifier)
        let source = input.source
        var fields: [PTVehiclePassportField] = []
        fields.append(field("adapter.vendor", vendor, source: vendor == nil ? .unknown : source, timestamp: input.timestamp, confidence: vendor == nil ? 0 : (input.isOfficialYMOBD ? 1 : 0.7)))
        fields.append(field("adapter.model", model, source: model == nil ? .unknown : source, timestamp: input.timestamp, confidence: model == nil ? 0 : 0.85))
        fields.append(field("adapter.firmware", firmware, source: firmware == nil ? .unknown : source, timestamp: input.timestamp, confidence: firmware == nil ? 0 : 0.9))
        fields.append(field("adapter.transport", transport, source: transport == nil ? .unknown : source, timestamp: input.timestamp, confidence: transport == nil ? 0 : 0.8))
        fields.append(field("adapter.elmCapabilities", input.supportedCommandCount > 0 ? "supportedCommands=\(input.supportedCommandCount)" : nil, source: input.supportedCommandCount > 0 ? source : .unknown, timestamp: input.timestamp, confidence: input.supportedCommandCount > 0 ? 0.85 : 0))
        fields.append(field("adapter.vendorExtension", input.isOfficialYMOBD ? "YMOBD / AT+VERSION" : nil, source: input.isOfficialYMOBD ? source : .unknown, timestamp: input.timestamp, confidence: input.isOfficialYMOBD ? 0.95 : 0))
        fields.append(field("adapter.otaCapability", input.otaSupported ? "Jieli OTA supported (adapter only)" : nil, source: input.otaSupported ? source : .unknown, timestamp: input.timestamp, confidence: input.otaSupported ? 0.9 : 0))
        fields.append(field("adapter.identifierSuffix", redactedIdentifier(identifier), source: identifier == nil ? .unknown : source, timestamp: input.timestamp, confidence: identifier == nil ? 0 : 0.8))
        return fields
    }

    private static func field(_ key: String, _ value: String?, source: PTProtocolEvidenceSource, timestamp: Date, confidence: Double) -> PTVehiclePassportField {
        PTVehiclePassportField(key: key, value: value, source: source, timestamp: timestamp, confidence: confidence)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : String(normalized.prefix(256))
    }

    private static func redactedIdentifier(_ value: String?) -> String? {
        guard let value = nonEmpty(value) else { return nil }
        return String(value.suffix(8)).uppercased()
    }
}
