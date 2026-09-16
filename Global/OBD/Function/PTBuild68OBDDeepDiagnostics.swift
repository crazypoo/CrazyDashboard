//
//  PTBuild68OBDDeepDiagnostics.swift
//  CrazyDashboard
//
//  EN: Build 68 read-only OBD evidence, capability discovery, and telemetry quality.
//  ES: Evidencia OBD de solo lectura, descubrimiento de capacidades y calidad de telemetría de Build 68.
//  中文：Build 68 只读 OBD 证据、能力发现与遥测可信度实现。
//

import Foundation
import CryptoKit

// MARK: - Feature flags

/// EN: Every new Build 68 path is independently reversible without changing the stable transport core.
/// ES: Cada ruta nueva de Build 68 se puede revertir de forma independiente sin cambiar el núcleo de transporte estable.
/// 中文：Build 68 的每条新增路径都可以独立回滚，不改变稳定传输核心。
@MainActor
public enum PTBuild68FeatureFlags {
    public static var enableAutomaticDTCScan = true
    public static var enableFreezeFrameAutoRead = true
    public static var enableMode06DeepDiscovery = true
    public static var enableMode09ExtendedIdentity = true
    public static var enableAdaptivePollingV2 = true
    public static var enableTraceRedaction = true
}

// MARK: - Evidence and result models

public nonisolated enum PTBuild68EvidenceLevel: String, Codable, CaseIterable, Sendable {
    case candidate
    case probable
    case captured
    case repeatable
    case confirmed
}

public nonisolated enum PTBuild68EvidenceSource: String, Codable, Sendable {
    case mode01Capability
    case mode02FreezeFrame
    case mode03DTC
    case mode06
    case mode09
    case engineRuntime
    case telemetry
    case adapter
    case capturedCAN
}

public nonisolated enum PTBuild68DiagnosticTroubleCodeSource: String, Codable, Sendable {
    case confirmed
    case pending
    case permanent
}

public nonisolated struct PTBuild68DiagnosticAddressEvidence: Codable, Equatable, Sendable {
    public let txAddress: UInt32?
    public let rxAddress: UInt32?
    public let confidence: PTBuild68EvidenceLevel
    public let source: PTBuild68EvidenceSource

    public init(
        txAddress: UInt32? = nil,
        rxAddress: UInt32? = nil,
        confidence: PTBuild68EvidenceLevel,
        source: PTBuild68EvidenceSource
    ) {
        self.txAddress = txAddress
        self.rxAddress = rxAddress
        self.confidence = confidence
        self.source = source
    }
}

public nonisolated struct PTBuild68DiagnosticTroubleCodeRecord: Codable, Equatable, Sendable {
    public let code: String
    public let source: PTBuild68DiagnosticTroubleCodeSource
    public let ecuAddress: UInt32?
    public let firstObservedAt: Date
    public let lastObservedAt: Date
    public let sessionID: UUID
    public let evidenceLevel: PTBuild68EvidenceLevel

    public init(
        code: String,
        source: PTBuild68DiagnosticTroubleCodeSource,
        ecuAddress: UInt32? = nil,
        firstObservedAt: Date,
        lastObservedAt: Date,
        sessionID: UUID,
        evidenceLevel: PTBuild68EvidenceLevel = .captured
    ) {
        self.code = code.uppercased()
        self.source = source
        self.ecuAddress = ecuAddress
        self.firstObservedAt = firstObservedAt
        self.lastObservedAt = lastObservedAt
        self.sessionID = sessionID
        self.evidenceLevel = evidenceLevel
    }
}

public nonisolated struct PTBuild68MonitorStatus: Codable, Equatable, Sendable {
    public let isMILOn: Bool
    public let confirmedDTCCount: Int
    public let rawBytes: [UInt8]
    public let capturedAt: Date

    public init(
        isMILOn: Bool,
        confirmedDTCCount: Int,
        rawBytes: [UInt8],
        capturedAt: Date = Date()
    ) {
        self.isMILOn = isMILOn
        self.confirmedDTCCount = max(0, confirmedDTCCount)
        self.rawBytes = rawBytes
        self.capturedAt = capturedAt
    }
}

public nonisolated struct PTBuild68FreezeFrameValue: Codable, Equatable, Sendable {
    public let pid: String
    public let rawPayload: String
    public let numericValue: Double?
    public let displayValue: String?

    public init(
        pid: String,
        rawPayload: String,
        numericValue: Double? = nil,
        displayValue: String? = nil
    ) {
        self.pid = pid.uppercased()
        self.rawPayload = rawPayload.uppercased()
        self.numericValue = numericValue
        self.displayValue = displayValue
    }
}

public nonisolated struct PTBuild68FreezeFrameSnapshot: Codable, Equatable, Sendable {
    public let dtc: String?
    public let fuelSystemStatus: Int?
    public let calculatedLoad: Double?
    public let coolantTemperature: Double?
    public let shortTermFuelTrim: Double?
    public let longTermFuelTrim: Double?
    public let manifoldPressure: Double?
    public let engineRPM: Double?
    public let vehicleSpeed: Double?
    public let values: [PTBuild68FreezeFrameValue]
    public let capturedAt: Date
    public let ecuAddress: UInt32?

    public init(
        dtc: String? = nil,
        fuelSystemStatus: Int? = nil,
        calculatedLoad: Double? = nil,
        coolantTemperature: Double? = nil,
        shortTermFuelTrim: Double? = nil,
        longTermFuelTrim: Double? = nil,
        manifoldPressure: Double? = nil,
        engineRPM: Double? = nil,
        vehicleSpeed: Double? = nil,
        values: [PTBuild68FreezeFrameValue] = [],
        capturedAt: Date = Date(),
        ecuAddress: UInt32? = nil
    ) {
        self.dtc = dtc
        self.fuelSystemStatus = fuelSystemStatus
        self.calculatedLoad = calculatedLoad
        self.coolantTemperature = coolantTemperature
        self.shortTermFuelTrim = shortTermFuelTrim
        self.longTermFuelTrim = longTermFuelTrim
        self.manifoldPressure = manifoldPressure
        self.engineRPM = engineRPM
        self.vehicleSpeed = vehicleSpeed
        self.values = values
        self.capturedAt = capturedAt
        self.ecuAddress = ecuAddress
    }
}

public nonisolated struct PTBuild68CapabilityPage: Codable, Equatable, Sendable {
    public let command: String
    public let rawResponse: String
    public let status: PTOBDReadStatus
    public let mask: UInt32?
    public let supportedIdentifiers: [String]
    public let hasContinuation: Bool
    public let capturedAt: Date

    public init(
        command: String,
        rawResponse: String,
        status: PTOBDReadStatus,
        mask: UInt32? = nil,
        supportedIdentifiers: [String] = [],
        hasContinuation: Bool = false,
        capturedAt: Date = Date()
    ) {
        self.command = command.uppercased()
        self.rawResponse = rawResponse
        self.status = status
        self.mask = mask
        self.supportedIdentifiers = Array(Set(supportedIdentifiers.map { $0.uppercased() })).sorted()
        self.hasContinuation = hasContinuation
        self.capturedAt = capturedAt
    }
}

public nonisolated struct PTBuild68CapabilityProfile: Codable, Equatable, Sendable {
    public private(set) var mode01Masks: [String: UInt32]
    public private(set) var mode02PIDs: [String]
    public private(set) var mode06Masks: [String: UInt32]
    public private(set) var mode09PIDs: [String]
    public private(set) var supportedPIDs: [String]
    public private(set) var addressEvidence: [PTBuild68DiagnosticAddressEvidence]
    public private(set) var discoveredAt: Date?

    public init(
        mode01Masks: [String: UInt32] = [:],
        mode02PIDs: [String] = [],
        mode06Masks: [String: UInt32] = [:],
        mode09PIDs: [String] = [],
        supportedPIDs: [String] = [],
        addressEvidence: [PTBuild68DiagnosticAddressEvidence] = [],
        discoveredAt: Date? = nil
    ) {
        self.mode01Masks = mode01Masks
        self.mode02PIDs = mode02PIDs
        self.mode06Masks = mode06Masks
        self.mode09PIDs = mode09PIDs
        self.supportedPIDs = supportedPIDs
        self.addressEvidence = addressEvidence
        self.discoveredAt = discoveredAt
    }

    public mutating func merge(_ page: PTBuild68CapabilityPage) {
        guard page.status == .success else { return }
        discoveredAt = page.capturedAt
        let command = page.command.uppercased()
        switch command {
        case "0100", "0120", "0140":
            if let mask = page.mask { mode01Masks[command] = mask }
            appendUnique(page.supportedIdentifiers, to: &supportedPIDs)
        case "020000":
            appendUnique(page.supportedIdentifiers, to: &mode02PIDs)
        case let value where value.hasPrefix("06"):
            if let mask = page.mask { mode06Masks[command] = mask }
        case "0900":
            appendUnique(page.supportedIdentifiers, to: &mode09PIDs)
        default:
            break
        }
    }

    public mutating func mergeSupportedCommands(_ commands: [String]) {
        appendUnique(commands, to: &supportedPIDs)
    }

    public mutating func addAddressEvidence(_ evidence: PTBuild68DiagnosticAddressEvidence) {
        guard !addressEvidence.contains(where: {
            $0.txAddress == evidence.txAddress
                && $0.rxAddress == evidence.rxAddress
                && $0.source == evidence.source
        }) else { return }
        addressEvidence.append(evidence)
    }

    public func supports(_ command: String) -> Bool {
        let normalized = PTBuild68CommandCatalog.normalize(command)
        if normalized == "ATRV" { return true }
        return supportedPIDs.contains(normalized)
    }

    private func appendUnique(_ values: [String], to destination: inout [String]) {
        let existing = Set(destination.map { $0.uppercased() })
        destination.append(contentsOf: values.map { $0.uppercased() }.filter { !existing.contains($0) })
        destination = Array(Set(destination)).sorted()
    }
}

public nonisolated enum PTBuild68PIDAvailability: String, Codable, Sendable {
    case supported
    case temporarilyUnavailable
    case stale
    case unsupported
}

