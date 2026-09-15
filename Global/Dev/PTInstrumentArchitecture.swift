//
//  PTInstrumentArchitecture.swift
//  CrazyDashboard
//
//  EN: Splits read-only developer instrumentation into domain providers while preserving the existing snapshot schema.
//  ES: Divide la instrumentación de solo lectura en proveedores por dominio y conserva el esquema de instantáneas existente.
//  中文：将只读开发者 Instruments 按领域拆分，同时保持现有快照结构和导出格式不变。
//

import Foundation
import CoreBluetooth
import PooTools

public nonisolated enum PTInstrumentDomainSnapshot: Sendable {
    case xp400BLE(PTCrazyDashboardXP400BLEMetrics)
    case obd(PTCrazyDashboardOBDMetrics)
    case ymobdAdapter(PTCrazyDashboardAdapterMetrics)
    case adapterOTA(PTCrazyDashboardOTAMetrics)
    case can(PTCrazyDashboardCANMetrics)
    case telemetry(PTCrazyDashboardTelemetryMetrics)
    case gps(PTCrazyDashboardGPSMetrics)
    case speed(PTCrazyDashboardSpeedMetrics)
    case motion(PTCrazyDashboardMotionMetrics)
    case system(PTCrazyDashboardSystemMetrics)
}

@MainActor
public protocol PTInstrumentProvider: AnyObject {
    var domain: PTCrazyDashboardInstrumentDomain { get }
    func start()
    func stop()
    func snapshot(at date: Date) -> PTInstrumentDomainSnapshot
}

@MainActor
public final class PTXP400InstrumentProvider: NSObject, PTInstrumentProvider, PTBLEDashboardDelegate {
    public let domain: PTCrazyDashboardInstrumentDomain = .xp400BLE

    private var rxWindow = PTCrazyDashboardInstrumentRateWindow()
    private var isStarted = false

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        PTBluetoothServerManager.shared.addDelegate(self)
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        PTBluetoothServerManager.shared.removeDelegate(self)
    }

    public func snapshot(at date: Date) -> PTInstrumentDomainSnapshot {
        let vehicle = PTVehicleConnectivityCoordinator.shared.snapshot
        let reliability = PTVehicleConnectivityCoordinator.shared.dashboardBLEReliabilitySnapshot
        let telemetryCount = PTVehicleTelemetryConsumerHub.shared.latestSnapshot.values.count
        let manager = PTBluetoothServerManager.shared
        return .xp400BLE(
            PTCrazyDashboardXP400BLEMetrics(
                isConnected: vehicle.dashboard.state == .connected,
                lifecycle: manager.peripheralLifecycleState.rawValue,
                sessionID: reliability.activeSessionID,
                generation: reliability.activeGeneration,
                isAuthenticated: manager.authenticated,
                isTioSubscribed: manager.isTioSubscribed,
                isCreditsSubscribed: manager.isCreditsSubscribed,
                rxPerSecond: rxWindow.rate(at: date),
                txPerSecond: nil,
                txRateAvailability: "not-exposed-by-frozen-core",
                sendCredits: manager.sendCredits,
                localCredits: manager.localCredits,
                queueDepth: manager.sendQueue.jobs.count,
                isSending: manager.isSending,
                reconnectCount: reliability.eventCounts[PTXP400BLEReliabilityEventKind.automaticReconnect.rawValue] ?? 0,
                telemetrySignalCount: telemetryCount
            )
        )
    }

    nonisolated func dashboardManager(_ manager: PTBluetoothServerManager, dashboardData data: Any?) {
        Task { @MainActor [weak self] in
            self?.rxWindow.record(at: Date())
        }
    }

    nonisolated func dashboardManager(_ manager: PTBluetoothServerManager, didChangeConnectionState isConnected: Bool) {}

    nonisolated func dashboardManager(
        _ manager: PTBluetoothServerManager,
        didObserveLifecycleEvent event: PTXP400BLELifecycleEvent
    ) {}

    nonisolated func dashboardManager(
        _ manager: PTBluetoothServerManager,
        didUpdateConnectionIdentity identity: PTDashboardConnectionIdentity?
    ) {}
}

