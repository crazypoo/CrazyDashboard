//
//  PTBuild65Hardening.swift
//  CrazyDashboard
//
//  EN: Build 65 keeps concurrency ownership, release safety, privacy, and validation limits explicit.
//  ES: Build 65 mantiene explícitos los límites de concurrencia, seguridad de Release, privacidad y validación.
//  中文：Build 65 明确记录并发归属、Release 安全、隐私和验证边界。
//

import Foundation

public nonisolated enum PTBuild65MigrationStage: String, Codable, CaseIterable, Sendable {
    case testsAndPureModels
    case researchData
    case telemetry
    case obdCore
    case instruments
    case mainApp
    case widget
    case watch
}

public nonisolated enum PTBuild65ConcurrencyOwner: String, Codable, CaseIterable, Sendable {
    case mainActor
    case xp400SerialOwnership
    case elmSessionActor
    case telemetryActor
    case evidenceDatabaseExecutor
    case crazyTracePersistenceActor
    case providerActor
    case uiStoreMainActor
}

public nonisolated struct PTBuild65ConcurrencyOwnershipEntry: Codable, Equatable, Sendable {
    public let domain: String
    public let owner: PTBuild65ConcurrencyOwner
    public let mutableState: String
    public let migrationStage: PTBuild65MigrationStage
    public let protectedCore: Bool

    public init(
        domain: String,
        owner: PTBuild65ConcurrencyOwner,
        mutableState: String,
        migrationStage: PTBuild65MigrationStage,
        protectedCore: Bool = false
    ) {
        self.domain = domain
        self.owner = owner
        self.mutableState = mutableState
        self.migrationStage = migrationStage
        self.protectedCore = protectedCore
    }
}

public nonisolated enum PTBuild65ConcurrencyOwnershipMatrix {
    public static let entries: [PTBuild65ConcurrencyOwnershipEntry] = [
        PTBuild65ConcurrencyOwnershipEntry(
            domain: "UIKit / view controllers",
            owner: .mainActor,
            mutableState: "view hierarchy and user-facing state",
            migrationStage: .mainApp
        ),
        PTBuild65ConcurrencyOwnershipEntry(
            domain: "XP400 BLE session",
            owner: .xp400SerialOwnership,
            mutableState: "existing PTBluetoothManager serial state",
            migrationStage: .mainApp,
            protectedCore: true
        ),
        PTBuild65ConcurrencyOwnershipEntry(
            domain: "ELM327 / OBD session",
            owner: .elmSessionActor,
            mutableState: "PTELM327Session and the existing compatibility lease",
            migrationStage: .obdCore,
            protectedCore: true
        ),
        PTBuild65ConcurrencyOwnershipEntry(
            domain: "Unified telemetry resolver",
            owner: .telemetryActor,
            mutableState: "immutable observations and resolved projections",
            migrationStage: .telemetry
        ),
        PTBuild65ConcurrencyOwnershipEntry(
            domain: "Protocol Evidence database",
            owner: .evidenceDatabaseExecutor,
            mutableState: "SQLite connection behind one serialized executor",
            migrationStage: .researchData
        ),
        PTBuild65ConcurrencyOwnershipEntry(
            domain: "CrazyTrace persistence",
            owner: .crazyTracePersistenceActor,
            mutableState: "atomic package files and replay documents",
            migrationStage: .researchData
        ),
        PTBuild65ConcurrencyOwnershipEntry(
            domain: "Instruments sampling providers",
            owner: .providerActor,
            mutableState: "copied provider snapshots only",
            migrationStage: .instruments
        ),
        PTBuild65ConcurrencyOwnershipEntry(
            domain: "UI stores",
            owner: .uiStoreMainActor,
            mutableState: "bounded history and UI notifications",
            migrationStage: .mainApp
        )
    ]

    public static let protectedCoreFiles = [
        "Global/OBD/Function/PTHiddenOBDConnector.swift",
        "Global/OBD/Function/PTOBDCommand.swift",
        "Global/BLE/PTBluetoothManager.swift"
    ]

    public static let sendableModelNames = [
        "PTVehicleTelemetrySnapshot",
        "PTVehicleTelemetrySignal",
        "PTCrazyDashboardInstrumentSnapshot",
        "PTProtocolEvidenceRecord",
        "PTProtocolCANBitCandidate",
        "PTVehicleSignalDefinition",
        "PTElectronicControlUnit",
        "PTCrazyTraceEvent"
    ]

    public static func entry(for domain: String) -> PTBuild65ConcurrencyOwnershipEntry? {
        entries.first { $0.domain == domain }
    }
}

