//
//  PTVehicleIdentityModels.swift
//  CrazyDashboard
//
//  EN: Build 64 models the XP400 electronic identity without changing any transport core.
//  ES: Build 64 modela la identidad electrónica del XP400 sin cambiar ningún núcleo de transporte.
//  中文：Build 64 建模 XP400 电子身份，不修改任何传输核心。
//

import CryptoKit
import Foundation

// EN: The role describes a vehicle ECU; YMOBD is deliberately represented by a separate adapter type.
// ES: El rol describe una ECU del vehículo; YMOBD se representa deliberadamente como un adaptador separado.
// 中文：角色描述车辆 ECU；YMOBD 有意使用独立的适配器类型表示。
public nonisolated enum PTECURole: String, Codable, CaseIterable, Sendable {
    case dashboard
    case connectivityBox
    case engine
    case abs
    case body
    case unknown
}

// EN: These keys are the stable contract between identity evidence, topology, Passport projection, and diff reports.
// ES: Estas claves son el contrato estable entre la evidencia, la topología, el Passport y los informes de diferencias.
// 中文：这些键是身份证据、拓扑、Passport 投影和差异报告之间的稳定契约。
public nonisolated enum PTVehicleIdentityFieldKey: String, Codable, CaseIterable, Sendable {
    case vehicleModel = "vehicle.model"
    case vehicleVIN = "vehicle.vin"
    case electronicReference = "vehicle.electronicReference"
    case dashboardReference = "dashboard.reference"
    case dashboardHardware = "dashboard.hardware"
    case dashboardSoftware = "dashboard.software"
    case dashboardBoot = "dashboard.boot"
    case dashboardSerial = "dashboard.serial"
    case dashboardAddress = "dashboard.address"
    case connectivityReference = "connectivityBox.reference"
    case connectivityHardware = "connectivityBox.hardware"
    case connectivitySoftware = "connectivityBox.software"
    case connectivityBoot = "connectivityBox.boot"
    case connectivitySerial = "connectivityBox.serial"
    case connectivityBLEFingerprint = "connectivityBox.bleFingerprint"
    case connectivityProtocolFingerprint = "connectivityBox.protocolFingerprint"
    case connectivityAddress = "connectivityBox.address"
    case engineHardware = "engine.hardware"
    case engineSoftware = "engine.software"
    case engineBoot = "engine.boot"
    case engineCalibration = "engine.calibration"
    case engineSerial = "engine.serial"
    case engineAddress = "engine.address"
    case absHardware = "abs.hardware"
    case absSoftware = "abs.software"
    case absBoot = "abs.boot"
    case absCalibration = "abs.calibration"
    case absSerial = "abs.serial"
    case absAddress = "abs.address"
    case bodyHardware = "body.hardware"
    case bodySoftware = "body.software"
    case bodyBoot = "body.boot"
    case bodyCalibration = "body.calibration"
    case bodySerial = "body.serial"
    case bodyAddress = "body.address"
    case adapterVendor = "adapter.vendor"
    case adapterModel = "adapter.model"
    case adapterFirmware = "adapter.firmware"
    case adapterTransport = "adapter.transport"
    case adapterBLEFingerprint = "adapter.bleFingerprint"
    case adapterProtocolFingerprint = "adapter.protocolFingerprint"
    case adapterOTACapability = "adapter.otaCapability"
}

// EN: Provenance is explicit so a stored profile can never be mistaken for a live ECU read.
// ES: La procedencia es explícita para no confundir un perfil guardado con una lectura ECU en vivo.
// 中文：来源必须显式记录，避免把存储档案误认为实时 ECU 读取结果。
public nonisolated enum PTVehicleIdentityEvidenceTier: String, Codable, CaseIterable, Sendable {
    case official
    case liveCaptured
    case repeatedCaptured
    case storedProfile
    case unavailable

    public var rank: Int {
        switch self {
        case .official: return 4
        case .liveCaptured: return 3
        case .repeatedCaptured: return 2
        case .storedProfile: return 1
        case .unavailable: return 0
        }
    }
}

