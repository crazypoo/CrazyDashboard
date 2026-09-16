//
//  PTBuild69ProtocolIntelligence.swift
//  CrazyDashboard
//
//  EN: Provides bounded semantic evidence, candidate scoring, correlation, and Evidence v3 storage.
//  ES: Proporciona evidencia semántica acotada, puntuación de candidatos, correlación y almacenamiento Evidence v3.
//  中文：提供有界语义证据、候选评分、跨源相关性和 Evidence v3 存储。
//

import Foundation

// EN: Every observation identifies its transport origin so mock, replay, and live values cannot be conflated.
// ES: Cada observación identifica su origen de transporte para no mezclar valores simulados, replay y reales.
// 中文：每个观测都标记传输来源，防止 Mock、回放和真实数据混在一起。
public nonisolated enum PTBuild69ObservationSource: String, Codable, CaseIterable, Sendable {
    case xp400BLE
    case obd2
    case uds
    case gps
    case motion
    case derived
}

// EN: Availability and quality remain distinct; an unavailable reading is never encoded as a real zero.
// ES: Disponibilidad y calidad permanecen separadas; una lectura ausente nunca se codifica como cero real.
// 中文：可用性和质量保持分离，不把不可用读数编码成真实的 0。
public nonisolated enum PTBuild69ObservationAvailability: String, Codable, CaseIterable, Sendable {
    case available
    case unavailable
    case invalid
}

public nonisolated struct PTBuild69UnifiedObservation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let fieldKey: String
    public let source: PTBuild69ObservationSource
    public let wallClock: Date
    public let monotonicNanoseconds: UInt64
    public let dashboardTick: UInt8?
    public let dashboardTimeOfDaySeconds: Int?
    public let numericValue: Double?
    public let textValue: String?
    public let unit: String?
    public let availability: PTBuild69ObservationAvailability
    public let quality: PTXP400SemanticQuality
    public let confidence: Double
    public let evidenceID: UUID?

    public init(
        id: UUID = UUID(),
        fieldKey: String,
        source: PTBuild69ObservationSource,
        wallClock: Date,
        monotonicNanoseconds: UInt64,
        dashboardTick: UInt8? = nil,
        dashboardTimeOfDaySeconds: Int? = nil,
        numericValue: Double?,
        textValue: String? = nil,
        unit: String? = nil,
        availability: PTBuild69ObservationAvailability,
        quality: PTXP400SemanticQuality,
        confidence: Double,
        evidenceID: UUID? = nil
    ) {
        self.id = id
        self.fieldKey = String(fieldKey.prefix(160))
        self.source = source
        self.wallClock = wallClock
        self.monotonicNanoseconds = monotonicNanoseconds
        self.dashboardTick = dashboardTick
        self.dashboardTimeOfDaySeconds = dashboardTimeOfDaySeconds
        self.numericValue = numericValue?.isFinite == true ? numericValue : nil
        self.textValue = textValue.map { String($0.prefix(512)) }
        self.unit = unit.map { String($0.prefix(32)) }
        self.availability = availability
        self.quality = quality
        self.confidence = confidence.isFinite ? min(max(confidence, 0), 1) : 0
        self.evidenceID = evidenceID
    }
}

// EN: Field observations are the export contract for Inspector and Evidence v3.
// ES: Las observaciones de campo son el contrato de exportación para Inspector y Evidence v3.
// 中文：字段观测是 Inspector 和 Evidence v3 的导出契约。
public nonisolated struct PTBuild69FieldObservation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let fieldKey: String
    public let role: PTXP400SemanticFieldRole
    public let source: PTBuild69ObservationSource
    public let raw: String?
    public let normalizedValue: String?
    public let availability: PTBuild69ObservationAvailability
    public let quality: PTXP400SemanticQuality
    public let confidence: Double
    public let markerDistanceMilliseconds: Int64?
    public let dashboardTick: UInt8?
    public let monotonicNanoseconds: UInt64
    public let correlationIDs: [UUID]

    private enum CodingKeys: String, CodingKey {
        case id, fieldKey, role, source, raw, normalizedValue, availability, quality, confidence
        case markerDistanceMilliseconds, dashboardTick, monotonicNanoseconds, correlationIDs
    }

    public init(
        id: UUID = UUID(),
        fieldKey: String,
        role: PTXP400SemanticFieldRole,
        source: PTBuild69ObservationSource = .xp400BLE,
        raw: String?,
        normalizedValue: String?,
        availability: PTBuild69ObservationAvailability,
        quality: PTXP400SemanticQuality,
        confidence: Double,
        markerDistanceMilliseconds: Int64? = nil,
        dashboardTick: UInt8? = nil,
        monotonicNanoseconds: UInt64,
        correlationIDs: [UUID] = []
    ) {
        self.id = id
        self.fieldKey = String(fieldKey.prefix(160))
        self.role = role
        self.source = source
        self.raw = raw.map { String($0.prefix(512)) }
        self.normalizedValue = normalizedValue.map { String($0.prefix(512)) }
        self.availability = availability
        self.quality = quality
        self.confidence = confidence.isFinite ? min(max(confidence, 0), 1) : 0
        self.markerDistanceMilliseconds = markerDistanceMilliseconds
        self.dashboardTick = dashboardTick
        self.monotonicNanoseconds = monotonicNanoseconds
        self.correlationIDs = Array(Set(correlationIDs)).sorted { $0.uuidString < $1.uuidString }
    }

    // EN: Older Build 69 snapshots did not carry a source; they are safely treated as XP400 BLE observations.
    // ES: Las instantáneas antiguas de Build 69 no tenían origen; se tratan de forma segura como observaciones BLE XP400.
    // 中文：早期 Build 69 快照没有 source 字段，安全地按 XP400 BLE 观测恢复。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.fieldKey = String(try container.decode(String.self, forKey: .fieldKey).prefix(160))
        self.role = try container.decode(PTXP400SemanticFieldRole.self, forKey: .role)
        self.source = try container.decodeIfPresent(PTBuild69ObservationSource.self, forKey: .source) ?? .xp400BLE
        self.raw = try container.decodeIfPresent(String.self, forKey: .raw).map { String($0.prefix(512)) }
        self.normalizedValue = try container.decodeIfPresent(String.self, forKey: .normalizedValue).map { String($0.prefix(512)) }
        self.availability = try container.decode(PTBuild69ObservationAvailability.self, forKey: .availability)
        self.quality = try container.decode(PTXP400SemanticQuality.self, forKey: .quality)
        let decodedConfidence = try container.decode(Double.self, forKey: .confidence)
        self.confidence = decodedConfidence.isFinite ? min(max(decodedConfidence, 0), 1) : 0
        self.markerDistanceMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .markerDistanceMilliseconds)
        self.dashboardTick = try container.decodeIfPresent(UInt8.self, forKey: .dashboardTick)
        self.monotonicNanoseconds = try container.decode(UInt64.self, forKey: .monotonicNanoseconds)
        self.correlationIDs = Array(Set(try container.decodeIfPresent([UUID].self, forKey: .correlationIDs) ?? [])).sorted { $0.uuidString < $1.uuidString }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fieldKey, forKey: .fieldKey)
        try container.encode(role, forKey: .role)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(raw, forKey: .raw)
        try container.encodeIfPresent(normalizedValue, forKey: .normalizedValue)
        try container.encode(availability, forKey: .availability)
        try container.encode(quality, forKey: .quality)
        try container.encode(confidence, forKey: .confidence)
        try container.encodeIfPresent(markerDistanceMilliseconds, forKey: .markerDistanceMilliseconds)
        try container.encodeIfPresent(dashboardTick, forKey: .dashboardTick)
        try container.encode(monotonicNanoseconds, forKey: .monotonicNanoseconds)
        try container.encode(correlationIDs, forKey: .correlationIDs)
    }
}

// EN: Baseline statistics are bounded and descriptive; they do not promote hypotheses to protocol facts.
// ES: Las estadísticas base son acotadas y descriptivas; no convierten hipótesis en hechos del protocolo.
// 中文：基线统计有界且只描述数据，不会把假设升级成协议事实。
public nonisolated struct PTBuild69BaselineStatistics: Codable, Equatable, Sendable {
    public let fieldKey: String
    public let sampleCount: Int
    public let distinctValueCount: Int
    public let minimum: String?
    public let maximum: String?
    public let mode: String?
    public let changedSampleCount: Int
    public let markerHitCount: Int
    public let sourceCount: Int
    public let lastValue: String?

    public init(fieldKey: String, sampleCount: Int, distinctValueCount: Int, minimum: String?, maximum: String?, mode: String?, changedSampleCount: Int, markerHitCount: Int, sourceCount: Int, lastValue: String?) {
        self.fieldKey = fieldKey
        self.sampleCount = sampleCount
        self.distinctValueCount = distinctValueCount
        self.minimum = minimum
        self.maximum = maximum
        self.mode = mode
        self.changedSampleCount = changedSampleCount
        self.markerHitCount = markerHitCount
        self.sourceCount = sourceCount
        self.lastValue = lastValue
    }
}

