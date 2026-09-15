//
//  PTVehicleTelemetryBridge.swift
//  CrazyDashboard
//
//  EN: The bridge exposes one read-only live or replay telemetry surface to the UI.
//  ES: El puente expone a la interfaz una única superficie de telemetría en vivo o reproducida.
//  中文：桥接器为 UI 提供统一的只读实时或回放遥测表面。
//

import Foundation
import CoreLocation
import PooTools

@MainActor
public final class PTVehicleTelemetryBridge: NSObject, PTMotionDelegate {
    public static let shared = PTVehicleTelemetryBridge()
    public static let didChange = Notification.Name("PTVehicleTelemetryBridge.didChange")
    public static let replayEventDidChange = Notification.Name("PTVehicleTelemetryBridge.replayEventDidChange")

    public private(set) var snapshot: PTUnifiedVehicleTelemetrySnapshot = .empty
    public private(set) var adapterSnapshot: PTOBDAdapterSnapshot = .unavailable
    public private(set) var mode: PTVehicleTelemetryMode = .live

    private var resolver = PTVehicleTelemetryResolver()
    private var speedResolver = PTVehicleSpeedResolver()
    private var gpsSpeedProvider = PTGPSSpeedProvider()
    public private(set) var resolvedSpeed: PTResolvedVehicleSpeed = .unavailable
    private var hasStarted = false
    private var replayPlayer: PTCrazyTraceReplayPlayer?

    private override init() {
        super.init()
    }

    public var isReplayActive: Bool {
        mode == .replay
    }

    public var gpsSpeedDiagnostics: PTGPSSpeedDiagnostics {
        gpsSpeedProvider.diagnostics
    }

    public func speedResolverDiagnostics(at date: Date = Date()) -> PTVehicleSpeedResolverDiagnostics {
        let diagnostics = speedResolver.diagnostics(at: date, replayActive: isReplayActive)
        resolvedSpeed = diagnostics.resolved
        return diagnostics
    }

