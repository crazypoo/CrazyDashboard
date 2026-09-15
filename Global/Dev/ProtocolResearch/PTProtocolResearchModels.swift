//
//  PTProtocolResearchModels.swift
//  CrazyDashboard
//
//  EN: Build 63 value models describe repeatable protocol research without creating executable vehicle commands.
//  ES: Los modelos de valor de Build 63 describen investigación repetible sin crear comandos ejecutables del vehículo.
//  中文：Build 63 值模型用于描述可重复的协议研究，不会创建可执行的车辆指令。
//

import CryptoKit
import Foundation

public nonisolated enum PTVehicleResearchEvent: String, Codable, CaseIterable, Identifiable, Sendable {
    case leftIndicator
    case rightIndicator
    case hazard
    case highBeam
    case brake
    case sideStand
    case ignition
    case tcsMode
    case absState
    case engineRunning
    case rideMode
    case fuelChange

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .leftIndicator: return "Left indicator"
        case .rightIndicator: return "Right indicator"
        case .hazard: return "Hazard lights"
        case .highBeam: return "High beam"
        case .brake: return "Brake"
        case .sideStand: return "Side stand"
        case .ignition: return "Ignition"
        case .tcsMode: return "TCS mode"
        case .absState: return "ABS state"
        case .engineRunning: return "Engine running"
        case .rideMode: return "Ride mode"
        case .fuelChange: return "Fuel change"
        }
    }
}

public nonisolated enum PTCANExperimentStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case collecting
    case analyzed
    case archived
}

/// EN: A trial points to an existing capture and never starts a transport operation.
/// ES: Un ensayo apunta a una captura existente y nunca inicia una operación de transporte.
/// 中文：Trial 只引用已有抓包，不会启动任何传输操作。
public nonisolated struct PTCANExperimentTrial: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let captureID: UUID
    public let sessionID: UUID?
    public let activationMarkerID: UUID?
    public let deactivationMarkerID: UUID?
    public let controlWindow: ClosedRange<TimeInterval>?
    public let source: PTProtocolEvidenceSource
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case captureID
        case sessionID
        case activationMarkerID
        case deactivationMarkerID
        case controlWindowStart
        case controlWindowEnd
        case source
        case createdAt
    }

    public init(
        id: UUID = UUID(),
        captureID: UUID,
        sessionID: UUID? = nil,
        activationMarkerID: UUID? = nil,
        deactivationMarkerID: UUID? = nil,
        controlWindow: ClosedRange<TimeInterval>? = nil,
        source: PTProtocolEvidenceSource = .live,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.captureID = captureID
        self.sessionID = sessionID
        self.activationMarkerID = activationMarkerID
        self.deactivationMarkerID = deactivationMarkerID
        if let controlWindow, controlWindow.lowerBound <= controlWindow.upperBound {
            self.controlWindow = controlWindow
        } else {
            self.controlWindow = nil
        }
        self.source = source
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        captureID = try container.decode(UUID.self, forKey: .captureID)
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID)
        activationMarkerID = try container.decodeIfPresent(UUID.self, forKey: .activationMarkerID)
        deactivationMarkerID = try container.decodeIfPresent(UUID.self, forKey: .deactivationMarkerID)
        if let lower = try container.decodeIfPresent(TimeInterval.self, forKey: .controlWindowStart),
           let upper = try container.decodeIfPresent(TimeInterval.self, forKey: .controlWindowEnd),
           lower <= upper {
            controlWindow = lower...upper
        } else {
            controlWindow = nil
        }
        source = try container.decodeIfPresent(PTProtocolEvidenceSource.self, forKey: .source) ?? .live
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(captureID, forKey: .captureID)
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(activationMarkerID, forKey: .activationMarkerID)
        try container.encodeIfPresent(deactivationMarkerID, forKey: .deactivationMarkerID)
        try container.encodeIfPresent(controlWindow?.lowerBound, forKey: .controlWindowStart)
        try container.encodeIfPresent(controlWindow?.upperBound, forKey: .controlWindowEnd)
        try container.encode(source, forKey: .source)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

