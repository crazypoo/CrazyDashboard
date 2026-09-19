//
//  PTCrazyTrace.swift
//  CrazyDashboard
//
//  EN: Build 58 trace domains keep vehicle data, adapter evidence, and replay state auditable.
//  ES: Los dominios de traza de Build 58 mantienen auditables los datos del vehículo, el adaptador y la reproducción.
//  中文：Build 58 的轨迹域让车辆数据、适配器证据和回放状态保持可审计。
//

import Foundation

public nonisolated enum PTTraceDomain: String, Codable, CaseIterable, Equatable, Sendable {
    case xp400BLE
    case obd
    case ymobdAdapter
    case adapterOTA
    case vehicleTelemetry
    case location
    case motion
    case navigation
    case system
}

public nonisolated enum PTTraceDirection: String, Codable, Equatable, Sendable {
    case input
    case output
    case state
    case marker
}

public nonisolated enum PTTraceSource: String, Codable, Equatable, Sendable {
    case live
    case mock
    case replay
    case system
}

public nonisolated struct PTTraceProtocolPayload: Codable, Equatable, Sendable {
    public let raw: String
    public let command: String?
    public let metadata: [String: String]

    public init(
        raw: String,
        command: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.raw = String(raw.prefix(8_192))
        self.command = command.map { String($0.prefix(512)) }
        self.metadata = metadata.reduce(into: [:]) { result, pair in
            result[String(pair.key.prefix(128))] = String(pair.value.prefix(512))
        }
    }
}

public nonisolated struct PTTraceLocationPayload: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double
    public let speedKmh: Double?
    public let courseDegree: Double?

    public init(
        latitude: Double,
        longitude: Double,
        altitude: Double = 0,
        speedKmh: Double? = nil,
        courseDegree: Double? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speedKmh = speedKmh
        self.courseDegree = courseDegree
    }
}

public nonisolated struct PTTraceMotionPayload: Codable, Equatable, Sendable {
    public let roll: Double
    public let pitch: Double
    public let yaw: Double
    public let gForceX: Double
    public let gForceY: Double
    public let gForceZ: Double

    public init(
        roll: Double,
        pitch: Double,
        yaw: Double,
        gForceX: Double,
        gForceY: Double,
        gForceZ: Double
    ) {
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
        self.gForceX = gForceX
        self.gForceY = gForceY
        self.gForceZ = gForceZ
    }
}

public nonisolated struct PTTraceAdapterPayload: Codable, Equatable, Sendable {
    public let vendor: String?
    public let model: String?
    public let firmwareVersion: String?
    public let transport: PTOBDTransportKind
    public let isOfficialYMOBD: Bool
    public let mode: PTOBDAdapterMode

    public init(snapshot: PTOBDAdapterSnapshot) {
        vendor = snapshot.vendor
        model = snapshot.model
        firmwareVersion = snapshot.firmwareVersion
        transport = snapshot.transport
        isOfficialYMOBD = snapshot.isOfficialYMOBD
        mode = snapshot.mode
    }

    public var snapshot: PTOBDAdapterSnapshot {
        PTOBDAdapterSnapshot(
            vendor: vendor,
            model: model,
            firmwareVersion: firmwareVersion,
            transport: transport,
            isOfficialYMOBD: isOfficialYMOBD,
            mode: mode
        )
    }
}

public nonisolated struct PTTraceMarkerPayload: Codable, Equatable, Sendable {
    public let name: String
    public let metadata: [String: String]

    public init(name: String, metadata: [String: String] = [:]) {
        self.name = String(name.prefix(256))
        self.metadata = metadata.reduce(into: [:]) { result, pair in
            result[String(pair.key.prefix(128))] = String(pair.value.prefix(512))
        }
    }
}

