//
//  PTCrazyDashboardInstruments.swift
//  CrazyDashboard
//
//  EN: Provides read-only, bounded instrumentation for the vehicle domains.
//  ES: Proporciona instrumentación de solo lectura y acotada para los dominios del vehículo.
//  中文：为车辆各个域提供只读且有界的 Instruments 指标。
//

import Foundation

// EN: The domain list prevents XP400 BLE, ELM327, YMOBD, and Jieli events from being presented as one connection.
// ES: La lista de dominios evita presentar BLE XP400, ELM327, YMOBD y Jieli como una sola conexión.
// 中文：域列表避免把 XP400 BLE、ELM327、YMOBD 和 Jieli 错误地显示成同一条连接。
nonisolated public enum PTCrazyDashboardInstrumentDomain: String, Codable, CaseIterable, Sendable {
    case overview
    case xp400BLE
    case obd
    case ymobdAdapter
    case adapterOTA
    case can
    case telemetry
    case gps
    case speed
    case motion
    case system
}

nonisolated public struct PTCrazyDashboardInstrumentTimelineEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let domain: PTCrazyDashboardInstrumentDomain
    public let name: String
    public let detail: String?
    public let isActive: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        domain: PTCrazyDashboardInstrumentDomain,
        name: String,
        detail: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.domain = domain
        self.name = String(name.prefix(160))
        self.detail = detail.map { String($0.prefix(512)) }
        self.isActive = isActive
    }
}

nonisolated public struct PTCrazyDashboardXP400BLEMetrics: Codable, Equatable, Sendable {
    public let isConnected: Bool
    public let lifecycle: String
    public let sessionID: UUID?
    public let generation: UInt64?
    public let isAuthenticated: Bool
    public let isTioSubscribed: Bool
    public let isCreditsSubscribed: Bool
    public let rxPerSecond: Double?
    public let txPerSecond: Double?
    public let txRateAvailability: String
    public let sendCredits: Int
    public let localCredits: Int
    public let queueDepth: Int
    public let isSending: Bool
    public let reconnectCount: Int
    public let telemetrySignalCount: Int

    public init(
        isConnected: Bool = false,
        lifecycle: String = "idle",
        sessionID: UUID? = nil,
        generation: UInt64? = nil,
        isAuthenticated: Bool = false,
        isTioSubscribed: Bool = false,
        isCreditsSubscribed: Bool = false,
        rxPerSecond: Double? = nil,
        txPerSecond: Double? = nil,
        txRateAvailability: String = "not-exposed",
        sendCredits: Int = 0,
        localCredits: Int = 0,
        queueDepth: Int = 0,
        isSending: Bool = false,
        reconnectCount: Int = 0,
        telemetrySignalCount: Int = 0
    ) {
        self.isConnected = isConnected
        self.lifecycle = lifecycle
        self.sessionID = sessionID
        self.generation = generation
        self.isAuthenticated = isAuthenticated
        self.isTioSubscribed = isTioSubscribed
        self.isCreditsSubscribed = isCreditsSubscribed
        self.rxPerSecond = rxPerSecond
        self.txPerSecond = txPerSecond
        self.txRateAvailability = txRateAvailability
        self.sendCredits = max(sendCredits, 0)
        self.localCredits = max(localCredits, 0)
        self.queueDepth = max(queueDepth, 0)
        self.isSending = isSending
        self.reconnectCount = max(reconnectCount, 0)
        self.telemetrySignalCount = max(telemetrySignalCount, 0)
    }
}