// EN: Every resolved value carries source, confidence, evidence IDs, and time; nil means unavailable, never guessed.
// ES: Cada valor resuelto lleva fuente, confianza, IDs de evidencia y tiempo; nil significa no disponible, nunca estimado.
// 中文：每个解析值都携带来源、置信度、证据 ID 和时间；nil 表示不可用，绝不猜测。
public nonisolated struct PTEvidenceBackedValue<Value: Codable & Sendable>: Codable, Sendable {
    public let value: Value?
    public let source: PTProtocolEvidenceSource
    public let confidence: Double
    public let evidenceIDs: [UUID]
    public let updatedAt: Date
    public let tier: PTVehicleIdentityEvidenceTier

    public init(
        value: Value?,
        source: PTProtocolEvidenceSource,
        confidence: Double,
        evidenceIDs: [UUID] = [],
        updatedAt: Date = Date(),
        tier: PTVehicleIdentityEvidenceTier? = nil
    ) {
        let normalizedIDs = Array(Set(evidenceIDs)).sorted { $0.uuidString < $1.uuidString }
        let available = value != nil
        self.value = value
        self.source = available ? source : .unknown
        self.confidence = available && confidence.isFinite ? min(max(confidence, 0), 1) : 0
        self.evidenceIDs = available ? normalizedIDs : []
        self.updatedAt = updatedAt
        self.tier = available
            ? (normalizedIDs.isEmpty ? .storedProfile : (tier ?? Self.defaultTier(source: source, evidenceIDs: normalizedIDs)))
            : .unavailable
    }

    public static func unavailable(at date: Date = Date()) -> Self {
        Self(value: nil, source: .unknown, confidence: 0, updatedAt: date, tier: .unavailable)
    }

    public var isAvailable: Bool { value != nil }
    public var isTraceable: Bool { !evidenceIDs.isEmpty }

    private static func defaultTier(
        source: PTProtocolEvidenceSource,
        evidenceIDs: [UUID]
    ) -> PTVehicleIdentityEvidenceTier {
        guard !evidenceIDs.isEmpty else { return .storedProfile }
        return source == .live ? .liveCaptured : .repeatedCaptured
    }
}

extension PTEvidenceBackedValue: Equatable where Value: Equatable {}

