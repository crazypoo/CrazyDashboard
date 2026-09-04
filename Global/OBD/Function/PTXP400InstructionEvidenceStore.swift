//
//  PTXP400InstructionEvidenceStore.swift
//  CrazyDashboard
//
//  EN: Stores observed read-only XP400 responses without promoting them to commands.
//  ES: Guarda respuestas observadas de solo lectura del XP400 sin convertirlas en comandos.
//  中文：保存已观察到的 XP400 只读响应，但不会把它们升级成可执行指令。
//

import Foundation
import UIKit
import UniformTypeIdentifiers
import PooTools
import SnapKit
import SafeSFSymbols

public struct PTXP400EvidenceRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let vehicleID: UUID?
    public let vehicleName: String
    public let vehicleModel: String
    public let vin: String
    public let address: PTOBDDiagnosticAddress
    public let did: String
    public let requestHex: String
    public let rawResponse: String
    public let payloadHex: String?
    public let decodedText: String?
    public let status: PTOBDReadStatus
    public let negativeResponseCode: String?
    public let capturedAt: Date
    public let evidenceLevel: PTXP400InstructionEvidenceLevel
    public let source: String

    public init(
        id: UUID = UUID(),
        vehicleID: UUID? = nil,
        vehicleName: String = "",
        vehicleModel: String = "",
        vin: String = "",
        address: PTOBDDiagnosticAddress,
        did: String,
        requestHex: String? = nil,
        rawResponse: String,
        payloadHex: String? = nil,
        decodedText: String? = nil,
        status: PTOBDReadStatus,
        negativeResponseCode: String? = nil,
        capturedAt: Date = Date(),
        evidenceLevel: PTXP400InstructionEvidenceLevel = .observed,
        source: String = "live-read"
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.vehicleName = vehicleName
        self.vehicleModel = vehicleModel
        self.vin = vin
        self.address = address
        self.did = did.uppercased()
        self.requestHex = requestHex ?? "22\(did.uppercased())"
        self.rawResponse = rawResponse
        self.payloadHex = payloadHex
        self.decodedText = decodedText
        self.status = status
        self.negativeResponseCode = negativeResponseCode
        self.capturedAt = capturedAt
        self.evidenceLevel = evidenceLevel
        self.source = source
    }

    @MainActor
    public init(result: PTOBDIDReadResult, source: String = "live-read", capturedAt: Date = Date()) {
        let vehicle = PTMotorcycleGarageStore.shared.currentVehicle
        self.init(
            vehicleID: vehicle?.id,
            vehicleName: vehicle?.name ?? "",
            vehicleModel: vehicle?.model ?? "",
            vin: vehicle?.vin ?? "",
            address: result.address,
            did: result.did,
            rawResponse: result.rawResponse,
            payloadHex: result.payloadHex,
            decodedText: result.decodedText,
            status: result.status,
            negativeResponseCode: result.negativeResponseCode,
            capturedAt: capturedAt,
            evidenceLevel: .observed,
            source: source
        )
    }
}

// EN: Evidence is a bounded observation log; only the static catalog controls ordinary UI execution.
// ES: La evidencia es un registro acotado de observaciones; solo el catálogo estático controla la ejecución normal.
// 中文：证据只是有界观察日志，普通 UI 的执行权限仍只由静态目录控制。
@MainActor
public final class PTXP400InstructionEvidenceStore {
    public static let shared = PTXP400InstructionEvidenceStore()
    public static let storageKey = "PTXP400InstructionEvidence.v1"
    public static let maximumRecordCount = 500