nonisolated public struct PTCrazyDashboardOBDMetrics: Codable, Equatable, Sendable {
    public let isConnected: Bool
    public let transport: String
    public let elmState: String
    public let isPolling: Bool
    public let commandQueueDepth: Int?
    public let commandQueueAvailability: String
    public let currentLease: String
    public let pidPerSecond: Double?
    public let rttMilliseconds: Double?
    public let canMonitorState: String
    public let udsState: String
    public let lastError: String?

    public init(
        isConnected: Bool = false,
        transport: String = "unknown",
        elmState: String = "disconnected",
        isPolling: Bool = false,
        commandQueueDepth: Int? = nil,
        commandQueueAvailability: String = "not-exposed",
        currentLease: String = "not-exposed",
        pidPerSecond: Double? = nil,
        rttMilliseconds: Double? = nil,
        canMonitorState: String = "idle",
        udsState: String = "idle",
        lastError: String? = nil
    ) {
        self.isConnected = isConnected
        self.transport = transport
        self.elmState = elmState
        self.isPolling = isPolling
        self.commandQueueDepth = commandQueueDepth
        self.commandQueueAvailability = commandQueueAvailability
        self.currentLease = currentLease
        self.pidPerSecond = pidPerSecond
        self.rttMilliseconds = rttMilliseconds
        self.canMonitorState = canMonitorState
        self.udsState = udsState
        self.lastError = lastError
    }
}

nonisolated public struct PTCrazyDashboardAdapterMetrics: Codable, Equatable, Sendable {
    public let vendor: String?
    public let model: String?
    public let firmwareVersion: String?
    public let identifierSuffix: String?
    public let transport: String
    public let authentication: String
    public let capabilities: [String]
    public let mode: String
    public let isOfficialYMOBD: Bool

    public init(
        vendor: String? = nil,
        model: String? = nil,
        firmwareVersion: String? = nil,
        identifierSuffix: String? = nil,
        transport: String = "unknown",
        authentication: String = "unknown",
        capabilities: [String] = [],
        mode: String = "disconnected",
        isOfficialYMOBD: Bool = false
    ) {
        self.vendor = vendor
        self.model = model
        self.firmwareVersion = firmwareVersion
        self.identifierSuffix = identifierSuffix
        self.transport = transport
        self.authentication = authentication
        self.capabilities = capabilities
        self.mode = mode
        self.isOfficialYMOBD = isOfficialYMOBD
    }
}

nonisolated public struct PTCrazyDashboardOTAMetrics: Codable, Equatable, Sendable {
    public let isVisible: Bool
    public let sdkVersion: String
    public let state: String
    public let progress: Double
    public let completedBytes: Int64
    public let totalBytes: Int64
    public let reconnectCount: Int
    public let resumeState: String
    public let targetFirmwareVersion: String?
    public let currentFirmwareVersion: String?
    public let versionVerified: Bool?
    public let error: String?

    public init(
        isVisible: Bool = false,
        sdkVersion: String = "2.5.0",
        state: String = "idle",
        progress: Double = 0,
        completedBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        reconnectCount: Int = 0,
        resumeState: String = "none",
        targetFirmwareVersion: String? = nil,
        currentFirmwareVersion: String? = nil,
        versionVerified: Bool? = nil,
        error: String? = nil
    ) {
        self.isVisible = isVisible
        self.sdkVersion = sdkVersion
        self.state = state
        self.progress = progress.isFinite ? min(max(progress, 0), 1) : 0
        self.completedBytes = max(completedBytes, 0)
        self.totalBytes = max(totalBytes, 0)
        self.reconnectCount = max(reconnectCount, 0)
        self.resumeState = resumeState
        self.targetFirmwareVersion = targetFirmwareVersion
        self.currentFirmwareVersion = currentFirmwareVersion
        self.versionVerified = versionVerified
        self.error = error
    }
}

nonisolated public struct PTCrazyDashboardCANMetrics: Codable, Equatable, Sendable {
    public let state: String
    public let framesPerSecond: Double?
    public let totalFrameCount: Int
    public let retainedFrameCount: Int
    public let droppedFrameCount: Int
    public let headers: [String]

    public init(
        state: String = "idle",
        framesPerSecond: Double? = nil,
        totalFrameCount: Int = 0,
        retainedFrameCount: Int = 0,
        droppedFrameCount: Int = 0,
        headers: [String] = []
    ) {
        self.state = state
        self.framesPerSecond = framesPerSecond
        self.totalFrameCount = max(totalFrameCount, 0)
        self.retainedFrameCount = max(retainedFrameCount, 0)
        self.droppedFrameCount = max(droppedFrameCount, 0)
        self.headers = headers
    }
}