public nonisolated struct PTBuild68PIDRuntimeState: Codable, Equatable, Sendable {
    public private(set) var successCount = 0
    public private(set) var failureCount = 0
    public private(set) var consecutiveFailureCount = 0
    public private(set) var lastSuccessAt: Date?
    public private(set) var lastFailureAt: Date?
    public private(set) var latencyEWMA: TimeInterval?
    public private(set) var successRate = 0.0
    public private(set) var cooldownUntil: Date?
    public private(set) var isAdvertisedSupported: Bool?

    public init(isAdvertisedSupported: Bool? = nil) {
        self.isAdvertisedSupported = isAdvertisedSupported
    }

    public mutating func markCapability(_ supported: Bool) {
        isAdvertisedSupported = supported
    }

    public mutating func recordSuccess(latency: TimeInterval? = nil, at date: Date = Date()) {
        successCount += 1
        consecutiveFailureCount = 0
        lastSuccessAt = date
        cooldownUntil = nil
        if let latency, latency.isFinite, latency >= 0 {
            if let old = latencyEWMA {
                latencyEWMA = old * 0.8 + latency * 0.2
            } else {
                latencyEWMA = latency
            }
        }
        recalculateSuccessRate()
    }

    public mutating func recordFailure(at date: Date = Date()) {
        failureCount += 1
        consecutiveFailureCount += 1
        lastFailureAt = date
        let backoff = min(pow(2.0, Double(min(consecutiveFailureCount, 5))), 30)
        cooldownUntil = date.addingTimeInterval(backoff)
        recalculateSuccessRate()
    }

    public func shouldRequest(at date: Date = Date()) -> Bool {
        guard let cooldownUntil else { return true }
        return cooldownUntil <= date
    }

    public func availability(at date: Date = Date()) -> PTBuild68PIDAvailability {
        if isAdvertisedSupported == false { return .unsupported }
        if isAdvertisedSupported == nil, successCount == 0, failureCount >= 3 { return .unsupported }
        if let lastSuccessAt, date.timeIntervalSince(lastSuccessAt) > 60 { return .stale }
        if consecutiveFailureCount > 0 { return .temporarilyUnavailable }
        return .supported
    }

    private mutating func recalculateSuccessRate() {
        let total = successCount + failureCount
        successRate = total == 0 ? 0 : Double(successCount) / Double(total)
    }
}

public nonisolated enum PTBuild68BaselinePhase: String, Codable, CaseIterable, Sendable {
    case coldIdle
    case warmIdle
    case cruise30To50
    case cruise50To70
    case acceleration
    case deceleration
}

public nonisolated struct PTBuild68SignalBaseline: Codable, Equatable, Sendable {
    public let mean: Double
    public let median: Double
    public let minimum: Double
    public let maximum: Double
    public let standardDeviation: Double
    public let sampleCount: Int

    public init(values: [Double]) {
        let valid = values.filter { $0.isFinite }
        guard !valid.isEmpty else {
            mean = 0
            median = 0
            minimum = 0
            maximum = 0
            standardDeviation = 0
            sampleCount = 0
            return
        }

        let sorted = valid.sorted()
        let total = sorted.reduce(0, +)
        let average = total / Double(sorted.count)
        let middle = sorted.count / 2
        let medianValue = sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
        let variance = sorted.reduce(0) { partialResult, value in
            let delta = value - average
            return partialResult + delta * delta
        } / Double(sorted.count)

        mean = average
        median = medianValue
        minimum = sorted[0]
        maximum = sorted[sorted.count - 1]
        standardDeviation = sqrt(variance)
        sampleCount = sorted.count
    }
}

public nonisolated struct PTBuild68EngineSessionMetadata: Codable, Equatable, Sendable {
    public let engineStartedAt: Date?
    public let obdConnectedAt: Date
    public let engineRuntimeAtConnect: TimeInterval?
    public let confidence: PTBuild68EvidenceLevel

    public init(
        engineStartedAt: Date?,
        obdConnectedAt: Date,
        engineRuntimeAtConnect: TimeInterval?,
        confidence: PTBuild68EvidenceLevel
    ) {
        self.engineStartedAt = engineStartedAt
        self.obdConnectedAt = obdConnectedAt
        self.engineRuntimeAtConnect = engineRuntimeAtConnect
        self.confidence = confidence
    }
}

public nonisolated struct PTBuild68VoltageSnapshot: Codable, Equatable, Sendable {
    public let adapterVoltage: Double?
    public let controlModuleVoltage: Double?

    public init(adapterVoltage: Double? = nil, controlModuleVoltage: Double? = nil) {
        self.adapterVoltage = adapterVoltage
        self.controlModuleVoltage = controlModuleVoltage
    }

    public var delta: Double? {
        guard let adapterVoltage, let controlModuleVoltage else { return nil }
        return abs(controlModuleVoltage - adapterVoltage)
    }

    public var hasDiscrepancy: Bool {
        guard let delta else { return false }
        return delta > 1.0
    }
}

public nonisolated enum PTBuild68ThrottleSource: String, Codable, Sendable {
    case relative
    case absolute
    case xp400Candidate
}

public nonisolated struct PTBuild68ThrottleSnapshot: Codable, Equatable, Sendable {
    public let percent: Double?
    public let source: PTBuild68ThrottleSource?
    public let relativePercent: Double?
    public let absolutePercent: Double?

    public init(
        percent: Double? = nil,
        source: PTBuild68ThrottleSource? = nil,
        relativePercent: Double? = nil,
        absolutePercent: Double? = nil
    ) {
        self.percent = percent
        self.source = source
        self.relativePercent = relativePercent
        self.absolutePercent = absolutePercent
    }
}

public nonisolated struct PTBuild68CalibrationRecord: Codable, Equatable, Sendable {
    public let calibrationID: String
    public let cvn: String?

    public init(calibrationID: String, cvn: String? = nil) {
        self.calibrationID = calibrationID
        self.cvn = cvn
    }
}

public nonisolated struct PTBuild68InUsePerformanceRecord: Codable, Equatable, Sendable {
    public let ignitionCounter: UInt32?
    public let obdConditionCounter: UInt32?
    public let catalystCompletionCounter: UInt32?
    public let oxygenSensorCompletionCounter: UInt32?
    public let rawValues: [String: UInt32]
    public let rawHex: String

    public init(
        ignitionCounter: UInt32? = nil,
        obdConditionCounter: UInt32? = nil,
        catalystCompletionCounter: UInt32? = nil,
        oxygenSensorCompletionCounter: UInt32? = nil,
        rawValues: [String: UInt32] = [:],
        rawHex: String = ""
    ) {
        self.ignitionCounter = ignitionCounter
        self.obdConditionCounter = obdConditionCounter
        self.catalystCompletionCounter = catalystCompletionCounter
        self.oxygenSensorCompletionCounter = oxygenSensorCompletionCounter
        self.rawValues = rawValues
        self.rawHex = rawHex.uppercased()
    }
}

public nonisolated struct PTBuild68ElectronicControlUnit: Codable, Equatable, Sendable {
    public let rxAddress: UInt32
    public let txAddress: UInt32?
    public let ecuName: String?
    public let calibrationRecords: [PTBuild68CalibrationRecord]
    public let inUsePerformance: PTBuild68InUsePerformanceRecord?
    public let rawResponses: [String: String]
    public let fingerprint: String?
    public let evidenceLevel: PTBuild68EvidenceLevel
    public let capturedAt: Date

    public init(
        rxAddress: UInt32,
        txAddress: UInt32? = nil,
        ecuName: String? = nil,
        calibrationRecords: [PTBuild68CalibrationRecord] = [],
        inUsePerformance: PTBuild68InUsePerformanceRecord? = nil,
        rawResponses: [String: String] = [:],
        fingerprint: String? = nil,
        evidenceLevel: PTBuild68EvidenceLevel = .captured,
        capturedAt: Date = Date()
    ) {
        self.rxAddress = rxAddress
        self.txAddress = txAddress
        self.ecuName = ecuName
        self.calibrationRecords = calibrationRecords
        self.inUsePerformance = inUsePerformance
        self.rawResponses = rawResponses
        self.fingerprint = fingerprint
        self.evidenceLevel = evidenceLevel
        self.capturedAt = capturedAt
    }

    public func redactedForExport() -> PTBuild68ElectronicControlUnit {
        PTBuild68ElectronicControlUnit(
            rxAddress: rxAddress,
            txAddress: txAddress,
            ecuName: ecuName,
            calibrationRecords: calibrationRecords,
            inUsePerformance: inUsePerformance,
            rawResponses: rawResponses.mapValues {
                PTBuild68TraceRedactor.redact($0, level: .standard)
            },
            fingerprint: fingerprint,
            evidenceLevel: evidenceLevel,
            capturedAt: capturedAt
        )
    }
}

public nonisolated struct PTBuild68RawCommandResult: Codable, Equatable, Sendable {
    public let command: String
    public let rawResponse: String
    public let payloadHex: String?
    public let status: PTOBDReadStatus
    public let negativeResponseCode: String?
    public let latency: TimeInterval?
    public let capturedAt: Date
    public let evidenceLevel: PTBuild68EvidenceLevel

    public init(
        command: String,
        rawResponse: String,
        payloadHex: String? = nil,
        status: PTOBDReadStatus,
        negativeResponseCode: String? = nil,
        latency: TimeInterval? = nil,
        capturedAt: Date = Date(),
        evidenceLevel: PTBuild68EvidenceLevel = .captured
    ) {
        self.command = command.uppercased()
        self.rawResponse = rawResponse
        self.payloadHex = payloadHex
        self.status = status
        self.negativeResponseCode = negativeResponseCode
        self.latency = latency
        self.capturedAt = capturedAt
        self.evidenceLevel = evidenceLevel
    }

    public func redactedForExport() -> PTBuild68RawCommandResult {
        PTBuild68RawCommandResult(
            command: command,
            rawResponse: PTBuild68TraceRedactor.redact(rawResponse, level: .standard),
            payloadHex: payloadHex,
            status: status,
            negativeResponseCode: negativeResponseCode,
            latency: latency,
            capturedAt: capturedAt,
            evidenceLevel: evidenceLevel
        )
    }
}

public nonisolated struct PTBuild68DiagnosticSessionRecord: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let capability: PTBuild68CapabilityProfile
    public let monitorStatus: PTBuild68MonitorStatus?
    public let troubleCodes: [PTBuild68DiagnosticTroubleCodeRecord]
    public let freezeFrame: PTBuild68FreezeFrameSnapshot?
    public let electronicControlUnit: PTBuild68ElectronicControlUnit?
    public let engineSession: PTBuild68EngineSessionMetadata?
    public let voltage: PTBuild68VoltageSnapshot
    public let throttle: PTBuild68ThrottleSnapshot
    public let baselines: [String: [String: PTBuild68SignalBaseline]]
    public let pidRuntime: [String: PTBuild68PIDRuntimeState]
    public let rawCommandResults: [PTBuild68RawCommandResult]

    public init(
        sessionID: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        capability: PTBuild68CapabilityProfile = PTBuild68CapabilityProfile(),
        monitorStatus: PTBuild68MonitorStatus? = nil,
        troubleCodes: [PTBuild68DiagnosticTroubleCodeRecord] = [],
        freezeFrame: PTBuild68FreezeFrameSnapshot? = nil,
        electronicControlUnit: PTBuild68ElectronicControlUnit? = nil,
        engineSession: PTBuild68EngineSessionMetadata? = nil,
        voltage: PTBuild68VoltageSnapshot = PTBuild68VoltageSnapshot(),
        throttle: PTBuild68ThrottleSnapshot = PTBuild68ThrottleSnapshot(),
        baselines: [String: [String: PTBuild68SignalBaseline]] = [:],
        pidRuntime: [String: PTBuild68PIDRuntimeState] = [:],
        rawCommandResults: [PTBuild68RawCommandResult] = []
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.capability = capability
        self.monitorStatus = monitorStatus
        self.troubleCodes = troubleCodes
        self.freezeFrame = freezeFrame
        self.electronicControlUnit = electronicControlUnit
        self.engineSession = engineSession
        self.voltage = voltage
        self.throttle = throttle
        self.baselines = baselines
        self.pidRuntime = pidRuntime
        self.rawCommandResults = rawCommandResults
    }

    public func redactedForExport() -> PTBuild68DiagnosticSessionRecord {
        PTBuild68DiagnosticSessionRecord(
            sessionID: sessionID,
            startedAt: startedAt,
            endedAt: endedAt,
            capability: capability,
            monitorStatus: monitorStatus,
            troubleCodes: troubleCodes,
            freezeFrame: freezeFrame,
            electronicControlUnit: electronicControlUnit?.redactedForExport(),
            engineSession: engineSession,
            voltage: voltage,
            throttle: throttle,
            baselines: baselines,
            pidRuntime: pidRuntime,
            rawCommandResults: rawCommandResults.map { $0.redactedForExport() }
        )
    }
}