public nonisolated struct PTBuild69CandidateScore: Codable, Equatable, Sendable {
    public let total: Double
    public let markerCorrelation: Double
    public let repeatability: Double
    public let crossSourceAgreement: Double
    public let variability: Double
    public let rarity: Double

    public init(total: Double, markerCorrelation: Double, repeatability: Double, crossSourceAgreement: Double, variability: Double, rarity: Double) {
        self.total = total.isFinite ? min(max(total, 0), 1) : 0
        self.markerCorrelation = min(max(markerCorrelation, 0), 1)
        self.repeatability = min(max(repeatability, 0), 1)
        self.crossSourceAgreement = min(max(crossSourceAgreement, 0), 1)
        self.variability = min(max(variability, 0), 1)
        self.rarity = min(max(rarity, 0), 1)
    }
}

public nonisolated struct PTBuild69ProtocolCandidate: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let fieldKey: String
    public let frameID: UInt8
    public let score: PTBuild69CandidateScore
    public let sampleCount: Int
    public let evidenceIDs: [UUID]
    public let quality: PTXP400SemanticQuality
    public let note: String

    public init(id: UUID = UUID(), fieldKey: String, frameID: UInt8, score: PTBuild69CandidateScore, sampleCount: Int, evidenceIDs: [UUID] = [], quality: PTXP400SemanticQuality = .experimental, note: String = "candidate only; no executable command") {
        self.id = id
        self.fieldKey = fieldKey
        self.frameID = frameID
        self.score = score
        self.sampleCount = sampleCount
        self.evidenceIDs = Array(Set(evidenceIDs)).sorted { $0.uuidString < $1.uuidString }
        self.quality = quality
        self.note = String(note.prefix(512))
    }
}

public nonisolated enum PTBuild69AnomalySeverity: String, Codable, CaseIterable, Sendable {
    case info
    case warning
    case error
    case critical
}

public nonisolated struct PTBuild69ProtocolAnomaly: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let severity: PTBuild69AnomalySeverity
    public let fieldKey: String?
    public let frameID: UInt8?
    public let message: String
    public let evidenceID: UUID?
    public let timestamp: Date

    public init(id: UUID = UUID(), severity: PTBuild69AnomalySeverity, fieldKey: String? = nil, frameID: UInt8? = nil, message: String, evidenceID: UUID? = nil, timestamp: Date = Date()) {
        self.id = id
        self.severity = severity
        self.fieldKey = fieldKey
        self.frameID = frameID
        self.message = String(message.prefix(1_024))
        self.evidenceID = evidenceID
        self.timestamp = timestamp
    }
}

// EN: Sentinel recognition is exact and field-scoped, preserving legitimate zero values.
// ES: El reconocimiento de centinelas es exacto y local al campo, conservando ceros legítimos.
// 中文：哨兵识别严格按字段执行，保留合法的 0 值。
public nonisolated enum PTBuild69SentinelDetector {
    public static func isSentinel(_ raw: Data, rule: PTXP400SentinelRule) -> Bool {
        rule.matches(raw)
    }

    public static func isAllFF(_ raw: Data) -> Bool {
        !raw.isEmpty && raw.allSatisfy { $0 == 0xFF }
    }

    public static func isAllZero(_ raw: Data) -> Bool {
        !raw.isEmpty && raw.allSatisfy { $0 == 0 }
    }
}

// EN: Candidate scoring uses only repeatable, informative variation and never scores clocks or counters.
// ES: La puntuación usa solo variación repetible e informativa y nunca puntúa relojes ni contadores.
// 中文：候选评分只使用可重复且有信息量的变化，永不评分时钟或计数器。
public nonisolated enum PTBuild69CandidateScorer {
    public static func score(
        markerCorrelation: Double,
        repeatability: Double,
        crossSourceAgreement: Double,
        variability: Double,
        rarity: Double
    ) -> PTBuild69CandidateScore {
        let values = [markerCorrelation, repeatability, crossSourceAgreement, variability, rarity].map { min(max($0.isFinite ? $0 : 0, 0), 1) }
        let total = values[0] * 0.25 + values[1] * 0.25 + values[2] * 0.20 + values[3] * 0.15 + values[4] * 0.15
        return PTBuild69CandidateScore(total: total, markerCorrelation: values[0], repeatability: values[1], crossSourceAgreement: values[2], variability: values[3], rarity: values[4])
    }
}

private struct PTBuild69MutableBaseline: Sendable {
    var values: [String] = []
    var changedSampleCount = 0
    var markerHitCount = 0
    var sources: Set<String> = []
    var frameID: UInt8 = 0
    var lastValue: String?

    mutating func add(_ observation: PTBuild69FieldObservation, frameID: UInt8) {
        if let lastValue, lastValue != observation.normalizedValue { changedSampleCount += 1 }
        if let normalizedValue = observation.normalizedValue {
            values.append(normalizedValue)
            if values.count > 128 { values.removeFirst(values.count - 128) }
            self.lastValue = normalizedValue
        }
        if observation.markerDistanceMilliseconds.map({ abs($0) <= 500 }) == true { markerHitCount += 1 }
        sources.insert(observation.source.rawValue)
        self.frameID = frameID
    }

    func snapshot(fieldKey: String) -> PTBuild69BaselineStatistics {
        let counts = values.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let sorted = values.sorted()
        return PTBuild69BaselineStatistics(
            fieldKey: fieldKey,
            sampleCount: values.count,
            distinctValueCount: counts.count,
            minimum: sorted.first,
            maximum: sorted.last,
            mode: counts.max { $0.value < $1.value }?.key,
            changedSampleCount: changedSampleCount,
            markerHitCount: markerHitCount,
            sourceCount: sources.count,
            lastValue: lastValue
        )
    }
}

// EN: The actor serializes baseline updates so callbacks can enqueue quickly without sharing mutable dictionaries.
// ES: El actor serializa las actualizaciones base para que las callbacks no compartan diccionarios mutables.
// 中文：该 actor 串行化基线更新，回调只需快速入队，不共享可变字典。
public actor PTBuild69BaselineLearner {
    private var baselines: [String: PTBuild69MutableBaseline] = [:]

    public init() {}

    public func ingest(_ observation: PTBuild69FieldObservation, frameID: UInt8) -> PTBuild69ProtocolCandidate? {
        guard observation.role == .candidate || observation.role == .unknown || observation.role == .provisional || observation.role == .flags,
              observation.availability == .available,
              observation.quality != .sentinel,
              observation.quality != .unavailable,
              observation.normalizedValue != nil else {
            return nil
        }

        var baseline = baselines[observation.fieldKey, default: PTBuild69MutableBaseline()]
        let previousValue = baseline.lastValue
        baseline.add(observation, frameID: frameID)
        baselines[observation.fieldKey] = baseline
        guard let previousValue, previousValue != observation.normalizedValue,
              baseline.values.count >= 3,
              baseline.changedSampleCount > 0 else {
            return nil
        }

        let statistics = baseline.snapshot(fieldKey: observation.fieldKey)
        let repeatability = min(Double(statistics.changedSampleCount) / 3, 1)
        let variability = min(Double(statistics.distinctValueCount) / 4, 1)
        let marker = min(Double(statistics.markerHitCount) / 2, 1)
        let rarity = statistics.distinctValueCount <= 2 ? 0.8 : 0.4
        let score = PTBuild69CandidateScorer.score(
            markerCorrelation: marker,
            repeatability: repeatability,
            crossSourceAgreement: statistics.sourceCount > 1 ? 1 : 0,
            variability: variability,
            rarity: rarity
        )
        guard score.total >= 0.35 else { return nil }
        return PTBuild69ProtocolCandidate(
            fieldKey: observation.fieldKey,
            frameID: frameID,
            score: score,
            sampleCount: statistics.sampleCount,
            evidenceIDs: [],
            note: "baseline changed from \(previousValue) to \(observation.normalizedValue ?? "—"); candidate only"
        )
    }

    public func snapshot() -> [PTBuild69BaselineStatistics] {
        baselines.keys.sorted().map { baselines[$0]!.snapshot(fieldKey: $0) }
    }

    public func reset() {
        baselines.removeAll(keepingCapacity: true)
    }
}

