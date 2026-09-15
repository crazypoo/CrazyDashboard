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

@MainActor
public final class PTCrazyTraceRecorder {
    public static let shared = PTCrazyTraceRecorder()
    public static let maximumEventCount = 50_000

    public private(set) var isRecording = false
    public private(set) var eventCount = 0
    public private(set) var droppedEventCount = 0
    public private(set) var lastDocument: PTCrazyTraceDocument?

    private var traceID = UUID()
    private var traceName = ""
    private var vehicleID: String?
    private var startedAt = Date()
    private var nextSequence = 0
    private var events: [PTCrazyTraceEvent] = []

    private init() {}

    @discardableResult
    public func start(name: String, vehicleID: String? = nil, at date: Date = Date()) -> UUID? {
        guard !isRecording else { return nil }
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
        guard isRecording else { return }
        guard events.count < Self.maximumEventCount else {
            droppedEventCount += 1
            return
        }
        let event = PTCrazyTraceEvent(
            sequence: nextSequence,
            timestamp: date,
            elapsed: date.timeIntervalSince(startedAt),
            domain: domain,
            direction: direction,
            source: source,
            payload: payload
        )
        events.append(event)
        nextSequence += 1
        eventCount = events.count
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
        record(
            domain: domain,
            direction: direction,
            source: source,
            payload: .protocolMessage(PTTraceProtocolPayload(raw: raw, command: command, metadata: metadata)),
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