public nonisolated struct PTBuild65ReleaseSafetyPolicy: Codable, Equatable, Sendable {
    public let developerSurfaceVisible: Bool
    public let unknownUDSMutationAllowed: Bool
    public let firmwareResearchReadOnly: Bool
    public let canInjectionAllowed: Bool
    public let securityAccessAutomationAllowed: Bool
    public let jieliOTARestrictedToYMOBD: Bool

    public init(
        developerSurfaceVisible: Bool,
        unknownUDSMutationAllowed: Bool,
        firmwareResearchReadOnly: Bool,
        canInjectionAllowed: Bool,
        securityAccessAutomationAllowed: Bool,
        jieliOTARestrictedToYMOBD: Bool
    ) {
        self.developerSurfaceVisible = developerSurfaceVisible
        self.unknownUDSMutationAllowed = unknownUDSMutationAllowed
        self.firmwareResearchReadOnly = firmwareResearchReadOnly
        self.canInjectionAllowed = canInjectionAllowed
        self.securityAccessAutomationAllowed = securityAccessAutomationAllowed
        self.jieliOTARestrictedToYMOBD = jieliOTARestrictedToYMOBD
    }

    // EN: The public Release baseline is safe by default; an explicit TestFlight developer gate remains a separate decision.
    // ES: La línea base pública de Release es segura por defecto; la puerta explícita de desarrollador de TestFlight es una decisión separada.
    // 中文：公开 Release 基线默认安全；TestFlight 的显式开发者门禁仍是独立决策。
    public static let publicReleaseDefault = PTBuild65ReleaseSafetyPolicy(
        developerSurfaceVisible: false,
        unknownUDSMutationAllowed: false,
        firmwareResearchReadOnly: true,
        canInjectionAllowed: false,
        securityAccessAutomationAllowed: false,
        jieliOTARestrictedToYMOBD: true
    )

    public func allowsJieliOTA(for adapterVendor: String?) -> Bool {
        guard jieliOTARestrictedToYMOBD else { return true }
        return adapterVendor?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ymobd"
    }

    public var isSafePublicBaseline: Bool {
        !developerSurfaceVisible &&
        !unknownUDSMutationAllowed &&
        firmwareResearchReadOnly &&
        !canInjectionAllowed &&
        !securityAccessAutomationAllowed &&
        jieliOTARestrictedToYMOBD
    }
}

public nonisolated enum PTBuild65PrivacyPolicy {
    public static let redactedExportFields = [
        "VIN",
        "MAC",
        "precise parking",
        "home location",
        "contacts",
        "PTT audio",
        "notification text"
    ]

    private static let sensitiveKeyFragments = [
        "vin", "mac", "uuid", "address", "latitude", "longitude", "location", "park", "home",
        "contact", "phone", "email", "ptt", "audio", "notification", "message", "title", "body", "lyric"
    ]

    public static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return sensitiveKeyFragments.contains { normalized.contains($0) }
    }

    public static func redactFreeText(_ value: String) -> String {
        guard !value.isEmpty else { return value }
        return "<redacted-text>"
    }

    public static func redactProtocolText(_ value: String) -> String {
        value
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t" || $0 == "," || $0 == ";" || $0 == "|" })
            .map { token -> String in
                let tokenString = String(token)
                let uppercased = tokenString.uppercased()
                if uppercased.hasPrefix("VIN=") || uppercased.hasPrefix("VIN:") {
                    return String(tokenString.prefix(4)) + "<redacted>"
                }
                if uppercased.hasPrefix("MAC=") || uppercased.hasPrefix("MAC:") {
                    return String(tokenString.prefix(4)) + "<redacted>"
                }
                if uppercased.hasPrefix("UUID=") || uppercased.hasPrefix("UUID:") {
                    return String(tokenString.prefix(5)) + "<redacted>"
                }
                let scalars = tokenString.unicodeScalars
                if scalars.count == 17 && scalars.allSatisfy(CharacterSet.alphanumerics.contains) {
                    return "<redacted-vin>"
                }
                return tokenString
            }
            .joined(separator: " ")
    }

    // EN: Redact free-form export text only when its label indicates personal content; protocol facts stay useful.
    // ES: Redacta texto libre solo cuando su etiqueta indica contenido personal; los hechos del protocolo siguen siendo útiles.
    // 中文：只有文本标签指向个人内容时才整体脱敏，保留普通协议事实的研究价值。
    public static func redactExportText(_ value: String) -> String {
        let normalized = value.lowercased()
        let privateFragments = [
            "notification", "message", "audio", "ptt", "contact", "phone", "email",
            "home", "parking", "latitude", "longitude", "location"
        ]
        if privateFragments.contains(where: normalized.contains) {
            return redactFreeText(value)
        }
        return redactProtocolText(value)
    }
}