// EN: A marker is metadata for a reversible experiment; it never contains an executable vehicle command.
// ES: Una marca es metadato de un experimento reversible; nunca contiene un comando ejecutable del vehículo.
// 中文：Marker 只是可逆实验的元数据，绝不包含可执行车辆指令。
public nonisolated enum PTBuild69MarkerType: String, Codable, CaseIterable, Sendable {
    case ignition
    case sidestand
    case tcs
    case absSelfTest
    case settingChange
    case fuelLevel
    case custom
}

public nonisolated struct PTBuild69CaptureMarker: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let type: PTBuild69MarkerType
    public let name: String
    public let monotonicNanoseconds: UInt64
    public let timestamp: Date
    public let metadata: [String: String]

    public init(id: UUID = UUID(), type: PTBuild69MarkerType, name: String, monotonicNanoseconds: UInt64, timestamp: Date = Date(), metadata: [String: String] = [:]) {
        self.id = id
        self.type = type
        self.name = String(name.prefix(160))
        self.monotonicNanoseconds = monotonicNanoseconds
        self.timestamp = timestamp
        self.metadata = metadata.prefix(32).reduce(into: [:]) { $0[String($1.key.prefix(64))] = String($1.value.prefix(256)) }
    }
}

public nonisolated struct PTBuild69CaptureTemplateV2: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let domain: PTProtocolEvidenceDomain
    public let purpose: String
    public let readOnly: Bool
    public let requiresMarker: Bool
    public let requiredSources: [PTBuild69ObservationSource]
    public let durationSeconds: Int
    public let preRollSeconds: Int
    public let postRollSeconds: Int
    public let repeatCount: Int
    public let expectedFields: [String]
    public let safety: String

    public init(id: String, title: String, domain: PTProtocolEvidenceDomain, purpose: String, readOnly: Bool = true, requiresMarker: Bool = true, requiredSources: [PTBuild69ObservationSource], durationSeconds: Int, preRollSeconds: Int = 2, postRollSeconds: Int = 2, repeatCount: Int = 3, expectedFields: [String], safety: String) {
        self.id = id
        self.title = title
        self.domain = domain
        self.purpose = purpose
        self.readOnly = readOnly
        self.requiresMarker = requiresMarker
        self.requiredSources = requiredSources
        self.durationSeconds = max(durationSeconds, 1)
        self.preRollSeconds = max(preRollSeconds, 0)
        self.postRollSeconds = max(postRollSeconds, 0)
        self.repeatCount = max(repeatCount, 3)
        self.expectedFields = expectedFields
        self.safety = safety
    }
}

public nonisolated enum PTBuild69CaptureTemplateCatalog {
    public static let templates: [PTBuild69CaptureTemplateV2] = [
        PTBuild69CaptureTemplateV2(id: "ignition", title: "Ignition transition", domain: .xp400BLESemantic, purpose: "Observe engine-state transitions without writing to the vehicle.", requiredSources: [.xp400BLE, .obd2], durationSeconds: 20, expectedFields: ["data2.engine.statusRaw", "control.rpm"], safety: "Ignition only; never send a probe."),
        PTBuild69CaptureTemplateV2(id: "sidestand", title: "Side-stand transition", domain: .xp400BLESemantic, purpose: "Compare candidate low-bit changes around a user marker.", requiredSources: [.xp400BLE], durationSeconds: 20, expectedFields: ["data2.flags.byte0Low2", "data2.flags.byte2Low3"], safety: "Stationary motorcycle; rider controls the stand."),
        PTBuild69CaptureTemplateV2(id: "tcs", title: "TCS state transition", domain: .xp400BLESemantic, purpose: "Compare low-nibble TCS mode and unresolved status bits.", requiredSources: [.xp400BLE], durationSeconds: 30, expectedFields: ["control.tcsMode", "control.tcsStatusCandidateBit7"], safety: "Use only the official dashboard control."),
        PTBuild69CaptureTemplateV2(id: "abs-self-test", title: "ABS self test", domain: .xp400BLESemantic, purpose: "Observe ABS status candidates while retaining FF padding as sentinel.", requiredSources: [.xp400BLE], durationSeconds: 30, expectedFields: ["abs.statusCandidate", "abs.padding3to7"], safety: "Perform the manufacturer self-test only."),
        PTBuild69CaptureTemplateV2(id: "settings", title: "Dashboard setting A/B", domain: .xp400BLESemantic, purpose: "Compare one official setting at a time with three repetitions.", requiredSources: [.xp400BLE], durationSeconds: 45, expectedFields: ["data3.configurationFlagsA", "data3.configurationCandidate6", "data3.configurationCandidate7"], safety: "Official reversible setting only; no raw command."),
        PTBuild69CaptureTemplateV2(id: "fuel", title: "Fuel-level relation", domain: .xp400BLESemantic, purpose: "Study DATA1 byte 1 against the confirmed fuel field.", requiredSources: [.xp400BLE], durationSeconds: 60, expectedFields: ["data1.fuel", "data1.fuelRelatedUnknown"], safety: "Passive observation only."),
    ]
}

// EN: Correlation windows default to ±250 ms and prioritize monotonic time over wall-clock time.
// ES: Las ventanas de correlación usan ±250 ms por defecto y priorizan el tiempo monótono sobre la hora civil.
// 中文：相关性窗口默认 ±250ms，并优先使用单调时间而不是墙上时间。
public nonisolated struct PTBuild69CorrelationWindow: Codable, Equatable, Sendable {
    public let nanoseconds: UInt64

    public init(nanoseconds: UInt64 = 250_000_000) {
        self.nanoseconds = min(max(nanoseconds, 1), 10_000_000_000)
    }

    public static let `default` = PTBuild69CorrelationWindow()
}

public nonisolated struct PTBuild69CorrelationMetric: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let leftField: String
    public let rightField: String
    public let pairCount: Int
    public let windowNanoseconds: UInt64
    public let meanAbsoluteDifference: Double?
    public let pearsonCorrelation: Double?
    public let rSquared: Double?
    public let slope: Double?
    public let intercept: Double?
    public let suggestionOnly: Bool

    public init(id: UUID = UUID(), leftField: String, rightField: String, pairCount: Int, windowNanoseconds: UInt64, meanAbsoluteDifference: Double?, pearsonCorrelation: Double?, rSquared: Double?, slope: Double?, intercept: Double?, suggestionOnly: Bool = true) {
        self.id = id
        self.leftField = leftField
        self.rightField = rightField
        self.pairCount = pairCount
        self.windowNanoseconds = windowNanoseconds
        self.meanAbsoluteDifference = meanAbsoluteDifference
        self.pearsonCorrelation = pearsonCorrelation
        self.rSquared = rSquared
        self.slope = slope
        self.intercept = intercept
        self.suggestionOnly = suggestionOnly
    }
}

public nonisolated enum PTBuild69TelemetryCorrelationEngine {
    public static func correlate(observations: [PTBuild69UnifiedObservation], window: PTBuild69CorrelationWindow = .default) -> [PTBuild69CorrelationMetric] {
        let pairs = [
            ("control.rearSpeed", "abs.frontSpeed"),
            ("control.rearSpeed", "gps.speed"),
            ("control.rearSpeed", "obd.vehicleSpeed"),
            ("control.rpm", "obd.rpm"),
            ("data2.battery", "obd.controlModuleVoltage"),
            ("motion.acceleration", "obd.acceleration"),
            ("motion.lean", "motion.lateral")
        ]
        return pairs.compactMap { correlate(leftField: $0.0, rightField: $0.1, observations: observations, window: window) }
    }

    public static func correlate(leftField: String, rightField: String, observations: [PTBuild69UnifiedObservation], window: PTBuild69CorrelationWindow = .default) -> PTBuild69CorrelationMetric? {
        let left = observations.filter { $0.fieldKey == leftField && $0.numericValue != nil && $0.availability == .available }
        let right = observations.filter { $0.fieldKey == rightField && $0.numericValue != nil && $0.availability == .available }
        guard !left.isEmpty, !right.isEmpty else { return nil }

        var values: [(Double, Double)] = []
        for lhs in left {
            guard let rhs = right.min(by: { distance(lhs, $0) < distance(lhs, $1) }),
                  distance(lhs, rhs) <= window.nanoseconds else { continue }
            values.append((lhs.numericValue!, rhs.numericValue!))
        }
        guard !values.isEmpty else { return nil }
        let x = values.map(\.0)
        let y = values.map(\.1)
        let meanX = x.reduce(0, +) / Double(x.count)
        let meanY = y.reduce(0, +) / Double(y.count)
        let covariance = zip(x, y).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let varianceX = x.reduce(0) { $0 + pow($1 - meanX, 2) }
        let varianceY = y.reduce(0) { $0 + pow($1 - meanY, 2) }
        let denominator = sqrt(varianceX * varianceY)
        let pearson = denominator > 0 ? covariance / denominator : nil
        let slope = varianceX > 0 ? covariance / varianceX : nil
        let intercept = slope.map { meanY - $0 * meanX }
        let rSquared = pearson.map { $0 * $0 }
        let meanAbsoluteDifference = zip(x, y).map { abs($0 - $1) }.reduce(0, +) / Double(values.count)
        return PTBuild69CorrelationMetric(leftField: leftField, rightField: rightField, pairCount: values.count, windowNanoseconds: window.nanoseconds, meanAbsoluteDifference: meanAbsoluteDifference, pearsonCorrelation: pearson, rSquared: rSquared, slope: slope, intercept: intercept)
    }

    private static func distance(_ lhs: PTBuild69UnifiedObservation, _ rhs: PTBuild69UnifiedObservation) -> UInt64 {
        if lhs.monotonicNanoseconds > 0, rhs.monotonicNanoseconds > 0 {
            return lhs.monotonicNanoseconds >= rhs.monotonicNanoseconds ? lhs.monotonicNanoseconds - rhs.monotonicNanoseconds : rhs.monotonicNanoseconds - lhs.monotonicNanoseconds
        }
        let seconds = abs(lhs.wallClock.timeIntervalSince(rhs.wallClock))
        return UInt64(max(seconds, 0) * 1_000_000_000)
    }
}