nonisolated public struct PTCrazyDashboardTelemetryMetrics: Codable, Equatable, Sendable {
    public let mode: String
    public let valueCount: Int
    public let signalNames: [String]
    public let containsSyntheticData: Bool
    public let updatedAt: Date

    public init(
        mode: String = "live",
        valueCount: Int = 0,
        signalNames: [String] = [],
        containsSyntheticData: Bool = false,
        updatedAt: Date = .distantPast
    ) {
        self.mode = mode
        self.valueCount = max(valueCount, 0)
        self.signalNames = signalNames
        self.containsSyntheticData = containsSyntheticData
        self.updatedAt = updatedAt
    }
}

nonisolated public struct PTCrazyDashboardGPSMetrics: Codable, Equatable, Sendable {
    public let isTracking: Bool
    public let horizontalAccuracyMeters: Double?

    public init(isTracking: Bool = false, horizontalAccuracyMeters: Double? = nil) {
        self.isTracking = isTracking
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
    }
}

// EN: Each candidate stays visible so a connected but stale transport is distinguishable from an unavailable provider.
// ES: Cada candidato permanece visible para distinguir un transporte conectado pero obsoleto de un proveedor ausente.
// 中文：保留每个候选值，便于区分“传输已连接但数据过期”和“来源不可用”。
nonisolated public struct PTCrazyDashboardSpeedCandidateMetrics: Codable, Equatable, Sendable {
    public let source: String
    public let speedKPH: Double
    public let ageSeconds: Double
    public let isFresh: Bool
    public let isSynthetic: Bool
    public let horizontalAccuracyMeters: Double?
    public let speedAccuracyMetersPerSecond: Double?
    public let rawSpeedMetersPerSecond: Double?

    public init(
        source: String,
        speedKPH: Double,
        ageSeconds: Double,
        isFresh: Bool,
        isSynthetic: Bool,
        horizontalAccuracyMeters: Double? = nil,
        speedAccuracyMetersPerSecond: Double? = nil,
        rawSpeedMetersPerSecond: Double? = nil
    ) {
        self.source = source
        self.speedKPH = speedKPH
        self.ageSeconds = max(ageSeconds, 0)
        self.isFresh = isFresh
        self.isSynthetic = isSynthetic
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.speedAccuracyMetersPerSecond = speedAccuracyMetersPerSecond
        self.rawSpeedMetersPerSecond = rawSpeedMetersPerSecond
    }
}