// EN: Stable IDs keep repeated identity resolution diffable across app launches.
// ES: Los IDs estables permiten comparar resoluciones repetidas entre lanzamientos de la app.
// 中文：稳定 ID 让多次身份解析可以跨 App 启动进行差异比较。
public nonisolated enum PTVehicleIdentityStableID {
    public static func make(_ seed: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

// EN: One ECU record contains only read-only identity facts and their provenance.
// ES: Cada ECU contiene únicamente hechos de identidad de solo lectura y su procedencia.
// 中文：每条 ECU 记录只包含只读身份事实及其来源。
public nonisolated struct PTElectronicControlUnit: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let role: PTECURole
    public let reference: PTEvidenceBackedValue<String>
    public let diagnosticAddress: PTOBDiagnosticAddress?
    public let diagnosticAddressEvidenceIDs: [UUID]
    public let hardwareVersion: PTEvidenceBackedValue<String>
    public let softwareVersion: PTEvidenceBackedValue<String>
    public let bootVersion: PTEvidenceBackedValue<String>
    public let calibrationID: PTEvidenceBackedValue<String>
    public let serialNumber: PTEvidenceBackedValue<String>
    public let lastSeenAt: Date?

    public init(
        id: UUID = UUID(),
        role: PTECURole,
        reference: PTEvidenceBackedValue<String> = .unavailable(),
        diagnosticAddress: PTOBDiagnosticAddress? = nil,
        diagnosticAddressEvidenceIDs: [UUID] = [],
        hardwareVersion: PTEvidenceBackedValue<String> = .unavailable(),
        softwareVersion: PTEvidenceBackedValue<String> = .unavailable(),
        bootVersion: PTEvidenceBackedValue<String> = .unavailable(),
        calibrationID: PTEvidenceBackedValue<String> = .unavailable(),
        serialNumber: PTEvidenceBackedValue<String> = .unavailable(),
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.role = role
        self.reference = reference
        self.diagnosticAddress = diagnosticAddress
        self.diagnosticAddressEvidenceIDs = Array(Set(diagnosticAddressEvidenceIDs)).sorted { $0.uuidString < $1.uuidString }
        self.hardwareVersion = hardwareVersion
        self.softwareVersion = softwareVersion
        self.bootVersion = bootVersion
        self.calibrationID = calibrationID
        self.serialNumber = serialNumber
        self.lastSeenAt = lastSeenAt
    }

    public var evidenceIDs: [UUID] {
        Array(Set([
            reference.evidenceIDs,
            diagnosticAddressEvidenceIDs,
            hardwareVersion.evidenceIDs,
            softwareVersion.evidenceIDs,
            bootVersion.evidenceIDs,
            calibrationID.evidenceIDs,
            serialNumber.evidenceIDs
        ].flatMap { $0 })).sorted { $0.uuidString < $1.uuidString }
    }

    public var hasIdentity: Bool {
        reference.isAvailable || diagnosticAddress != nil || hardwareVersion.isAvailable || softwareVersion.isAvailable
            || bootVersion.isAvailable || calibrationID.isAvailable || serialNumber.isAvailable
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case reference
        case diagnosticAddress
        case diagnosticAddressEvidenceIDs
        case hardwareVersion
        case softwareVersion
        case bootVersion
        case calibrationID
        case serialNumber
        case lastSeenAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.role = try container.decode(PTECURole.self, forKey: .role)
        self.reference = try container.decodeIfPresent(PTEvidenceBackedValue<String>.self, forKey: .reference)
            ?? .unavailable(at: Date(timeIntervalSince1970: 0))
        self.diagnosticAddress = try container.decodeIfPresent(PTOBDiagnosticAddress.self, forKey: .diagnosticAddress)
        self.diagnosticAddressEvidenceIDs = Array(Set(
            try container.decodeIfPresent([UUID].self, forKey: .diagnosticAddressEvidenceIDs) ?? []
        )).sorted { $0.uuidString < $1.uuidString }
        self.hardwareVersion = try container.decode(PTEvidenceBackedValue<String>.self, forKey: .hardwareVersion)
        self.softwareVersion = try container.decode(PTEvidenceBackedValue<String>.self, forKey: .softwareVersion)
        self.bootVersion = try container.decode(PTEvidenceBackedValue<String>.self, forKey: .bootVersion)
        self.calibrationID = try container.decode(PTEvidenceBackedValue<String>.self, forKey: .calibrationID)
        self.serialNumber = try container.decode(PTEvidenceBackedValue<String>.self, forKey: .serialNumber)
        self.lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(reference, forKey: .reference)
        try container.encodeIfPresent(diagnosticAddress, forKey: .diagnosticAddress)
        try container.encode(diagnosticAddressEvidenceIDs, forKey: .diagnosticAddressEvidenceIDs)
        try container.encode(hardwareVersion, forKey: .hardwareVersion)
        try container.encode(softwareVersion, forKey: .softwareVersion)
        try container.encode(bootVersion, forKey: .bootVersion)
        try container.encode(calibrationID, forKey: .calibrationID)
        try container.encode(serialNumber, forKey: .serialNumber)
        try container.encodeIfPresent(lastSeenAt, forKey: .lastSeenAt)
    }
}

// EN: YMOBD is diagnostic hardware, never a vehicle ECU in the topology.
// ES: YMOBD es hardware de diagnóstico, nunca una ECU del vehículo en la topología.
// 中文：YMOBD 是诊断硬件，在拓扑中绝不是车辆 ECU。
public nonisolated struct PTDiagnosticAdapterIdentity: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let vendor: PTEvidenceBackedValue<String>
    public let model: PTEvidenceBackedValue<String>
    public let firmwareVersion: PTEvidenceBackedValue<String>
    public let transport: PTEvidenceBackedValue<String>
    public let bleFingerprint: PTEvidenceBackedValue<String>
    public let protocolFingerprint: PTEvidenceBackedValue<String>
    public let supportsJieliOTA: PTEvidenceBackedValue<Bool>

    public init(
        id: UUID = UUID(),
        vendor: PTEvidenceBackedValue<String> = .unavailable(),
        model: PTEvidenceBackedValue<String> = .unavailable(),
        firmwareVersion: PTEvidenceBackedValue<String> = .unavailable(),
        transport: PTEvidenceBackedValue<String> = .unavailable(),
        bleFingerprint: PTEvidenceBackedValue<String> = .unavailable(),
        protocolFingerprint: PTEvidenceBackedValue<String> = .unavailable(),
        supportsJieliOTA: PTEvidenceBackedValue<Bool> = .unavailable()
    ) {
        self.id = id
        self.vendor = vendor
        self.model = model
        self.firmwareVersion = firmwareVersion
        self.transport = transport
        self.bleFingerprint = bleFingerprint
        self.protocolFingerprint = protocolFingerprint
        self.supportsJieliOTA = supportsJieliOTA
    }

    public var evidenceIDs: [UUID] {
        Array(Set([
            vendor.evidenceIDs,
            model.evidenceIDs,
            firmwareVersion.evidenceIDs,
            transport.evidenceIDs,
            bleFingerprint.evidenceIDs,
            protocolFingerprint.evidenceIDs,
            supportsJieliOTA.evidenceIDs
        ].flatMap { $0 })).sorted { $0.uuidString < $1.uuidString }
    }

    public var isAvailable: Bool {
        vendor.isAvailable || model.isAvailable || firmwareVersion.isAvailable
            || transport.isAvailable || bleFingerprint.isAvailable || protocolFingerprint.isAvailable
            || supportsJieliOTA.isAvailable
    }
}