// EN: Converts the semantic decoder output into field and unified observations without touching CoreBluetooth.
// ES: Convierte la salida semántica en observaciones de campo y unificadas sin tocar CoreBluetooth.
// 中文：将语义解码结果转换为字段观测和统一观测，不接触 CoreBluetooth。
public nonisolated enum PTBuild69ObservationAdapter {
    public static func observations(
        from frame: PTXP400SemanticFrame,
        source: PTBuild69ObservationSource = .xp400BLE,
        timestamp: Date = Date(),
        monotonicNanoseconds: UInt64 = 0,
        dashboardTick: UInt8? = nil,
        evidenceID: UUID? = nil
    ) -> ([PTBuild69FieldObservation], [PTBuild69UnifiedObservation]) {
        let fieldObservations = frame.fields.map { field in
            PTBuild69FieldObservation(
                fieldKey: field.id,
                role: field.role,
                source: source,
                raw: field.rawHex,
                normalizedValue: field.normalizedValue,
                availability: field.availability == .available ? .available : (field.quality == .invalid ? .invalid : .unavailable),
                quality: field.quality,
                confidence: field.confidence,
                dashboardTick: dashboardTick,
                monotonicNanoseconds: monotonicNanoseconds
            )
        }
        let dashboardTimeOfDaySeconds = PTXP400SemanticClock.clock(from: frame).map {
            Int($0.hour) * 3_600 + Int($0.minute) * 60 + Int($0.second)
        }
        let unified = fieldObservations.compactMap { field -> PTBuild69UnifiedObservation? in
            guard let numeric = field.normalizedValue.flatMap(Double.init) else { return nil }
            return PTBuild69UnifiedObservation(
                fieldKey: field.fieldKey,
                source: source,
                wallClock: timestamp,
                monotonicNanoseconds: monotonicNanoseconds,
                dashboardTick: dashboardTick,
                dashboardTimeOfDaySeconds: dashboardTimeOfDaySeconds,
                numericValue: numeric,
                textValue: field.normalizedValue,
                availability: field.availability,
                quality: field.quality,
                confidence: field.confidence,
                evidenceID: evidenceID
            )
        }
        return (fieldObservations, unified)
    }
}

// EN: Bridges the existing unified telemetry snapshot into the Build 69 evidence contract without creating another resolver.
// ES: Conecta la instantánea de telemetría unificada existente con el contrato de evidencia de Build 69 sin crear otro resolvedor.
// 中文：将现有统一遥测快照桥接到 Build 69 证据契约，不再创建第二套 Resolver。
public nonisolated enum PTBuild69UnifiedObservationAdapter {
    public static func observations(
        from snapshot: PTUnifiedVehicleTelemetrySnapshot,
        at date: Date = Date()
    ) -> [PTBuild69UnifiedObservation] {
        snapshot.values.compactMap { value in
            makeObservation(
                signal: value.signal,
                value: value.value,
                source: value.source,
                capturedAt: value.capturedAt,
                freshness: value.freshness,
                confidence: value.confidence,
                isSynthetic: value.isSynthetic,
                at: date
            )
        }
    }

    public static func observations(
        from observations: [PTVehicleTelemetryObservation],
        at date: Date = Date()
    ) -> [PTBuild69UnifiedObservation] {
        observations.compactMap { observation in
            makeObservation(
                signal: observation.signal,
                value: observation.value,
                source: observation.source,
                capturedAt: observation.capturedAt,
                freshness: observation.isValid && observation.capturedAt <= date
                    && date.timeIntervalSince(observation.capturedAt) <= PTVehicleTelemetryFreshnessPolicy.maximumAge(for: observation.signal)
                    ? .fresh
                    : .stale,
                confidence: observation.confidence,
                isSynthetic: observation.isSynthetic,
                at: date
            )
        }
    }

    private static func makeObservation(
        signal: PTVehicleTelemetrySignal,
        value: PTVehicleTelemetryValue,
        source: PTVehicleTelemetrySource,
        capturedAt: Date,
        freshness: PTTelemetryFreshness,
        confidence: Double,
        isSynthetic: Bool,
        at _: Date
    ) -> PTBuild69UnifiedObservation? {
        let valid = signal.accepts(value)
        let availability: PTBuild69ObservationAvailability
        if !valid {
            availability = .invalid
        } else if freshness == .fresh {
            availability = .available
        } else {
            availability = .unavailable
        }

        let numericValue: Double?
        let textValue: String?
        switch value {
        case .double(let value):
            numericValue = value
            textValue = String(format: "%.3f", value)
        case .integer(let value):
            numericValue = Double(value)
            textValue = String(value)
        case .boolean(let value):
            numericValue = value ? 1 : 0
            textValue = value ? "true" : "false"
        case .location(let latitude, let longitude, let altitude):
            numericValue = nil
            textValue = String(format: "%.6f,%.6f,%.1f", latitude, longitude, altitude)
        }

        return PTBuild69UnifiedObservation(
            fieldKey: fieldKey(for: signal, source: source),
            source: evidenceSource(for: source),
            wallClock: capturedAt,
            monotonicNanoseconds: 0,
            numericValue: numericValue,
            textValue: textValue,
            unit: unit(for: signal),
            availability: availability,
            quality: valid && freshness == .fresh
                ? (isSynthetic ? .experimental : .confirmed)
                : (valid ? .unavailable : .invalid),
            confidence: confidence
        )
    }

    private static func evidenceSource(for source: PTVehicleTelemetrySource) -> PTBuild69ObservationSource {
        switch source.domain {
        case .xp400BLE: return .xp400BLE
        case .obd: return .obd2
        case .gps: return .gps
        case .motion: return .motion
        case .calculated, .replay, .unknown: return .derived
        }
    }

    private static func fieldKey(for signal: PTVehicleTelemetrySignal, source: PTVehicleTelemetrySource) -> String {
        switch source.domain {
        case .xp400BLE:
            switch signal {
            case .speed: return "control.rearSpeed"
            case .rpm: return "control.rpm"
            case .fuel: return "data1.fuel"
            case .trip: return "data1.trip"
            case .odometer: return "data1.odometer"
            case .range: return "data3.autonomy"
            case .maintenanceDistance: return "data3.maintenance"
            case .batteryVoltage: return "data2.battery"
            case .engineStatus: return "data2.engine.statusRaw"
            case .frontWheelSpeed: return "abs.frontSpeed"
            case .abs: return "abs.statusCandidate"
            case .tcs: return "control.tcsMode"
            case .lights: return "control.lightFlags"
            case .leftTurn, .rightTurn, .hazard: return "control.turnFlags"
            case .kickstandDown: return "data2.flags.kickstandCandidate"
            case .engineTemperature: return "data2.outsideTemperature"
            default: return "xp400.\(signal.rawValue)"
            }
        case .obd:
            switch signal {
            case .speed: return "obd.vehicleSpeed"
            case .rpm: return "obd.rpm"
            case .batteryVoltage, .controlModuleVoltage: return "obd.controlModuleVoltage"
            case .adapterVoltage: return "obd.adapterVoltage"
            case .throttlePercent: return "obd.throttle"
            case .engineTemperature: return "obd.engineTemperature"
            case .engineStatus: return "obd.engineStatus"
            case .gForceX: return "obd.acceleration"
            default: return "obd.\(signal.rawValue)"
            }
        case .gps:
            return signal == .speed ? "gps.speed" : "gps.\(signal.rawValue)"
        case .motion:
            switch signal {
            case .gForceX: return "motion.acceleration"
            case .gForceY: return "motion.lateral"
            default: return "motion.\(signal.rawValue)"
            }
        case .calculated, .replay, .unknown:
            return "derived.\(signal.rawValue)"
        }
    }

    private static func unit(for signal: PTVehicleTelemetrySignal) -> String? {
        switch signal {
        case .speed, .frontWheelSpeed, .trip, .odometer, .range, .maintenanceDistance: return "km"
        case .rpm: return "rpm"
        case .fuel, .throttlePercent: return "%"
        case .batteryVoltage, .adapterVoltage, .controlModuleVoltage: return "V"
        case .engineTemperature: return "°C"
        case .lean, .pitch, .yaw: return "deg"
        case .gForceX, .gForceY, .gForceZ: return "g"
        default: return nil
        }
    }
}