@MainActor
public final class PTOBDInstrumentProvider: NSObject, PTInstrumentProvider, PTMotoTelemetryDelegate {
    public let domain: PTCrazyDashboardInstrumentDomain = .obd

    private var measurementWindow = PTCrazyDashboardInstrumentRateWindow()
    private var lastEventName: String?
    private var isStarted = false

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        PTMotoTelemetryManager.shared.addDelegate(self)
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        PTMotoTelemetryManager.shared.removeDelegate(self)
    }

    public func updateMetadata(lastEventName: String?) {
        self.lastEventName = lastEventName.map { String($0.prefix(128)) }
    }

    public func snapshot(at date: Date) -> PTInstrumentDomainSnapshot {
        let vehicle = PTVehicleConnectivityCoordinator.shared.snapshot
        let manager = PTMotoTelemetryManager.shared
        let connector = connector(for: vehicle.obd.transport)
        let connected = vehicle.obd.state == .connected || manager.isConnected
        let polling = manager.telemetryPollingTask != nil
        let elmState: String
        if vehicle.obd.state == .connecting {
            elmState = "connecting"
        } else if !connected {
            elmState = "disconnected"
        } else if connector?.isSnifferMode == true {
            elmState = "monitoring"
        } else if polling {
            elmState = "polling"
        } else {
            elmState = "ready"
        }
        return .obd(
            PTCrazyDashboardOBDMetrics(
                isConnected: connected,
                transport: vehicle.obd.transport?.rawValue ?? "unknown",
                elmState: elmState,
                isPolling: polling,
                commandQueueDepth: nil,
                commandQueueAvailability: "legacy-manager-not-exposed",
                currentLease: "not-exposed",
                pidPerSecond: measurementWindow.rate(at: date),
                rttMilliseconds: nil,
                canMonitorState: PTCANExperimentCoordinator.shared.state.rawValue,
                udsState: lastEventName ?? "idle",
                lastError: vehicle.obd.errorMessage
            )
        )
    }

    nonisolated public func telemetryManager(
        _ manager: PTMotoTelemetryManager,
        didUpdateMeasurements measurements: [String: Any]
    ) {
        Task { @MainActor [weak self] in
            self?.measurementWindow.record(at: Date())
        }
    }

    nonisolated public func telemetryManager(_ manager: PTMotoTelemetryManager, didChangeConnectionState isConnected: Bool) {}

    private func connector(for transport: PTVehicleTransport?) -> PTOBDTransportBase? {
        switch transport {
        case .obdBluetooth:
            return PTHiddenOBDConnector.shared
        case .obdWiFi:
            return PTWifiOBDConnector.shared
        case .obdMock:
            return PTMockOBDConnector.shared
        default:
            return nil
        }
    }
}

@MainActor
public final class PTYMOBDInstrumentProvider: NSObject, PTInstrumentProvider {
    public let domain: PTCrazyDashboardInstrumentDomain = .ymobdAdapter
    private var modeOverride: PTYMOBDAdapterMode?

    public func start() {}
    public func stop() {}

    public func snapshot(at date: Date) -> PTInstrumentDomainSnapshot {
        .ymobdAdapter(makeMetrics())
    }

    public func currentMetrics() -> PTCrazyDashboardAdapterMetrics {
        makeMetrics()
    }

    public func updateMode(_ mode: PTYMOBDAdapterMode?) {
        modeOverride = mode
    }

