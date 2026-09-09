//
//  PTXP400BLEReliability.swift
//  CrazyDashboard
//
//  EN: Reliability policies and bounded diagnostics around the frozen XP400 BLE transport.
//  ES: Políticas de fiabilidad y diagnóstico acotado alrededor del transporte BLE congelado del XP400.
//  中文：围绕已冻结 XP400 BLE 传输核心提供可靠性策略和有界诊断。
//

import Foundation

// EN: This file deliberately stays outside PTBluetoothManager.swift; it cannot silently become a second transport implementation.
// ES: Este archivo permanece deliberadamente fuera de PTBluetoothManager.swift; no puede convertirse en otra implementación de transporte.
// 中文：本文件刻意位于 PTBluetoothManager.swift 外部，不能悄悄演变成第二套传输实现。
// ponytail: Keep the safe boundary small until real-device traces justify a core refactor.

/// EN: Identifies one dashboard connection generation and makes delayed tasks comparable.
/// ES: Identifica una generación de conexión del tablero y permite comparar tareas retrasadas.
/// 中文：标识一次仪表连接代次，便于比较延迟任务。
nonisolated public struct PTXP400BLESessionToken: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let generation: UInt64

    public init(id: UUID = UUID(), generation: UInt64 = 0) {
        self.id = id
        self.generation = generation
    }

    /// EN: Start a new generation without reusing the old UUID.
    /// ES: Inicia una nueva generación sin reutilizar el UUID anterior.
    /// 中文：创建新的代次，不复用旧 UUID。
    public func next() -> Self {
        Self(
            generation: generation == .max ? 0 : generation + 1
        )
    }
}

/// EN: Chooses the smallest safe payload size without changing the confirmed 20-byte protocol ceiling.
/// ES: Elige el tamaño de carga seguro más pequeño sin cambiar el límite de protocolo confirmado de 20 bytes.
/// 中文：在不改变已确认 20 字节协议上限的前提下选择最小安全 Payload 大小。
nonisolated public enum PTXP400BLETransportPolicy {
    public static func effectiveChunkLength(
        protocolMaximum: Int = PTXP400BLEProtocol.maxTIOChunkLength,
        maximumUpdateValueLength: Int?
    ) -> Int {
        let safeProtocolMaximum = max(1, protocolMaximum)
        guard let maximumUpdateValueLength, maximumUpdateValueLength > 0 else {
            return safeProtocolMaximum
        }
        return min(safeProtocolMaximum, maximumUpdateValueLength)
    }
}

/// EN: The official local-name value is intentionally unknown until an Android or real-device capture confirms it.
/// ES: El nombre local oficial permanece desconocido hasta confirmarlo con Android o una captura real.
/// 中文：在 Android 或实车抓包确认前，不猜测官方 Local Name。
nonisolated public enum PTXP400BLELocalNameParity: String, Codable, Sendable {
    case unknown
    case absent
    case matched
    case mismatched
}