    private let userDefaults: UserDefaults
    public private(set) var records: [PTXP400EvidenceRecord]

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let decoded = userDefaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([PTXP400EvidenceRecord].self, from: $0) }
            ?? []
        self.records = Array(decoded.sorted { $0.capturedAt > $1.capturedAt }.prefix(Self.maximumRecordCount))
        persist()
    }

    @discardableResult
    public func record(
        result: PTOBDIDReadResult,
        source: String = "live-read",
        capturedAt: Date = Date()
    ) -> Bool {
        let record = PTXP400EvidenceRecord(result: result, source: source, capturedAt: capturedAt)
        return insert(record, deduplicateWithin: 3)
    }

    @discardableResult
    public func record(
        results: [PTOBDIDReadResult],
        source: String = "live-read",
        capturedAt: Date = Date()
    ) -> Int {
        results.reduce(into: 0) { count, result in
            if record(result: result, source: source, capturedAt: capturedAt) {
                count += 1
            }
        }
    }

    @discardableResult
    public func remove(id: UUID) -> Bool {
        let originalCount = records.count
        records.removeAll { $0.id == id }
        guard records.count != originalCount else { return false }
        persist()
        return true
    }

    public func clear() {
        records.removeAll(keepingCapacity: true)
        persist()
    }

    public func exportJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(records.map(ExportRecord.init))
    }

    public func exportCSVData() -> Data {
        var rows = [
            "id,vehicleName,vehicleModel,vin,addressTx,addressRx,did,requestHex,rawResponse,payloadHex,decodedText,status,negativeResponseCode,capturedAt,evidenceLevel,source"
        ]
        rows.append(contentsOf: records.map { record in
            [
                record.id.uuidString,
                record.vehicleName,
                record.vehicleModel,
                Self.redactVIN(record.vin),
                record.address.tx,
                record.address.rx,
                record.did,
                record.requestHex,
                Self.redactResponse(record.rawResponse, did: record.did),
                record.payloadHex ?? "",
                Self.redactVIN(record.decodedText ?? ""),
                record.status.rawValue,
                record.negativeResponseCode ?? "",
                ISO8601DateFormatter().string(from: record.capturedAt),
                record.evidenceLevel.rawValue,
                record.source
            ].map(Self.csvField).joined(separator: ",")
        })
        return Data(rows.joined(separator: "\n").utf8)
    }

    public func exportURL(format: PTRideSafetyExportFormat) throws -> URL {
        let fileName = "xp400-evidence-\(Int(Date().timeIntervalSince1970)).\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let data = format == .json ? try exportJSONData() : exportCSVData()
        try data.write(to: url, options: .atomic)
        return url
    }
}

private extension PTXP400InstructionEvidenceStore {
    struct ExportRecord: Codable {
        let id: UUID
        let vehicleName: String
        let vehicleModel: String
        let vin: String
        let addressTx: String
        let addressRx: String
        let did: String
        let requestHex: String
        let rawResponse: String
        let payloadHex: String?
        let decodedText: String?
        let status: PTOBDReadStatus
        let negativeResponseCode: String?
        let capturedAt: Date
        let evidenceLevel: PTXP400InstructionEvidenceLevel
        let source: String

        @MainActor
        init(_ record: PTXP400EvidenceRecord) {
            self.id = record.id
            self.vehicleName = record.vehicleName
            self.vehicleModel = record.vehicleModel
            self.vin = PTXP400InstructionEvidenceStore.redactVIN(record.vin)
            self.addressTx = record.address.tx
            self.addressRx = record.address.rx
            self.did = record.did
            self.requestHex = record.requestHex
            self.rawResponse = PTXP400InstructionEvidenceStore.redactResponse(record.rawResponse, did: record.did)
            self.payloadHex = record.payloadHex
            self.decodedText = PTXP400InstructionEvidenceStore.redactVIN(record.decodedText ?? "")
            self.status = record.status
            self.negativeResponseCode = record.negativeResponseCode
            self.capturedAt = record.capturedAt
            self.evidenceLevel = record.evidenceLevel
            self.source = record.source
        }
    }