public nonisolated struct PTBuild65StorageStressProfile: Codable, Equatable, Sendable {
    public let evidenceRecords: Int
    public let canFrames: Int
    public let crazyTraceHours: Int
    public let rideCount: Int

    public init(
        evidenceRecords: Int = 100_000,
        canFrames: Int = 1_000_000,
        crazyTraceHours: Int = 4,
        rideCount: Int = 1_000
    ) {
        self.evidenceRecords = max(0, evidenceRecords)
        self.canFrames = max(0, canFrames)
        self.crazyTraceHours = max(0, crazyTraceHours)
        self.rideCount = max(0, rideCount)
    }

    public static let releaseProfile = PTBuild65StorageStressProfile()
    public static let boundedUnitTestProfile = PTBuild65StorageStressProfile(
        evidenceRecords: 256,
        canFrames: 512,
        crazyTraceHours: 1,
        rideCount: 8
    )
}

public nonisolated enum PTBuild65LifecycleScenario: String, Codable, CaseIterable, Sendable {
    case foreground
    case background
    case screenLocked
    case bluetoothOffOn
    case networkOffOn
    case lowPowerMode
    case thermalPressure
    case memoryWarning
    case appTerminated
    case stateRestoration
    case xp400BLEOnly
    case obdOnly
    case xp400AndOBD
    case navigation
    case ptt
    case instruments
    case canCapture
}

public nonisolated struct PTBuild65LifecycleMatrixRow: Codable, Equatable, Sendable {
    public let scenario: PTBuild65LifecycleScenario
    public let validationLevel: String
    public let expectedInvariant: String

    public init(scenario: PTBuild65LifecycleScenario, validationLevel: String, expectedInvariant: String) {
        self.scenario = scenario
        self.validationLevel = validationLevel
        self.expectedInvariant = expectedInvariant
    }
}

public nonisolated enum PTBuild65LifecycleMatrix {
    public static let rows: [PTBuild65LifecycleMatrixRow] = [
        PTBuild65LifecycleMatrixRow(scenario: .foreground, validationLevel: "real iPhone", expectedInvariant: "active sessions continue without duplicate owners"),
        PTBuild65LifecycleMatrixRow(scenario: .background, validationLevel: "real iPhone", expectedInvariant: "safe background work continues and developer authorization is revoked"),
        PTBuild65LifecycleMatrixRow(scenario: .screenLocked, validationLevel: "real iPhone", expectedInvariant: "permitted telemetry survives screen lock without UI assumptions"),
        PTBuild65LifecycleMatrixRow(scenario: .bluetoothOffOn, validationLevel: "real iPhone + vehicle", expectedInvariant: "disconnect and reconnect do not duplicate callbacks"),
        PTBuild65LifecycleMatrixRow(scenario: .networkOffOn, validationLevel: "real iPhone", expectedInvariant: "local data remains available and cloud errors are explicit"),
        PTBuild65LifecycleMatrixRow(scenario: .lowPowerMode, validationLevel: "real iPhone", expectedInvariant: "sampling remains bounded"),
        PTBuild65LifecycleMatrixRow(scenario: .thermalPressure, validationLevel: "real iPhone", expectedInvariant: "sampling can be reduced without corrupting storage"),
        PTBuild65LifecycleMatrixRow(scenario: .memoryWarning, validationLevel: "real iPhone", expectedInvariant: "bounded histories release without losing committed files"),
        PTBuild65LifecycleMatrixRow(scenario: .appTerminated, validationLevel: "real iPhone", expectedInvariant: "atomic files and checkpoints remain readable"),
        PTBuild65LifecycleMatrixRow(scenario: .stateRestoration, validationLevel: "real iPhone", expectedInvariant: "last committed state restores without replaying commands"),
        PTBuild65LifecycleMatrixRow(scenario: .xp400BLEOnly, validationLevel: "real XP400", expectedInvariant: "BLE lifecycle remains independent from OBD OTA"),
        PTBuild65LifecycleMatrixRow(scenario: .obdOnly, validationLevel: "real adapter", expectedInvariant: "ELM lease returns after success, cancel, and disconnect"),
        PTBuild65LifecycleMatrixRow(scenario: .xp400AndOBD, validationLevel: "real XP400 + adapter", expectedInvariant: "two domains never stop each other accidentally"),
        PTBuild65LifecycleMatrixRow(scenario: .navigation, validationLevel: "real road", expectedInvariant: "navigation and telemetry remain responsive"),
        PTBuild65LifecycleMatrixRow(scenario: .ptt, validationLevel: "real iPhone + group", expectedInvariant: "audio/session cleanup releases live state"),
        PTBuild65LifecycleMatrixRow(scenario: .instruments, validationLevel: "real iPhone", expectedInvariant: "history remains bounded and export is atomic"),
        PTBuild65LifecycleMatrixRow(scenario: .canCapture, validationLevel: "real adapter", expectedInvariant: "capture is explicit, bounded, and cannot inject frames")
    ]
}