/// EN: Describes the currently confirmed XP400 advertisement boundary.
/// ES: Describe el límite de publicidad XP400 actualmente confirmado.
/// 中文：描述当前已经确认的 XP400 广播边界。
nonisolated public struct PTXP400BLEAdvertisementProfile: Codable, Equatable, Sendable {
    public let serviceUUID: String
    public let expectedLocalName: String?

    public init(serviceUUID: String = PTXP400BLEProtocol.tioServiceUUID, expectedLocalName: String? = nil) {
        self.serviceUUID = Self.normalize(serviceUUID)
        self.expectedLocalName = expectedLocalName.map(Self.normalize)
    }

    /// EN: The current core advertises FEFB without a guessed local name.
    /// ES: El núcleo actual anuncia FEFB sin adivinar un nombre local.
    /// 中文：当前核心只广播 FEFB，不猜测 Local Name。
    public static let confirmedXP400 = Self()

    public func matches(advertisedServiceUUIDs: [String], localName: String?) -> Bool {
        guard advertisedServiceUUIDs.contains(where: { Self.normalize($0) == serviceUUID }) else {
            return false
        }

        guard let expectedLocalName else {
            return true
        }
        return localName.map(Self.normalize) == expectedLocalName
    }

    public func localNameParity(observedLocalName: String?) -> PTXP400BLELocalNameParity {
        guard let expectedLocalName else { return .unknown }
        guard let observedLocalName else { return .absent }
        return Self.normalize(observedLocalName) == expectedLocalName ? .matched : .mismatched
    }

    private nonisolated static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

/// EN: Result of validating the only response-with-write flow currently exposed by the protocol: remote TIO credits.
/// ES: Resultado de validar el único flujo de respuesta con escritura expuesto actualmente: créditos TIO remotos.
/// 中文：校验当前协议唯一已暴露的“带回复写入”流程：远端 TIO Credits。
nonisolated public enum PTXP400BLEWriteValidationResult: Equatable, Sendable {
    case accepted(amount: Int)
    case missingValue
    case invalidLength(actual: Int)
    case invalidAmount(actual: Int)
    case balanceOverflow(current: Int, adding: Int)

    public var acceptedAmount: Int? {
        if case .accepted(let amount) = self { return amount }
        return nil
    }
}

/// EN: Mirrors the frozen core's credit boundary for tests, diagnostics, and future transport hooks.
/// ES: Reproduce el límite de créditos del núcleo congelado para pruebas, diagnóstico y futuros hooks de transporte.
/// 中文：为测试、诊断和未来传输 Hook 复用冻结核心的 Credits 边界。
nonisolated public enum PTXP400BLEWriteValidator {
    public static func validateRemoteCredits(
        _ data: Data?,
        currentCredits: Int
    ) -> PTXP400BLEWriteValidationResult {
        guard let data else { return .missingValue }
        guard data.count == 1 else { return .invalidLength(actual: data.count) }
        guard let amount = PTXP400BLEProtocol.validatedRemoteCreditValue(in: data) else {
            return .invalidAmount(actual: Int(data[0]))
        }
        guard PTXP400BLEProtocol.canAcceptRemoteCredits(current: currentCredits, adding: amount) else {
            return .balanceOverflow(current: currentCredits, adding: amount)
        }
        return .accepted(amount: amount)
    }
}

/// EN: Small pure state machine for detecting a queue that remains blocked after backpressure.
/// ES: Pequeña máquina de estado pura para detectar una cola bloqueada después de backpressure.
/// 中文：用于检测背压后持续阻塞队列的小型纯状态机。
nonisolated public struct PTXP400BLESendQueueStallDetector: Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case waitingForCapacity
        case stalled
    }

    public enum Event: Equatable, Sendable {
        case stalled(pendingCount: Int)
    }

    public private(set) var state: State = .idle
    public private(set) var pendingCount = 0

    private let timeoutNanoseconds: UInt64
    private var lastProgressNanoseconds: UInt64?
    private var didReportStall = false

    public init(timeoutNanoseconds: UInt64 = 5_000_000_000) {
        self.timeoutNanoseconds = max(1, timeoutNanoseconds)
    }

    public mutating func enqueue(at nanoseconds: UInt64) {
        pendingCount += 1
        lastProgressNanoseconds = lastProgressNanoseconds ?? nanoseconds
        state = .waitingForCapacity
    }

    /// EN: Call this only after the real transport reports one successful updateValue.
    /// ES: Llama a esto solo después de que el transporte real informe un updateValue exitoso.
    /// 中文：只有真实传输报告一次成功的 updateValue 后才调用。
    public mutating func markProgress(at nanoseconds: UInt64) {
        pendingCount = max(0, pendingCount - 1)
        lastProgressNanoseconds = pendingCount == 0 ? nil : nanoseconds
        didReportStall = false
        state = pendingCount == 0 ? .idle : .waitingForCapacity
    }

    public mutating func markBackpressure(at nanoseconds: UInt64) {
        guard pendingCount > 0 else { return }
        lastProgressNanoseconds = lastProgressNanoseconds ?? nanoseconds
        state = .waitingForCapacity
    }

    public mutating func poll(at nanoseconds: UInt64) -> Event? {
        guard pendingCount > 0,
              let lastProgressNanoseconds,
              nanoseconds >= lastProgressNanoseconds,
              nanoseconds - lastProgressNanoseconds >= timeoutNanoseconds,
              !didReportStall else {
            return nil
        }

        didReportStall = true
        state = .stalled
        return .stalled(pendingCount: pendingCount)
    }

    public mutating func reset() {
        pendingCount = 0
        lastProgressNanoseconds = nil
        didReportStall = false
        state = .idle
    }
}

nonisolated public enum PTXP400BLEReliabilityEventKind: String, Codable, CaseIterable, Sendable {
    case sessionStarted
    case sessionReady
    case automaticReconnect
    case sessionDisconnected
    case sessionFailed
    case staleCallbackIgnored
    case phaseTimeout
    case backgroundReconciled
    case foregroundReconciled
    case malformedWrite
    case backpressure
    case queueStall
    case restorationUnavailable
    case transportCapabilityObserved
    case advertisementObserved
}