// EN: The result crosses actors as immutable data and is safe to persist or hand to the UI.
// ES: El resultado cruza actores como datos inmutables y puede persistirse o entregarse a la UI.
// 中文：结果以不可变数据跨 actor 传递，可安全持久化或交给 UI。
public nonisolated struct PTBuild69EvidenceIngestResult: Codable, Equatable, Sendable {
    public let evidenceID: UUID
    public let timestamp: Date
    public let frame: PTXP400SemanticFrame
    public let fieldObservations: [PTBuild69FieldObservation]
    public let observations: [PTBuild69UnifiedObservation]
    public let candidates: [PTBuild69ProtocolCandidate]
    public let anomalies: [PTBuild69ProtocolAnomaly]

    private enum CodingKeys: String, CodingKey {
        case evidenceID, timestamp, frame, fieldObservations, observations, candidates, anomalies
    }

    public init(evidenceID: UUID, timestamp: Date = Date(), frame: PTXP400SemanticFrame, fieldObservations: [PTBuild69FieldObservation], observations: [PTBuild69UnifiedObservation], candidates: [PTBuild69ProtocolCandidate], anomalies: [PTBuild69ProtocolAnomaly]) {
        self.evidenceID = evidenceID
        self.timestamp = timestamp
        self.frame = frame
        self.fieldObservations = fieldObservations
        self.observations = observations
        self.candidates = candidates
        self.anomalies = anomalies
    }

    // EN: Decode pre-timestamp snapshots using the first observation timestamp when available.
    // ES: Decodifica instantáneas anteriores sin timestamp usando la primera observación cuando existe.
    // 中文：兼容没有 timestamp 的旧快照，优先使用第一条观测的时间。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.evidenceID = try container.decode(UUID.self, forKey: .evidenceID)
        self.frame = try container.decode(PTXP400SemanticFrame.self, forKey: .frame)
        let decodedFieldObservations = try container.decode([PTBuild69FieldObservation].self, forKey: .fieldObservations)
        let decodedObservations = try container.decode([PTBuild69UnifiedObservation].self, forKey: .observations)
        let decodedCandidates = try container.decode([PTBuild69ProtocolCandidate].self, forKey: .candidates)
        let decodedAnomalies = try container.decode([PTBuild69ProtocolAnomaly].self, forKey: .anomalies)
        self.fieldObservations = decodedFieldObservations
        self.observations = decodedObservations
        self.candidates = decodedCandidates
        self.anomalies = decodedAnomalies
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
            ?? decodedObservations.first?.wallClock
            ?? decodedAnomalies.first?.timestamp
            ?? .distantPast
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(evidenceID, forKey: .evidenceID)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(frame, forKey: .frame)
        try container.encode(fieldObservations, forKey: .fieldObservations)
        try container.encode(observations, forKey: .observations)
        try container.encode(candidates, forKey: .candidates)
        try container.encode(anomalies, forKey: .anomalies)
    }
}

// EN: This actor performs semantic analysis off the BLE callback and keeps all research collections bounded.
// ES: Este actor realiza el análisis semántico fuera de la callback BLE y limita todas las colecciones de investigación.
// 中文：该 actor 将语义分析移出 BLE 回调，并限制所有研究集合的大小。
public actor PTBuild69SemanticIntelligenceActor {
    public static let shared = PTBuild69SemanticIntelligenceActor()
    private let learner = PTBuild69BaselineLearner()
    private var results: [PTBuild69EvidenceIngestResult] = []
    private var previousDashboardTick: UInt8?

    public init() {}

    public func ingest(frame: PTXP400SemanticFrame, source: PTBuild69ObservationSource = .xp400BLE, timestamp: Date = Date(), monotonicNanoseconds: UInt64 = 0, dashboardTick: UInt8? = nil) async -> PTBuild69EvidenceIngestResult {
        let evidenceID = UUID()
        let adapted = PTBuild69ObservationAdapter.observations(from: frame, source: source, timestamp: timestamp, monotonicNanoseconds: monotonicNanoseconds, dashboardTick: dashboardTick, evidenceID: evidenceID)
        var candidates: [PTBuild69ProtocolCandidate] = []
        for observation in adapted.0 {
            if let candidate = await learner.ingest(observation, frameID: frame.id) {
                candidates.append(PTBuild69ProtocolCandidate(id: candidate.id, fieldKey: candidate.fieldKey, frameID: candidate.frameID, score: candidate.score, sampleCount: candidate.sampleCount, evidenceIDs: [evidenceID], quality: candidate.quality, note: candidate.note))
            }
        }
        var anomalies = frame.fields.compactMap { field -> PTBuild69ProtocolAnomaly? in
            guard field.quality == .invalid else { return nil }
            return PTBuild69ProtocolAnomaly(severity: .warning, fieldKey: field.id, frameID: frame.id, message: "Invalid decoded value; raw payload retained.", evidenceID: evidenceID, timestamp: timestamp)
        }
        if let padding = frame.fields.first(where: { $0.role == .padding }), padding.quality != .sentinel {
            anomalies.append(PTBuild69ProtocolAnomaly(severity: .warning, fieldKey: padding.id, frameID: frame.id, message: "Declared sentinel/padding changed; preserve raw bytes and repeat the capture.", evidenceID: evidenceID, timestamp: timestamp))
        }
        if let previousDashboardTick, let dashboardTick {
            let delta = PTXP400RollingTick.moduloDelta(from: previousDashboardTick, to: dashboardTick)
            let suspiciousJump = delta > 25 || (delta > 5 && !delta.isMultiple(of: 5))
            if suspiciousJump {
                anomalies.append(PTBuild69ProtocolAnomaly(severity: .warning, fieldKey: "control.rollingTick", frameID: frame.id, message: "Rolling tick jump (delta); possible dropped or reordered dashboard frame.", evidenceID: evidenceID, timestamp: timestamp))
            }
        }
        previousDashboardTick = dashboardTick ?? previousDashboardTick
        let result = PTBuild69EvidenceIngestResult(evidenceID: evidenceID, timestamp: timestamp, frame: frame, fieldObservations: adapted.0, observations: adapted.1, candidates: candidates, anomalies: anomalies)
        results.append(result)
        if results.count > 500 { results.removeFirst(results.count - 500) }
        return result
    }

    public func recentResults() -> [PTBuild69EvidenceIngestResult] { results }

    public func reset() async {
        results.removeAll(keepingCapacity: true)
        previousDashboardTick = nil
        await learner.reset()
    }
}