public nonisolated struct PTBuild68DTCReadBatch: Sendable {
    public let results: [PTBuild68RawCommandResult]
    public let records: [PTBuild68DiagnosticTroubleCodeRecord]

    public init(results: [PTBuild68RawCommandResult], records: [PTBuild68DiagnosticTroubleCodeRecord]) {
        self.results = results
        self.records = records
    }
}

public nonisolated struct PTBuild68FreezeFrameReadBatch: Sendable {
    public let results: [PTBuild68RawCommandResult]
    public let snapshot: PTBuild68FreezeFrameSnapshot?

    public init(results: [PTBuild68RawCommandResult], snapshot: PTBuild68FreezeFrameSnapshot?) {
        self.results = results
        self.snapshot = snapshot
    }
}

public nonisolated struct PTBuild68IdentityReadResult: Sendable {
    public let results: [PTBuild68RawCommandResult]
    public let electronicControlUnit: PTBuild68ElectronicControlUnit

    public init(results: [PTBuild68RawCommandResult], electronicControlUnit: PTBuild68ElectronicControlUnit) {
        self.results = results
        self.electronicControlUnit = electronicControlUnit
    }
}

public nonisolated struct PTBuild68EvidenceDocument: Codable, Sendable {
    public let schemaVersion: Int
    public let sessions: [PTBuild68DiagnosticSessionRecord]

    public init(schemaVersion: Int = 1, sessions: [PTBuild68DiagnosticSessionRecord] = []) {
        self.schemaVersion = schemaVersion
        self.sessions = sessions
    }
}

// MARK: - Command catalog

public nonisolated enum PTBuild68CommandCatalog {
    public static let dtcCommands = ["03", "07", "0A"]
    public static let freezeFramePIDs = ["02", "03", "04", "05", "06", "07", "0B", "0C", "0D"]
    public static let extendedIdentityCommands = ["0904", "0906", "0908", "090A"]
    public static let mode06CapabilityCommands = ["0600", "0620", "0640", "0660", "0680", "06A0"]
    public static let capabilityCommands = ["0100", "0120", "0140", "020000", "0600", "0900"]
    // EN: Capability pages are session probes, never runtime telemetry commands.
    // ES: Las páginas de capacidad son sondeos de sesión, nunca comandos de telemetría en tiempo real.
    // 中文：能力页只属于会话探测，绝不能进入实时遥测指令。
    public static let capabilityOnlyCommands: Set<String> = [
        "0100", "0120", "0140", "020000", "0600", "0620", "0640", "0660", "0680", "06A0", "0900"
    ]

    public static func normalize(_ command: String) -> String {
        command
            .filter { !$0.isWhitespace }
            .uppercased()
    }

    public static func isReadOnlyDeepCommand(_ command: String) -> Bool {
        let normalized = normalize(command)
        if normalized == "ATRV" { return true }
        guard normalized.count >= 2, normalized.allSatisfy(\.isHexDigit) else { return false }
        let service = String(normalized.prefix(2))
        return ["01", "02", "03", "06", "07", "09", "0A"].contains(service)
    }

    public static func isCapabilityOnlyCommand(_ command: String) -> Bool {
        capabilityOnlyCommands.contains(normalize(command))
    }
}

// MARK: - Protocol parser