nonisolated public struct PTCrazyDashboardSpeedMetrics: Codable, Equatable, Sendable {
    public let resolvedSpeedKPH: Double?
    public let resolvedSource: String?
    public let resolutionReason: String
    public let resolvedAgeSeconds: Double?
    public let isFresh: Bool
    public let switchCount: Int
    public let pendingSource: String?
    public let pendingSampleCount: Int
    public let gpsStatus: String
    public let gpsRawSpeedMetersPerSecond: Double?
    public let gpsFilteredSpeedKPH: Double?
    public let gpsHorizontalAccuracyMeters: Double?
    public let gpsSpeedAccuracyMetersPerSecond: Double?
    public let gpsSampleAgeSeconds: Double?
    public let candidates: [PTCrazyDashboardSpeedCandidateMetrics]

    public init(
        resolvedSpeedKPH: Double? = nil,
        resolvedSource: String? = nil,
        resolutionReason: String = "noValidSource",
        resolvedAgeSeconds: Double? = nil,
        isFresh: Bool = false,
        switchCount: Int = 0,
        pendingSource: String? = nil,
        pendingSampleCount: Int = 0,
        gpsStatus: String = "idle",
        gpsRawSpeedMetersPerSecond: Double? = nil,
        gpsFilteredSpeedKPH: Double? = nil,
        gpsHorizontalAccuracyMeters: Double? = nil,
        gpsSpeedAccuracyMetersPerSecond: Double? = nil,
        gpsSampleAgeSeconds: Double? = nil,
        candidates: [PTCrazyDashboardSpeedCandidateMetrics] = []
    ) {
        self.resolvedSpeedKPH = resolvedSpeedKPH
        self.resolvedSource = resolvedSource
        self.resolutionReason = resolutionReason
        self.resolvedAgeSeconds = resolvedAgeSeconds
        self.isFresh = isFresh
        self.switchCount = max(switchCount, 0)
        self.pendingSource = pendingSource
        self.pendingSampleCount = max(pendingSampleCount, 0)
        self.gpsStatus = gpsStatus
        self.gpsRawSpeedMetersPerSecond = gpsRawSpeedMetersPerSecond
        self.gpsFilteredSpeedKPH = gpsFilteredSpeedKPH
        self.gpsHorizontalAccuracyMeters = gpsHorizontalAccuracyMeters
        self.gpsSpeedAccuracyMetersPerSecond = gpsSpeedAccuracyMetersPerSecond
        self.gpsSampleAgeSeconds = gpsSampleAgeSeconds
        self.candidates = candidates
    }

    private enum CodingKeys: String, CodingKey {
        case resolvedSpeedKPH
        case resolvedSource
        case resolutionReason
        case resolvedAgeSeconds
        case isFresh
        case switchCount
        case pendingSource
        case pendingSampleCount
        case gpsStatus
        case gpsRawSpeedMetersPerSecond
        case gpsFilteredSpeedKPH
        case gpsHorizontalAccuracyMeters
        case gpsSpeedAccuracyMetersPerSecond
        case gpsSampleAgeSeconds
        case candidates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            resolvedSpeedKPH: try container.decodeIfPresent(Double.self, forKey: .resolvedSpeedKPH),
            resolvedSource: try container.decodeIfPresent(String.self, forKey: .resolvedSource),
            resolutionReason: try container.decodeIfPresent(String.self, forKey: .resolutionReason) ?? "noValidSource",
            resolvedAgeSeconds: try container.decodeIfPresent(Double.self, forKey: .resolvedAgeSeconds),
            isFresh: try container.decodeIfPresent(Bool.self, forKey: .isFresh) ?? false,
            switchCount: try container.decodeIfPresent(Int.self, forKey: .switchCount) ?? 0,
            pendingSource: try container.decodeIfPresent(String.self, forKey: .pendingSource),
            pendingSampleCount: try container.decodeIfPresent(Int.self, forKey: .pendingSampleCount) ?? 0,
            gpsStatus: try container.decodeIfPresent(String.self, forKey: .gpsStatus) ?? "idle",
            gpsRawSpeedMetersPerSecond: try container.decodeIfPresent(Double.self, forKey: .gpsRawSpeedMetersPerSecond),
            gpsFilteredSpeedKPH: try container.decodeIfPresent(Double.self, forKey: .gpsFilteredSpeedKPH),
            gpsHorizontalAccuracyMeters: try container.decodeIfPresent(Double.self, forKey: .gpsHorizontalAccuracyMeters),
            gpsSpeedAccuracyMetersPerSecond: try container.decodeIfPresent(Double.self, forKey: .gpsSpeedAccuracyMetersPerSecond),
            gpsSampleAgeSeconds: try container.decodeIfPresent(Double.self, forKey: .gpsSampleAgeSeconds),
            candidates: try container.decodeIfPresent([PTCrazyDashboardSpeedCandidateMetrics].self, forKey: .candidates) ?? []
        )
    }
}