public nonisolated struct PTCANExperiment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let vehicleID: UUID
    public let name: String
    public let targetEvent: PTVehicleResearchEvent
    public let trials: [PTCANExperimentTrial]
    public let createdAt: Date
    public let updatedAt: Date
    public let status: PTCANExperimentStatus

    public init(
        id: UUID = UUID(),
        vehicleID: UUID,
        name: String,
        targetEvent: PTVehicleResearchEvent,
        trials: [PTCANExperimentTrial] = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        status: PTCANExperimentStatus = .draft
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        self.targetEvent = targetEvent
        self.trials = Array(trials.prefix(256))
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.status = status
    }

    public func adding(_ trial: PTCANExperimentTrial, status: PTCANExperimentStatus = .collecting) -> PTCANExperiment {
        PTCANExperiment(
            id: id,
            vehicleID: vehicleID,
            name: name,
            targetEvent: targetEvent,
            trials: trials + [trial],
            createdAt: createdAt,
            updatedAt: Date(),
            status: status
        )
    }
}

public nonisolated struct PTCANCandidateKey: Codable, Equatable, Hashable, Sendable {
    public let header: String
    public let byteIndex: Int
    public let bitIndex: Int?

    public init(header: String, byteIndex: Int, bitIndex: Int?) {
        self.header = header
            .replacingOccurrences(of: "0x", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        self.byteIndex = max(0, byteIndex)
        if let bitIndex, (0...7).contains(bitIndex) {
            self.bitIndex = bitIndex
        } else {
            self.bitIndex = nil
        }
    }

    public var stableID: String {
        "\(header):b\(byteIndex):bit\(bitIndex.map(String.init) ?? "byte")"
    }
}

public nonisolated enum PTProtocolConfidence: String, Codable, CaseIterable, Sendable {
    case unknown
    case observed
    case repeatable
    case capturedRepeatable
    case humanConfirmed

    public var score: Double {
        switch self {
        case .unknown: return 0
        case .observed: return 0.35
        case .repeatable: return 0.65
        case .capturedRepeatable: return 0.85
        case .humanConfirmed: return 1
        }
    }

    public static func from(score: Double) -> PTProtocolConfidence {
        switch score {
        case 0.9...: return .humanConfirmed
        case 0.75..<0.9: return .capturedRepeatable
        case 0.5..<0.75: return .repeatable
        case 0.1..<0.5: return .observed
        default: return .unknown
        }
    }
}

public nonisolated enum PTSignalTransport: String, Codable, CaseIterable, Sendable {
    case can
    case xp400BLE
    case obd
    case unifiedTelemetry
}

public nonisolated enum PTSignalEncoding: String, Codable, CaseIterable, Sendable {
    case boolean
    case unsignedInteger
    case signedInteger
    case scaled
    case enumeration
}

public nonisolated enum PTSignalDefinitionStatus: String, Codable, CaseIterable, Sendable {
    case candidate
    case probable
    case confirmed
    case deprecated
    case rejected
}

public nonisolated struct PTCANFalsePositiveReport: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let key: PTCANCandidateKey
    public let backgroundFrameCount: Int
    public let backgroundComparisons: Int
    public let backgroundChanges: Int
    public let mutationRate: Double
    public let backgroundIsolation: Double
    public let confidenceAdjustment: Double

    public init(
        id: UUID = UUID(),
        key: PTCANCandidateKey,
        backgroundFrameCount: Int,
        backgroundComparisons: Int,
        backgroundChanges: Int,
        mutationRate: Double,
        backgroundIsolation: Double,
        confidenceAdjustment: Double
    ) {
        self.id = id
        self.key = key
        self.backgroundFrameCount = max(0, backgroundFrameCount)
        self.backgroundComparisons = max(0, backgroundComparisons)
        self.backgroundChanges = max(0, backgroundChanges)
        self.mutationRate = PTProtocolResearchMath.clamp(mutationRate)
        self.backgroundIsolation = PTProtocolResearchMath.clamp(backgroundIsolation)
        self.confidenceAdjustment = PTProtocolResearchMath.clamp(confidenceAdjustment)
    }
}