    private func makeMetrics() -> PTCrazyDashboardAdapterMetrics {
        let vehicle = PTVehicleConnectivityCoordinator.shared.snapshot
        let bridge = PTVehicleTelemetryBridge.shared
        let hiddenConnector = PTHiddenOBDConnector.shared
        let obdInfo = PTMotoTelemetryManager.shared.obdInfo
        let canonical = bridge.adapterSnapshot
        let official = canonical.isOfficialYMOBD || hiddenConnector.isOfficialYMOBD
        let vendor = canonical.vendor ?? nonEmpty(obdInfo.moudleInfo.company)
        let model = canonical.model ?? nonEmpty(obdInfo.moudleInfo.deviceType)
        let firmware = canonical.firmwareVersion ?? nonEmpty(obdInfo.moudleInfo.version) ?? nonEmpty(obdInfo.ecuVersion)
        let identifier: String? = nonEmpty(obdInfo.moudleInfo.deviceMac)
            ?? redactedIdentifier(hiddenConnector.obdPeripheral?.identifier.uuidString)
        var capabilities = ["supportedCommands=\(obdInfo.supportCommand.count)"]
        if official { capabilities.append("officialYMOBD") }
        if let mask = hiddenConnector.pid0100Mask {
            capabilities.append(String(format: "PID0100=0x%08X", mask))
        }
        let mode = modeOverride
            ?? (PTJieliOTAManager.shared.isRunning && official ? .jieliOTA : (vehicle.obd.state == .connected ? .elm : .disconnected))
        let authenticated = connector(for: vehicle.obd.transport)?.isUnlocked == true
            ? "unlocked"
            : (vehicle.obd.state == .connected ? "locked-or-unknown" : "not-connected")
        return PTCrazyDashboardAdapterMetrics(
            vendor: vendor,
            model: model ?? nonEmpty(obdInfo.moudleInfo.deviceName),
            firmwareVersion: firmware,
            identifierSuffix: identifier.flatMap(redactedIdentifier),
            transport: canonical.transport == .unknown
                ? (vehicle.obd.transport?.rawValue ?? "unknown")
                : canonical.transport.rawValue,
            authentication: authenticated,
            capabilities: capabilities,
            mode: mode.rawValue,
            isOfficialYMOBD: official
        )
    }

    private func connector(for transport: PTVehicleTransport?) -> PTOBDTransportBase? {
        switch transport {
        case .obdBluetooth: return PTHiddenOBDConnector.shared
        case .obdWiFi: return PTWifiOBDConnector.shared
        case .obdMock: return PTMockOBDConnector.shared
        default: return nil
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : String(normalized.prefix(128))
    }

    private func redactedIdentifier(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return String(value.suffix(8)).uppercased()
    }
}

@MainActor
public final class PTJieliOTAInstrumentProvider: NSObject, PTInstrumentProvider {
    public let domain: PTCrazyDashboardInstrumentDomain = .adapterOTA
    private let adapterProvider: PTYMOBDInstrumentProvider
    private var resumeState = "none"

    public init(adapterProvider: PTYMOBDInstrumentProvider) {
        self.adapterProvider = adapterProvider
        super.init()
    }

    public func start() {}
    public func stop() {}

    public func updateResumeState(_ value: String) {
        resumeState = String(value.prefix(128))
    }

    public func snapshot(at date: Date) -> PTInstrumentDomainSnapshot {
        let ota = PTJieliOTAManager.shared
        let visible = PTDeveloperSafetyGate.shared.isEnabled
            && ota.isRunning
            && adapterProvider.currentMetrics().isOfficialYMOBD
        return .adapterOTA(
            PTCrazyDashboardOTAMetrics(
                isVisible: visible,
                sdkVersion: "2.5.0",
                state: ota.state.rawValue,
                progress: ota.progress.fractionCompleted,
                completedBytes: ota.progress.completedBytes,
                totalBytes: ota.progress.totalBytes,
                reconnectCount: ota.reconnectCount,
                resumeState: resumeState,
                targetFirmwareVersion: ota.currentSession?.targetFirmwareVersion,
                currentFirmwareVersion: ota.currentSession?.oldFirmwareVersion ?? adapterProvider.currentMetrics().firmwareVersion,
                versionVerified: ota.state == .completed ? true : (ota.state == .failed ? false : nil),
                error: ota.lastError?.localizedDescription
            )
        )
    }
}

@MainActor
public final class PTCANInstrumentProvider: NSObject, PTInstrumentProvider {
    public let domain: PTCrazyDashboardInstrumentDomain = .can
    private var previousFrameCount: Int?
    private var previousSampleAt: Date?