nonisolated public struct PTCrazyDashboardMotionMetrics: Codable, Equatable, Sendable {
    public let source: String
    public let sampleRateHz: Double?
    public let roll: Double
    public let pitch: Double
    public let yaw: Double
    public let gForceX: Double
    public let gForceY: Double
    public let gForceZ: Double

    public init(
        source: String = "iphone",
        sampleRateHz: Double? = nil,
        roll: Double = 0,
        pitch: Double = 0,
        yaw: Double = 0,
        gForceX: Double = 0,
        gForceY: Double = 0,
        gForceZ: Double = 0
    ) {
        self.source = source
        self.sampleRateHz = sampleRateHz
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
        self.gForceX = gForceX
        self.gForceY = gForceY
        self.gForceZ = gForceZ
    }
}

nonisolated public struct PTCrazyDashboardSystemMetrics: Codable, Equatable, Sendable {
    public let appVersion: String
    public let buildVersion: String
    public let generatedAt: Date
    public let isReadOnly: Bool
    public let isReplayActive: Bool

    public init(
        appVersion: String = "unknown",
        buildVersion: String = "unknown",
        generatedAt: Date = Date(),
        isReadOnly: Bool = true,
        isReplayActive: Bool = false
    ) {
        self.appVersion = appVersion
        self.buildVersion = buildVersion
        self.generatedAt = generatedAt
        self.isReadOnly = isReadOnly
        self.isReplayActive = isReplayActive
    }
}

nonisolated public struct PTCrazyDashboardInstrumentSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let xp400BLE: PTCrazyDashboardXP400BLEMetrics
    public let obd: PTCrazyDashboardOBDMetrics
    public let ymobdAdapter: PTCrazyDashboardAdapterMetrics
    public let adapterOTA: PTCrazyDashboardOTAMetrics
    public let can: PTCrazyDashboardCANMetrics
    public let telemetry: PTCrazyDashboardTelemetryMetrics
    public let gps: PTCrazyDashboardGPSMetrics
    public let speed: PTCrazyDashboardSpeedMetrics
    public let motion: PTCrazyDashboardMotionMetrics
    public let system: PTCrazyDashboardSystemMetrics

    public init(
        generatedAt: Date = Date(),
        xp400BLE: PTCrazyDashboardXP400BLEMetrics = .init(),
        obd: PTCrazyDashboardOBDMetrics = .init(),
        ymobdAdapter: PTCrazyDashboardAdapterMetrics = .init(),
        adapterOTA: PTCrazyDashboardOTAMetrics = .init(),
        can: PTCrazyDashboardCANMetrics = .init(),
        telemetry: PTCrazyDashboardTelemetryMetrics = .init(),
        gps: PTCrazyDashboardGPSMetrics = .init(),
        speed: PTCrazyDashboardSpeedMetrics = .init(),
        motion: PTCrazyDashboardMotionMetrics = .init(),
        system: PTCrazyDashboardSystemMetrics = .init()
    ) {
        self.generatedAt = generatedAt
        self.xp400BLE = xp400BLE
        self.obd = obd
        self.ymobdAdapter = ymobdAdapter
        self.adapterOTA = adapterOTA
        self.can = can
        self.telemetry = telemetry
        self.gps = gps
        self.speed = speed
        self.motion = motion
        self.system = system
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt
        case xp400BLE
        case obd
        case ymobdAdapter
        case adapterOTA
        case can
        case telemetry
        case gps
        case speed
        case motion
        case system
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            generatedAt: try container.decode(Date.self, forKey: .generatedAt),
            xp400BLE: try container.decodeIfPresent(PTCrazyDashboardXP400BLEMetrics.self, forKey: .xp400BLE) ?? .init(),
            obd: try container.decodeIfPresent(PTCrazyDashboardOBDMetrics.self, forKey: .obd) ?? .init(),
            ymobdAdapter: try container.decodeIfPresent(PTCrazyDashboardAdapterMetrics.self, forKey: .ymobdAdapter) ?? .init(),
            adapterOTA: try container.decodeIfPresent(PTCrazyDashboardOTAMetrics.self, forKey: .adapterOTA) ?? .init(),
            can: try container.decodeIfPresent(PTCrazyDashboardCANMetrics.self, forKey: .can) ?? .init(),
            telemetry: try container.decodeIfPresent(PTCrazyDashboardTelemetryMetrics.self, forKey: .telemetry) ?? .init(),
            gps: try container.decodeIfPresent(PTCrazyDashboardGPSMetrics.self, forKey: .gps) ?? .init(),
            speed: try container.decodeIfPresent(PTCrazyDashboardSpeedMetrics.self, forKey: .speed) ?? .init(),
            motion: try container.decodeIfPresent(PTCrazyDashboardMotionMetrics.self, forKey: .motion) ?? .init(),
            system: try container.decodeIfPresent(PTCrazyDashboardSystemMetrics.self, forKey: .system) ?? .init()
        )
    }

    public static let empty = PTCrazyDashboardInstrumentSnapshot()
}