// EN: The coordinator is passive: it accepts frames already received by the stable transport and never sends anything.
// ES: El coordinador es pasivo: acepta tramas recibidas por el transporte estable y nunca envía nada.
// 中文：协调器是被动的，只接收稳定传输层已经收到的帧，绝不会发送数据。
public actor PTBuild69ProtocolEvidenceCoordinator {
    public static let shared = PTBuild69ProtocolEvidenceCoordinator()
    private var lastStableFingerprint: String?

    public init() {}

    public func ingestBLEFrame(_ rawData: Data, timestamp: Date = Date(), monotonicNanoseconds: UInt64 = 0) async -> PTBuild69EvidenceIngestResult? {
        guard let decoded = PTXP400TelemetryDecoder.decode(rawData),
              let semantic = PTXP400SemanticDecoder.decode(frame: decoded) else { return nil }
        let tick = semantic.fields.first(where: { $0.id == "control.rollingTick" })?.raw.first
        if let clock = PTXP400SemanticClock.clock(from: semantic) {
            _ = await PTXP400DashboardClockAnchor.shared.ingest(clock: clock, dashboardTick: tick, monotonicNanoseconds: monotonicNanoseconds, hostDate: timestamp)
        }
        let fingerprint = stableFingerprint(for: semantic)
        // EN: Periodic RTC and counter updates do not create a new persisted record when semantic state is unchanged.
        // ES: Las actualizaciones periódicas de RTC y contador no crean un registro persistido si el estado semántico no cambia.
        // 中文：当语义状态没有变化时，周期性 RTC 和计数器更新不会产生新的持久化记录。
        let isDuplicate = fingerprint == lastStableFingerprint
        lastStableFingerprint = fingerprint
        // EN: Baseline learning still receives every frame; only duplicate results are suppressed at the persistence boundary.
        // ES: El aprendizaje de la línea base sigue recibiendo cada trama; solo se suprimen resultados duplicados al persistir.
        // 中文：基线学习仍接收每一帧，只有在持久化边界抑制重复结果。
        let result = await PTBuild69SemanticIntelligenceActor.shared.ingest(frame: semantic, timestamp: timestamp, monotonicNanoseconds: monotonicNanoseconds, dashboardTick: tick)
        return isDuplicate ? nil : result
    }

    public func reset() async {
        lastStableFingerprint = nil
        await PTBuild69SemanticIntelligenceActor.shared.reset()
        await PTXP400DashboardClockAnchor.shared.reset()
    }

    private func stableFingerprint(for frame: PTXP400SemanticFrame) -> String {
        frame.fields
            .filter { $0.role != .clock && $0.role != .counter }
            .map { "\($0.id):\($0.role.rawValue):\($0.rawHex):\($0.quality.rawValue):\($0.availability.rawValue)" }
            .joined(separator: "|")
    }
}

public nonisolated enum PTXP400SemanticClock {
    public static func clock(from frame: PTXP400SemanticFrame) -> PTDashboardClock? {
        guard frame.id == PTXP400BLEProtocol.data2FrameID,
              let second = frame.fields.first(where: { $0.id == "data2.rtc.second" })?.normalizedValue.flatMap(UInt8.init),
              let minute = frame.fields.first(where: { $0.id == "data2.rtc.minute" })?.normalizedValue.flatMap(UInt8.init),
              let hour = frame.fields.first(where: { $0.id == "data2.rtc.hour" })?.normalizedValue.flatMap(UInt8.init) else { return nil }
        let clock = PTDashboardClock(hour: hour, minute: minute, second: second)
        return clock.isValid ? clock : nil
    }
}

// EN: Evidence records are produced only after a frame was already received; this factory has no transport side effects.
// ES: Los registros se producen solo después de recibir una trama; esta fábrica no tiene efectos de transporte.
// 中文：证据记录只在帧已经收到后生成，该工厂不产生任何传输副作用。
public nonisolated enum PTBuild69EvidenceRecordFactory {
    public static func records(from result: PTBuild69EvidenceIngestResult, source: PTProtocolEvidenceSource = .live) -> [PTProtocolEvidenceRecord] {
        var records = [PTProtocolEvidenceRecord(
            id: result.evidenceID,
            domain: .xp400BLESemantic,
            kind: .frame,
            direction: .rx,
            source: source,
            timestamp: result.timestamp,
            confidence: 1,
            value: result.frame.summary,
            request: nil,
            response: result.frame.rawPayload.map { String(format: "%02X", $0) }.joined(),
            fingerprint: "xp400:semantic:\(result.frame.id):\(result.frame.rawPayload.map { String(format: "%02X", $0) }.joined())",
            vehicleID: nil,
            referenceID: nil,
            reference: nil,
            note: "raw payload retained; candidate fields require repeatable baseline"
        )]
        records.append(contentsOf: result.candidates.map { candidate in
            PTProtocolEvidenceRecord(
                id: candidate.id,
                domain: .xp400BLESemantic,
                kind: .candidate,
                direction: .state,
                source: source,
                timestamp: result.timestamp,
                confidence: candidate.score.total,
                value: "\(candidate.fieldKey) score=\(String(format: "%.3f", candidate.score.total))",
                request: nil,
                response: nil,
                fingerprint: "candidate:\(candidate.fieldKey)",
                vehicleID: nil,
                referenceID: result.evidenceID,
                reference: nil,
                note: candidate.note
            )
        })
        if result.frame.id == PTXP400BLEProtocol.connectionFrameID,
           let serial = result.frame.fields.first(where: { $0.id == "connection.serial" })?.normalizedValue,
           !serial.isEmpty {
            records.append(PTProtocolEvidenceRecord(
                domain: .xp400BLESemantic,
                kind: .identity,
                direction: .rx,
                source: source,
                timestamp: result.timestamp,
                confidence: 1,
                value: serial,
                response: result.frame.rawPayload.map { String(format: "%02X", $0) }.joined(),
                fingerprint: "xp400:connectivity-box:(serial)",
                referenceID: result.evidenceID,
                reference: "passport.adapter.connectivityBox.identity",
                note: "Connection frame identifies the Connectivity Box; dashboard identity remains separate."
            ))
            records.append(PTProtocolEvidenceRecord(
                domain: .xp400BLESemantic,
                kind: .identity,
                direction: .rx,
                source: source,
                timestamp: result.timestamp,
                confidence: 1,
                value: String(serial.suffix(8)).uppercased(),
                fingerprint: "xp400:connectivity-box:suffix:(serial.suffix(8))",
                referenceID: result.evidenceID,
                reference: "passport.adapter.connectivityBox.identifierSuffix",
                note: "Stable suffix derived from the Connectivity Box identity."
            ))
        }
        records.append(contentsOf: result.anomalies.map { anomaly in
            PTProtocolEvidenceRecord(
                id: anomaly.id,
                domain: .xp400BLESemantic,
                kind: .research,
                direction: .state,
                source: source,
                timestamp: anomaly.timestamp,
                confidence: 0.5,
                value: anomaly.message,
                request: nil,
                response: nil,
                fingerprint: "anomaly:\(anomaly.fieldKey ?? "frame")",
                vehicleID: nil,
                referenceID: anomaly.evidenceID,
                reference: nil,
                note: anomaly.severity.rawValue
            )
        })
        return records
    }
}

// EN: Passport reduction only accepts explicit evidence references; it never assigns an unexplained ECU value to the dashboard.
// ES: La reducción Passport solo acepta referencias explícitas; nunca asigna un valor ECU inexplicado al tablero.
// 中文：Passport 归约只接受显式证据引用，不会把无法解释的 ECU 值放进仪表字段。
public nonisolated enum PTBuild69PassportReducer {
    public static func reduce(base: PTVehiclePassport, records: [PTProtocolEvidenceRecord], generatedAt: Date = Date()) -> PTVehiclePassport {
        var vehicleFields = base.vehicleFields
        var adapterFields = base.adapterFields
        for record in records {
            guard let reference = record.reference,
                  reference.hasPrefix("passport."),
                  !record.value.isEmpty else { continue }
            let isAdapter = reference.hasPrefix("passport.adapter.")
            let key = reference.replacingOccurrences(of: "passport.adapter.", with: "").replacingOccurrences(of: "passport.vehicle.", with: "")
            let field = PTVehiclePassportField(key: key, value: record.value, source: record.source, timestamp: record.timestamp, confidence: record.confidence, evidenceIDs: [record.id])
            if isAdapter {
                adapterFields.removeAll { $0.key == key }
                adapterFields.append(field)
            } else {
                vehicleFields.removeAll { $0.key == key }
                vehicleFields.append(field)
            }
        }
        return PTVehiclePassport(schemaVersion: max(base.schemaVersion, 3), generatedAt: generatedAt, vehicleID: base.vehicleID, vehicleFields: vehicleFields.sorted { $0.key < $1.key }, adapterFields: adapterFields.sorted { $0.key < $1.key })
    }
}