public nonisolated struct PTCANCandidateStatistic: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let experimentID: UUID
    public let key: PTCANCandidateKey
    public let activationTrials: Int
    public let activationHits: Int
    public let deactivationTrials: Int
    public let deactivationHits: Int
    public let backgroundChanges: Int
    public let backgroundComparisons: Int
    public let medianDelay: TimeInterval?
    public let p95Delay: TimeInterval?
    public let sessions: Int
    public let confidence: Double
    public let score: Int
    public let temporalProximity: Double
    public let backgroundIsolation: Double
    public let crossSessionRepeatability: Double
    public let sourceCorrelation: Double
    public let status: PTSignalDefinitionStatus
    public let evidenceIDs: [UUID]

    public init(
        id: UUID = UUID(),
        experimentID: UUID,
        key: PTCANCandidateKey,
        activationTrials: Int,
        activationHits: Int,
        deactivationTrials: Int,
        deactivationHits: Int,
        backgroundChanges: Int,
        backgroundComparisons: Int,
        medianDelay: TimeInterval?,
        p95Delay: TimeInterval?,
        sessions: Int,
        confidence: Double,
        score: Int,
        temporalProximity: Double,
        backgroundIsolation: Double,
        crossSessionRepeatability: Double,
        sourceCorrelation: Double,
        status: PTSignalDefinitionStatus = .candidate,
        evidenceIDs: [UUID] = []
    ) {
        self.id = id
        self.experimentID = experimentID
        self.key = key
        self.activationTrials = max(0, activationTrials)
        self.activationHits = min(max(0, activationHits), self.activationTrials)
        self.deactivationTrials = max(0, deactivationTrials)
        self.deactivationHits = min(max(0, deactivationHits), self.deactivationTrials)
        self.backgroundChanges = max(0, backgroundChanges)
        self.backgroundComparisons = max(0, backgroundComparisons)
        self.medianDelay = medianDelay.map { max(0, $0) }
        self.p95Delay = p95Delay.map { max(0, $0) }
        self.sessions = max(0, sessions)
        self.confidence = PTProtocolResearchMath.clamp(confidence)
        self.score = min(max(0, score), 100)
        self.temporalProximity = PTProtocolResearchMath.clamp(temporalProximity)
        self.backgroundIsolation = PTProtocolResearchMath.clamp(backgroundIsolation)
        self.crossSessionRepeatability = PTProtocolResearchMath.clamp(crossSessionRepeatability)
        self.sourceCorrelation = PTProtocolResearchMath.clamp(sourceCorrelation)
        self.status = status
        self.evidenceIDs = Array(Set(evidenceIDs)).sorted { $0.uuidString < $1.uuidString }
    }

    public var activationConsistency: Double {
        PTProtocolResearchMath.ratio(activationHits, activationTrials)
    }

    public var deactivationConsistency: Double {
        PTProtocolResearchMath.ratio(deactivationHits, deactivationTrials)
    }
}

public nonisolated struct PTCANCandidateGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let key: PTCANCandidateKey
    public let experimentIDs: [UUID]
    public let statisticIDs: [UUID]
    public let bestScore: Int
    public let status: PTSignalDefinitionStatus

    public init(
        id: UUID = UUID(),
        key: PTCANCandidateKey,
        experimentIDs: [UUID],
        statisticIDs: [UUID],
        bestScore: Int,
        status: PTSignalDefinitionStatus = .candidate
    ) {
        self.id = id
        self.key = key
        self.experimentIDs = Array(Set(experimentIDs)).sorted { $0.uuidString < $1.uuidString }
        self.statisticIDs = Array(Set(statisticIDs)).sorted { $0.uuidString < $1.uuidString }
        self.bestScore = min(max(0, bestScore), 100)
        self.status = status
    }
}

public nonisolated struct PTCANExperimentAnalysisReport: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let experimentID: UUID
    public let vehicleID: UUID
    public let targetEvent: PTVehicleResearchEvent
    public let generatedAt: Date
    public let statistics: [PTCANCandidateStatistic]
    public let groups: [PTCANCandidateGroup]
    public let falsePositives: [PTCANFalsePositiveReport]

    public init(
        id: UUID = UUID(),
        experimentID: UUID,
        vehicleID: UUID,
        targetEvent: PTVehicleResearchEvent,
        generatedAt: Date = Date(),
        statistics: [PTCANCandidateStatistic],
        groups: [PTCANCandidateGroup],
        falsePositives: [PTCANFalsePositiveReport]
    ) {
        self.id = id
        self.experimentID = experimentID
        self.vehicleID = vehicleID
        self.targetEvent = targetEvent
        self.generatedAt = generatedAt
        self.statistics = statistics.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.key.stableID < rhs.key.stableID
        }
        self.groups = groups.sorted { $0.key.stableID < $1.key.stableID }
        self.falsePositives = falsePositives.sorted { $0.key.stableID < $1.key.stableID }
    }
}