nonisolated public struct PTCrazyDashboardInstrumentExportDocument: Codable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let snapshot: PTCrazyDashboardInstrumentSnapshot
    public let history: [PTCrazyDashboardInstrumentSnapshot]
    public let timeline: [PTCrazyDashboardInstrumentTimelineEvent]

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        snapshot: PTCrazyDashboardInstrumentSnapshot,
        history: [PTCrazyDashboardInstrumentSnapshot],
        timeline: [PTCrazyDashboardInstrumentTimelineEvent]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.snapshot = snapshot
        self.history = history
        self.timeline = timeline
    }
}

// EN: This ring buffer keeps long-running developer sessions from retaining unbounded history.
// ES: Este búfer circular evita conservar un historial ilimitado durante sesiones largas de desarrollador.
// 中文：环形缓冲区避免长时间开发者会话无限保留历史数据。
nonisolated public struct PTCrazyDashboardInstrumentHistory<Element: Sendable>: Sendable {
    public let maximumCount: Int
    public private(set) var elements: [Element] = []

    public init(maximumCount: Int = 300) {
        self.maximumCount = max(1, maximumCount)
    }

    public mutating func append(_ element: Element) {
        elements.append(element)
        if elements.count > maximumCount {
            elements.removeFirst(elements.count - maximumCount)
        }
    }
}

nonisolated public struct PTCrazyDashboardInstrumentRateWindow: Sendable {
    public let window: TimeInterval
    private var timestamps: [Date] = []

    public init(window: TimeInterval = 10) {
        self.window = max(window, 1)
    }

    public mutating func record(at date: Date) {
        timestamps.append(date)
        prune(reference: date)
    }

    public mutating func rate(at date: Date) -> Double? {
        prune(reference: date)
        guard let first = timestamps.first else { return nil }
        let elapsed = min(window, max(1, date.timeIntervalSince(first)))
        return Double(timestamps.count) / elapsed
    }

    public var count: Int { timestamps.count }

    private mutating func prune(reference: Date) {
        let lowerBound = reference.addingTimeInterval(-window)
        timestamps.removeAll { $0 < lowerBound }
    }
}

nonisolated public enum PTCrazyDashboardInstrumentCSV {
    public static func escape(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "\"", with: "\"\"")
        if normalized.contains(",") || normalized.contains("\n") || normalized.contains("\r") || normalized.contains("\"") {
            return "\"\(normalized)\""
        }
        return normalized
    }
}

// EN: Main-actor ownership keeps sampling and the UI notification race-free; all sampled values are copied value types.
// ES: La propiedad del actor principal evita carreras entre muestreo y UI; todos los valores muestreados son tipos valor.
// 中文：由主 actor 持有采样和 UI 通知，避免竞态；所有采样结果都是值类型副本。
@MainActor
public final class PTCrazyDashboardInstrumentsStore: NSObject {
    public static let shared = PTCrazyDashboardInstrumentsStore()
    public static let snapshotDidChange = Notification.Name("PTCrazyDashboardInstrumentsStore.snapshotDidChange")

    public private(set) var snapshot = PTCrazyDashboardInstrumentSnapshot.empty
    public private(set) var history: [PTCrazyDashboardInstrumentSnapshot] = []
    public private(set) var timeline: [PTCrazyDashboardInstrumentTimelineEvent] = []