    func insert(_ record: PTXP400EvidenceRecord, deduplicateWithin interval: TimeInterval) -> Bool {
        guard !records.contains(where: {
            $0.address == record.address &&
            $0.did == record.did &&
            $0.rawResponse == record.rawResponse &&
            abs($0.capturedAt.timeIntervalSince(record.capturedAt)) <= interval
        }) else {
            return false
        }
        records.insert(record, at: 0)
        records = Array(records.prefix(Self.maximumRecordCount))
        persist()
        return true
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    static func redactVIN(_ value: String) -> String {
        guard value.count > 6 else { return value.isEmpty ? "" : "***" }
        return "\(value.prefix(3))***\(value.suffix(3))"
    }

    static func redactResponse(_ value: String, did: String) -> String {
        guard did.uppercased() == "F190" else { return value }
        let clean = value.uppercased().filter { "0123456789ABCDEF".contains($0) }
        guard clean.count > 8 else { return value }
        return "\(clean.prefix(8))" + String(repeating: "X", count: min(clean.count - 8, 32))
    }

    static func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

// MARK: - BLE Evidence Import

// EN: Import types are intentionally separate from executable BLE commands and are read-only developer evidence.
// ES: Los tipos importados están separados deliberadamente de los comandos BLE ejecutables y son evidencia de solo lectura.
// 中文：导入类型刻意与可执行 BLE 指令分离，只作为开发者只读证据。
public enum PTXP400BLEEvidenceDirection: String, Codable, Sendable {
    case tx
    case rx
    case unknown
}

public enum PTXP400BLEEvidenceClassification: String, Codable, Sendable {
    case knownOutboundEnvelope
    case knownAuthenticationKey
    case knownAuthenticationChallenge
    case knownConnectionFrame
    case knownVehicleStatusFrame
    case unknownValidHex
    case invalidHex
}

public struct PTXP400BLEEvidenceFrame: Codable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: TimeInterval
    public let direction: PTXP400BLEEvidenceDirection
    public let characteristicUUID: String?
    public let rawHex: String
    public let note: String?

    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        direction: PTXP400BLEEvidenceDirection,
        characteristicUUID: String? = nil,
        rawHex: String,
        note: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.direction = direction
        self.characteristicUUID = characteristicUUID
        self.rawHex = Self.normalizedHex(rawHex)
        self.note = note
    }

    private static func normalizedHex(_ value: String) -> String {
        value.filter { $0.isHexDigit }.uppercased()
    }
}

public struct PTXP400BLEEvidenceSession: Codable, Equatable, Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let centralUUID: String?
    public let deviceName: String?
    public let frames: [PTXP400BLEEvidenceFrame]
    public let conclusion: String?

    public init(
        id: UUID = UUID(),
        capturedAt: Date,
        centralUUID: String? = nil,
        deviceName: String? = nil,
        frames: [PTXP400BLEEvidenceFrame],
        conclusion: String? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.centralUUID = centralUUID
        self.deviceName = deviceName
        self.frames = frames
        self.conclusion = conclusion
    }
}

public struct PTXP400BLEEvidenceDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let vehicleModel: String
    public let firmwareVersion: String?
    public let sessions: [PTXP400BLEEvidenceSession]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        vehicleModel: String,
        firmwareVersion: String? = nil,
        sessions: [PTXP400BLEEvidenceSession]
    ) {
        self.schemaVersion = schemaVersion
        self.vehicleModel = vehicleModel
        self.firmwareVersion = firmwareVersion
        self.sessions = sessions
    }
}

public struct PTXP400BLEEvidenceFrameResult: Codable, Equatable, Sendable {
    public let frame: PTXP400BLEEvidenceFrame
    public let classification: PTXP400BLEEvidenceClassification
    public let validationMessage: String?

    public init(
        frame: PTXP400BLEEvidenceFrame,
        classification: PTXP400BLEEvidenceClassification,
        validationMessage: String? = nil
    ) {
        self.frame = frame
        self.classification = classification
        self.validationMessage = validationMessage
    }
}

public struct PTXP400BLEEvidenceSessionReport: Codable, Equatable, Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let centralUUID: String?
    public let deviceName: String?
    public let conclusion: String?
    public let frames: [PTXP400BLEEvidenceFrameResult]

    public init(
        id: UUID,
        capturedAt: Date,
        centralUUID: String?,
        deviceName: String?,
        conclusion: String?,
        frames: [PTXP400BLEEvidenceFrameResult]
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.centralUUID = centralUUID
        self.deviceName = deviceName
        self.conclusion = conclusion
        self.frames = frames
    }
}