// EN: Evidence v3 is additive, so v2 documents remain decodable and historical records are never marked confirmed by migration.
// ES: Evidence v3 es aditivo; los documentos v2 siguen siendo decodificables y la migración nunca confirma registros históricos.
// 中文：Evidence v3 采用增量结构，v2 文档仍可解码，迁移不会把历史记录标记为已确认。
public nonisolated struct PTProtocolEvidenceV3Document: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 3
    public let schemaVersion: Int
    public let generatedAt: Date
    public let migratedFromSchemaVersion: Int?
    public let records: [PTProtocolEvidenceRecord]
    public let semanticFrames: [PTXP400SemanticFrame]
    public let fieldObservations: [PTBuild69FieldObservation]
    public let observations: [PTBuild69UnifiedObservation]
    public let candidates: [PTBuild69ProtocolCandidate]
    public let anomalies: [PTBuild69ProtocolAnomaly]
    public let correlations: [PTBuild69CorrelationMetric]
    public let passport: PTVehiclePassport
    public let captureTemplates: [PTBuild69CaptureTemplateV2]
    public let migrationNotes: [String]

    public init(schemaVersion: Int = currentSchemaVersion, generatedAt: Date = Date(), migratedFromSchemaVersion: Int? = nil, records: [PTProtocolEvidenceRecord], semanticFrames: [PTXP400SemanticFrame], fieldObservations: [PTBuild69FieldObservation], observations: [PTBuild69UnifiedObservation], candidates: [PTBuild69ProtocolCandidate], anomalies: [PTBuild69ProtocolAnomaly], correlations: [PTBuild69CorrelationMetric], passport: PTVehiclePassport, captureTemplates: [PTBuild69CaptureTemplateV2] = PTBuild69CaptureTemplateCatalog.templates, migrationNotes: [String] = []) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.migratedFromSchemaVersion = migratedFromSchemaVersion
        self.records = records
        self.semanticFrames = semanticFrames
        self.fieldObservations = fieldObservations
        self.observations = observations
        self.candidates = candidates
        self.anomalies = anomalies
        self.correlations = correlations
        self.passport = passport
        self.captureTemplates = captureTemplates
        self.migrationNotes = migrationNotes
    }
}

public nonisolated enum PTProtocolEvidenceV3Migration {
    public static func fromV2(_ document: PTProtocolEvidenceV2Document) -> PTProtocolEvidenceV3Document {
        PTProtocolEvidenceV3Document(
            generatedAt: document.generatedAt,
            migratedFromSchemaVersion: document.schemaVersion,
            records: document.records,
            semanticFrames: [],
            fieldObservations: [],
            observations: [],
            candidates: [],
            anomalies: [],
            correlations: [],
            passport: document.passport,
            migrationNotes: ["Migrated from Evidence v2; no historical record was promoted to confirmed semantic evidence."]
        )
    }
}