    private let historyLimit: Int
    private let providerRegistry = PTInstrumentProviderRegistry()
    private var isStarted = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var metadataTask: Task<Void, Never>?
    private var lastMetadataReadAt = Date.distantPast
    private var timelineStates: [String: String] = [:]
    private var previousPollingState: Bool?
    private var previousOTAActive = false
    private var waitingForELMReconnectAfterOTA = false

    public init(historyLimit: Int = 300) {
        self.historyLimit = max(1, historyLimit)
        super.init()
    }

    deinit {
        timer?.invalidate()
        metadataTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    public func start() {
        guard !isStarted else {
            refresh()
            return
        }
        isStarted = true
        providerRegistry.start()
        let notificationNames: [Notification.Name] = [
            PTVehicleConnectivityCoordinator.snapshotDidChange,
            PTVehicleConnectivityCoordinator.telemetryDidChange,
            PTVehicleTelemetryBridge.didChange,
            PTDeveloperSafetyGate.stateDidChange
        ]
        observers = notificationNames.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        refresh()
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        timer?.invalidate()
        timer = nil
        metadataTask?.cancel()
        metadataTask = nil
        providerRegistry.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll(keepingCapacity: true)
    }

    public func refresh(at date: Date = Date()) {
        let next = makeSnapshot(at: date)
        appendTimelineTransitions(for: next, at: date)
        snapshot = next
        history.append(next)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
        scheduleMetadataReadIfNeeded(at: date)
        NotificationCenter.default.post(
            name: Self.snapshotDidChange,
            object: self,
            userInfo: ["snapshot": next]
        )
    }

    public func exportJSONURL() throws -> URL {
        let document = makeExportDocument()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "crazydashboard-instruments-\(Int(Date().timeIntervalSince1970)).json"
        )
        try data.write(to: url, options: .atomic)
        return url
    }

    public func exportCSVURL() throws -> URL {
        let formatter = ISO8601DateFormatter()
        var rows = ["timestamp,domain,name,detail,active"]
        rows.reserveCapacity(timeline.count + 1)
        for event in timeline {
            rows.append([
                formatter.string(from: event.timestamp),
                event.domain.rawValue,
                event.name,
                event.detail ?? "",
                event.isActive ? "true" : "false"
            ].map(PTCrazyDashboardInstrumentCSV.escape).joined(separator: ","))
        }
        let data = Data(rows.joined(separator: "\n").utf8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "crazydashboard-instruments-\(Int(Date().timeIntervalSince1970)).csv"
        )
        try data.write(to: url, options: .atomic)
        return url
    }

    private func makeSnapshot(at date: Date) -> PTCrazyDashboardInstrumentSnapshot {
        providerRegistry.snapshot(at: date)
    }