/// EN: This parser strips the optional ELM327 DLC and ISO-TP transport bytes before decoding OBD data.
/// ES: Este analizador elimina el DLC opcional de ELM327 y los bytes de transporte ISO-TP antes de decodificar OBD.
/// 中文：该解析器在解码 OBD 前剥离可选的 ELM327 DLC 与 ISO-TP 传输字节。
public nonisolated enum PTBuild68ResponseParser {
    public static func responseStatus(for command: String, response: String) -> PTOBDReadStatus {
        if containsNoData(response) { return .noData }
        if negativeResponseCode(in: response, command: command) != nil { return .negativeResponse }
        guard let service = expectedService(for: command), !servicePayload(response: response, service: service).isEmpty else {
            return .invalidResponse
        }
        return .success
    }

    public static func negativeResponseCode(in response: String, command: String) -> String? {
        guard let expectedService = expectedService(for: command) else { return nil }
        for frame in frames(in: response) {
            let bytes = frame
            guard bytes.count >= 3 else { continue }
            for index in 0...(bytes.count - 3) where bytes[index] == 0x7F {
                guard bytes[index + 1] == expectedService else { continue }
                return String(format: "%02X", bytes[index + 2])
            }
        }
        return nil
    }

    public static func payloadHex(for command: String, response: String) -> String? {
        guard let service = expectedService(for: command) else { return nil }
        let bytes = servicePayload(response: response, service: service)
        return bytes.isEmpty ? nil : bytes.map { String(format: "%02X", $0) }.joined()
    }

    public static func parseCapability(command: String, response: String) -> PTBuild68CapabilityPage {
        let normalized = PTBuild68CommandCatalog.normalize(command)
        let status = responseStatus(for: normalized, response: response)
        guard status == .success,
              let service = expectedService(for: normalized) else {
            return PTBuild68CapabilityPage(command: normalized, rawResponse: response, status: status)
        }

        let payload = servicePayload(response: response, service: service)
        let maskBytes: [UInt8]
        let baseOffset: Int
        if normalized == "020000" {
            guard payload.count >= 6 else {
                return PTBuild68CapabilityPage(command: normalized, rawResponse: response, status: .invalidResponse)
            }
            maskBytes = Array(payload.dropFirst(2).prefix(4))
            baseOffset = 0
        } else {
            guard payload.count >= 5 else {
                return PTBuild68CapabilityPage(command: normalized, rawResponse: response, status: .invalidResponse)
            }
            maskBytes = Array(payload.dropFirst().prefix(4))
            baseOffset = Int(normalized.suffix(2), radix: 16) ?? 0
        }

        guard maskBytes.count == 4 else {
            return PTBuild68CapabilityPage(command: normalized, rawResponse: response, status: .invalidResponse)
        }
        let mask = maskBytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let hasContinuation = (mask & 0x01) != 0
        let supported: [String]

        switch normalized {
        case "0100", "0120", "0140":
            supported = supportedIdentifiers(mask: mask, base: baseOffset) { pid in
                String(format: "01%02X", pid)
            }
        case "020000":
            supported = supportedIdentifiers(mask: mask, base: 0) { pid in
                String(format: "%02X", pid)
            }
        case let value where value.hasPrefix("06"):
            supported = supportedIdentifiers(mask: mask, base: baseOffset) { pid in
                String(format: "06%02X", pid)
            }
        case "0900":
            supported = supportedIdentifiers(mask: mask, base: 0) { pid in
                String(format: "09%02X", pid)
            }
        default:
            supported = []
        }

        return PTBuild68CapabilityPage(
            command: normalized,
            rawResponse: response,
            status: status,
            mask: mask,
            supportedIdentifiers: supported,
            hasContinuation: hasContinuation
        )
    }

    public static func parseMonitorStatus0101(response: String, capturedAt: Date = Date()) -> PTBuild68MonitorStatus? {
        let payload = servicePayload(response: response, service: 0x41)
        guard payload.count >= 5, payload[0] == 0x01 else { return nil }
        let bytes = Array(payload.dropFirst().prefix(4))
        guard bytes.count == 4 else { return nil }
        return PTBuild68MonitorStatus(
            isMILOn: (bytes[0] & 0x80) != 0,
            confirmedDTCCount: Int(bytes[0] & 0x7F),
            rawBytes: bytes,
            capturedAt: capturedAt
        )
    }

    public static func parseDTCs(
        response: String,
        source: PTBuild68DiagnosticTroubleCodeSource,
        sessionID: UUID,
        ecuAddress: UInt32? = nil,
        observedAt: Date = Date()
    ) -> [PTBuild68DiagnosticTroubleCodeRecord] {
        let expected: UInt8
        switch source {
        case .confirmed: expected = 0x43
        case .pending: expected = 0x47
        case .permanent: expected = 0x4A
        }
        let payload = servicePayload(response: response, service: expected)
        guard payload.count >= 2 else { return [] }

        var records: [PTBuild68DiagnosticTroubleCodeRecord] = []
        var seen = Set<String>()
        for index in stride(from: 0, to: payload.count - 1, by: 2) {
            let raw = (UInt16(payload[index]) << 8) | UInt16(payload[index + 1])
            guard raw != 0 else { continue }
            let code = decodeDTC(raw)
            guard seen.insert(code).inserted else { continue }
            records.append(
                PTBuild68DiagnosticTroubleCodeRecord(
                    code: code,
                    source: source,
                    ecuAddress: ecuAddress,
                    firstObservedAt: observedAt,
                    lastObservedAt: observedAt,
                    sessionID: sessionID
                )
            )
        }
        return records
    }

    public static func parseFreezeFrameValue(pid: String, response: String) -> PTBuild68FreezeFrameValue? {
        let normalizedPID = pid.uppercased()
        guard let pidByte = UInt8(normalizedPID, radix: 16) else { return nil }
        let payload = servicePayload(response: response, service: 0x42)
        // EN: Standard Mode 02 echoes the PID and then its data; a request frame byte is not part of the response payload.
        // ES: El Mode 02 estándar devuelve el PID seguido de sus datos; el byte de trama de la solicitud no forma parte de la respuesta.
        // 中文：标准 Mode 02 响应会回显 PID，随后直接返回数据；请求中的帧号不属于响应 Payload。
        guard let start = payload.firstIndex(of: pidByte), payload.count > start + 1 else { return nil }
        let bytes = Array(payload.dropFirst(start + 1))
        guard !bytes.isEmpty else { return nil }
        let raw = bytes.map { String(format: "%02X", $0) }.joined()

        switch normalizedPID {
        case "02":
            guard bytes.count >= 2 else { return PTBuild68FreezeFrameValue(pid: normalizedPID, rawPayload: raw) }
            let code = decodeDTC((UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return PTBuild68FreezeFrameValue(pid: normalizedPID, rawPayload: raw, displayValue: code)
        case "03":
            return PTBuild68FreezeFrameValue(pid: normalizedPID, rawPayload: raw, numericValue: Double(bytes[0]))
        case "04":
            let value = Double(bytes[0]) * 100 / 255
            return PTBuild68FreezeFrameValue(pid: normalizedPID, rawPayload: raw, numericValue: value)
        case "05":
            return PTBuild68FreezeFrameValue(pid: normalizedPID, rawPayload: raw, numericValue: Double(bytes[0]) - 40)
        case "06", "07":
            let value = Double(bytes[0]) * 100 / 128 - 100
            return PTBuild68FreezeFrameValue(pid: normalizedPID, rawPayload: raw, numericValue: value)
        case "0B":
            return PTBuild68FreezeFrameValue(pid: normalizedPID, rawPayload: raw, numericValue: Double(bytes[0]))
        case "0C":
            guard bytes.count >= 2 else { return nil }
            let value = (Double(bytes[0]) * 256 + Double(bytes[1])) / 4
            return PTBuild68FreezeFrameValue(pid: normalizedPID, rawPayload: raw, numericValue: value)
        case "0D":
            return PTBuild68FreezeFrameValue(pid: normalizedPID, rawPayload: raw, numericValue: Double(bytes[0]))
        default:
            return PTBuild68FreezeFrameValue(pid: normalizedPID, rawPayload: raw)
        }
    }

    public static func makeFreezeFrameSnapshot(
        results: [String: PTBuild68RawCommandResult],
        dtc: String? = nil,
        ecuAddress: UInt32? = nil,
        capturedAt: Date = Date()
    ) -> PTBuild68FreezeFrameSnapshot? {
        var values: [PTBuild68FreezeFrameValue] = []
        for pid in PTBuild68CommandCatalog.freezeFramePIDs {
            guard let result = results["02\(pid)00"],
                  let value = parseFreezeFrameValue(pid: pid, response: result.rawResponse) else { continue }
            values.append(value)
        }
        guard !values.isEmpty else { return nil }

        func number(_ pid: String) -> Double? {
            values.first(where: { $0.pid == pid })?.numericValue
        }
        let status = values.first(where: { $0.pid == "03" })?.numericValue.map(Int.init)
        let frameDTC = values.first(where: { $0.pid == "02" })?.displayValue

        return PTBuild68FreezeFrameSnapshot(
            dtc: frameDTC ?? dtc,
            fuelSystemStatus: status,
            calculatedLoad: number("04"),
            coolantTemperature: number("05"),
            shortTermFuelTrim: number("06"),
            longTermFuelTrim: number("07"),
            manifoldPressure: number("0B"),
            engineRPM: number("0C"),
            vehicleSpeed: number("0D"),
            values: values,
            capturedAt: capturedAt,
            ecuAddress: ecuAddress
        )
    }

    public static func parseASCII(response: String, service: UInt8, identifier: UInt8) -> String? {
        var payload = servicePayload(response: response, service: service)
        guard let start = payload.firstIndex(of: identifier) else { return nil }
        payload = Array(payload.dropFirst(start + 1))
        if let count = payload.first, count <= 8, payload.dropFirst().contains(where: { (32...126).contains($0) }) {
            payload.removeFirst()
        }
        let text = payload
            .filter { (32...126).contains($0) }
            .map { String(UnicodeScalar($0)) }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    public static func parseCalibrationIDs(response: String) -> [String] {
        guard let text = parseASCII(response: response, service: 0x49, identifier: 0x04) else { return [] }
        return splitIdentityText(text, chunkLength: 16)
    }

    public static func parseCVNs(response: String) -> [String] {
        let payload = identityData(response: response, service: 0x49, identifier: 0x06)
        guard !payload.isEmpty else { return [] }
        return stride(from: 0, to: payload.count - 3, by: 4).map { index in
            payload[index..<(index + 4)].map { String(format: "%02X", $0) }.joined()
        }
    }

    public static func parseInUsePerformance(response: String) -> PTBuild68InUsePerformanceRecord? {
        let payload = identityData(response: response, service: 0x49, identifier: 0x08)
        guard !payload.isEmpty else { return nil }
        var rawValues: [String: UInt32] = [:]
        for (index, offset) in stride(from: 0, to: payload.count - 3, by: 4).enumerated() {
            let value = payload[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            rawValues[String(format: "counter%02d", index + 1)] = value
        }
        return PTBuild68InUsePerformanceRecord(
            ignitionCounter: rawValues["counter01"],
            obdConditionCounter: rawValues["counter02"],
            catalystCompletionCounter: rawValues["counter03"],
            oxygenSensorCompletionCounter: rawValues["counter04"],
            rawValues: rawValues,
            rawHex: payload.map { String(format: "%02X", $0) }.joined()
        )
    }

    public static func parseEngineRuntime(response: String) -> TimeInterval? {
        let payload = servicePayload(response: response, service: 0x41)
        guard let index = payload.firstIndex(of: 0x1F), payload.count > index + 2 else { return nil }
        let a = Double(payload[index + 1])
        let b = Double(payload[index + 2])
        return a * 256 + b
    }

    public static func preferredThrottle(relative: Double?, absolute: Double?, xp400: Double? = nil) -> PTBuild68ThrottleSnapshot {
        if let relative, relative.isFinite, (0...100).contains(relative) {
            return PTBuild68ThrottleSnapshot(percent: relative, source: .relative, relativePercent: relative, absolutePercent: absolute)
        }
        if let absolute, absolute.isFinite, (0...100).contains(absolute) {
            return PTBuild68ThrottleSnapshot(percent: absolute, source: .absolute, relativePercent: relative, absolutePercent: absolute)
        }
        return PTBuild68ThrottleSnapshot(percent: xp400, source: xp400 == nil ? nil : .xp400Candidate, relativePercent: relative, absolutePercent: absolute)
    }

    public static func makeFingerprint(
        rxAddress: UInt32,
        ecuName: String?,
        calibrationRecords: [PTBuild68CalibrationRecord],
        protocolName: String? = nil
    ) -> String {
        let records = calibrationRecords
            .map { "\($0.calibrationID.uppercased()):\($0.cvn?.uppercased() ?? "")" }
            .sorted()
            .joined(separator: "|")
        let seed = [
            String(format: "%X", rxAddress),
            ecuName?.uppercased() ?? "",
            protocolName?.uppercased() ?? "",
            records
        ].joined(separator: "|")
        return SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02X", $0) }.joined()
    }

    public static func parseECUName(response: String) -> String? {
        parseASCII(response: response, service: 0x49, identifier: 0x0A)
    }

    public static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func expectedService(for command: String) -> UInt8? {
        let normalized = PTBuild68CommandCatalog.normalize(command)
        guard normalized.count >= 2 else { return nil }
        switch normalized.prefix(2) {
        case "01": return 0x41
        case "02": return 0x42
        case "03": return 0x43
        case "06": return 0x46
        case "07": return 0x47
        case "09": return 0x49
        case "0A": return 0x4A
        case "22": return 0x62
        case "23": return 0x63
        default: return nil
        }
    }

    private static func servicePayload(response: String, service: UInt8) -> [UInt8] {
        var payload: [UInt8] = []
        var foundService = false
        for rawFrame in frames(in: response) {
            var frame = normalizedFrame(rawFrame, service: service)
            if !foundService {
                guard let index = frame.firstIndex(of: service) else { continue }
                foundService = true
                frame = Array(frame.dropFirst(index + 1))
            } else if let first = frame.first, (first & 0xF0) == 0x20 {
                frame.removeFirst()
            }
            payload.append(contentsOf: frame)
        }
        return payload
    }

    private static func identityData(response: String, service: UInt8, identifier: UInt8) -> [UInt8] {
        var payload = servicePayload(response: response, service: service)
        guard let index = payload.firstIndex(of: identifier) else { return [] }
        payload = Array(payload.dropFirst(index + 1))
        if let count = payload.first, count <= 8 {
            payload.removeFirst()
        }
        return payload
    }

    private static func frames(in response: String) -> [[UInt8]] {
        response
            .components(separatedBy: .newlines)
            .compactMap { line -> [UInt8]? in
                let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                guard !tokens.isEmpty else { return nil }

                if tokens.count == 1 {
                    let compact = tokens[0].filter { $0 != ">" }.uppercased()
                    if let headerLength = canHeaderLength(compact), compact.count > headerLength {
                        return splitBytes(String(compact.dropFirst(headerLength)))
                    }
                }

                let start = canHeaderLength(tokens[0]) == nil ? 0 : 1
                let bytes = tokens.dropFirst(start).flatMap(splitBytes)
                return bytes.isEmpty ? nil : bytes
            }
    }

    private static func normalizedFrame(_ raw: [UInt8], service: UInt8) -> [UInt8] {
        guard raw.count >= 2 else { return raw }
        let secondByteIsSingleFrame = raw[1] & 0xF0 == 0x00 && raw.count >= 3 && raw[2] == service
        let secondByteIsISOTransport = [0x10, 0x20, 0x30].contains(raw[1] & 0xF0)
        if raw[0] <= 8, raw[1] == service || secondByteIsSingleFrame || secondByteIsISOTransport {
            // EN: ATD1 may prefix every CAN frame with DLC; remove that prefix before ISO-TP handling.
            // ES: ATD1 puede anteponer el DLC a cada trama CAN; elimina ese prefijo antes de procesar ISO-TP.
            // 中文：ATD1 可能在每个 CAN 帧前添加 DLC；先移除该前缀，再处理 ISO-TP。
            return Array(raw.dropFirst())
        }
        if raw[0] == 0x10, raw.count >= 3, raw[2] == service {
            return Array(raw.dropFirst(2))
        }
        return raw
    }

    private static func splitBytes(_ value: String) -> [UInt8] {
        let clean = value.filter { $0.isHexDigit }.uppercased()
        guard clean.count >= 2, clean.count.isMultiple(of: 2) else { return [] }
        return stride(from: 0, to: clean.count, by: 2).compactMap {
            let start = clean.index(clean.startIndex, offsetBy: $0)
            let end = clean.index(start, offsetBy: 2)
            return UInt8(clean[start..<end], radix: 16)
        }
    }

    private static func canHeaderLength(_ value: String) -> Int? {
        let clean = value.uppercased()
        guard clean.allSatisfy(\.isHexDigit) else { return nil }
        if clean.count == 3, let value = UInt16(clean, radix: 16), value <= 0x7FF { return 3 }
        if clean.count == 8, let value = UInt32(clean, radix: 16), value <= 0x1FFF_FFFF { return 8 }
        return nil
    }

    private static func containsNoData(_ response: String) -> Bool {
        let normalized = response.uppercased().replacingOccurrences(of: " ", with: "")
        return normalized.contains("NODATA") || normalized.contains("ERROR") || normalized.contains("UNABLETOCONNECT")
    }

    private static func supportedIdentifiers(
        mask: UInt32,
        base: Int,
        makeIdentifier: (Int) -> String
    ) -> [String] {
        (0..<32).compactMap { index in
            ((mask >> (31 - index)) & 1) == 1 ? makeIdentifier(base + index + 1) : nil
        }
    }

    private static func decodeDTC(_ raw: UInt16) -> String {
        let first = Int((raw >> 12) & 0x0F)
        let prefix: String
        switch first {
        case 0...3: prefix = "P\(first)"
        case 4...7: prefix = "C\(first - 4)"
        case 8...11: prefix = "B\(first - 8)"
        default: prefix = "U\(first - 12)"
        }
        return prefix + String(format: "%03X", raw & 0x0FFF)
    }

    private static func splitIdentityText(_ value: String, chunkLength: Int) -> [String] {
        let tokens = value
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t" || $0 == "," || $0 == ";" })
            .map(String.init)
            .filter { !$0.isEmpty }
        if tokens.count > 1 { return tokens }
        guard let token = tokens.first else { return [] }
        if token.count >= chunkLength, token.count.isMultiple(of: chunkLength) {
            return stride(from: 0, to: token.count, by: chunkLength).map {
                let start = token.index(token.startIndex, offsetBy: $0)
                let end = token.index(start, offsetBy: chunkLength)
                return String(token[start..<end])
            }
        }
        return [token]
    }
}

// MARK: - Adaptive polling recommendation

public nonisolated enum PTBuild68PollingTier: String, Codable, Sendable {
    case tierA
    case tierB
    case tierC
    case tierD
}

public nonisolated struct PTBuild68PollingRecommendation: Codable, Equatable, Sendable {
    public let tier: PTBuild68PollingTier
    public let commands: [String]
    public let weight: Double

    public init(tier: PTBuild68PollingTier, commands: [String], weight: Double) {
        self.tier = tier
        self.commands = commands
        self.weight = weight
    }
}

public nonisolated enum PTBuild68AdaptivePollScheduler {
    public static func recommendations(
        supportedCommands: [String],
        runtimeStates: [String: PTBuild68PIDRuntimeState]
    ) -> [PTBuild68PollingRecommendation] {
        let supported = Set(
            supportedCommands
                .map(PTBuild68CommandCatalog.normalize)
                .filter { !PTBuild68CommandCatalog.isCapabilityOnlyCommand($0) }
        )
        let groups: [(PTBuild68PollingTier, [String], Double)] = [
            (.tierA, ["010C", "010D", "0145", "0111"], 4),
            (.tierB, ["010B", "0104", "0106", "0114"], 2),
            (.tierC, ["0105", "010F", "0107", "0142", "ATRV"], 1),
            (.tierD, ["0101", "0141", "014D", "0904", "0906", "0908", "090A"], 0.2)
        ]

        return groups.compactMap { tier, commands, baseWeight in
            let filtered = commands.filter { supported.contains($0) || $0 == "ATRV" }
            guard !filtered.isEmpty else { return nil }
            let reliability = filtered.reduce(0.0) { partialResult, command in
                partialResult + (runtimeStates[command]?.successRate ?? 0.5)
            } / Double(filtered.count)
            return PTBuild68PollingRecommendation(
                tier: tier,
                commands: filtered,
                weight: baseWeight * (0.5 + reliability)
            )
        }
    }
}

// MARK: - Trace redaction

public nonisolated enum PTBuild68TraceRedactionLevel: String, Codable, Sendable {
    case none
    case standard
    case strict
}

public nonisolated enum PTBuild68TraceRedactor {
    public static func redact(_ value: String, level: PTBuild68TraceRedactionLevel = .standard) -> String {
        guard level != .none else { return String(value.prefix(4_096)) }
        var result = value
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" || $0 == "|" })
            .map { redactToken(String($0), level: level) }
            .joined(separator: " ")
        if level == .strict {
            result = redactStrictVIN(result)
        }
        return String(result.prefix(4_096))
    }

    private static func redactToken(_ token: String, level: PTBuild68TraceRedactionLevel) -> String {
        let upper = token.uppercased()
        if let range = upper.range(of: "AT+SETCRYPT") {
            return String(token[..<range.lowerBound]) + "AT+SETCRYPT<REDACTED>"
        }
        if upper.hasPrefix("CRYPT:") || upper.hasPrefix("CRYPT=") {
            return String(token.prefix(6)) + "<REDACTED>"
        }
        if let mac = maskedMAC(token) {
            return mac
        }
        if level == .strict, upper.hasPrefix("VIN:") || upper.hasPrefix("VIN=") {
            return String(token.prefix(4)) + "<REDACTED>"
        }
        return token
    }

    private static func maskedMAC(_ token: String) -> String? {
        // EN: Preserve a label such as MAC= while masking only the six address octets.
        // ES: Conserva una etiqueta como MAC= y oculta solo los seis octetos de la dirección.
        // 中文：保留 MAC= 这样的标签，只脱敏后面的六段地址。
        let separator: Character
        let addressStart: String.Index
        if let equals = token.firstIndex(of: "=") {
            addressStart = token.index(after: equals)
        } else if let colon = token.firstIndex(of: ":"), token[..<colon].count > 2 {
            addressStart = token.index(after: colon)
        } else {
            addressStart = token.startIndex
        }

        let address = String(token[addressStart...])
        if address.split(separator: ":").count == 6 { separator = ":" }
        else if address.split(separator: "-").count == 6 { separator = "-" }
        else { return nil }

        let parts = address.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 6, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isHexDigit) }) else { return nil }
        let masked = [parts[0], "**", "**", "**", "**", parts[5]].joined(separator: String(separator))
        return String(token[..<addressStart]) + masked
    }

    private static func redactStrictVIN(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)\bVIN[:=][A-Z0-9]{17}\b"#) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: "VIN=<REDACTED>")
    }
}