public struct PTXP400BLEEvidenceImportReport: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let schemaVersion: Int
    public let sourceFileName: String
    public let vehicleModel: String
    public let firmwareVersion: String?
    public let importedAt: Date
    public let sessions: [PTXP400BLEEvidenceSessionReport]

    public var frameCount: Int {
        sessions.reduce(0) { $0 + $1.frames.count }
    }

    public var invalidFrameCount: Int {
        sessions.reduce(0) { total, session in
            total + session.frames.count(where: { $0.classification == .invalidHex })
        }
    }

    public init(
        id: UUID = UUID(),
        schemaVersion: Int,
        sourceFileName: String,
        vehicleModel: String,
        firmwareVersion: String?,
        importedAt: Date = Date(),
        sessions: [PTXP400BLEEvidenceSessionReport]
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.sourceFileName = sourceFileName
        self.vehicleModel = vehicleModel
        self.firmwareVersion = firmwareVersion
        self.importedAt = importedAt
        self.sessions = sessions
    }
}

public enum PTXP400BLEEvidenceImportError: Error, LocalizedError, Sendable {
    case invalidEncoding
    case unsupportedSchema
    case emptyVehicleModel
    case invalidSession
    case invalidIdentity
    case invalidFrame
    case oversizedInput
    case invalidCSVHeader

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "BLE 证据编码无效 / La codificación de la evidencia BLE no es válida."
        case .unsupportedSchema:
            return "BLE 证据版本不支持 / La versión de evidencia BLE no es compatible."
        case .emptyVehicleModel:
            return "缺少车型信息 / Falta el modelo del vehículo."
        case .invalidSession:
            return "BLE 验证会话无效 / La sesión de validación BLE no es válida."
        case .invalidIdentity:
            return "设备身份字段无效 / El campo de identidad del dispositivo no es válido."
        case .invalidFrame:
            return "BLE 原始帧无效 / La trama BLE sin procesar no es válida."
        case .oversizedInput:
            return "BLE 证据文件超过大小限制 / El archivo de evidencia BLE supera el límite de tamaño."
        case .invalidCSVHeader:
            return "BLE CSV 表头不匹配 / La cabecera CSV de BLE no coincide."
        }
    }
}

// EN: This store validates and classifies imported traces but never forwards them to CoreBluetooth.
// ES: Este almacén valida y clasifica trazas importadas, pero nunca las envía a CoreBluetooth.
// 中文：该存储负责校验和分类导入的抓包，但绝不把它们转发到 CoreBluetooth。
@MainActor
public final class PTXP400BLEEvidenceStore {
    public static let shared = PTXP400BLEEvidenceStore()
    public static let storageKey = "PTXP400BLEEvidenceReports.v1"
    public static let maximumReportCount = 50
    public static let maximumInputBytes = 10 * 1024 * 1024
    public static let maximumSessionCount = 100
    public static let maximumFrameCount = 50_000

    public private(set) var reports: [PTXP400BLEEvidenceImportReport]
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        reports = userDefaults.data(forKey: Self.storageKey)
            .flatMap { try? decoder.decode([PTXP400BLEEvidenceImportReport].self, from: $0) }
            .map { Array($0.prefix(Self.maximumReportCount)) }
            ?? []
    }

    @discardableResult
    public func importEvidence(
        data: Data,
        fileName: String
    ) throws -> PTXP400BLEEvidenceImportReport {
        guard data.count <= Self.maximumInputBytes else {
            throw PTXP400BLEEvidenceImportError.oversizedInput
        }
        let document: PTXP400BLEEvidenceDocument
        if fileName.lowercased().hasSuffix(".csv") {
            document = try Self.decodeCSV(data)
        } else {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let value = try? decoder.decode(PTXP400BLEEvidenceDocument.self, from: data) else {
                throw PTXP400BLEEvidenceImportError.invalidEncoding
            }
            document = value
        }

        let report = try validate(document: document, fileName: fileName)
        reports.insert(report, at: 0)
        reports = Array(reports.prefix(Self.maximumReportCount))
        persist()
        return report
    }

    public func remove(id: UUID) -> Bool {
        let count = reports.count
        reports.removeAll { $0.id == id }
        guard reports.count != count else { return false }
        persist()
        return true
    }

    public func clear() {
        reports.removeAll(keepingCapacity: true)
        persist()
    }

    public func exportJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(reports.map(Self.redactedReport))
    }

    public func exportCSVData() -> Data {
        var rows = [Self.csvHeader]
        for report in reports {
            for session in report.sessions {
                for item in session.frames {
                    let values = [
                        String(report.schemaVersion),
                        session.id.uuidString,
                        ISO8601DateFormatter().string(from: session.capturedAt),
                        report.vehicleModel,
                        report.firmwareVersion ?? "",
                        Self.redactIdentity(session.centralUUID),
                        Self.redactDeviceName(session.deviceName),
                        String(format: "%.6f", item.frame.timestamp),
                        item.frame.direction.rawValue,
                        item.frame.characteristicUUID ?? "",
                        item.frame.rawHex,
                        item.frame.note ?? "",
                        session.conclusion ?? ""
                    ]
                    rows.append(values.map { Self.csvField($0 ?? "") }.joined(separator: ","))
                }
            }
        }
        return Data(rows.joined(separator: "\n").utf8)
    }
}