    public func start() {}
    public func stop() {}

    public func snapshot(at date: Date) -> PTInstrumentDomainSnapshot {
        let session = PTCANRecorder.shared.snapshot()
        let currentCount = session?.totalFrameCount ?? 0
        var framesPerSecond: Double?
        if let previousFrameCount,
           let previousSampleAt {
            let elapsed = date.timeIntervalSince(previousSampleAt)
            if elapsed > 0 {
                framesPerSecond = Double(max(0, currentCount - previousFrameCount)) / elapsed
            }
        }
        self.previousFrameCount = currentCount
        self.previousSampleAt = date
        let headers = Array(Set(session?.frames.compactMap(\.header) ?? [])).sorted().prefix(32)
        return .can(
            PTCrazyDashboardCANMetrics(
                state: PTCANExperimentCoordinator.shared.state.rawValue,
                framesPerSecond: framesPerSecond,
                totalFrameCount: session?.totalFrameCount ?? 0,
                retainedFrameCount: session?.retainedFrameCount ?? 0,
                droppedFrameCount: session?.droppedFrameCount ?? 0,
                headers: Array(headers)
            )
        )
    }
}

@MainActor
public final class PTTelemetryInstrumentProvider: NSObject, PTInstrumentProvider {
    public let domain: PTCrazyDashboardInstrumentDomain = .telemetry
    private var latestSnapshot: PTUnifiedVehicleTelemetrySnapshot = .empty

    public func start() {}
    public func stop() {}

    public func update(_ snapshot: PTUnifiedVehicleTelemetrySnapshot) {
        latestSnapshot = snapshot
    }

    public func snapshot(at date: Date) -> PTInstrumentDomainSnapshot {
        .telemetry(
            PTCrazyDashboardTelemetryMetrics(
                mode: latestSnapshot.mode.rawValue,
                valueCount: latestSnapshot.values.count,
                signalNames: latestSnapshot.values.map(\.signal.rawValue),
                containsSyntheticData: latestSnapshot.containsSyntheticData,
                updatedAt: latestSnapshot.updatedAt
            )
        )
    }
}

@MainActor
public final class PTGPSInstrumentProvider: NSObject, PTInstrumentProvider {
    public let domain: PTCrazyDashboardInstrumentDomain = .gps

    public func start() {}
    public func stop() {}

    public func snapshot(at date: Date) -> PTInstrumentDomainSnapshot {
        let location = PTLocationEngine.shared.lastLocation
        let accuracy: Double?
        if let value = location?.horizontalAccuracy, value >= 0, value.isFinite {
            accuracy = value
        } else {
            accuracy = nil
        }
        return .gps(
            PTCrazyDashboardGPSMetrics(
                isTracking: PTLocationEngine.shared.isTracking,
                horizontalAccuracyMeters: accuracy
            )
        )
    }
}

// EN: The speed provider exposes resolver candidates and GPS quality in one read-only snapshot for developer diagnostics.
// ES: El proveedor de velocidad expone los candidatos del resolvedor y la calidad GPS en una instantánea de diagnóstico de solo lectura.
// 中文：速度 Provider 在一个只读诊断快照中暴露 Resolver 候选值和 GPS 质量。
@MainActor
public final class PTSpeedInstrumentProvider: NSObject, PTInstrumentProvider {
    public let domain: PTCrazyDashboardInstrumentDomain = .speed