// MARK: - Persistent evidence

/// EN: The evidence store is bounded and uses the existing iCloud-capable persistence actor.
/// ES: El almacén de evidencia está limitado y usa el actor de persistencia existente compatible con iCloud.
/// 中文：证据存储有界，并复用现有支持 iCloud 的持久化 actor。
public actor PTBuild68EvidenceStore {
    public static let shared = PTBuild68EvidenceStore()
    public static let fileName = "PTBuild68OBDEvidence.json"
    private let maximumSessionCount = 10

    private init() {}

    public func save(_ session: PTBuild68DiagnosticSessionRecord) async throws {
        var sessions: [PTBuild68DiagnosticSessionRecord] = []
        if let data = try? await PTDataPersistenceActor.shared.readData(fileName: Self.fileName),
           let document = try? JSONDecoder().decode(PTBuild68EvidenceDocument.self, from: data) {
            sessions = document.sessions
        }
        sessions.removeAll { $0.sessionID == session.sessionID }
        sessions.append(session)
        sessions.sort { $0.startedAt > $1.startedAt }
        sessions = Array(sessions.prefix(maximumSessionCount))
        let data = try JSONEncoder().encode(PTBuild68EvidenceDocument(sessions: sessions))
        _ = try await PTDataPersistenceActor.shared.writeData(
            data,
            fileName: Self.fileName,
            revision: Int64(Date().timeIntervalSince1970 * 1_000),
            syncToICloud: true
        )
    }

    public func loadLatest() async -> PTBuild68DiagnosticSessionRecord? {
        guard let data = try? await PTDataPersistenceActor.shared.readData(fileName: Self.fileName),
              let document = try? JSONDecoder().decode(PTBuild68EvidenceDocument.self, from: data) else {
            return nil
        }
        return document.sessions.first
    }

    /// EN: Export only the bounded, redacted Build 68 document for sharing or support review.
    /// ES: Exporta solo el documento limitado y redactado de Build 68 para compartirlo o revisarlo con soporte.
    /// 中文：只导出有界且脱敏的 Build 68 文档，用于分享或支持排查。
    public func exportLatestURL() async throws -> URL? {
        guard let data = try? await PTDataPersistenceActor.shared.readData(fileName: Self.fileName),
              let document = try? JSONDecoder().decode(PTBuild68EvidenceDocument.self, from: data),
              !document.sessions.isEmpty else {
            return nil
        }
        let redacted = PTBuild68EvidenceDocument(
            schemaVersion: document.schemaVersion,
            sessions: document.sessions.map { $0.redactedForExport() }
        )
        let exportData = try JSONEncoder().encode(redacted)
        let fileName = "xp400-build68-evidence-\(Int(Date().timeIntervalSince1970)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try exportData.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Evidence bridge

/// EN: Project Build 68 session facts into the existing protocol evidence store without sending anything to the vehicle.
/// ES: Proyecta los hechos de la sesión de Build 68 al almacén de evidencia existente sin enviar nada al vehículo.
/// 中文：把 Build 68 会话事实投影到现有协议证据库，不向车辆发送任何内容。
public nonisolated enum PTBuild68EvidenceBridge {
    public static func records(
        from session: PTBuild68DiagnosticSessionRecord,
        vehicleID: UUID?,
        source: PTProtocolEvidenceSource,
        importedAt: Date = Date()
    ) -> [PTProtocolEvidenceRecord] {
        var records: [PTProtocolEvidenceRecord] = []

        func confidence(_ level: PTBuild68EvidenceLevel) -> Double {
            switch level {
            case .candidate: return 0.3
            case .probable: return 0.55
            case .captured: return 0.8
            case .repeatable: return 0.9
            case .confirmed: return 1.0
            }
        }

        func id(_ suffix: String) -> UUID {
            PTVehicleIdentityStableID.make("build68:\(session.sessionID.uuidString):\(suffix)")
        }

        func address(_ value: UInt32?) -> String? {
            value.map { String(format: "0x%03X", $0) }
        }

        let sessionValue = [
            "build=68",
            "capabilities=\(session.capability.supportedPIDs.count)",
            "dtcs=\(session.troubleCodes.count)",
            "rawResults=\(session.rawCommandResults.count)",
            "ended=\(session.endedAt != nil)"
        ].joined(separator: ";")
        records.append(
            PTProtocolEvidenceRecord(
                id: id("session"),
                domain: .obd,
                kind: .session,
                direction: .state,
                source: source,
                timestamp: session.endedAt ?? importedAt,
                confidence: session.rawCommandResults.isEmpty ? 0.35 : 0.8,
                value: sessionValue,
                referenceID: session.sessionID,
                reference: "build68-read-only",
                note: "read-only diagnostic session"
            )
        )

        for (index, evidence) in session.capability.addressEvidence.enumerated() {
            let value = [
                "role=engine",
                address(evidence.txAddress).map { "tx=\($0)" },
                address(evidence.rxAddress).map { "rx=\($0)" }
            ].compactMap { $0 }.joined(separator: " ")
            records.append(
                PTProtocolEvidenceRecord(
                    id: id("address-\(index)"),
                    domain: .obd,
                    kind: .identity,
                    direction: .state,
                    source: source,
                    timestamp: session.capability.discoveredAt ?? session.startedAt,
                    confidence: confidence(evidence.confidence),
                    value: value,
                    vehicleID: vehicleID,
                    referenceID: session.sessionID,
                    reference: "diagnostic-address",
                    note: evidence.source.rawValue
                )
            )
        }

        if let ecu = session.electronicControlUnit {
            let identityValue = [
                "role=engine",
                "rx=\(address(ecu.rxAddress) ?? "unknown")",
                address(ecu.txAddress).map { "tx=\($0)" },
                ecu.ecuName.map { "ecuName=\($0.replacingOccurrences(of: " ", with: "_"))" },
                ecu.fingerprint.map { "fingerprint=\($0)" }
            ].compactMap { $0 }.joined(separator: " ")
            records.append(
                PTProtocolEvidenceRecord(
                    id: id("ecu-identity"),
                    domain: .uds,
                    kind: .identity,
                    direction: .state,
                    source: source,
                    timestamp: ecu.capturedAt,
                    confidence: confidence(ecu.evidenceLevel),
                    value: identityValue,
                    fingerprint: ecu.fingerprint.map { "build68:\($0)" },
                    vehicleID: vehicleID,
                    referenceID: session.sessionID,
                    reference: "0904,0906,0908,090A",
                    note: "ECU identity is read-only; CALID/CVN remain in the session record"
                )
            )

            for (index, calibration) in ecu.calibrationRecords.enumerated() {
                let value = [
                    "role=engine",
                    "calibration=\(calibration.calibrationID)",
                    calibration.cvn.map { "cvn=\($0)" }
                ].compactMap { $0 }.joined(separator: " ")
                records.append(
                    PTProtocolEvidenceRecord(
                        id: id("calibration-\(index)"),
                        domain: .uds,
                        kind: .identity,
                        direction: .state,
                        source: source,
                        timestamp: ecu.capturedAt,
                        confidence: confidence(ecu.evidenceLevel),
                        value: value,
                        fingerprint: ecu.fingerprint.map { "build68:\($0)" },
                        vehicleID: vehicleID,
                        referenceID: session.sessionID,
                        reference: "0904/0906",
                        note: "CALID/CVN pair"
                    )
                )
            }
        }

        if let engine = session.engineSession {
            let value = [
                "engineStartedAt=\(engine.engineStartedAt?.timeIntervalSince1970.description ?? "unknown")",
                "obdConnectedAt=\(engine.obdConnectedAt.timeIntervalSince1970)",
                engine.engineRuntimeAtConnect.map { "runtime=\($0)" }
            ].compactMap { $0 }.joined(separator: " ")
            records.append(
                PTProtocolEvidenceRecord(
                    id: id("engine-session"),
                    domain: .obd,
                    kind: .telemetry,
                    direction: .state,
                    source: source,
                    timestamp: engine.obdConnectedAt,
                    confidence: confidence(engine.confidence),
                    value: value,
                    vehicleID: vehicleID,
                    referenceID: session.sessionID,
                    reference: "011F",
                    note: "engine start time inferred from read-only runtime"
                )
            )
        }

        let voltageValue = [
            session.voltage.adapterVoltage.map { "adapterVoltage=\($0)" },
            session.voltage.controlModuleVoltage.map { "controlModuleVoltage=\($0)" },
            session.voltage.delta.map { "delta=\($0)" }
        ].compactMap { $0 }.joined(separator: " ")
        if !voltageValue.isEmpty {
            records.append(
                PTProtocolEvidenceRecord(
                    id: id("voltage"),
                    domain: .obd,
                    kind: .telemetry,
                    direction: .state,
                    source: source,
                    timestamp: session.startedAt,
                    confidence: 0.8,
                    value: voltageValue,
                    vehicleID: vehicleID,
                    referenceID: session.sessionID,
                    reference: "0142/ATRV",
                    note: session.voltage.hasDiscrepancy ? "adapter voltage discrepancy; not a battery diagnosis" : nil
                )
            )
        }

        if let throttle = session.throttle.percent {
            records.append(
                PTProtocolEvidenceRecord(
                    id: id("throttle"),
                    domain: .obd,
                    kind: .telemetry,
                    direction: .state,
                    source: source,
                    timestamp: session.startedAt,
                    confidence: 0.8,
                    value: "throttle=\(throttle) source=\(session.throttle.source?.rawValue ?? "unknown")",
                    vehicleID: vehicleID,
                    referenceID: session.sessionID,
                    reference: "0145/0111"
                )
            )
        }

        for (index, dtc) in session.troubleCodes.enumerated() {
            records.append(
                PTProtocolEvidenceRecord(
                    id: id("dtc-\(index)-\(dtc.source.rawValue)"),
                    domain: .obd,
                    kind: .response,
                    direction: .rx,
                    source: source,
                    timestamp: dtc.lastObservedAt,
                    confidence: confidence(dtc.evidenceLevel),
                    value: "role=engine code=\(dtc.code) dtcSource=\(dtc.source.rawValue)",
                    vehicleID: vehicleID,
                    referenceID: session.sessionID,
                    reference: dtc.ecuAddress.map { String(format: "0x%03X", $0) },
                    note: "DTC evidence only; no clear command was sent"
                )
            )
        }

        for (index, result) in session.rawCommandResults.prefix(64).enumerated() {
            records.append(
                PTProtocolEvidenceRecord(
                    id: id("raw-\(index)-\(result.command)"),
                    domain: .uds,
                    kind: .response,
                    direction: .rx,
                    source: source,
                    timestamp: result.capturedAt,
                    confidence: confidence(result.evidenceLevel),
                    value: "command=\(result.command) status=\(result.status.rawValue)",
                    request: result.command,
                    response: PTBuild68TraceRedactor.redact(result.rawResponse, level: .standard),
                    vehicleID: vehicleID,
                    referenceID: session.sessionID,
                    reference: "build68-raw"
                )
            )
        }

        return records
    }
}

// MARK: - Read-only service

/// EN: All commands in this service are allow-listed standard reads and execute through the existing bus lease.
/// ES: Todos los comandos de este servicio son lecturas estándar permitidas y pasan por la concesión de bus existente.
/// 中文：该服务中的所有指令都是白名单内的标准读取，并通过现有总线租约执行。
public nonisolated final class PTBuild68ReadOnlyService {
    public static let shared = PTBuild68ReadOnlyService()

    private init() {}

    public func readRaw(command: String) async throws -> PTBuild68RawCommandResult {
        let normalized = PTBuild68CommandCatalog.normalize(command)
        guard PTBuild68CommandCatalog.isReadOnlyDeepCommand(normalized),
              PTOBDCommandClassifier.isOrdinaryReadAllowed(normalized) else {
            throw PTOBDDiagnosticError.readNotAllowed
        }
        let startedAt = Date()
        let response = try await PTAdvancedOBDCoordinator.shared.executeReadOnly {
            try Task.checkCancellation()
            return try await PTMotoTelemetryManager.shared.sendRawCommandAsync(normalized)
        }
        let endedAt = Date()
        return PTBuild68RawCommandResult(
            command: normalized,
            rawResponse: response,
            payloadHex: PTBuild68ResponseParser.payloadHex(for: normalized, response: response),
            status: PTBuild68ResponseParser.responseStatus(for: normalized, response: response),
            negativeResponseCode: PTBuild68ResponseParser.negativeResponseCode(in: response, command: normalized),
            latency: endedAt.timeIntervalSince(startedAt),
            capturedAt: endedAt
        )
    }

    public func discoverCapabilities(
        progress: (@MainActor @Sendable (Int, Int, PTBuild68CapabilityPage) -> Void)? = nil
    ) async throws -> [PTBuild68CapabilityPage] {
        let commands = PTBuild68CommandCatalog.capabilityCommands
        // EN: The denominator includes the bounded Mode 06 continuation window.
        // ES: El denominador incluye la ventana acotada de continuaciones de Mode 06.
        // 中文：进度分母包含有界的 Mode 06 continuation 窗口。
        let maximumProgress = commands.count + max(0, PTBuild68CommandCatalog.mode06CapabilityCommands.count - 1)
        return try await PTAdvancedOBDCoordinator.shared.executeReadOnly {
            var pages: [PTBuild68CapabilityPage] = []
            var dynamicCommands = ["0100", "020000", "0600", "0900"]
            var index = 0

            try Task.checkCancellation()
            if let first = try await Self.readCapabilityPage("0100") {
                pages.append(first)
                index += 1
                await progress?(min(index, maximumProgress), maximumProgress, first)
                if first.hasContinuation { dynamicCommands.insert("0120", at: 1) }
            }
            try Task.checkCancellation()
            if dynamicCommands.contains("0120"), let second = try await Self.readCapabilityPage("0120") {
                pages.append(second)
                index += 1
                await progress?(min(index, maximumProgress), maximumProgress, second)
                if second.hasContinuation { dynamicCommands.insert("0140", at: 2) }
            }
            try Task.checkCancellation()
            if dynamicCommands.contains("0140"), let third = try await Self.readCapabilityPage("0140") {
                pages.append(third)
                index += 1
                await progress?(min(index, maximumProgress), maximumProgress, third)
            }

            for command in ["020000", "0600", "0900"] {
                try Task.checkCancellation()
                guard let page = try await Self.readCapabilityPage(command) else { continue }
                pages.append(page)
                index += 1
                await progress?(min(index, maximumProgress), maximumProgress, page)
                if command == "0600", page.hasContinuation {
                    for continuation in PTBuild68CommandCatalog.mode06CapabilityCommands.dropFirst() {
                        try Task.checkCancellation()
                        guard let next = try await Self.readCapabilityPage(continuation) else { break }
                        pages.append(next)
                        index += 1
                        await progress?(min(index, maximumProgress), maximumProgress, next)
                        guard next.hasContinuation else { break }
                    }
                }
            }
            return pages
        }
    }

    public func readDTCs(
        sessionID: UUID,
        ecuAddress: UInt32? = 0x7E8
    ) async throws -> PTBuild68DTCReadBatch {
        let results = try await readBatch(commands: PTBuild68CommandCatalog.dtcCommands)
        let sources: [PTBuild68DiagnosticTroubleCodeSource] = [.confirmed, .pending, .permanent]
        var records: [PTBuild68DiagnosticTroubleCodeRecord] = []
        for (result, source) in zip(results, sources) where result.status == .success {
            records.append(contentsOf: PTBuild68ResponseParser.parseDTCs(
                response: result.rawResponse,
                source: source,
                sessionID: sessionID,
                ecuAddress: ecuAddress,
                observedAt: result.capturedAt
            ))
        }
        return PTBuild68DTCReadBatch(results: results, records: records)
    }

    public func readFreezeFrame(
        dtc: String?,
        ecuAddress: UInt32? = 0x7E8
    ) async throws -> PTBuild68FreezeFrameReadBatch {
        let commands = PTBuild68CommandCatalog.freezeFramePIDs.map { "02\($0)00" }
        let results = try await readBatch(commands: commands)
        let resultMap = Dictionary(uniqueKeysWithValues: results.map { ($0.command, $0) })
        let snapshot = PTBuild68ResponseParser.makeFreezeFrameSnapshot(
            results: resultMap,
            dtc: dtc,
            ecuAddress: ecuAddress,
            capturedAt: results.map(\.capturedAt).max() ?? Date()
        )
        return PTBuild68FreezeFrameReadBatch(results: results, snapshot: snapshot)
    }

    public func readExtendedIdentity(
        commands: [String] = PTBuild68CommandCatalog.extendedIdentityCommands,
        rxAddress: UInt32 = 0x7E8,
        txAddress: UInt32? = 0x7E0
    ) async throws -> PTBuild68IdentityReadResult {
        let normalized = commands.map(PTBuild68CommandCatalog.normalize).filter { command in
            PTBuild68CommandCatalog.extendedIdentityCommands.contains(command)
        }
        let results = try await readBatch(commands: normalized)
        let resultMap = Dictionary(uniqueKeysWithValues: results.map { ($0.command, $0) })
        let calibrationIDs = resultMap["0904"].flatMap { PTBuild68ResponseParser.parseCalibrationIDs(response: $0.rawResponse) } ?? []
        let cvns = resultMap["0906"].flatMap { PTBuild68ResponseParser.parseCVNs(response: $0.rawResponse) } ?? []
        let records = calibrationIDs.enumerated().map { index, value in
            PTBuild68CalibrationRecord(calibrationID: value, cvn: index < cvns.count ? cvns[index] : nil)
        }
        let name = resultMap["090A"].flatMap { PTBuild68ResponseParser.parseECUName(response: $0.rawResponse) }
        let performance = resultMap["0908"].flatMap { PTBuild68ResponseParser.parseInUsePerformance(response: $0.rawResponse) }
        let fingerprint = PTBuild68ResponseParser.makeFingerprint(
            rxAddress: rxAddress,
            ecuName: name,
            calibrationRecords: records
        )
        let ecu = PTBuild68ElectronicControlUnit(
            rxAddress: rxAddress,
            txAddress: txAddress,
            ecuName: name,
            calibrationRecords: records,
            inUsePerformance: performance,
            rawResponses: resultMap.mapValues(\.rawResponse),
            fingerprint: fingerprint,
            evidenceLevel: .captured,
            capturedAt: results.map(\.capturedAt).max() ?? Date()
        )
        return PTBuild68IdentityReadResult(results: results, electronicControlUnit: ecu)
    }
}

private extension PTBuild68ReadOnlyService {
    static func readCapabilityPage(_ command: String) async throws -> PTBuild68CapabilityPage? {
        try Task.checkCancellation()
        guard PTBuild68CommandCatalog.isReadOnlyDeepCommand(command),
              PTOBDCommandClassifier.isOrdinaryReadAllowed(command) else { return nil }
        let response = try await PTMotoTelemetryManager.shared.sendRawCommandAsync(command)
        return PTBuild68ResponseParser.parseCapability(command: command, response: response)
    }

    func readBatch(commands: [String]) async throws -> [PTBuild68RawCommandResult] {
        try await PTAdvancedOBDCoordinator.shared.executeReadOnly {
            var results: [PTBuild68RawCommandResult] = []
            results.reserveCapacity(commands.count)
            for command in commands {
                try Task.checkCancellation()
                let normalized = PTBuild68CommandCatalog.normalize(command)
                guard PTBuild68CommandCatalog.isReadOnlyDeepCommand(normalized),
                      PTOBDCommandClassifier.isOrdinaryReadAllowed(normalized) else {
                    throw PTOBDDiagnosticError.readNotAllowed
                }
                let startedAt = Date()
                let response = try await PTMotoTelemetryManager.shared.sendRawCommandAsync(normalized)
                let capturedAt = Date()
                results.append(
                    PTBuild68RawCommandResult(
                        command: normalized,
                        rawResponse: response,
                        payloadHex: PTBuild68ResponseParser.payloadHex(for: normalized, response: response),
                        status: PTBuild68ResponseParser.responseStatus(for: normalized, response: response),
                        negativeResponseCode: PTBuild68ResponseParser.negativeResponseCode(in: response, command: normalized),
                        latency: capturedAt.timeIntervalSince(startedAt),
                        capturedAt: capturedAt
                    )
                )
            }
            return results
        }
    }
}

// MARK: - Build 68 coordinator

/// EN: Coordinates Build 68 around the stable manager; it never owns BLE, ELM327, or polling transport.
/// ES: Coordina Build 68 alrededor del gestor estable; nunca posee BLE, ELM327 ni el transporte de sondeo.
/// 中文：围绕稳定管理器协调 Build 68，不拥有 BLE、ELM327 或轮询传输层。
@MainActor
public final class PTBuild68DiagnosticCoordinator: NSObject, PTMotoTelemetryDelegate {
    public static let shared = PTBuild68DiagnosticCoordinator()
    public static let didChange = Notification.Name("PTBuild68DiagnosticCoordinator.didChange")

    public private(set) var latestSession: PTBuild68DiagnosticSessionRecord?
    public private(set) var latestMonitorStatus: PTBuild68MonitorStatus?
    public private(set) var latestVoltage = PTBuild68VoltageSnapshot()
    public private(set) var latestThrottle = PTBuild68ThrottleSnapshot()
    public private(set) var latestPollingRecommendations: [PTBuild68PollingRecommendation] = []
    public private(set) var lastPersistenceError: String?

    private var hasStarted = false
    private var sessionID: UUID?
    private var sessionStartedAt: Date?
    private var discoveryTask: Task<Void, Never>?
    private var dtcTask: Task<Void, Never>?
    private var automaticDTCReadStarted = false
    private var lastAutomaticDTCReadAt: Date?
    private var capability = PTBuild68CapabilityProfile()
    private var troubleCodes: [PTBuild68DiagnosticTroubleCodeRecord] = []
    private var freezeFrame: PTBuild68FreezeFrameSnapshot?
    private var electronicControlUnit: PTBuild68ElectronicControlUnit?
    private var engineSession: PTBuild68EngineSessionMetadata?
    private var runtimeStates: [String: PTBuild68PIDRuntimeState] = [:]
    private var rawCommandResults: [PTBuild68RawCommandResult] = []
    private var engineRuntimeSamples: [(date: Date, runtime: TimeInterval)] = []
    private var baselineBuckets: [PTBuild68BaselinePhase: [String: [Double]]] = [:]
    private var previousSpeed: Double?
    private var lastUnifiedIngestAt: Date?

    private override init() {
        super.init()
    }

    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        if PTMotoTelemetryManager.shared.isConnected {
            beginSession()
        }
        PTMotoTelemetryManager.shared.addDelegate(self)
        Task { @MainActor [weak self] in
            guard let self, self.latestSession == nil else { return }
            self.latestSession = await PTBuild68EvidenceStore.shared.loadLatest()
            self.publishChange()
        }
    }

    public func runManualReadOnlyDiagnostic() async throws -> PTBuild68DiagnosticSessionRecord {
        guard PTMotoTelemetryManager.shared.isConnected else {
            throw PTOBDDiagnosticError.disconnected
        }
        if sessionID == nil { beginSession() }
        guard let sessionID else { throw PTOBDDiagnosticError.disconnected }
        let batch = try await PTBuild68ReadOnlyService.shared.readDTCs(sessionID: sessionID)
        apply(batch.results)
        troubleCodes = batch.records
        if !batch.records.isEmpty, PTBuild68FeatureFlags.enableFreezeFrameAutoRead {
            let freezeBatch = try await PTBuild68ReadOnlyService.shared.readFreezeFrame(dtc: batch.records.first?.code)
            apply(freezeBatch.results)
            freezeFrame = freezeBatch.snapshot
        }
        persistCurrentSession()
        return makeSessionRecord()
    }

    public nonisolated func telemetryManager(_ manager: PTMotoTelemetryManager, didChangeConnectionState isConnected: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if isConnected { self.beginSession() }
            else { self.finishSession() }
        }
    }

    public nonisolated func telemetryManager(_ manager: PTMotoTelemetryManager, didDiscoverSupportedCommands commands: [String]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.sessionID == nil { self.beginSession() }
            self.capability.mergeSupportedCommands(commands)
            self.capability.addAddressEvidence(
                PTBuild68DiagnosticAddressEvidence(
                    rxAddress: 0x7E8,
                    confidence: .captured,
                    source: .capturedCAN
                )
            )
            self.capability.addAddressEvidence(
                PTBuild68DiagnosticAddressEvidence(
                    txAddress: 0x7E0,
                    rxAddress: 0x7E8,
                    confidence: .probable,
                    source: .capturedCAN
                )
            )
            self.updatePollingRecommendations()
            self.publishChange()
        }
    }

    public nonisolated func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateMeasurements measurements: [String: Any]) {
        Task { @MainActor [weak self] in
            self?.ingest(measurements: measurements)
        }
    }
}