private extension PTXP400BLEEvidenceStore {
    static let csvHeader = "schemaVersion,sessionID,capturedAt,vehicleModel,firmwareVersion,centralUUID,deviceName,frameTimestamp,direction,characteristicUUID,rawHex,note,conclusion"

    func validate(
        document: PTXP400BLEEvidenceDocument,
        fileName: String
    ) throws -> PTXP400BLEEvidenceImportReport {
        guard document.schemaVersion == PTXP400BLEEvidenceDocument.currentSchemaVersion else {
            throw PTXP400BLEEvidenceImportError.unsupportedSchema
        }
        let vehicleModel = document.vehicleModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vehicleModel.isEmpty, vehicleModel.count <= 160 else {
            throw PTXP400BLEEvidenceImportError.emptyVehicleModel
        }
        guard !document.sessions.isEmpty,
              document.sessions.count <= Self.maximumSessionCount else {
            throw PTXP400BLEEvidenceImportError.invalidSession
        }
        let totalFrameCount = document.sessions.reduce(0) { $0 + $1.frames.count }
        guard totalFrameCount > 0, totalFrameCount <= Self.maximumFrameCount else {
            throw PTXP400BLEEvidenceImportError.invalidFrame
        }
        let firmwareVersion = Self.normalizedOptional(document.firmwareVersion, maximumLength: 80)
        let sessions = try document.sessions.map { session in
            guard session.capturedAt.timeIntervalSince1970.isFinite else {
                throw PTXP400BLEEvidenceImportError.invalidSession
            }
            if let centralUUID = session.centralUUID,
               UUID(uuidString: centralUUID) == nil {
                throw PTXP400BLEEvidenceImportError.invalidIdentity
            }
            if let deviceName = session.deviceName, deviceName.count > 128 {
                throw PTXP400BLEEvidenceImportError.invalidIdentity
            }
            if let conclusion = session.conclusion, conclusion.count > 2_000 {
                throw PTXP400BLEEvidenceImportError.invalidSession
            }
            let frames = try session.frames.map { frame in
                guard frame.timestamp.isFinite,
                      frame.rawHex.count <= 1_024,
                      let data = Self.hexData(frame.rawHex),
                      !data.isEmpty else {
                    return PTXP400BLEEvidenceFrameResult(
                        frame: frame,
                        classification: .invalidHex,
                        validationMessage: "rawHex is not an even hexadecimal byte string"
                    )
                }
                if let characteristicUUID = frame.characteristicUUID,
                   !Self.isValidUUIDValue(characteristicUUID) {
                    throw PTXP400BLEEvidenceImportError.invalidIdentity
                }
                let classification = Self.classify(data)
                return PTXP400BLEEvidenceFrameResult(
                    frame: frame,
                    classification: classification,
                    validationMessage: classification == .unknownValidHex
                        ? "Needs repeated capture and human confirmation"
                        : nil
                )
            }
            return PTXP400BLEEvidenceSessionReport(
                id: session.id,
                capturedAt: session.capturedAt,
                centralUUID: session.centralUUID,
                deviceName: session.deviceName,
                conclusion: session.conclusion,
                frames: frames
            )
        }
        return PTXP400BLEEvidenceImportReport(
            schemaVersion: document.schemaVersion,
            sourceFileName: fileName,
            vehicleModel: vehicleModel,
            firmwareVersion: firmwareVersion,
            sessions: sessions
        )
    }