    public func start() {}
    public func stop() {}

    public func snapshot(at date: Date) -> PTInstrumentDomainSnapshot {
        let bridge = PTVehicleTelemetryBridge.shared
        let diagnostics = bridge.speedResolverDiagnostics(at: date)
        let gps = bridge.gpsSpeedDiagnostics
        return .speed(
            PTCrazyDashboardSpeedMetrics(
                resolvedSpeedKPH: diagnostics.resolved.speedKPH,
                resolvedSource: diagnostics.resolved.source?.rawValue,
                resolutionReason: diagnostics.lastResolutionReason.rawValue,
                resolvedAgeSeconds: diagnostics.resolved.candidateAgeSeconds,
                isFresh: diagnostics.resolved.isFresh,
                switchCount: diagnostics.switchCount,
                pendingSource: diagnostics.pendingSource?.rawValue,
                pendingSampleCount: diagnostics.pendingSampleCount,
                gpsStatus: gps.status.rawValue,
                gpsRawSpeedMetersPerSecond: gps.rawSpeedMetersPerSecond,
                gpsFilteredSpeedKPH: gps.filteredSpeedKPH,
                gpsHorizontalAccuracyMeters: gps.horizontalAccuracyMeters,
                gpsSpeedAccuracyMetersPerSecond: gps.speedAccuracyMetersPerSecond,
                gpsSampleAgeSeconds: gps.sampleAgeSeconds,
                candidates: diagnostics.candidates.map {
                    PTCrazyDashboardSpeedCandidateMetrics(
                        source: $0.source.rawValue,
                        speedKPH: $0.speedKPH,
                        ageSeconds: $0.ageSeconds,
                        isFresh: $0.isFresh,
                        isSynthetic: $0.isSynthetic,
                        horizontalAccuracyMeters: $0.quality.horizontalAccuracyMeters,
                        speedAccuracyMetersPerSecond: $0.quality.speedAccuracyMetersPerSecond,
                        rawSpeedMetersPerSecond: $0.quality.rawSpeedMetersPerSecond
                    )
                }
            )
        )
    }
}

@MainActor
public final class PTMotionInstrumentProvider: NSObject, PTInstrumentProvider {
    public let domain: PTCrazyDashboardInstrumentDomain = .motion

    public func start() {}
    public func stop() {}

    public func snapshot(at date: Date) -> PTInstrumentDomainSnapshot {
        let motion = PTMotion.shared.currentData
        return .motion(
            PTCrazyDashboardMotionMetrics(
                source: motion.currentDataSource.rawValue,
                sampleRateHz: nil,
                roll: motion.roll,
                pitch: motion.pitch,
                yaw: motion.yaw,
                gForceX: motion.gForceX,
                gForceY: motion.gForceY,
                gForceZ: motion.gForceZ
            )
        )
    }
}

@MainActor
public final class PTSystemInstrumentProvider: NSObject, PTInstrumentProvider {
    public let domain: PTCrazyDashboardInstrumentDomain = .system

    public func start() {}
    public func stop() {}

    public func snapshot(at date: Date) -> PTInstrumentDomainSnapshot {
        .system(
            PTCrazyDashboardSystemMetrics(
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                buildVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                generatedAt: date,
                isReadOnly: true,
                isReplayActive: PTVehicleTelemetryConsumerHub.shared.latestSnapshot.mode == .replay
            )
        )
    }
}

@MainActor
public final class PTInstrumentProviderRegistry {
    public let xp400: PTXP400InstrumentProvider
    public let obd: PTOBDInstrumentProvider
    public let ymobd: PTYMOBDInstrumentProvider
    public let ota: PTJieliOTAInstrumentProvider
    public let can: PTCANInstrumentProvider
    public let telemetry: PTTelemetryInstrumentProvider
    public let gps: PTGPSInstrumentProvider
    public let speed: PTSpeedInstrumentProvider
    public let motion: PTMotionInstrumentProvider
    public let system: PTSystemInstrumentProvider