public nonisolated enum PTTracePayload: Codable, Equatable, Sendable {
    case telemetry(PTUnifiedVehicleTelemetrySnapshot)
    case protocolMessage(PTTraceProtocolPayload)
    case location(PTTraceLocationPayload)
    case motion(PTTraceMotionPayload)
    case adapter(PTTraceAdapterPayload)
    case marker(PTTraceMarkerPayload)
    case text(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case telemetry
        case protocolMessage
        case location
        case motion
        case adapter
        case marker
        case text
    }

    private enum Kind: String, Codable {
        case telemetry
        case protocolMessage
        case location
        case motion
        case adapter
        case marker
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .telemetry:
            self = .telemetry(try container.decode(PTUnifiedVehicleTelemetrySnapshot.self, forKey: .telemetry))
        case .protocolMessage:
            self = .protocolMessage(try container.decode(PTTraceProtocolPayload.self, forKey: .protocolMessage))
        case .location:
            self = .location(try container.decode(PTTraceLocationPayload.self, forKey: .location))
        case .motion:
            self = .motion(try container.decode(PTTraceMotionPayload.self, forKey: .motion))
        case .adapter:
            self = .adapter(try container.decode(PTTraceAdapterPayload.self, forKey: .adapter))
        case .marker:
            self = .marker(try container.decode(PTTraceMarkerPayload.self, forKey: .marker))
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .telemetry(let payload):
            try container.encode(Kind.telemetry, forKey: .kind)
            try container.encode(payload, forKey: .telemetry)
        case .protocolMessage(let payload):
            try container.encode(Kind.protocolMessage, forKey: .kind)
            try container.encode(payload, forKey: .protocolMessage)
        case .location(let payload):
            try container.encode(Kind.location, forKey: .kind)
            try container.encode(payload, forKey: .location)
        case .motion(let payload):
            try container.encode(Kind.motion, forKey: .kind)
            try container.encode(payload, forKey: .motion)
        case .adapter(let payload):
            try container.encode(Kind.adapter, forKey: .kind)
            try container.encode(payload, forKey: .adapter)
        case .marker(let payload):
            try container.encode(Kind.marker, forKey: .kind)
            try container.encode(payload, forKey: .marker)
        case .text(let payload):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(payload, forKey: .text)
        }
    }
}

public extension PTTracePayload {
    nonisolated var impliedDomain: PTTraceDomain? {
        switch self {
        case .telemetry:
            return .vehicleTelemetry
        case .location:
            return .location
        case .motion:
            return .motion
        case .adapter:
            return .ymobdAdapter
        case .protocolMessage, .marker, .text:
            return nil
        }
    }
}

public nonisolated struct PTCrazyTraceEvent: Codable, Equatable, Sendable {
    public let id: UUID
    public let sequence: Int
    public let timestamp: Date
    public let elapsed: TimeInterval
    public let domain: PTTraceDomain
    public let direction: PTTraceDirection
    public let source: PTTraceSource
    public let payload: PTTracePayload

    public init(
        id: UUID = UUID(),
        sequence: Int,
        timestamp: Date,
        elapsed: TimeInterval,
        domain: PTTraceDomain,
        direction: PTTraceDirection,
        source: PTTraceSource,
        payload: PTTracePayload
    ) {
        self.id = id
        self.sequence = sequence
        self.timestamp = timestamp
        self.elapsed = max(0, elapsed)
        self.domain = domain
        self.direction = direction
        self.source = source
        self.payload = payload
    }

    public var isDomainConsistent: Bool {
        guard let impliedDomain = payload.impliedDomain else { return true }
        return impliedDomain == domain
    }
}

public nonisolated struct PTCrazyTraceDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let traceID: UUID
    public let name: String
    public let vehicleID: String?
    public let startedAt: Date
    public let endedAt: Date?
    public let events: [PTCrazyTraceEvent]

    public init(
        schemaVersion: Int = PTCrazyTraceDocument.currentSchemaVersion,
        traceID: UUID = UUID(),
        name: String,
        vehicleID: String? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        events: [PTCrazyTraceEvent] = []
    ) {
        self.schemaVersion = schemaVersion
        self.traceID = traceID
        self.name = String(name.prefix(256))
        self.vehicleID = vehicleID.map { String($0.prefix(128)) }
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.events = events.sorted {
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.timestamp < $1.timestamp
        }
    }

    public var duration: TimeInterval {
        if let last = events.last?.elapsed { return max(0, last) }
        if let endedAt { return max(0, endedAt.timeIntervalSince(startedAt)) }
        return 0
    }

    public var hasConsistentDomains: Bool {
        events.allSatisfy(\.isDomainConsistent)
    }
}