    static func classify(_ data: Data) -> PTXP400BLEEvidenceClassification {
        if PTXP400BLEProtocol.isValidOutboundFrame(data) { return .knownOutboundEnvelope }
        if PTXP400BLEProtocol.isValidAuthenticationKeyConfiguration(data) { return .knownAuthenticationKey }
        if PTXP400BLEProtocol.isValidAuthenticationChallenge(data) { return .knownAuthenticationChallenge }
        if PTXP400BLEProtocol.connectionSerial(in: data) != nil { return .knownConnectionFrame }
        if PTXP400BLEProtocol.isVehicleStatusFrame(data) { return .knownVehicleStatusFrame }
        return .unknownValidHex
    }

    static func hexData(_ value: String) -> Data? {
        let clean = value.filter { $0.isHexDigit }
        guard clean.count == value.filter({ !$0.isWhitespace }).count,
              !clean.isEmpty,
              clean.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    static func isValidUUIDValue(_ value: String) -> Bool {
        UUID(uuidString: value) != nil || {
            let clean = value.filter { $0.isHexDigit }
            return (clean.count == 4 || clean.count == 8) && clean.count == value.filter({ !$0.isWhitespace }).count
        }()
    }

    static func decodeCSV(_ data: Data) throws -> PTXP400BLEEvidenceDocument {
        guard let text = String(data: data, encoding: .utf8) else {
            throw PTXP400BLEEvidenceImportError.invalidEncoding
        }
        let rows = text.split(whereSeparator: \.isNewline).map { parseCSVLine(String($0)) }
        guard let header = rows.first,
              header == csvHeader.split(separator: ",").map(String.init) else {
            throw PTXP400BLEEvidenceImportError.invalidCSVHeader
        }
        var sessions: [UUID: PTXP400BLEEvidenceSessionBuilder] = [:]
        var sessionOrder: [UUID] = []
        var model = ""
        var firmware: String?
        for row in rows.dropFirst() {
            guard row.count == header.count,
                  let schemaVersion = Int(row[0]),
                  let sessionID = UUID(uuidString: row[1]),
                  let capturedAt = ISO8601DateFormatter().date(from: row[2]),
                  let timestamp = Double(row[7]),
                  let direction = PTXP400BLEEvidenceDirection(rawValue: row[8]) else {
                throw PTXP400BLEEvidenceImportError.invalidSession
            }
            if model.isEmpty { model = row[3] }
            if firmware == nil, !row[4].isEmpty { firmware = row[4] }
            if sessions[sessionID] == nil {
                sessions[sessionID] = PTXP400BLEEvidenceSessionBuilder(
                    id: sessionID,
                    capturedAt: capturedAt,
                    centralUUID: row[5].isEmpty ? nil : row[5],
                    deviceName: row[6].isEmpty ? nil : row[6],
                    conclusion: row[12].isEmpty ? nil : row[12]
                )
                sessionOrder.append(sessionID)
            }
            sessions[sessionID]?.frames.append(
                PTXP400BLEEvidenceFrame(
                    timestamp: timestamp,
                    direction: direction,
                    characteristicUUID: row[9].isEmpty ? nil : row[9],
                    rawHex: row[10],
                    note: row[11].isEmpty ? nil : row[11]
                )
            )
            _ = schemaVersion
        }
        guard !model.isEmpty else { throw PTXP400BLEEvidenceImportError.emptyVehicleModel }
        let finalized = sessionOrder.compactMap { sessions[$0]?.build() }
        return PTXP400BLEEvidenceDocument(vehicleModel: model, firmwareVersion: firmware, sessions: finalized)
    }

    static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var value = ""
        var quoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if quoted, next < line.endIndex, line[next] == "\"" {
                    value.append("\"")
                    index = line.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if character == "," && !quoted {
                result.append(value)
                value.removeAll(keepingCapacity: true)
            } else {
                value.append(character)
            }
            index = line.index(after: index)
        }
        result.append(value)
        return result
    }