public nonisolated enum PTVehicleTopologyNodeKind: String, Codable, CaseIterable, Sendable {
    case vehicle
    case ecu
    case diagnosticAdapter
    case otaCapability
}

public nonisolated enum PTVehicleTopologyRelation: String, Codable, CaseIterable, Sendable {
    case contains
    case supports
    case reports
}

// EN: Topology nodes and edges carry evidence IDs so UI can navigate from a fact to its observation.
// ES: Los nodos y aristas llevan IDs de evidencia para navegar desde un hecho hasta su observación.
// 中文：拓扑节点和边携带证据 ID，界面可以从事实追溯到观察记录。
public nonisolated struct PTVehicleTopologyNode: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: PTVehicleTopologyNodeKind
    public let title: String
    public let role: PTECURole?
    public let diagnosticAddress: PTOBDDiagnosticAddress?
    public let evidenceIDs: [UUID]

    public init(
        id: String,
        kind: PTVehicleTopologyNodeKind,
        title: String,
        role: PTECURole? = nil,
        diagnosticAddress: PTOBDDiagnosticAddress? = nil,
        evidenceIDs: [UUID] = []
    ) {
        self.id = String(id.prefix(160))
        self.kind = kind
        self.title = String(title.prefix(160))
        self.role = role
        self.diagnosticAddress = diagnosticAddress
        self.evidenceIDs = Array(Set(evidenceIDs)).sorted { $0.uuidString < $1.uuidString }
    }
}

public nonisolated struct PTVehicleTopologyEdge: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let fromNodeID: String
    public let toNodeID: String
    public let relation: PTVehicleTopologyRelation
    public let evidenceIDs: [UUID]

    public init(
        id: String,
        fromNodeID: String,
        toNodeID: String,
        relation: PTVehicleTopologyRelation,
        evidenceIDs: [UUID] = []
    ) {
        self.id = String(id.prefix(160))
        self.fromNodeID = String(fromNodeID.prefix(160))
        self.toNodeID = String(toNodeID.prefix(160))
        self.relation = relation
        self.evidenceIDs = Array(Set(evidenceIDs)).sorted { $0.uuidString < $1.uuidString }
    }
}

public nonisolated struct PTVehicleElectronicTopology: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let vehicleID: UUID?
    public let generatedAt: Date
    public let nodes: [PTVehicleTopologyNode]
    public let edges: [PTVehicleTopologyEdge]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        vehicleID: UUID?,
        generatedAt: Date = Date(),
        nodes: [PTVehicleTopologyNode],
        edges: [PTVehicleTopologyEdge]
    ) {
        self.schemaVersion = schemaVersion
        self.vehicleID = vehicleID
        self.generatedAt = generatedAt
        self.nodes = nodes.sorted { $0.id < $1.id }
        self.edges = edges.sorted { $0.id < $1.id }
    }
}