// EN: Deterministic malformed inputs exercise every parser boundary without touching a live vehicle.
// ES: Las entradas malformadas deterministas ejercitan cada límite de análisis sin tocar un vehículo real.
// 中文：确定性异常输入覆盖各个解析边界，且不会接触真实车辆。
public nonisolated struct PTBuild65MalformedInput: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let data: Data

    public init(id: String, data: Data) {
        self.id = id
        self.data = data
    }
}

public nonisolated enum PTBuild65MalformedInputCorpus {
    public static let cases: [PTBuild65MalformedInput] = [
        PTBuild65MalformedInput(id: "empty", data: Data()),
        PTBuild65MalformedInput(id: "truncated", data: Data([0x16, 0x01, 0x00])),
        PTBuild65MalformedInput(id: "oversized", data: Data(repeating: 0x41, count: 100_000)),
        PTBuild65MalformedInput(id: "invalid-utf8", data: Data([0xFF, 0xFE, 0xFD])),
        PTBuild65MalformedInput(id: "invalid-hex", data: Data("GG ZZ 0x".utf8)),
        PTBuild65MalformedInput(id: "duplicate", data: Data("duplicate duplicate".utf8)),
        PTBuild65MalformedInput(id: "out-of-order", data: Data("sequence=2 sequence=1".utf8)),
        PTBuild65MalformedInput(id: "unknown-schema", data: Data("{\"schemaVersion\":999}".utf8))
    ]
}

public nonisolated struct PTBuild65SoakStage: Codable, Equatable, Sendable {
    public let durationMinutes: Int
    public let scenarios: [PTBuild65LifecycleScenario]
    public let observedMetrics: [String]

    public init(
        durationMinutes: Int,
        scenarios: [PTBuild65LifecycleScenario],
        observedMetrics: [String]
    ) {
        self.durationMinutes = max(1, durationMinutes)
        self.scenarios = Array(scenarios)
        self.observedMetrics = Array(observedMetrics.prefix(16))
    }
}

// EN: The soak plan is data, not an automatic vehicle operation; a human starts and stops each run.
// ES: El plan de resistencia es solo datos, no una operación automática del vehículo; una persona controla cada ejecución.
// 中文：Soak 计划只是数据，不会自动操作车辆；每次运行都由开发者人工开始和停止。
public nonisolated enum PTBuild65SoakPlan {
    public static let stages: [PTBuild65SoakStage] = [
        PTBuild65SoakStage(
            durationMinutes: 30,
            scenarios: [.xp400BLEOnly, .obdOnly, .xp400AndOBD, .navigation, .instruments, .canCapture],
            observedMetrics: ["memory", "cpu", "thermal", "battery", "queueDepth", "reconnectCount", "fileGrowth", "databaseGrowth"]
        ),
        PTBuild65SoakStage(
            durationMinutes: 120,
            scenarios: [.xp400AndOBD, .background, .screenLocked, .networkOffOn, .bluetoothOffOn, .ptt],
            observedMetrics: ["memory", "cpu", "thermal", "battery", "queueDepth", "reconnectCount"]
        ),
        PTBuild65SoakStage(
            durationMinutes: 240,
            scenarios: [.xp400AndOBD, .navigation, .ptt, .instruments, .canCapture, .stateRestoration],
            observedMetrics: ["memory", "cpu", "thermal", "battery", "queueDepth", "reconnectCount", "fileGrowth", "databaseGrowth"]
        )
    ]
}