    static func redactedReport(_ report: PTXP400BLEEvidenceImportReport) -> PTXP400BLEEvidenceImportReport {
        PTXP400BLEEvidenceImportReport(
            id: report.id,
            schemaVersion: report.schemaVersion,
            sourceFileName: report.sourceFileName,
            vehicleModel: report.vehicleModel,
            firmwareVersion: report.firmwareVersion,
            importedAt: report.importedAt,
            sessions: report.sessions.map { session in
                PTXP400BLEEvidenceSessionReport(
                    id: session.id,
                    capturedAt: session.capturedAt,
                    centralUUID: redactIdentity(session.centralUUID),
                    deviceName: redactDeviceName(session.deviceName),
                    conclusion: redactText(session.conclusion),
                    frames: session.frames.map { item in
                        PTXP400BLEEvidenceFrameResult(
                            frame: PTXP400BLEEvidenceFrame(
                                id: item.frame.id,
                                timestamp: item.frame.timestamp,
                                direction: item.frame.direction,
                                characteristicUUID: item.frame.characteristicUUID,
                                rawHex: item.frame.rawHex,
                                note: redactText(item.frame.note)
                            ),
                            classification: item.classification,
                            validationMessage: item.validationMessage
                        )
                    }
                )
            }
        )
    }

    static func redactIdentity(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value.count > 8 ? "\(value.prefix(4))…\(value.suffix(4))" : "***"
    }

    static func redactDeviceName(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value.count > 2 ? "\(value.prefix(2))***" : "***"
    }

    static func redactText(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value.count > 64 ? "\(value.prefix(64))…" : value
    }

    static func normalizedOptional(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= maximumLength else { return nil }
        return normalized
    }

    static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(reports) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    struct PTXP400BLEEvidenceSessionBuilder {
        let id: UUID
        let capturedAt: Date
        let centralUUID: String?
        let deviceName: String?
        let conclusion: String?
        var frames: [PTXP400BLEEvidenceFrame] = []

        func build() -> PTXP400BLEEvidenceSession {
            PTXP400BLEEvidenceSession(
                id: id,
                capturedAt: capturedAt,
                centralUUID: centralUUID,
                deviceName: deviceName,
                frames: frames,
                conclusion: conclusion
            )
        }
    }
}

@MainActor
final class PTXP400EvidenceViewController: PTListViewController, UIDocumentPickerDelegate {
    private let cellIdentifier = "PTXP400EvidenceCell"