public nonisolated struct PTVehicleSignalDefinition: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let vehicleModel: String
    public let transport: PTSignalTransport
    public let frameIdentifier: String
    public let byteIndex: Int
    public let bitIndex: Int?
    public let encoding: PTSignalEncoding
    public let confidence: PTProtocolConfidence
    public let evidenceIDs: [UUID]
    public let status: PTSignalDefinitionStatus
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        name: String,
        vehicleModel: String,
        transport: PTSignalTransport,
        frameIdentifier: String,
        byteIndex: Int,
        bitIndex: Int?,
        encoding: PTSignalEncoding,
        confidence: PTProtocolConfidence,
        evidenceIDs: [UUID],
        status: PTSignalDefinitionStatus = .candidate,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = String(id.prefix(160))
        self.name = String(name.prefix(160))
        self.vehicleModel = String(vehicleModel.prefix(160))
        self.transport = transport
        self.frameIdentifier = String(frameIdentifier.prefix(32)).uppercased()
        self.byteIndex = max(0, byteIndex)
        self.bitIndex = bitIndex.flatMap { (0...7).contains($0) ? $0 : nil }
        self.encoding = encoding
        self.confidence = confidence
        self.evidenceIDs = Array(Set(evidenceIDs)).sorted { $0.uuidString < $1.uuidString }
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public func changingStatus(to newStatus: PTSignalDefinitionStatus, at date: Date = Date()) -> PTVehicleSignalDefinition {
        PTVehicleSignalDefinition(
            id: id,
            name: name,
            vehicleModel: vehicleModel,
            transport: transport,
            frameIdentifier: frameIdentifier,
            byteIndex: byteIndex,
            bitIndex: bitIndex,
            encoding: encoding,
            confidence: confidence,
            evidenceIDs: evidenceIDs,
            status: newStatus,
            createdAt: createdAt,
            updatedAt: date
        )
    }
}

public nonisolated struct PTVehicleSignalCatalog: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public private(set) var definitions: [PTVehicleSignalDefinition]

    public init(definitions: [PTVehicleSignalDefinition] = []) {
        schemaVersion = Self.currentSchemaVersion
        self.definitions = definitions.sorted { $0.id < $1.id }
    }

    public func definition(for id: String) -> PTVehicleSignalDefinition? {
        definitions.first { $0.id == id }
    }

    /// EN: Discovery can only insert a candidate; confirmation is an explicit human decision.
    /// ES: Discovery solo puede insertar un candidato; la confirmación es una decisión humana explícita.
    /// 中文：自动发现只能插入候选，确认必须由用户显式决定。
    public mutating func insertCandidate(_ definition: PTVehicleSignalDefinition) {
        guard definition.status == .candidate else { return }
        if let index = definitions.firstIndex(where: { $0.id == definition.id }) {
            let existing = definitions[index]
            let mergedEvidence = Array(Set(existing.evidenceIDs + definition.evidenceIDs)).sorted { $0.uuidString < $1.uuidString }
            definitions[index] = PTVehicleSignalDefinition(
                id: existing.id,
                name: existing.name,
                vehicleModel: existing.vehicleModel,
                transport: existing.transport,
                frameIdentifier: existing.frameIdentifier,
                byteIndex: existing.byteIndex,
                bitIndex: existing.bitIndex,
                encoding: existing.encoding,
                confidence: max(existing.confidence.score, definition.confidence.score) >= 0.85 ? .capturedRepeatable : existing.confidence,
                evidenceIDs: mergedEvidence,
                status: existing.status,
                createdAt: existing.createdAt,
                updatedAt: Date()
            )
        } else {
            definitions.append(definition)
            definitions.sort { $0.id < $1.id }
        }
    }

    @discardableResult
    public mutating func setStatus(_ status: PTSignalDefinitionStatus, for id: String) -> Bool {
        guard let index = definitions.firstIndex(where: { $0.id == id }) else { return false }
        definitions[index] = definitions[index].changingStatus(to: status)
        return true
    }
}

public nonisolated enum PTProtocolResearchTimelineSource: String, Codable, CaseIterable, Hashable, Sendable {
    case userMarker
    case can
    case xp400BLE
    case obd
    case unifiedTelemetry
}

public nonisolated struct PTProtocolResearchTimelineEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let source: PTProtocolResearchTimelineSource
    public let timestamp: Date
    public let summary: String
    public let stateKey: String?
    public let confidence: Double
    public let evidenceIDs: [UUID]

    public init(
        id: UUID = UUID(),
        source: PTProtocolResearchTimelineSource,
        timestamp: Date,
        summary: String,
        stateKey: String? = nil,
        confidence: Double,
        evidenceIDs: [UUID] = []
    ) {
        self.id = id
        self.source = source
        self.timestamp = timestamp
        self.summary = String(summary.prefix(1_024))
        self.stateKey = stateKey.map { String($0.prefix(160)) }
        self.confidence = PTProtocolResearchMath.clamp(confidence)
        self.evidenceIDs = Array(Set(evidenceIDs)).sorted { $0.uuidString < $1.uuidString }
    }
}