// EN: Build 77 keeps the replay contract aligned with the unified live telemetry snapshot.
// ES: Build 77 mantiene el contrato de reproducción alineado con la instantánea unificada en vivo.
// 中文：Build 77 让回放契约与统一实时遥测快照保持一致。
public typealias PTVehicleRealtimeSnapshot = PTUnifiedVehicleTelemetrySnapshot

// EN: Diagnostics are derived from the document so they never become a second source of truth.
// ES: Los diagnósticos se derivan del documento para no crear una segunda fuente de verdad.
// 中文：诊断摘要从文档派生，避免形成第二套事实来源。
public nonisolated struct PTCrazyTraceDiagnosticsSummary: Codable, Equatable, Sendable {
    public let eventCount: Int
    public let duration: TimeInterval
    public let domainCounts: [String: Int]
    public let sourceCounts: [String: Int]
    public let vehicleSampleCount: Int
    public let motionSampleCount: Int
    public let gpsSampleCount: Int
    public let markerCount: Int
    public let hasSyntheticData: Bool

    public init(document: PTCrazyTraceDocument) {
        eventCount = document.events.count
        duration = document.duration
        domainCounts = Self.counts(document.events.map { $0.domain.rawValue })
        sourceCounts = Self.counts(document.events.map { $0.source.rawValue })
        vehicleSampleCount = document.events.reduce(into: 0) { count, event in
            if case .telemetry = event.payload { count += 1 }
        }
        motionSampleCount = document.events.reduce(into: 0) { count, event in
            if case .motion = event.payload { count += 1 }
        }
        gpsSampleCount = document.events.reduce(into: 0) { count, event in
            if case .location = event.payload { count += 1 }
        }
        markerCount = document.events.reduce(into: 0) { count, event in
            if case .marker = event.payload { count += 1 }
        }
        hasSyntheticData = document.events.contains { event in
            if case .telemetry(let snapshot) = event.payload {
                return snapshot.containsSyntheticData
            }
            return event.source == .mock || event.source == .replay
        }
    }

    private static func counts(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { result, value in
            result[value, default: 0] += 1
        }
    }
}

@MainActor
public final class PTCrazyTraceRecorder {
    public static let shared = PTCrazyTraceRecorder()
    public static let maximumEventCount = 50_000
    public static let maximumRollingEventCount = 20_000
    public static let maximumRollingDuration: TimeInterval = 60

    public private(set) var isRecording = false
    public private(set) var eventCount = 0
    public private(set) var droppedEventCount = 0
    public private(set) var lastDocument: PTCrazyTraceDocument?
    public private(set) var isBlackBoxArmed = false

    /// EN: The live bridge uses this single gate for normal recording and black-box capture.
    /// ES: El puente en vivo usa esta única compuerta para la grabación normal y la caja negra.
    /// 中文：实时桥接器统一使用这个门控判断普通录制和黑匣子采集。
    public var shouldCapture: Bool {
        isRecording || isBlackBoxArmed
    }

    public var rollingEventCount: Int {
        rollingEvents.count
    }

    private var traceID = UUID()
    private var traceName = ""
    private var vehicleID: String?
    private var startedAt = Date()
    private var nextSequence = 0
    private var events: [PTCrazyTraceEvent] = []
    private var rollingEvents: [PTCrazyTraceEvent] = []
    private var incidentCaptureInProgress = false

    private init() {}

    @discardableResult
    public func start(name: String, vehicleID: String? = nil, at date: Date = Date()) -> UUID? {
        guard !isRecording else { return nil }
        isBlackBoxArmed = false
        rollingEvents.removeAll(keepingCapacity: true)
        traceID = UUID()
        traceName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
        if traceName.isEmpty { traceName = "Vehicle Trace" }
        self.vehicleID = vehicleID.map { String($0.prefix(128)) }
        startedAt = date
        nextSequence = 0
        events.removeAll(keepingCapacity: true)
        eventCount = 0
        droppedEventCount = 0
        isRecording = true
        return traceID
    }