// EN: CSV export is field-oriented so raw, normalized, quality, and provenance are visible without parsing JSON.
// ES: La exportación CSV está orientada a campos para ver bruto, normalizado, calidad y procedencia sin analizar JSON.
// 中文：CSV 按字段导出，直接查看原始值、规范值、质量和来源，无需解析 JSON。
public nonisolated enum PTProtocolEvidenceV3Exporter {
    public static func jsonData(for document: PTProtocolEvidenceV3Document, privacyLevel: String = "redacted") throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(privacyLevel.caseInsensitiveCompare("redacted") == .orderedSame ? redacted(document) : document)
    }

    public static func csvData(for document: PTProtocolEvidenceV3Document) -> Data {
        var rows = ["evidenceID,fieldKey,role,raw,normalizedValue,availability,quality,confidence,markerDistanceMilliseconds,dashboardTick,monotonicNanoseconds,correlationIDs"]
        rows.append(contentsOf: document.fieldObservations.map { field in
            [
                field.id.uuidString,
                field.fieldKey,
                field.role.rawValue,
                field.raw ?? "",
                field.normalizedValue ?? "",
                field.availability.rawValue,
                field.quality.rawValue,
                String(format: "%.3f", field.confidence),
                field.markerDistanceMilliseconds.map(String.init) ?? "",
                field.dashboardTick.map(String.init) ?? "",
                String(field.monotonicNanoseconds),
                field.correlationIDs.map(\.uuidString).joined(separator: "|")
            ].map(csvField).joined(separator: ",")
        })
        return Data(rows.joined(separator: "\n").utf8)
    }

    private static func redacted(_ document: PTProtocolEvidenceV3Document) -> PTProtocolEvidenceV3Document {
        let redact: (String?) -> String? = { $0.map(PTBuild65PrivacyPolicy.redactExportText) }
        return PTProtocolEvidenceV3Document(
            schemaVersion: document.schemaVersion,
            generatedAt: document.generatedAt,
            migratedFromSchemaVersion: document.migratedFromSchemaVersion,
            records: document.records.map(redacted),
            semanticFrames: document.semanticFrames.map { frame in
                PTXP400SemanticFrame(id: frame.id, name: frame.name, rawPayload: frame.id == PTXP400BLEProtocol.connectionFrameID ? Data() : frame.rawPayload, fields: frame.fields.map { field in
                    PTXP400SemanticField(id: field.id, role: field.role, raw: field.id == "connection.serial" ? Data() : field.raw, normalizedValue: field.id == "connection.serial" ? nil : redact(field.normalizedValue), unit: field.unit, availability: field.availability, quality: field.quality, confidence: field.confidence)
                })
            },
            fieldObservations: document.fieldObservations.map { field in
                PTBuild69FieldObservation(id: field.id, fieldKey: field.fieldKey, role: field.role, source: field.source, raw: field.fieldKey == "connection.serial" ? nil : redact(field.raw), normalizedValue: field.fieldKey == "connection.serial" ? nil : redact(field.normalizedValue), availability: field.availability, quality: field.quality, confidence: field.confidence, markerDistanceMilliseconds: field.markerDistanceMilliseconds, dashboardTick: field.dashboardTick, monotonicNanoseconds: field.monotonicNanoseconds, correlationIDs: field.correlationIDs)
            },
            observations: document.observations,
            candidates: document.candidates,
            anomalies: document.anomalies,
            correlations: document.correlations,
            passport: redacted(document.passport),
            captureTemplates: document.captureTemplates,
            migrationNotes: document.migrationNotes
        )
    }

    private static func redacted(_ record: PTProtocolEvidenceRecord) -> PTProtocolEvidenceRecord {
        let identityRecord = record.reference?.contains("identity") == true
            || record.reference?.contains("identifierSuffix") == true
            || record.kind == .identity
        let value = identityRecord ? "<redacted-identity>" : PTBuild65PrivacyPolicy.redactExportText(record.value)
        let response = identityRecord ? nil : record.response.map(PTBuild65PrivacyPolicy.redactExportText)
        return PTProtocolEvidenceRecord(
            id: record.id,
            domain: record.domain,
            kind: record.kind,
            direction: record.direction,
            source: record.source,
            timestamp: record.timestamp,
            confidence: record.confidence,
            value: value,
            request: record.request.map(PTBuild65PrivacyPolicy.redactExportText),
            response: response,
            fingerprint: identityRecord ? "<redacted-identity>" : record.fingerprint.map(PTBuild65PrivacyPolicy.redactExportText),
            vehicleID: nil,
            referenceID: record.referenceID,
            reference: record.reference.map(PTBuild65PrivacyPolicy.redactExportText),
            note: record.note.map(PTBuild65PrivacyPolicy.redactExportText)
        )
    }

    private static func redacted(_ passport: PTVehiclePassport) -> PTVehiclePassport {
        func redactField(_ field: PTVehiclePassportField) -> PTVehiclePassportField {
            let value = PTBuild65PrivacyPolicy.isSensitiveKey(field.key) || field.key.contains("identity") || field.key.contains("suffix")
                ? nil
                : field.value.map(PTBuild65PrivacyPolicy.redactExportText)
            return PTVehiclePassportField(key: field.key, value: value, source: field.source, timestamp: field.timestamp, confidence: field.confidence, evidenceIDs: field.evidenceIDs)
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
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

public nonisolated struct PTBuild69PersistedEvidence: Codable, Sendable {
    public let schemaVersion: Int
    public let results: [PTBuild69EvidenceIngestResult]
    public let markers: [PTBuild69CaptureMarker]

    public init(schemaVersion: Int = 3, results: [PTBuild69EvidenceIngestResult], markers: [PTBuild69CaptureMarker]) {
        self.schemaVersion = schemaVersion
        self.results = results
        self.markers = markers
    }
}

// EN: The local v3 store is bounded and additive; it never calls a transport or emits a vehicle command.
// ES: El almacén local v3 es acotado y aditivo; nunca llama a un transporte ni emite comandos del vehículo.
// 中文：本地 v3 证据库有界且只追加，绝不会调用传输层或发送车辆指令。
@MainActor
public final class PTBuild69EvidenceStore {
    public static let shared = PTBuild69EvidenceStore()
    public static let storageKey = "PTBuild69EvidenceStore.v3"
    public static let maximumResultCount = 500

    public private(set) var results: [PTBuild69EvidenceIngestResult]
    public private(set) var markers: [PTBuild69CaptureMarker]
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let persisted = try? Self.decoder.decode(PTBuild69PersistedEvidence.self, from: data) {
            self.results = Array(persisted.results.suffix(Self.maximumResultCount))
            self.markers = Array(persisted.markers.suffix(128))
        } else {
            self.results = []
            self.markers = []
        }
    }

    @discardableResult
    public func merge(_ result: PTBuild69EvidenceIngestResult) -> Bool {
        guard !results.contains(where: { $0.evidenceID == result.evidenceID }) else { return false }
        results.append(result)
        if results.count > Self.maximumResultCount { results.removeFirst(results.count - Self.maximumResultCount) }
        persist()
        return true
    }

    public func addMarker(_ marker: PTBuild69CaptureMarker) {
        markers.append(marker)
        if markers.count > 128 { markers.removeFirst(markers.count - 128) }
        persist()
    }

    public func snapshot() -> [PTBuild69EvidenceIngestResult] { results }

    public func document(at date: Date = Date(), records: [PTProtocolEvidenceRecord] = [], passport: PTVehiclePassport? = nil) -> PTProtocolEvidenceV3Document {
        let frames = results.map(\.frame)
        let fields = results.flatMap { result in
            let markerDistance = nearestMarkerDistanceMilliseconds(for: result)
            return result.fieldObservations.map { field in
                PTBuild69FieldObservation(
                    id: field.id,
                    fieldKey: field.fieldKey,
                    role: field.role,
                    source: field.source,
                    raw: field.raw,
                    normalizedValue: field.normalizedValue,
                    availability: field.availability,
                    quality: field.quality,
                    confidence: field.confidence,
                    markerDistanceMilliseconds: field.markerDistanceMilliseconds ?? markerDistance,
                    dashboardTick: field.dashboardTick,
                    monotonicNanoseconds: field.monotonicNanoseconds,
                    correlationIDs: field.correlationIDs
                )
            }
        }
        // EN: Add the latest unified snapshot so BLE, OBD, GPS, and Motion can be compared at export time.
        // ES: Añade la última instantánea unificada para comparar BLE, OBD, GPS y Motion al exportar.
        // 中文：导出时加入最新统一遥测快照，使 BLE、OBD、GPS 和 Motion 可以进行跨源比较。
        let evidenceObservations = results.flatMap(\.observations)
        let liveObservations = PTBuild69UnifiedObservationAdapter.observations(
            from: PTVehicleTelemetryBridge.shared.snapshot,
            at: date
        )
        let observations = Self.mergeObservations(evidenceObservations + liveObservations)
        let candidates = results.flatMap(\.candidates).sorted { $0.score.total > $1.score.total }
        let anomalies = results.flatMap(\.anomalies).sorted { $0.timestamp > $1.timestamp }
        let correlation = PTBuild69TelemetryCorrelationEngine.correlate(observations: observations)
        let basePassport = passport ?? PTVehiclePassport(schemaVersion: 3, generatedAt: date, vehicleID: nil, vehicleFields: [], adapterFields: [])
        return PTProtocolEvidenceV3Document(generatedAt: date, records: records, semanticFrames: Array(frames.suffix(500)), fieldObservations: Array(fields.suffix(2_000)), observations: Array(observations.suffix(2_000)), candidates: Array(candidates.prefix(500)), anomalies: Array(anomalies.prefix(500)), correlations: correlation, passport: PTBuild69PassportReducer.reduce(base: basePassport, records: records, generatedAt: date))
    }

    public func exportJSONData(at date: Date = Date(), records: [PTProtocolEvidenceRecord] = [], passport: PTVehiclePassport? = nil) throws -> Data {
        try PTProtocolEvidenceV3Exporter.jsonData(for: document(at: date, records: records, passport: passport))
    }

    public func exportCSVData(at date: Date = Date(), records: [PTProtocolEvidenceRecord] = [], passport: PTVehiclePassport? = nil) -> Data {
        PTProtocolEvidenceV3Exporter.csvData(for: document(at: date, records: records, passport: passport))
    }

    public func clear() {
        results.removeAll(keepingCapacity: true)
        markers.removeAll(keepingCapacity: true)
        persist()
    }

    // EN: Select the nearest marker using monotonic time whenever both sides provide it, then fall back to wall time.
    // ES: Selecciona la marca más cercana usando tiempo monótono cuando ambos lados lo tienen y luego usa hora civil.
    // 中文：双方都有单调时间时优先用它选择最近 Marker，否则回退到墙上时间。
    private func nearestMarkerDistanceMilliseconds(for result: PTBuild69EvidenceIngestResult) -> Int64? {
        guard !markers.isEmpty else { return nil }
        let observationMonotonicNanoseconds = result.fieldObservations.first(where: { $0.monotonicNanoseconds > 0 })?.monotonicNanoseconds
        let candidates: [(distance: Int64, absolute: Double)] = markers.compactMap { marker in
            if let observationMonotonicNanoseconds, marker.monotonicNanoseconds > 0 {
                let delta = marker.monotonicNanoseconds >= observationMonotonicNanoseconds
                    ? Double(marker.monotonicNanoseconds - observationMonotonicNanoseconds)
                    : -Double(observationMonotonicNanoseconds - marker.monotonicNanoseconds)
                return (Int64(delta / 1_000_000), abs(delta))
            }
            let milliseconds = marker.timestamp.timeIntervalSince(result.timestamp) * 1_000
            guard milliseconds.isFinite else { return nil }
            return (Int64(milliseconds.rounded()), abs(milliseconds))
        }
        return candidates.min { $0.absolute < $1.absolute }?.distance
    }

    private static func mergeObservations(_ observations: [PTBuild69UnifiedObservation]) -> [PTBuild69UnifiedObservation] {
        var seen = Set<String>()
        return observations.filter { observation in
            let key = [
                observation.fieldKey,
                observation.source.rawValue,
                String(observation.monotonicNanoseconds),
                observation.wallClock.timeIntervalSince1970.description,
                observation.numericValue?.description ?? observation.textValue ?? "—"
            ].joined(separator: "|")
            return seen.insert(key).inserted
        }
    }

    private func persist() {
        guard let data = try? Self.encoder.encode(PTBuild69PersistedEvidence(results: results, markers: markers)) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public nonisolated struct PTBuild69HistoricalReanalysis: Codable, Equatable, Sendable {
    public let sourceRecordCount: Int
    public let candidateCount: Int
    public let anomalyCount: Int
    public let ignoredPeriodicCount: Int
    public let notes: [String]

    public init(sourceRecordCount: Int, candidateCount: Int, anomalyCount: Int, ignoredPeriodicCount: Int, notes: [String]) {
        self.sourceRecordCount = sourceRecordCount
        self.candidateCount = candidateCount
        self.anomalyCount = anomalyCount
        self.ignoredPeriodicCount = ignoredPeriodicCount
        self.notes = notes
    }
}

public nonisolated enum PTBuild69HistoricalReanalyzer {
    public static func analyze(records: [PTProtocolEvidenceRecord]) -> PTBuild69HistoricalReanalysis {
        let periodic = records.filter { $0.value.contains("rollingCounter") || $0.value.contains("RTC:") || $0.value.contains("padding") }.count
        let candidateCount = records.filter { $0.kind == .candidate || $0.value.localizedCaseInsensitiveContains("candidate") }.count
        let anomalies = records.filter { $0.value.localizedCaseInsensitiveContains("invalid") || $0.value.localizedCaseInsensitiveContains("malformed") }.count
        return PTBuild69HistoricalReanalysis(sourceRecordCount: records.count, candidateCount: candidateCount, anomalyCount: anomalies, ignoredPeriodicCount: periodic, notes: ["Historical records remain observations; re-analysis does not create executable commands."])
    }
}

// EN: The v3 export is an additive bridge from the established evidence store; it does not alter v2 persistence.
// ES: La exportación v3 es un puente aditivo desde el almacén existente y no altera la persistencia v2.
// 中文：v3 导出是现有证据库的增量桥接，不改变 v2 持久化格式。
@MainActor
public extension PTProtocolEvidenceV2Store {
    func exportBuild69JSONData(at date: Date = Date()) throws -> Data {
        try PTBuild69EvidenceStore.shared.exportJSONData(at: date, records: records, passport: passport(at: date))
    }

    func exportBuild69CSVData(at date: Date = Date()) -> Data {
        PTBuild69EvidenceStore.shared.exportCSVData(at: date, records: records, passport: passport(at: date))
    }
}