private extension PTBuild68DiagnosticCoordinator {
    func beginSession() {
        discoveryTask?.cancel()
        dtcTask?.cancel()
        sessionID = UUID()
        sessionStartedAt = Date()
        capability = PTBuild68CapabilityProfile()
        troubleCodes.removeAll(keepingCapacity: true)
        freezeFrame = nil
        electronicControlUnit = nil
        engineSession = nil
        latestMonitorStatus = nil
        latestVoltage = PTBuild68VoltageSnapshot()
        latestThrottle = PTBuild68ThrottleSnapshot()
        runtimeStates.removeAll(keepingCapacity: true)
        rawCommandResults.removeAll(keepingCapacity: true)
        engineRuntimeSamples.removeAll(keepingCapacity: true)
        baselineBuckets.removeAll(keepingCapacity: true)
        previousSpeed = nil
        automaticDTCReadStarted = false
        lastAutomaticDTCReadAt = nil
        scheduleDiscovery()
        publishChange()
    }

    func finishSession() {
        discoveryTask?.cancel()
        dtcTask?.cancel()
        discoveryTask = nil
        dtcTask = nil
        guard sessionID != nil else { return }
        persistCurrentSession(endedAt: Date())
        sessionID = nil
    }

    func scheduleDiscovery() {
        guard PTBuild68FeatureFlags.enableMode09ExtendedIdentity || PTBuild68FeatureFlags.enableMode06DeepDiscovery else { return }
        guard let expectedSessionID = sessionID else { return }
        discoveryTask?.cancel()
        discoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self, self.sessionID == expectedSessionID else { return }
            await self.runDiscovery(sessionID: expectedSessionID)
        }
    }

    func runDiscovery(sessionID: UUID) async {
        guard self.sessionID == sessionID else { return }
        do {
            let pages = try await PTBuild68ReadOnlyService.shared.discoverCapabilities()
            guard self.sessionID == sessionID else { return }
            pages.forEach { capability.merge($0) }
            apply(
                pages.map {
                    PTBuild68RawCommandResult(
                        command: $0.command,
                        rawResponse: $0.rawResponse,
                        payloadHex: PTBuild68ResponseParser.payloadHex(for: $0.command, response: $0.rawResponse),
                        status: $0.status,
                        latency: nil,
                        capturedAt: $0.capturedAt
                    )
                }
            )
            updatePollingRecommendations()

            if PTBuild68FeatureFlags.enableMode09ExtendedIdentity {
                let commands = PTBuild68CommandCatalog.extendedIdentityCommands.filter {
                    capability.mode09PIDs.contains($0)
                }
                if !commands.isEmpty {
                    let identity = try await PTBuild68ReadOnlyService.shared.readExtendedIdentity(commands: commands)
                    guard self.sessionID == sessionID else { return }
                    electronicControlUnit = identity.electronicControlUnit
                    apply(identity.results)
                }
            }
            persistCurrentSession()
        } catch is CancellationError {
            return
        } catch {
            lastPersistenceError = error.localizedDescription
            publishChange()
        }
    }

    func ingest(measurements: [String: Any]) {
        guard PTMotoTelemetryManager.shared.isConnected else { return }
        if sessionID == nil { beginSession() }
        let now = Date()

        for (key, value) in measurements {
            let command = PTBuild68CommandCatalog.normalize(key)
            guard command.count >= 2, PTBuild68CommandCatalog.isReadOnlyDeepCommand(command) else { continue }
            if let number = PTBuild68ResponseParser.doubleValue(value), number.isFinite {
                // EN: The legacy delegate exposes successful values, but not per-request failures; do not invent failures here.
                // ES: El delegado heredado expone valores exitosos, pero no fallos por solicitud; no inventamos fallos aquí.
                // 中文：旧代理只暴露成功值而不暴露逐请求失败，因此这里不伪造失败统计。
                // EN: Zero is a valid OBD value (for example a stopped vehicle speed); retain it as success.
                // ES: Cero es un valor OBD válido (por ejemplo, velocidad con el vehículo detenido); se conserva como éxito.
                // 中文：0 是合法的 OBD 数值（例如停车时的车速），必须记录为成功。
                var state = runtimeStates[command] ?? PTBuild68PIDRuntimeState()
                state.recordSuccess(at: now)
                runtimeStates[command] = state
            }
        }

        if let status = measurements["0101"] as? PTVehicleStatus0101 {
            processMonitorStatus(
                PTBuild68MonitorStatus(
                    isMILOn: status.isMILOn,
                    confirmedDTCCount: status.dtcCount,
                    rawBytes: [],
                    capturedAt: now
                )
            )
        } else if let raw = measurements["0101"] as? String,
                  let status = PTBuild68ResponseParser.parseMonitorStatus0101(response: raw, capturedAt: now) {
            processMonitorStatus(status)
        }

        // EN: Runtime zero is ambiguous during connect and must not fabricate an engine start timestamp.
        // ES: Un tiempo de funcionamiento cero es ambiguo durante la conexión y no debe fabricar una hora de arranque.
        // 中文：连接初期的 runtime=0 语义不明确，不能据此伪造发动机启动时间。
        if let runtime = PTBuild68ResponseParser.doubleValue(measurements["011F"]), runtime.isFinite, runtime > 0 {
            processEngineRuntime(runtime, at: now)
        }

        let controlModuleVoltage = PTBuild68ResponseParser.doubleValue(measurements["0142"])
        let adapterVoltage = PTBuild68ResponseParser.doubleValue(measurements["ATRV"])
        if controlModuleVoltage != nil || adapterVoltage != nil {
            latestVoltage = PTBuild68VoltageSnapshot(
                adapterVoltage: adapterVoltage ?? latestVoltage.adapterVoltage,
                controlModuleVoltage: controlModuleVoltage ?? latestVoltage.controlModuleVoltage
            )
        }

        let relativeThrottle = PTBuild68ResponseParser.doubleValue(measurements["0145"])
        let absoluteThrottle = PTBuild68ResponseParser.doubleValue(measurements["0111"])
        if relativeThrottle != nil || absoluteThrottle != nil {
            latestThrottle = PTBuild68ResponseParser.preferredThrottle(
                relative: relativeThrottle,
                absolute: absoluteThrottle
            )
        }

        ingestBaseline(measurements: measurements)
        ingestUnifiedTelemetry(measurements: measurements, at: now)
        updatePollingRecommendations()
    }

    func processMonitorStatus(_ status: PTBuild68MonitorStatus) {
        latestMonitorStatus = status
        guard status.confirmedDTCCount > 0,
              PTBuild68FeatureFlags.enableAutomaticDTCScan,
              !automaticDTCReadStarted else {
            publishChange()
            return
        }
        if let lastAutomaticDTCReadAt, Date().timeIntervalSince(lastAutomaticDTCReadAt) < 60 {
            return
        }
        automaticDTCReadStarted = true
        lastAutomaticDTCReadAt = Date()
        guard let expectedSessionID = sessionID else { return }
        dtcTask?.cancel()
        dtcTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let batch = try await PTBuild68ReadOnlyService.shared.readDTCs(sessionID: expectedSessionID)
                guard self.sessionID == expectedSessionID else { return }
                self.apply(batch.results)
                self.troubleCodes = batch.records
                if !batch.records.isEmpty, PTBuild68FeatureFlags.enableFreezeFrameAutoRead {
                    let freezeBatch = try await PTBuild68ReadOnlyService.shared.readFreezeFrame(dtc: batch.records.first?.code)
                    guard self.sessionID == expectedSessionID else { return }
                    self.apply(freezeBatch.results)
                    self.freezeFrame = freezeBatch.snapshot
                }
                self.persistCurrentSession()
            } catch is CancellationError {
                return
            } catch {
                self.lastPersistenceError = error.localizedDescription
                self.publishChange()
            }
            self.dtcTask = nil
        }
    }

    func processEngineRuntime(_ runtime: TimeInterval, at date: Date) {
        guard runtime.isFinite, runtime > 0 else { return }
        engineRuntimeSamples.append((date: date, runtime: runtime))
        engineRuntimeSamples = Array(engineRuntimeSamples.suffix(3))
        guard let connectedAt = sessionStartedAt else { return }
        let inferredStart = date.addingTimeInterval(-runtime)
        let confidence: PTBuild68EvidenceLevel
        if engineRuntimeSamples.count >= 2 {
            let starts = engineRuntimeSamples.map { $0.date.addingTimeInterval(-$0.runtime) }
            let spread = (starts.max() ?? inferredStart).timeIntervalSince(starts.min() ?? inferredStart)
            confidence = spread <= 2 ? .confirmed : .probable
        } else {
            confidence = .probable
        }
        let metadata = PTBuild68EngineSessionMetadata(
            engineStartedAt: inferredStart,
            obdConnectedAt: connectedAt,
            engineRuntimeAtConnect: max(0, connectedAt.timeIntervalSince(inferredStart)),
            confidence: confidence
        )
        engineSession = metadata
        PTTripManager.shared.recordEngineSessionMetadata(metadata)
    }

    func ingestUnifiedTelemetry(measurements: [String: Any], at date: Date) {
        guard lastUnifiedIngestAt.map({ date.timeIntervalSince($0) >= 0.2 }) ?? true else { return }
        let source: PTVehicleTelemetrySource = PTVehicleConnectivityCoordinator.shared.snapshot.obd.transport == .obdMock ? .obdMock : .obd
        var observations: [PTVehicleTelemetryObservation] = []
        if let coolant = PTBuild68ResponseParser.doubleValue(measurements["0105"]) {
            observations.append(PTVehicleTelemetryObservation(signal: .engineTemperature, value: .double(coolant), source: source, capturedAt: date))
        }
        if let controlVoltage = latestVoltage.controlModuleVoltage {
            observations.append(PTVehicleTelemetryObservation(signal: .controlModuleVoltage, value: .double(controlVoltage), source: source, capturedAt: date))
            observations.append(PTVehicleTelemetryObservation(signal: .batteryVoltage, value: .double(controlVoltage), source: source, capturedAt: date))
        }
        if let adapterVoltage = latestVoltage.adapterVoltage {
            observations.append(PTVehicleTelemetryObservation(signal: .adapterVoltage, value: .double(adapterVoltage), source: source, capturedAt: date))
        }
        if let throttle = latestThrottle.percent {
            observations.append(PTVehicleTelemetryObservation(signal: .throttlePercent, value: .double(throttle), source: source, capturedAt: date))
        }
        guard !observations.isEmpty else { return }
        lastUnifiedIngestAt = date
        PTVehicleTelemetryBridge.shared.ingest(observations: observations, at: date)
    }

    func ingestBaseline(measurements: [String: Any]) {
        let speed = PTBuild68ResponseParser.doubleValue(measurements["010D"])
        let coolant = PTBuild68ResponseParser.doubleValue(measurements["0105"])
        guard let speed, speed.isFinite, let coolant, coolant.isFinite else { return }
        let phase: PTBuild68BaselinePhase
        if speed <= 0.5 {
            phase = coolant < 60 ? .coldIdle : .warmIdle
        } else if let previousSpeed, speed - previousSpeed >= 3 {
            phase = .acceleration
        } else if let previousSpeed, previousSpeed - speed >= 3 {
            phase = .deceleration
        } else if (30...50).contains(speed) {
            phase = .cruise30To50
        } else if (50...70).contains(speed) {
            phase = .cruise50To70
        } else {
            previousSpeed = speed
            return
        }
        previousSpeed = speed

        let signals = ["010C", "010B", "0104", "0106", "0107", "0114", "010F", "0142", "ATRV", "0111", "0145"]
        for command in signals {
            guard let value = PTBuild68ResponseParser.doubleValue(measurements[command]), value.isFinite else { continue }
            var phaseValues = baselineBuckets[phase] ?? [:]
            var values = phaseValues[command] ?? []
            values.append(value)
            phaseValues[command] = Array(values.suffix(512))
            baselineBuckets[phase] = phaseValues
        }
    }

    func apply(_ results: [PTBuild68RawCommandResult]) {
        rawCommandResults.append(contentsOf: results)
        rawCommandResults = Array(rawCommandResults.suffix(128))
        for result in results {
            var state = runtimeStates[result.command] ?? PTBuild68PIDRuntimeState()
            if result.status == .success {
                state.recordSuccess(latency: result.latency, at: result.capturedAt)
            } else {
                state.recordFailure(at: result.capturedAt)
            }
            runtimeStates[result.command] = state
        }
        updatePollingRecommendations()
    }

    func updatePollingRecommendations() {
        guard PTBuild68FeatureFlags.enableAdaptivePollingV2 else {
            latestPollingRecommendations = []
            return
        }
        latestPollingRecommendations = PTBuild68AdaptivePollScheduler.recommendations(
            supportedCommands: capability.supportedPIDs + PTBuild68CommandCatalog.extendedIdentityCommands,
            runtimeStates: runtimeStates
        )
    }

    func makeSessionRecord(endedAt: Date? = nil) -> PTBuild68DiagnosticSessionRecord {
        let baselines = Dictionary(uniqueKeysWithValues: baselineBuckets.map { phase, values in
            (phase.rawValue, values.mapValues(PTBuild68SignalBaseline.init(values:)))
        })
        return PTBuild68DiagnosticSessionRecord(
            sessionID: sessionID ?? UUID(),
            startedAt: sessionStartedAt ?? Date(),
            endedAt: endedAt,
            capability: capability,
            monitorStatus: latestMonitorStatus,
            troubleCodes: troubleCodes,
            freezeFrame: freezeFrame,
            electronicControlUnit: electronicControlUnit,
            engineSession: engineSession,
            voltage: latestVoltage,
            throttle: latestThrottle,
            baselines: baselines,
            pidRuntime: runtimeStates,
            rawCommandResults: rawCommandResults
        )
    }

    func persistCurrentSession(endedAt: Date? = nil) {
        let record = makeSessionRecord(endedAt: endedAt)
        latestSession = record
        let vehicleID = PTMotorcycleGarageStore.shared.selectedVehicleID
        let evidenceSource: PTProtocolEvidenceSource =
            PTVehicleConnectivityCoordinator.shared.snapshot.obd.transport == .obdMock ? .mock : .live
        // EN: Keep the rich session in the bounded evidence file and project a read-only summary into the Passport evidence store.
        // ES: Conserva la sesión completa en el archivo limitado y proyecta un resumen de solo lectura al almacén Passport.
        // 中文：完整会话保存到有界证据文件，同时把只读摘要投影到 Passport 证据库。
        _ = PTProtocolEvidenceV2Store.shared.merge(
            PTBuild68EvidenceBridge.records(
                from: record,
                vehicleID: vehicleID,
                source: evidenceSource
            )
        )
        Task { @MainActor [weak self, record] in
            do {
                try await PTBuild68EvidenceStore.shared.save(record)
            } catch {
                self?.lastPersistenceError = error.localizedDescription
                self?.publishChange()
            }
        }
        publishChange()
    }

    func publishChange() {
        NotificationCenter.default.post(
            name: Self.didChange,
            object: self,
            userInfo: ["session": latestSession as Any]
        )
    }
}