    public func record(
        domain: PTTraceDomain,
        direction: PTTraceDirection = .state,
        source: PTTraceSource = .live,
        payload: PTTracePayload,
        at date: Date = Date()
    ) {
        guard shouldCapture else { return }
        let event = PTCrazyTraceEvent(
            sequence: nextSequence,
            timestamp: date,
            elapsed: date.timeIntervalSince(startedAt),
            domain: domain,
            direction: direction,
            source: source,
            payload: payload
        )
        nextSequence += 1
        if isRecording {
            if events.count < Self.maximumEventCount {
                events.append(event)
                eventCount = events.count
            } else {
                droppedEventCount += 1
            }
        }
        if isBlackBoxArmed {
            rollingEvents.append(event)
            pruneRollingEvents(through: date)
        }
    }

    public func recordTelemetry(
        _ snapshot: PTUnifiedVehicleTelemetrySnapshot,
        source: PTTraceSource = .live,
        at date: Date = Date()
    ) {
        record(domain: .vehicleTelemetry, source: source, payload: .telemetry(snapshot), at: date)
    }

    public func recordProtocol(
        domain: PTTraceDomain,
        raw: String,
        command: String? = nil,
        direction: PTTraceDirection,
        source: PTTraceSource = .live,
        metadata: [String: String] = [:],
        at date: Date = Date()
    ) {
        let redactionLevel: PTBuild68TraceRedactionLevel = PTBuild68FeatureFlags.enableTraceRedaction ? .standard : .none
        // EN: Redact protocol payloads at capture time so a later export cannot accidentally expose adapter credentials.
        // ES: Redacta la carga del protocolo al capturarla para que una exportación posterior no exponga credenciales.
        // 中文：在抓取时就脱敏协议 Payload，避免后续导出意外暴露适配器认证信息。
        let safeRaw = PTBuild68TraceRedactor.redact(raw, level: redactionLevel)
        let safeCommand = command.map { PTBuild68TraceRedactor.redact($0, level: redactionLevel) }
        let safeMetadata = metadata.mapValues { PTBuild68TraceRedactor.redact($0, level: redactionLevel) }
        record(
            domain: domain,
            direction: direction,
            source: source,
            payload: .protocolMessage(PTTraceProtocolPayload(raw: safeRaw, command: safeCommand, metadata: safeMetadata)),
            at: date
        )
    }

    public func recordLocation(_ payload: PTTraceLocationPayload, source: PTTraceSource = .live, at date: Date = Date()) {
        record(domain: .location, source: source, payload: .location(payload), at: date)
    }

    public func recordMotion(_ payload: PTTraceMotionPayload, source: PTTraceSource = .live, at date: Date = Date()) {
        record(domain: .motion, source: source, payload: .motion(payload), at: date)
    }

    public func recordAdapter(_ snapshot: PTOBDAdapterSnapshot, source: PTTraceSource = .live, at date: Date = Date()) {
        record(domain: .ymobdAdapter, source: source, payload: .adapter(PTTraceAdapterPayload(snapshot: snapshot)), at: date)
    }

    public func mark(_ name: String, metadata: [String: String] = [:], at date: Date = Date()) {
        record(
            domain: .system,
            direction: .marker,
            payload: .marker(PTTraceMarkerPayload(name: name, metadata: metadata)),
            at: date
        )
    }

    // EN: Arms a bounded rolling capture without starting a visible export session.
    // ES: Activa una captura circular limitada sin iniciar una sesión de exportación visible.
    // 中文：开启有界滚动采集，但不启动可见的导出会话。
    @discardableResult
    public func armBlackBox(at date: Date = Date()) -> Bool {
        guard !isRecording else { return false }
        isBlackBoxArmed = true
        incidentCaptureInProgress = false
        rollingEvents.removeAll(keepingCapacity: true)
        nextSequence = 0
        startedAt = date
        return true
    }

    // EN: Disarms the rolling capture and releases its in-memory samples.
    // ES: Desactiva la captura circular y libera sus muestras en memoria.
    // 中文：关闭滚动采集并释放内存中的样本。
    public func disarmBlackBox() {
        guard !incidentCaptureInProgress else {
            isRecording = false
            incidentCaptureInProgress = false
            eventCount = events.count
            isBlackBoxArmed = false
            rollingEvents.removeAll(keepingCapacity: true)
            return
        }
        isBlackBoxArmed = false
        rollingEvents.removeAll(keepingCapacity: true)
    }