public nonisolated struct PTProtocolResearchCorrelationCluster: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let markerID: UUID
    public let markerName: String
    public let markerTimestamp: Date
    public let entryIDs: [UUID]
    public let sources: [PTProtocolResearchTimelineSource]
    public let temporalProximity: TimeInterval?
    public let repetitionCount: Int
    public let stateAgreement: Double
    public let confidence: Double

    public init(
        id: UUID = UUID(),
        markerID: UUID,
        markerName: String,
        markerTimestamp: Date,
        entryIDs: [UUID],
        sources: [PTProtocolResearchTimelineSource],
        temporalProximity: TimeInterval?,
        repetitionCount: Int,
        stateAgreement: Double,
        confidence: Double
    ) {
        self.id = id
        self.markerID = markerID
        self.markerName = String(markerName.prefix(160))
        self.markerTimestamp = markerTimestamp
        self.entryIDs = Array(Set(entryIDs)).sorted { $0.uuidString < $1.uuidString }
        self.sources = Array(Set(sources)).sorted { $0.rawValue < $1.rawValue }
        self.temporalProximity = temporalProximity.map { max(0, $0) }
        self.repetitionCount = max(0, repetitionCount)
        self.stateAgreement = PTProtocolResearchMath.clamp(stateAgreement)
        self.confidence = PTProtocolResearchMath.clamp(confidence)
    }
}

public nonisolated struct PTProtocolResearchCorrelationReport: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let experimentID: UUID
    public let vehicleID: UUID
    public let generatedAt: Date
    public let entries: [PTProtocolResearchTimelineEntry]
    public let clusters: [PTProtocolResearchCorrelationCluster]

    public init(
        id: UUID = UUID(),
        experimentID: UUID,
        vehicleID: UUID,
        generatedAt: Date = Date(),
        entries: [PTProtocolResearchTimelineEntry],
        clusters: [PTProtocolResearchCorrelationCluster]
    ) {
        self.id = id
        self.experimentID = experimentID
        self.vehicleID = vehicleID
        self.generatedAt = generatedAt
        self.entries = entries.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        self.clusters = clusters.sorted { $0.markerTimestamp < $1.markerTimestamp }
    }
}

public nonisolated enum PTProtocolResearchGraphNodeKind: String, Codable, CaseIterable, Sendable {
    case vehicleEvent
    case canSignal
    case xp400Signal
    case obdSignal
    case telemetrySignal
    case evidence
}

public nonisolated struct PTProtocolResearchGraphNode: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: PTProtocolResearchGraphNodeKind
    public let title: String
    public let evidenceIDs: [UUID]

    public init(id: String, kind: PTProtocolResearchGraphNodeKind, title: String, evidenceIDs: [UUID] = []) {
        self.id = String(id.prefix(256))
        self.kind = kind
        self.title = String(title.prefix(256))
        self.evidenceIDs = Array(Set(evidenceIDs)).sorted { $0.uuidString < $1.uuidString }
    }
}

public nonisolated enum PTProtocolResearchGraphRelation: String, Codable, CaseIterable, Sendable {
    case coObserved
    case candidateAssociation
    case mapsTo
}

public nonisolated struct PTProtocolResearchGraphEdge: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let fromNodeID: String
    public let toNodeID: String
    public let relation: PTProtocolResearchGraphRelation
    public let confidence: Double
    public let temporalProximity: TimeInterval?
    public let evidenceIDs: [UUID]

    public init(
        id: String,
        fromNodeID: String,
        toNodeID: String,
        relation: PTProtocolResearchGraphRelation,
        confidence: Double,
        temporalProximity: TimeInterval?,
        evidenceIDs: [UUID]
    ) {
        self.id = String(id.prefix(256))
        self.fromNodeID = String(fromNodeID.prefix(256))
        self.toNodeID = String(toNodeID.prefix(256))
        self.relation = relation
        self.confidence = PTProtocolResearchMath.clamp(confidence)
        self.temporalProximity = temporalProximity.map { max(0, $0) }
        self.evidenceIDs = Array(Set(evidenceIDs)).sorted { $0.uuidString < $1.uuidString }
    }
}