    public override func installListViewConstraints(_ listView: PTCollectionView) {
        listView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total)
        }
    }
    
    public override func makeListViewConfiguration() -> PTCollectionViewConfig {
        let cConfig = PTCollectionViewConfig()
        cConfig.viewType = .Normal
        cConfig.itemOriginalX = PTAppBaseConfig.share.defaultViewSpace
        cConfig.itemHeight = 72
        return cConfig
    }
    
    public override func configureListView(_ listView: PTCollectionView) {
        listView.cellInCollection = { collectionView ,dataModel,indexPath in
            if let itemRow = dataModel.rows?[indexPath.row],let cell = collectionView.dequeueReusableCell(withReuseIdentifier: itemRow.reuseID, for: indexPath) as? PTFusionCell,let cellModel = itemRow.dataModel as? PTFusionCellModel {
                cell.cellModel  = cellModel
                return cell
            }
            return nil
        }
    }
    
    lazy var exportButton:PTBaseButton = {
        let view = PTBaseButton(type:.custom)
        view.setImage(UIImage(.shared.withYou), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            self.exportAction()
        })
        return view
    }()

    lazy var clearButton:PTBaseButton = {
        let view = PTBaseButton(type:.custom)
        view.setImage(UIImage(.xmark.circleFill), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            self.clearAction()
        })
        return view
    }()

    // EN: Import is exposed only on the existing developer evidence screen and remains read-only.
    // ES: La importación solo aparece en la pantalla de evidencia del desarrollador y sigue siendo de solo lectura.
    // 中文：导入入口只放在现有开发者证据页面，并且始终保持只读。
    lazy var importButton: PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setImage(UIImage(.square.andArrowUp), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers { [weak self] _ in
            self?.importAction()
        }
        return view
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = PTDashboardConfig.languageFunc(text: "obd_evidence_title")
        self.showDetail()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setCustomRightButtons(buttons: [clearButton, exportButton, importButton], buttonSpacing: CGFloat.GlobalItemSpacing)
        self.showDetail()
    }

    func showDetail() {
        var mSections = [PTSection]()
        let permissionRows = PTXP400InstructionEvidenceStore.shared.records.map {
            let cellModel = PTFusionCellModel()
            cellModel.name = "\($0.address.tx) → \($0.address.rx) · \($0.did) · \($0.evidenceLevel.rawValue)"
            cellModel.content = "\($0.status.rawValue) · \($0.rawResponse)"
            
            let row = PTRows(ID: PTFusionCell.ID,dataModel: cellModel)
            row.cellClass = PTFusionCell.self
            return row
        }
        let section = PTSection(rows: permissionRows)
        mSections.append(section)

        let bleRows = PTXP400BLEEvidenceStore.shared.reports.flatMap { report in
            report.sessions.map { session in
                let cellModel = PTFusionCellModel()
                cellModel.name = "BLE · \(report.vehicleModel) · \(session.id.uuidString.prefix(8))"
                cellModel.content = "\(report.frameCount) frames · invalid \(report.invalidFrameCount) · \(report.sourceFileName)"
                let row = PTRows(ID: PTFusionCell.ID, dataModel: cellModel)
                row.cellClass = PTFusionCell.self
                return row
            }
        }
        if !bleRows.isEmpty {
            mSections.append(PTSection(rows: bleRows))
        }
        
        listView.layoutIfNeeded()
        listView.showCollectionDetail(collectionData: mSections)
    }

    @objc private func exportAction() {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "obd_evidence_export"),
            message: PTDashboardConfig.languageFunc(text: "obd_evidence_export_hint"),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(
            title: "JSON",
            style: .default
        ) { [weak self] _ in
            self?.share { try PTXP400InstructionEvidenceStore.shared.exportURL(format: .json) }
        })
        alert.addAction(UIAlertAction(
            title: "CSV",
            style: .default
        ) { [weak self] _ in
            self?.share { try PTXP400InstructionEvidenceStore.shared.exportURL(format: .csv) }
        })
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_cancel"),
            style: .cancel
        ))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    @objc private func clearAction() {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "obd_evidence_clear"),
            message: PTDashboardConfig.languageFunc(text: "obd_evidence_clear_hint"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "obd_evidence_clear"),
            style: .destructive
        ) { [weak self] _ in
            PTXP400InstructionEvidenceStore.shared.clear()
            self?.showDetail()
        })
        alert.addAction(UIAlertAction(title: PTDashboardConfig.languageFunc(text: "button_cancel"), style: .cancel))
        present(alert, animated: true)
    }

    @objc private func importAction() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.json, .commaSeparatedText, .plainText],
            asCopy: true
        )
        picker.delegate = self
        present(picker, animated: true)
    }

    // EN: Import through a document picker so the developer explicitly chooses the evidence file.
    // ES: Importa mediante un selector de documentos para que el desarrollador elija explícitamente el archivo.
    // 中文：通过文件选择器导入，让开发者明确选择证据文件。
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let report = try PTXP400BLEEvidenceStore.shared.importEvidence(
                data: Data(contentsOf: url),
                fileName: url.lastPathComponent
            )
            showImportResult(report)
            showDetail()
        } catch {
            showImportError(error)
        }
    }

    private func showImportResult(_ report: PTXP400BLEEvidenceImportReport) {
        let message = String(
            format: PTDashboardConfig.languageFunc(text: "obd_evidence_import_success"),
            report.sessions.count,
            report.frameCount,
            report.invalidFrameCount
        )
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "obd_evidence_import"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: PTDashboardConfig.languageFunc(text: "button_confirm"), style: .default))
        present(alert, animated: true)
    }

    private func showImportError(_ error: Error) {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "obd_evidence_import"),
            message: "\(PTDashboardConfig.languageFunc(text: "obd_evidence_import_failed"))\n\(error.localizedDescription)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: PTDashboardConfig.languageFunc(text: "button_confirm"), style: .default))
        present(alert, animated: true)
    }

    private func share(_ makeURL: () throws -> URL) {
        do {
            let activity = UIActivityViewController(activityItems: [try makeURL()], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            }
            present(activity, animated: true)
        } catch {
            let alert = UIAlertController(title: PTDashboardConfig.languageFunc(text: "alert_title"), message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: PTDashboardConfig.languageFunc(text: "button_confirm"), style: .default))
            present(alert, animated: true)
        }
    }
}