    // EN: Promotes the last 60 seconds into a trace and keeps recording for the post-roll window.
    // ES: Promueve los últimos 60 segundos a una traza y continúa grabando durante la ventana posterior.
    // 中文：将最近 60 秒提升为 Trace，并继续采集后置时间窗口。
    public func triggerIncident(
        name: String,
        vehicleID: String? = nil,
        preRoll: TimeInterval = 60,
        postRoll: TimeInterval = 30,
        at date: Date = Date()
    ) async -> PTCrazyTraceDocument? {
        guard isBlackBoxArmed, !isRecording else { return nil }
        let boundedPreRoll = preRoll.isFinite
            ? min(max(preRoll, 0), Self.maximumRollingDuration)
            : 0
        let boundedPostRoll = postRoll.isFinite
            ? min(max(postRoll, 0), 30)
            : 0
        let cutoff = date.addingTimeInterval(-boundedPreRoll)
        let captured = rollingEvents.filter { $0.timestamp >= cutoff && $0.timestamp <= date }
        let traceStart = captured.first?.timestamp ?? date

        traceID = UUID()
        traceName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
        if traceName.isEmpty { traceName = "Vehicle Incident" }
        self.vehicleID = vehicleID.map { String($0.prefix(128)) }
        startedAt = traceStart
        events = captured.enumerated().map { index, event in
            PTCrazyTraceEvent(
                id: event.id,
                sequence: index,
                timestamp: event.timestamp,
                elapsed: event.timestamp.timeIntervalSince(traceStart),
                domain: event.domain,
                direction: event.direction,
                source: event.source,
                payload: event.payload
            )
        }
        nextSequence = events.count
        eventCount = events.count
        droppedEventCount = 0
        isRecording = true
        incidentCaptureInProgress = true
        mark("incident_triggered", metadata: [
            "preRollSeconds": String(Int(boundedPreRoll)),
            "postRollSeconds": String(Int(boundedPostRoll))
        ], at: date)

        if boundedPostRoll > 0 {
            try? await Task.sleep(nanoseconds: UInt64(boundedPostRoll * 1_000_000_000))
        }
        guard isBlackBoxArmed else {
            isRecording = false
            incidentCaptureInProgress = false
            return nil
        }
        incidentCaptureInProgress = false
        return stop(at: Date())
    }

    private func pruneRollingEvents(through date: Date) {
        let cutoff = date.addingTimeInterval(-Self.maximumRollingDuration)
        if let firstValidIndex = rollingEvents.firstIndex(where: { $0.timestamp >= cutoff }) {
            if firstValidIndex > 0 {
                rollingEvents.removeFirst(firstValidIndex)
            }
        } else {
            rollingEvents.removeAll(keepingCapacity: true)
        }
        if rollingEvents.count > Self.maximumRollingEventCount {
            rollingEvents.removeFirst(rollingEvents.count - Self.maximumRollingEventCount)
        }
    }

    @discardableResult
    public func stop(at date: Date = Date()) -> PTCrazyTraceDocument? {
        guard isRecording else { return lastDocument }
        let document = PTCrazyTraceDocument(
            traceID: traceID,
            name: traceName,
            vehicleID: vehicleID,
            startedAt: startedAt,
            endedAt: date,
            events: events
        )
        lastDocument = document
        isRecording = false
        incidentCaptureInProgress = false
        eventCount = events.count
        return document
    }

    public func export(_ document: PTCrazyTraceDocument) async throws -> URL {
        let data = try await Self.encode(document)
        let fileName = "\(Self.fileStem(document.name))-\(document.traceID.uuidString).crazytrace"
        let result = try await PTDataPersistenceActor.shared.writeData(
            data,
            fileName: fileName,
            revision: Int64(document.startedAt.timeIntervalSince1970),
            syncToICloud: true
        )
        return result.localURL
    }

    public func exportLatest() async throws -> URL? {
        guard let lastDocument else { return nil }
        return try await export(lastDocument)
    }