    private func appendTimelineTransitions(
        for next: PTCrazyDashboardInstrumentSnapshot,
        at date: Date
    ) {
        appendTransition(
            key: "xp400BLE.lifecycle",
            domain: .xp400BLE,
            name: "XP400 BLE",
            state: next.xp400BLE.isConnected ? "connected" : "disconnected",
            detail: "lifecycle=\(next.xp400BLE.lifecycle)"
        )
        appendTransition(
            key: "obd.elm",
            domain: .obd,
            name: "OBD ELM",
            state: next.obd.elmState,
            detail: "transport=\(next.obd.transport)"
        )
        if let previousPollingState, previousPollingState && !next.obd.isPolling {
            appendEvent(
                PTCrazyDashboardInstrumentTimelineEvent(
                    timestamp: date,
                    domain: .obd,
                    name: "OBD polling stopped",
                    detail: "polling stopped"
                )
            )
        }
        appendTransition(
            key: "obd.polling",
            domain: .obd,
            name: "OBD polling",
            state: next.obd.isPolling ? "running" : "stopped"
        )
        previousPollingState = next.obd.isPolling
        appendTransition(
            key: "adapter.mode",
            domain: .ymobdAdapter,
            name: "YMOBD adapter mode",
            state: next.ymobdAdapter.mode,
            detail: next.ymobdAdapter.isOfficialYMOBD ? "official YMOBD" : "generic ELM-compatible adapter"
        )
        if next.adapterOTA.isVisible && next.adapterOTA.state == PTOTAState.checking.rawValue {
            appendTransition(
                key: "adapter.ota.firmwareCheck",
                domain: .adapterOTA,
                name: "YMOBD firmware check",
                state: "checking",
                detail: "read-only firmware metadata check"
            )
        }
        let otaActive = next.adapterOTA.isVisible
        if otaActive && !previousOTAActive {
            appendEvent(
                PTCrazyDashboardInstrumentTimelineEvent(
                    timestamp: date,
                    domain: .adapterOTA,
                    name: "Jieli OTA started",
                    detail: "adapter-only OTA domain"
                )
            )
        }
        if previousOTAActive && !otaActive {
            waitingForELMReconnectAfterOTA = true
        }
        appendTransition(
            key: "adapter.ota",
            domain: .adapterOTA,
            name: "Jieli OTA",
            state: next.adapterOTA.state,
            detail: next.adapterOTA.isVisible ? "developer-only panel visible" : "panel hidden unless YMOBD OTA is active",
            isActive: otaActive
        )
        if waitingForELMReconnectAfterOTA && next.obd.isConnected {
            appendEvent(
                PTCrazyDashboardInstrumentTimelineEvent(
                    timestamp: date,
                    domain: .obd,
                    name: "ELM reconnect after OTA",
                    detail: "OBD link observed after adapter OTA domain ended"
                )
            )
            waitingForELMReconnectAfterOTA = false
        }
        previousOTAActive = otaActive
        appendTransition(
            key: "can.state",
            domain: .can,
            name: "CAN monitor",
            state: next.can.state,
            detail: "frames=\(next.can.totalFrameCount)"
        )
        appendTransition(
            key: "telemetry.mode",
            domain: .telemetry,
            name: "Vehicle telemetry",
            state: next.telemetry.mode,
            detail: "signals=\(next.telemetry.valueCount)"
        )
        appendTransition(
            key: "speed.resolution",
            domain: .speed,
            name: "Unified speed",
            state: "\(next.speed.resolvedSource ?? "none"):\(next.speed.resolutionReason)",
            detail: "speed=\(next.speed.resolvedSpeedKPH.map { String(format: "%.1f km/h", $0) } ?? "unavailable")"
        )
    }

    private func appendTransition(
        key: String,
        domain: PTCrazyDashboardInstrumentDomain,
        name: String,
        state: String,
        detail: String? = nil,
        isActive: Bool = true
    ) {
        guard timelineStates[key] != state else { return }
        timelineStates[key] = state
        appendEvent(
            PTCrazyDashboardInstrumentTimelineEvent(
                domain: domain,
                name: name,
                detail: detail.map { "\($0); state=\(state)" } ?? "state=\(state)",
                isActive: isActive
            )
        )
    }

    private func appendEvent(_ event: PTCrazyDashboardInstrumentTimelineEvent) {
        timeline.append(event)
        if timeline.count > historyLimit {
            timeline.removeFirst(timeline.count - historyLimit)
        }
    }

    private func makeExportDocument() -> PTCrazyDashboardInstrumentExportDocument {
        PTCrazyDashboardInstrumentExportDocument(
            generatedAt: Date(),
            snapshot: snapshot,
            history: history,
            timeline: timeline
        )
    }

    private func scheduleMetadataReadIfNeeded(at date: Date) {
        guard date.timeIntervalSince(lastMetadataReadAt) >= 1 else { return }
        lastMetadataReadAt = date
        metadataTask?.cancel()
        metadataTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.providerRegistry.refreshMetadata()
            guard !Task.isCancelled else { return }
            self.refresh()
        }
    }
}