public nonisolated struct PTProtocolResearchGraph: Codable, Equatable, Sendable {
    public let nodes: [PTProtocolResearchGraphNode]
    public let edges: [PTProtocolResearchGraphEdge]

    public init(nodes: [PTProtocolResearchGraphNode], edges: [PTProtocolResearchGraphEdge]) {
        self.nodes = nodes.sorted { $0.id < $1.id }
        self.edges = edges.sorted { $0.id < $1.id }
    }
}

public nonisolated struct PTProtocolResearchTemplate: Codable, Equatable, Identifiable, Sendable {
    public let id: PTVehicleResearchEvent
    public let title: String
    public let purpose: String
    public let steps: [String]
    public let reversible: Bool
    public let requiresUserMarker: Bool
    public let recommendedWindow: TimeInterval

    public init(
        id: PTVehicleResearchEvent,
        title: String,
        purpose: String,
        steps: [String],
        reversible: Bool = true,
        requiresUserMarker: Bool = true,
        recommendedWindow: TimeInterval = 2
    ) {
        self.id = id
        self.title = String(title.prefix(160))
        self.purpose = String(purpose.prefix(512))
        self.steps = Array(steps.prefix(12)).map { String($0.prefix(256)) }
        self.reversible = reversible
        self.requiresUserMarker = requiresUserMarker
        self.recommendedWindow = max(0.5, recommendedWindow)
    }
}

public nonisolated enum PTProtocolResearchTemplateCatalog {
    public static let templates: [PTProtocolResearchTemplate] = [
        make(.leftIndicator, "Left indicator", "Observe one reversible left-indicator action.", "left indicator", "right indicator"),
        make(.rightIndicator, "Right indicator", "Observe one reversible right-indicator action.", "right indicator", "left indicator"),
        make(.hazard, "Hazard lights", "Observe hazard activation and deactivation.", "hazard", "hazard off"),
        make(.highBeam, "High beam", "Observe high-beam activation without sending a command.", "high beam", "low beam"),
        make(.brake, "Brake", "Observe a controlled stationary brake action.", "front brake", "release brake"),
        make(.sideStand, "Side stand", "Observe side-stand state transitions while parked.", "side stand down", "side stand up"),
        make(.ignition, "Ignition", "Observe ignition state transitions only when safe and stationary.", "ignition on", "ignition off"),
        make(.tcsMode, "TCS mode", "Observe a user-selected TCS mode change and restore it.", "record current TCS", "restore current TCS"),
        make(.absState, "ABS state", "Observe ABS state evidence without changing safety configuration.", "record ABS state", "stop"),
        make(.engineRunning, "Engine running", "Compare engine-off and engine-running telemetry.", "engine off", "engine off"),
        make(.rideMode, "Ride mode", "Observe one reversible ride-mode selection.", "record current ride mode", "restore current ride mode"),
        make(.fuelChange, "Fuel change", "Observe fuel telemetry around a controlled refill.", "record fuel baseline", "record fuel result")
    ]

    private static func make(
        _ id: PTVehicleResearchEvent,
        _ title: String,
        _ purpose: String,
        _ firstAction: String,
        _ lastAction: String
    ) -> PTProtocolResearchTemplate {
        PTProtocolResearchTemplate(
            id: id,
            title: title,
            purpose: purpose,
            steps: [
                "Start passive capture",
                "Mark baseline",
                "Perform: (firstAction)",
                "Mark activation",
                "Restore: (lastAction)",
                "Mark deactivation",
                "Stop capture and review candidates"
            ]
        )
    }
}

public nonisolated enum PTProtocolResearchMath {
    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    public static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return clamp(Double(max(0, numerator)) / Double(denominator))
    }

    public static func percentile(_ values: [TimeInterval], percentile: Double) -> TimeInterval? {
        let sorted = values.filter { $0.isFinite && $0 >= 0 }.sorted()
        guard !sorted.isEmpty else { return nil }
        let position = (Double(sorted.count - 1) * clamp(percentile))
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        if lower == upper { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    /// EN: Stable IDs make replay reports comparable across repeated offline runs.
    /// ES: Los identificadores estables hacen comparables los informes entre ejecuciones offline.
    /// 中文：稳定 ID 让离线回放多次运行时可以直接比较报告。
    public static func stableUUID(_ seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let value = String(digest.prefix(32))
        let uuidString = "\(value.prefix(8))-\(value.dropFirst(8).prefix(4))-\(value.dropFirst(12).prefix(4))-\(value.dropFirst(16).prefix(4))-\(value.dropFirst(20).prefix(12))"
        return UUID(uuidString: uuidString) ?? UUID()
    }
}