    public func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        PTMotion.shared.addDelegate(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLocationUpdate(_:)),
            name: PTLocationEngineDidUpdate,
            object: nil
        )
        if let location = PTLocationEngine.shared.lastLocation {
            ingest(location: location)
        }
        ingest(motion: PTMotion.shared.currentData)
    }

    public func ingest(
        legacySnapshot: PTVehicleTelemetrySnapshot,
        connectionSnapshot: PTVehicleSnapshot? = nil,
        at date: Date = Date()
    ) {
        startIfNeeded()
        guard mode == .live else { return }
        if let connectionSnapshot {
            applyConnectionSnapshot(connectionSnapshot)
            if isAvailable(connectionSnapshot.dashboard) {
                ingestLiveObservations(
                    PTXP400TelemetryAdapter.observations(from: legacySnapshot, at: date),
                    at: date
                )
            }
            if isAvailable(connectionSnapshot.obd) {
                ingestLiveObservations(
                    PTOBDTelemetryAdapter.observations(from: legacySnapshot, at: date),
                    at: date
                )
            }
        } else {
            ingestLiveObservations(
                PTXP400TelemetryAdapter.observations(from: legacySnapshot, at: date),
                at: date
            )
            ingestLiveObservations(
                PTOBDTelemetryAdapter.observations(from: legacySnapshot, at: date),
                at: date
            )
        }
        publishLiveSnapshot(at: date)
    }

    public func updateConnectionSnapshot(_ connectionSnapshot: PTVehicleSnapshot) {
        startIfNeeded()
        guard mode == .live else { return }
        applyConnectionSnapshot(connectionSnapshot)
        publishLiveSnapshot()
    }

    private func applyConnectionSnapshot(_ connectionSnapshot: PTVehicleSnapshot) {
        if !isAvailable(connectionSnapshot.dashboard) {
            resolver.remove(domain: .xp400BLE)
            speedResolver.removeSource(.xp400)
        }
        if !isAvailable(connectionSnapshot.obd) {
            resolver.remove(domain: .obd)
            speedResolver.removeSource(.obd)
        }
    }

    private func isAvailable(_ link: PTVehicleLinkSnapshot) -> Bool {
        link.state == .connected || link.state == .connecting
    }

    public func ingest(observations: [PTVehicleTelemetryObservation], at date: Date = Date()) {
        startIfNeeded()
        guard mode == .live else { return }
        ingestLiveObservations(observations, at: date)
        publishLiveSnapshot(at: date)
    }

    public func ingest(location: CLLocation, at date: Date = Date()) {
        startIfNeeded()
        guard mode == .live else { return }
        ingestLiveObservations(
            PTGPSMotionTelemetryAdapter.observations(from: location, capturedAt: date),
            at: date
        )
        if PTBuild66FeatureFlags.gpsSpeedFallbackEnabled {
            if let sample = gpsSpeedProvider.ingest(location: location, now: date) {
                speedResolver.ingest(sample)
            }
        } else {
            // EN: Disable only the GPS speed candidate; location, heading, and environment remain available.
            // ES: Desactiva solo el candidato de velocidad GPS; ubicación, rumbo y entorno siguen disponibles.
            // 中文：只禁用 GPS 车速候选值，位置、航向和环境数据仍然可用。
            speedResolver.removeSource(.gps)
            gpsSpeedProvider.reset()
        }
        if PTCrazyTraceRecorder.shared.isRecording {
            let speedKmh = location.speed >= 0 && location.speed.isFinite ? location.speed * 3.6 : nil
            let course = location.course >= 0 && location.course.isFinite ? location.course : nil
            PTCrazyTraceRecorder.shared.recordLocation(
                PTTraceLocationPayload(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    altitude: location.altitude.isFinite ? location.altitude : 0,
                    speedKmh: speedKmh,
                    courseDegree: course
                ),
                at: date
            )
        }
        publishLiveSnapshot(at: date)
    }

    public func ingest(motion: PTMotionData, at date: Date = Date()) {
        startIfNeeded()
        guard mode == .live else { return }
        resolver.ingest(PTGPSMotionTelemetryAdapter.observations(from: motion, capturedAt: date))
        if PTCrazyTraceRecorder.shared.isRecording {
            PTCrazyTraceRecorder.shared.recordMotion(
                PTTraceMotionPayload(
                    roll: motion.roll,
                    pitch: motion.pitch,
                    yaw: motion.yaw,
                    gForceX: motion.gForceX,
                    gForceY: motion.gForceY,
                    gForceZ: motion.gForceZ
                ),
                at: date
            )
        }
        publishLiveSnapshot(at: date)
    }

    public func updateAdapterSnapshot(_ snapshot: PTOBDAdapterSnapshot, at date: Date = Date()) {
        guard mode == .live else { return }
        adapterSnapshot = snapshot
        guard PTCrazyTraceRecorder.shared.isRecording else { return }
        let source: PTTraceSource = snapshot.transport == .mock ? .mock : .live
        PTCrazyTraceRecorder.shared.recordAdapter(snapshot, source: source, at: date)
    }

    // EN: Adapter capabilities stay metadata and never enter the vehicle signal resolver.
    // ES: Las capacidades del adaptador siguen siendo metadatos y nunca entran en el resolvedor de señales del vehículo.
    // 中文：适配器能力始终属于元数据，不会进入车辆信号解析器。
    public func updateAdapterSnapshot(
        capabilities: PTELM327Capabilities,
        mode: PTOBDAdapterMode = .disconnected,
        firmwareVersion: String? = nil,
        at date: Date = Date()
    ) {
        updateAdapterSnapshot(
            PTOBDAdapterSnapshot(
                capabilities: capabilities,
                mode: mode,
                firmwareVersion: firmwareVersion
            ),
            at: date
        )
    }

    // EN: Trace controls expose one bounded recorder for all protocol domains and never send a device command.
    // ES: Los controles de traza exponen un único registrador acotado para todos los dominios y nunca envían comandos al dispositivo.
    // 中文：轨迹控制为所有协议域提供一个有界记录器，绝不向设备发送指令。
    @discardableResult
    public func startTrace(
        name: String,
        vehicleID: String? = nil,
        at date: Date = Date()
    ) -> UUID? {
        let traceID = PTCrazyTraceRecorder.shared.start(name: name, vehicleID: vehicleID, at: date)
        if traceID != nil, snapshot != .empty {
            PTCrazyTraceRecorder.shared.recordTelemetry(
                snapshot,
                source: snapshot.containsSyntheticData ? .mock : .live,
                at: date
            )
        }
        return traceID
    }

    @discardableResult
    public func stopTrace(at date: Date = Date()) -> PTCrazyTraceDocument? {
        PTCrazyTraceRecorder.shared.stop(at: date)
    }

    public func exportLatestTrace() async throws -> URL? {
        try await PTCrazyTraceRecorder.shared.exportLatest()
    }

    public func markTrace(_ name: String, metadata: [String: String] = [:], at date: Date = Date()) {
        PTCrazyTraceRecorder.shared.mark(name, metadata: metadata, at: date)
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
        PTCrazyTraceRecorder.shared.recordProtocol(
            domain: domain,
            raw: raw,
            command: command,
            direction: direction,
            source: source,
            metadata: metadata,
            at: date
        )
    }

    public func startReplay(_ document: PTCrazyTraceDocument) {
        endReplay(restoreLiveState: false)
        mode = .replay
        resolver.reset()
        speedResolver.reset()
        gpsSpeedProvider.reset()
        resolvedSpeed = .unavailable
        adapterSnapshot = .unavailable
        snapshot = PTUnifiedVehicleTelemetrySnapshot(updatedAt: Date(), mode: .replay)
        notifySnapshotChange()

        let player = PTCrazyTraceReplayPlayer(document: document)
        player.onEvent = { [weak self] event in
            self?.applyReplayEvent(event)
        }
        replayPlayer = player
        player.play()
    }

    public func startReplay(from url: URL) async throws {
        let document = try await PTCrazyTraceRecorder.load(from: url)
        startReplay(document)
    }

    public func pauseReplay() {
        replayPlayer?.pause()
    }

    public func resumeReplay() {
        replayPlayer?.play()
    }

    public func seekReplay(to elapsed: TimeInterval) {
        guard replayPlayer != nil else { return }
        // EN: Rebuild replay state before a backward seek so later location, motion, and adapter values cannot leak backward.
        // ES: Reconstruye el estado antes de buscar hacia atrás para que ubicación, movimiento y adaptador posteriores no se filtren.
        // 中文：回放定位前重建状态，防止后段的位置、运动和适配器数据泄漏到更早时间点。
        resetReplayState()
        replayPlayer?.seek(to: elapsed)
    }

    public func stopReplay() {
        endReplay(restoreLiveState: true)
    }

    private func endReplay(restoreLiveState: Bool) {
        replayPlayer?.stop()
        replayPlayer = nil
        guard mode == .replay else { return }
        mode = .live
        resolver.reset()
        speedResolver.reset()
        gpsSpeedProvider.reset()
        resolvedSpeed = .unavailable
        adapterSnapshot = .unavailable
        snapshot = .empty
        if restoreLiveState {
            let connectivity = PTVehicleConnectivityCoordinator.shared
            ingest(
                legacySnapshot: connectivity.telemetrySnapshot,
                connectionSnapshot: connectivity.snapshot
            )
        } else {
            notifySnapshotChange()
        }
    }

    private func resetReplayState() {
        resolver.reset()
        speedResolver.reset()
        gpsSpeedProvider.reset()
        resolvedSpeed = .unavailable
        adapterSnapshot = .unavailable
        snapshot = PTUnifiedVehicleTelemetrySnapshot(updatedAt: Date(), mode: .replay)
        notifySnapshotChange()
    }

    nonisolated public func motionManager(_ manager: PTMotion, didUpdateData data: PTMotionData) {
        Task { @MainActor [weak self] in
            self?.ingest(motion: data)
        }
    }

    nonisolated public func motionManager(_ manager: PTMotion, didChangeDataSource source: PTMotionDataSource) {}

    @objc private func handleLocationUpdate(_ notification: Notification) {
        guard let tripData = notification.object as? PTTripData,
              let location = tripData.currentLocation else { return }
        ingest(location: location)
    }

    private func publishLiveSnapshot(at date: Date = Date()) {
        if !PTBuild66FeatureFlags.gpsSpeedFallbackEnabled {
            speedResolver.removeSource(.gps)
        }
        let baseSnapshot = resolver.snapshot(at: date, mode: .live)
        let speed = speedResolver.resolve(at: date)
        resolvedSpeed = speed
        var values = baseSnapshot.values.filter { $0.signal != .speed }
        if let speedKPH = speed.speedKPH,
           let source = speed.source {
            values.append(
                PTVehicleTelemetryResolvedValue(
                    signal: .speed,
                    value: .double(speedKPH),
                    source: telemetrySource(for: source, isSynthetic: speed.isSynthetic),
                    capturedAt: speed.sampleTimestamp ?? date,
                    freshness: .fresh,
                    confidence: speedConfidence(for: source),
                    isSynthetic: speed.isSynthetic
                )
            )
        }
        snapshot = PTUnifiedVehicleTelemetrySnapshot(values: values, updatedAt: date, mode: .live)
        if PTCrazyTraceRecorder.shared.isRecording {
            PTCrazyTraceRecorder.shared.recordTelemetry(
                snapshot,
                source: snapshot.containsSyntheticData ? .mock : .live,
                at: date
            )
        }
        notifySnapshotChange()
    }

    private func applyReplayEvent(_ event: PTCrazyTraceEvent) {
        guard mode == .replay else { return }
        switch event.payload {
        case .telemetry(let historicalSnapshot):
            if let speedKPH = historicalSnapshot.speedKmh,
               let sample = PTVehicleSpeedSample(
                   speedKPH: speedKPH,
                   source: .replay,
                   timestamp: event.timestamp,
                   quality: .valid,
                   isSynthetic: true
               ) {
                speedResolver.ingest(sample)
            }
            let historicalValues = historicalSnapshot.values.filter { $0.signal != .speed }
            let values = historicalValues.map {
                PTVehicleTelemetryResolvedValue(
                    signal: $0.signal,
                    value: $0.value,
                    source: .replay,
                    capturedAt: event.timestamp,
                    freshness: .fresh,
                    confidence: $0.confidence,
                    isSynthetic: true
                )
            }
            let speed = speedResolver.resolve(at: event.timestamp, replayActive: true)
            resolvedSpeed = speed
            var replayValues = values
            if let speedKPH = speed.speedKPH {
                replayValues.append(
                    PTVehicleTelemetryResolvedValue(
                        signal: .speed,
                        value: .double(speedKPH),
                        source: .replay,
                        capturedAt: speed.sampleTimestamp ?? event.timestamp,
                        freshness: .fresh,
                        confidence: 1,
                        isSynthetic: true
                    )
                )
            }
            snapshot = PTUnifiedVehicleTelemetrySnapshot(values: replayValues, updatedAt: event.timestamp, mode: .replay)
            notifySnapshotChange()
        case .location(let payload):
            var values = [
                PTVehicleTelemetryResolvedValue(
                    signal: .location,
                    value: .location(
                        latitude: payload.latitude,
                        longitude: payload.longitude,
                        altitude: payload.altitude
                    ),
                    source: .replay,
                    capturedAt: event.timestamp,
                    freshness: .fresh,
                    confidence: 1,
                    isSynthetic: true
                )
            ]
            if let speedKPH = payload.speedKmh,
               let sample = PTVehicleSpeedSample(
                   speedKPH: speedKPH,
                   source: .replay,
                   timestamp: event.timestamp,
                   quality: .valid,
                   isSynthetic: true
               ) {
                speedResolver.ingest(sample)
            }
            let speed = speedResolver.resolve(at: event.timestamp, replayActive: true)
            resolvedSpeed = speed
            if let speedKPH = speed.speedKPH {
                values.append(
                    PTVehicleTelemetryResolvedValue(
                        signal: .speed,
                        value: .double(speedKPH),
                        source: .replay,
                        capturedAt: speed.sampleTimestamp ?? event.timestamp,
                        freshness: .fresh,
                        confidence: 1,
                        isSynthetic: true
                    )
                )
            }
            mergeReplayValues(
                values,
                at: event.timestamp
            )
        case .motion(let payload):
            mergeReplayValues(
                [
                    replayValue(.lean, payload.roll, at: event.timestamp),
                    replayValue(.pitch, payload.pitch, at: event.timestamp),
                    replayValue(.yaw, payload.yaw, at: event.timestamp),
                    replayValue(.gForceX, payload.gForceX, at: event.timestamp),
                    replayValue(.gForceY, payload.gForceY, at: event.timestamp),
                    replayValue(.gForceZ, payload.gForceZ, at: event.timestamp)
                ],
                at: event.timestamp
            )
        case .adapter(let payload):
            adapterSnapshot = payload.snapshot
            NotificationCenter.default.post(
                name: Self.replayEventDidChange,
                object: self,
                userInfo: ["event": event]
            )
        case .protocolMessage, .marker, .text:
            NotificationCenter.default.post(
                name: Self.replayEventDidChange,
                object: self,
                userInfo: ["event": event]
            )
        }
    }

    private func mergeReplayValues(_ newValues: [PTVehicleTelemetryResolvedValue], at date: Date) {
        var values = snapshot.values.filter { existing in
            !newValues.contains { $0.signal == existing.signal }
        }
        values.append(contentsOf: newValues)
        snapshot = PTUnifiedVehicleTelemetrySnapshot(values: values, updatedAt: date, mode: .replay)
        notifySnapshotChange()
    }

    // EN: Only this bridge converts legacy observations into the specialized speed domain; all other signals keep the existing resolver.
    // ES: Solo este puente convierte observaciones heredadas al dominio especializado de velocidad; las demás señales conservan el resolvedor existente.
    // 中文：只有 Bridge 将旧观测转换到专用速度领域，其余信号继续使用现有 Resolver。
    private func ingestLiveObservations(
        _ observations: [PTVehicleTelemetryObservation],
        at date: Date
    ) {
        resolver.ingest(observations.filter { $0.signal != .speed })
        for observation in observations where observation.signal == .speed {
            guard case .double(let speedKPH) = observation.value,
                  let source = speedSource(for: observation.source),
                  let sample = PTVehicleSpeedSample(
                      speedKPH: speedKPH,
                      source: source,
                      timestamp: observation.capturedAt,
                      quality: PTVehicleSpeedQuality(
                          isValid: observation.isValid,
                          sampleAgeSeconds: max(0, date.timeIntervalSince(observation.capturedAt))
                      ),
                      isSynthetic: observation.isSynthetic
                  ) else {
                continue
            }
            speedResolver.ingest(sample)
        }
    }

    private func speedSource(for source: PTVehicleTelemetrySource) -> PTVehicleSpeedSource? {
        switch source.domain {
        case .xp400BLE: return .xp400
        case .obd: return .obd
        case .gps:
            // EN: GPS speed must pass through PTGPSSpeedProvider; never bypass its quality gates here.
            // ES: La velocidad GPS debe pasar por PTGPSSpeedProvider; nunca omite sus filtros de calidad aquí.
            // 中文：GPS 车速必须经过 PTGPSSpeedProvider，不能在这里绕过质量门禁。
            return nil
        case .replay: return .replay
        case .motion, .calculated, .unknown: return nil
        }
    }

    private func telemetrySource(
        for source: PTVehicleSpeedSource,
        isSynthetic: Bool
    ) -> PTVehicleTelemetrySource {
        switch source {
        case .xp400: return isSynthetic ? .dashboardMock : .xp400BLE
        case .obd: return isSynthetic ? .obdMock : .obd
        case .gps: return .gps
        case .replay: return .replay
        }
    }

    private func speedConfidence(for source: PTVehicleSpeedSource) -> Double {
        switch source {
        case .xp400: return 1
        case .obd: return 0.95
        case .gps: return 0.75
        case .replay: return 1
        }
    }

    private func replayValue(
        _ signal: PTVehicleTelemetrySignal,
        _ value: Double,
        at date: Date
    ) -> PTVehicleTelemetryResolvedValue {
        PTVehicleTelemetryResolvedValue(
            signal: signal,
            value: .double(value),
            source: .replay,
            capturedAt: date,
            freshness: .fresh,
            confidence: 1,
            isSynthetic: true
        )
    }

    private func notifySnapshotChange() {
        PTVehicleTelemetryConsumerHub.shared.publish(snapshot)
        NotificationCenter.default.post(
            name: Self.didChange,
            object: self,
            userInfo: ["snapshot": snapshot]
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