// EN: This is the Build 64 source-of-truth snapshot; the older Passport remains a compatibility projection.
// ES: Esta es la instantánea fuente de verdad de Build 64; el Passport anterior sigue siendo una proyección compatible.
// 中文：这是 Build 64 的身份事实源；旧 Passport 继续作为兼容投影保留。
public nonisolated struct PTVehicleElectronicIdentity: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public let vehicleID: UUID?
    public let vehicleModel: PTEvidenceBackedValue<String>
    public let electronicReference: PTEvidenceBackedValue<String>
    public let ecus: [PTElectronicControlUnit]
    public let diagnosticAdapter: PTDiagnosticAdapterIdentity?
    public let topology: PTVehicleElectronicTopology
    public let evidenceIDs: [UUID]
    public let generatedAt: Date
    public let lastVerifiedAt: Date?

    public init(
        schemaVersion: Int = currentSchemaVersion,
        id: UUID = UUID(),
        vehicleID: UUID?,
        vehicleModel: PTEvidenceBackedValue<String> = .unavailable(),
        electronicReference: PTEvidenceBackedValue<String> = .unavailable(),
        ecus: [PTElectronicControlUnit] = [],
        diagnosticAdapter: PTDiagnosticAdapterIdentity? = nil,
        topology: PTVehicleElectronicTopology,
        evidenceIDs: [UUID] = [],
        generatedAt: Date = Date(),
        lastVerifiedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.vehicleID = vehicleID
        self.vehicleModel = vehicleModel
        self.electronicReference = electronicReference
        self.ecus = ecus.sorted {
            if $0.role != $1.role { return $0.role.rawValue < $1.role.rawValue }
            return $0.id.uuidString < $1.id.uuidString
        }
        self.diagnosticAdapter = diagnosticAdapter
        self.topology = topology
        self.evidenceIDs = Array(Set([
            evidenceIDs,
            vehicleModel.evidenceIDs,
            electronicReference.evidenceIDs,
            self.ecus.flatMap(\.evidenceIDs),
            diagnosticAdapter?.evidenceIDs ?? []
        ].flatMap { $0 })).sorted { $0.uuidString < $1.uuidString }
        self.generatedAt = generatedAt
        self.lastVerifiedAt = lastVerifiedAt
    }

    public var dashboard: PTElectronicControlUnit? { ecu(for: .dashboard) }
    public var connectivityBox: PTElectronicControlUnit? { ecu(for: .connectivityBox) }
    public var engine: PTElectronicControlUnit? { ecu(for: .engine) }
    public var abs: PTElectronicControlUnit? { ecu(for: .abs) }
    public var body: PTElectronicControlUnit? { ecu(for: .body) }

    public func ecu(for role: PTECURole) -> PTElectronicControlUnit? {
        ecus.first { $0.role == role }
    }
}

public nonisolated enum PTVehicleIdentityFieldChangeKind: String, Codable, CaseIterable, Sendable {
    case added
    case removed
    case changed
}

public nonisolated struct PTVehicleIdentityFieldDiff: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let key: PTVehicleIdentityFieldKey
    public let kind: PTVehicleIdentityFieldChangeKind
    public let oldValue: String?
    public let newValue: String?
    public let firstSeenAt: Date?
    public let lastSeenAt: Date?
    public let evidenceIDs: [UUID]

    public init(
        id: UUID = UUID(),
        key: PTVehicleIdentityFieldKey,
        kind: PTVehicleIdentityFieldChangeKind,
        oldValue: String?,
        newValue: String?,
        firstSeenAt: Date?,
        lastSeenAt: Date?,
        evidenceIDs: [UUID] = []
    ) {
        self.id = id
        self.key = key
        self.kind = kind
        self.oldValue = oldValue
        self.newValue = newValue
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.evidenceIDs = Array(Set(evidenceIDs)).sorted { $0.uuidString < $1.uuidString }
    }
}

public nonisolated struct PTVehicleIdentityDiff: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let vehicleID: UUID?
    public let oldIdentityID: UUID?
    public let newIdentityID: UUID?
    public let generatedAt: Date
    public let changes: [PTVehicleIdentityFieldDiff]

    public init(
        id: UUID = UUID(),
        vehicleID: UUID?,
        oldIdentityID: UUID?,
        newIdentityID: UUID?,
        generatedAt: Date = Date(),
        changes: [PTVehicleIdentityFieldDiff]
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.oldIdentityID = oldIdentityID
        self.newIdentityID = newIdentityID
        self.generatedAt = generatedAt
        self.changes = changes.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    public var hasChanges: Bool { !changes.isEmpty }
}