    private var isStarted = false

    public init() {
        let ymobd = PTYMOBDInstrumentProvider()
        self.xp400 = PTXP400InstrumentProvider()
        self.obd = PTOBDInstrumentProvider()
        self.ymobd = ymobd
        self.ota = PTJieliOTAInstrumentProvider(adapterProvider: ymobd)
        self.can = PTCANInstrumentProvider()
        self.telemetry = PTTelemetryInstrumentProvider()
        self.gps = PTGPSInstrumentProvider()
        self.speed = PTSpeedInstrumentProvider()
        self.motion = PTMotionInstrumentProvider()
        self.system = PTSystemInstrumentProvider()
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        xp400.start()
        obd.start()
        ymobd.start()
        ota.start()
        can.start()
        telemetry.start()
        gps.start()
        speed.start()
        motion.start()
        system.start()
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        xp400.stop()
        obd.stop()
        ymobd.stop()
        ota.stop()
        can.stop()
        telemetry.stop()
        gps.stop()
        speed.stop()
        motion.stop()
        system.stop()
    }

    public func updateMetadata(adapterMode: PTYMOBDAdapterMode?, lastEventName: String?, resumeState: String?) {
        ymobd.updateMode(adapterMode)
        obd.updateMetadata(lastEventName: lastEventName)
        if let resumeState {
            ota.updateResumeState(resumeState)
        }
    }

    // EN: Metadata reads stay behind the registry so the store only coordinates providers and publishes values.
    // ES: Las lecturas de metadatos permanecen detrás del registro para que el store solo coordine proveedores y publique valores.
    // 中文：元数据读取封装在 Registry 内，让 Store 只负责协调 Provider 和发布结果。
    public func refreshMetadata() async {
        let mode = await PTYMOBDAdapterModeCoordinator.shared.mode
        let traceSnapshot = await PTOBDSessionTrace.shared.snapshot()
        let checkpoint = try? await PTOTAResumeStore.shared.load()
        guard !Task.isCancelled else { return }

        let resumeState: String
        if let checkpoint {
            resumeState = "\(checkpoint.state.rawValue) (\(Int(checkpoint.progress.fractionCompleted * 100))%)"
        } else {
            resumeState = "none"
        }
        updateMetadata(
            adapterMode: mode,
            lastEventName: traceSnapshot.events.last?.name,
            resumeState: resumeState
        )
    }

    public func snapshot(at date: Date = Date()) -> PTCrazyDashboardInstrumentSnapshot {
        telemetry.update(PTVehicleTelemetryConsumerHub.shared.latestSnapshot)
        guard case .xp400BLE(let xp400Metrics) = xp400.snapshot(at: date),
              case .obd(let obdMetrics) = obd.snapshot(at: date),
              case .ymobdAdapter(let ymobdMetrics) = ymobd.snapshot(at: date),
              case .adapterOTA(let otaMetrics) = ota.snapshot(at: date),
              case .can(let canMetrics) = can.snapshot(at: date),
              case .telemetry(let telemetryMetrics) = telemetry.snapshot(at: date),
              case .gps(let gpsMetrics) = gps.snapshot(at: date),
              case .speed(let speedMetrics) = speed.snapshot(at: date),
              case .motion(let motionMetrics) = motion.snapshot(at: date),
              case .system(let systemMetrics) = system.snapshot(at: date) else {
            return .empty
        }
        return PTCrazyDashboardInstrumentSnapshot(
            generatedAt: date,
            xp400BLE: xp400Metrics,
            obd: obdMetrics,
            ymobdAdapter: ymobdMetrics,
            adapterOTA: otaMetrics,
            can: canMetrics,
            telemetry: telemetryMetrics,
            gps: gpsMetrics,
            speed: speedMetrics,
            motion: motionMetrics,
            system: systemMetrics
        )
    }
}