    public static func load(from url: URL) async throws -> PTCrazyTraceDocument {
        let packageManifestURL = url.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: packageManifestURL.path) {
            // EN: Schema 2 packages are read through the checksum-validating platform before replay.
            // ES: Los paquetes de esquema 2 pasan por la plataforma que valida las sumas antes de reproducirse.
            // 中文：Schema 2 数据包在回放前必须经过带校验的 Package Reader。
            return try await Task.detached(priority: .utility) {
                try PTCrazyTracePackageReader.load(from: url).document
            }.value
        }
        let data = try await Task.detached(priority: .utility) {
            try Data(contentsOf: url)
        }.value
        return try JSONDecoder.crazyTraceDecoder.decode(PTCrazyTraceDocument.self, from: data)
    }

    private static func encode(_ document: PTCrazyTraceDocument) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let encoder = JSONEncoder.crazyTraceEncoder
            return try encoder.encode(document)
        }.value
    }

    private static func fileStem(_ value: String) -> String {
        let allowed = value.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                return Character(String(scalar))
            }
            return "-"
        }
        let stem = String(allowed).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String((stem.isEmpty ? "vehicle-trace" : stem).prefix(64))
    }
}

public extension JSONEncoder {
    nonisolated static var crazyTraceEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    nonisolated static var crazyTraceDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

@MainActor
public final class PTCrazyTraceReplayPlayer {
    public let document: PTCrazyTraceDocument
    public var playbackRate: Double = 1
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var isPlaying = false
    public var onEvent: ((PTCrazyTraceEvent) -> Void)?

    private var eventIndex = 0
    private var lastTickAt: Date?
    private var timer: Timer?

    public init(document: PTCrazyTraceDocument) {
        self.document = document
    }

    public var duration: TimeInterval { document.duration }

    public func play() {
        guard !isPlaying, !document.events.isEmpty else { return }
        isPlaying = true
        lastTickAt = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    public func pause() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
        lastTickAt = nil
    }

    public func stop() {
        pause()
        elapsed = 0
        eventIndex = 0
    }

    public func seek(to requestedElapsed: TimeInterval) {
        pause()
        elapsed = min(max(0, requestedElapsed), duration)
        eventIndex = 0
        emitEventsThroughCurrentTime()
    }

    private func tick() {
        guard isPlaying else { return }
        let now = Date()
        let delta = now.timeIntervalSince(lastTickAt ?? now) * min(max(playbackRate, 0.1), 8)
        lastTickAt = now
        elapsed = min(duration, elapsed + max(0, delta))
        emitEventsThroughCurrentTime()
        if elapsed >= duration {
            pause()
        }
    }

    private func emitEventsThroughCurrentTime() {
        while eventIndex < document.events.count,
              document.events[eventIndex].elapsed <= elapsed {
            onEvent?(document.events[eventIndex])
            eventIndex += 1
        }
    }

    deinit {
        timer?.invalidate()
    }
}

// EN: Live and replay expose the same read-only state boundary to the Digital Twin.
// ES: El modo vivo y la reproducción exponen el mismo límite de estado de solo lectura al Digital Twin.
// 中文：实时和回放向 Digital Twin 暴露同一个只读状态边界。
@MainActor
public protocol PTVehicleStateStreaming: AnyObject {
    var currentSnapshot: PTVehicleRealtimeSnapshot { get }

    func start()
    func pause()
    func resume()
    func stop()
}

// EN: This adapter reuses the existing bridge and replay clock; it never opens a transport.
// ES: Este adaptador reutiliza el puente y el reloj de reproducción existentes; nunca abre un transporte.
// 中文：该适配器复用现有桥接器和回放时钟，绝不打开新的传输层。
@MainActor
public final class PTReplayVehicleStateSource: PTVehicleStateStreaming {
    public let document: PTCrazyTraceDocument

    private let bridge: PTVehicleTelemetryBridge

    public init(
        document: PTCrazyTraceDocument,
        bridge: PTVehicleTelemetryBridge? = nil
    ) {
        self.document = document
        self.bridge = bridge ?? PTVehicleTelemetryBridge.shared
    }

    public var currentSnapshot: PTVehicleRealtimeSnapshot {
        bridge.snapshot
    }

    public var isPlaying: Bool {
        bridge.mode == .replay
    }

    public func start() {
        bridge.startReplay(document)
    }

    public func pause() {
        bridge.pauseReplay()
    }

    public func resume() {
        bridge.resumeReplay()
    }

    public func stop() {
        bridge.stopReplay()
    }

    public func seek(to elapsed: TimeInterval) {
        bridge.seekReplay(to: elapsed)
    }
}