/// EN: A bounded event contains lifecycle metadata only; it never stores VIN, coordinates, or raw payloads.
/// ES: Un evento acotado solo contiene metadatos de ciclo de vida; nunca guarda VIN, coordenadas ni cargas sin procesar.
/// 中文：有界事件只保存生命周期元数据，不保存 VIN、坐标或原始 Payload。
nonisolated public struct PTXP400BLEReliabilityEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let kind: PTXP400BLEReliabilityEventKind
    public let tokenID: UUID?
    public let generation: UInt64?
    public let detail: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: PTXP400BLEReliabilityEventKind,
        token: PTXP400BLESessionToken? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.tokenID = token?.id
        self.generation = token?.generation
        self.detail = detail.map { String($0.prefix(256)) }
    }
}

nonisolated public struct PTXP400BLEReliabilitySnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let activeSessionID: UUID?
    public let activeGeneration: UInt64?
    public let totalEventCount: Int
    public let droppedEventCount: Int
    public let eventCounts: [String: Int]
    public let recentEvents: [PTXP400BLEReliabilityEvent]
}

/// EN: Main-actor ownership keeps reliability counters race-free while remaining synchronous for the coordinator.
/// ES: La propiedad del actor principal mantiene los contadores sin carreras y sigue siendo síncrona para el coordinador.
/// 中文：由主 actor 持有指标，避免竞争，同时让协调器可以同步调用。
@MainActor
public final class PTXP400BLEReliabilityMonitor {
    public static let shared = PTXP400BLEReliabilityMonitor()
    nonisolated public static let maximumEventCount = 200

    public private(set) var snapshot: PTXP400BLEReliabilitySnapshot

    private let maximumEventCount: Int
    private var activeToken: PTXP400BLESessionToken?
    private var events: [PTXP400BLEReliabilityEvent] = []
    private var eventCounts: [String: Int] = [:]
    private var droppedEventCount = 0

    public init(maximumEventCount: Int = PTXP400BLEReliabilityMonitor.maximumEventCount) {
        self.maximumEventCount = max(1, maximumEventCount)
        self.snapshot = PTXP400BLEReliabilitySnapshot(
            generatedAt: Date(),
            activeSessionID: nil,
            activeGeneration: nil,
            totalEventCount: 0,
            droppedEventCount: 0,
            eventCounts: [:],
            recentEvents: []
        )
    }

    public func beginSession(_ token: PTXP400BLESessionToken) {
        activeToken = token
        record(.sessionStarted, token: token)
    }

    public func markReady(_ token: PTXP400BLESessionToken) {
        record(.sessionReady, token: token)
    }

    @discardableResult
    public func endSession(
        _ token: PTXP400BLESessionToken,
        kind: PTXP400BLEReliabilityEventKind = .sessionDisconnected,
        detail: String? = nil
    ) -> Bool {
        guard activeToken == token else { return false }
        record(kind, token: token, detail: detail)
        activeToken = nil
        rebuildSnapshot()
        return true
    }

    public func record(
        _ kind: PTXP400BLEReliabilityEventKind,
        token: PTXP400BLESessionToken? = nil,
        detail: String? = nil
    ) {
        let event = PTXP400BLEReliabilityEvent(kind: kind, token: token, detail: detail)
        events.append(event)
        eventCounts[kind.rawValue, default: 0] += 1
        if events.count > maximumEventCount {
            events.removeFirst(events.count - maximumEventCount)
            droppedEventCount += 1
        }
        rebuildSnapshot()
    }

    public func reset() {
        activeToken = nil
        events.removeAll(keepingCapacity: true)
        eventCounts.removeAll(keepingCapacity: true)
        droppedEventCount = 0
        rebuildSnapshot()
    }

    public func exportJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    public func exportURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xp400-ble-reliability-\(Int(Date().timeIntervalSince1970)).json"
        )
        try exportJSONData().write(to: url, options: .atomic)
        return url
    }

    private func rebuildSnapshot() {
        snapshot = PTXP400BLEReliabilitySnapshot(
            generatedAt: Date(),
            activeSessionID: activeToken?.id,
            activeGeneration: activeToken?.generation,
            totalEventCount: eventCounts.values.reduce(0, +),
            droppedEventCount: droppedEventCount,
            eventCounts: eventCounts,
            recentEvents: events
        )
    }
}

/// EN: One export surface combines bounded reliability metrics with the existing passive protocol evidence export.
/// ES: Una superficie de exportación combina métricas acotadas con la exportación de evidencia pasiva existente.
/// 中文：统一导出入口同时提供有界可靠性指标和已有的被动协议证据。
nonisolated public enum PTXP400BLETraceExport {
    @MainActor
    public static func exportReliabilityMetricsURL() throws -> URL {
        try PTXP400BLEReliabilityMonitor.shared.exportURL()
    }

    public static func exportProtocolEvidenceURL() async throws -> URL? {
        try await PTProtocolDiscoveryRecorder.shared.exportURL()
    }
}
