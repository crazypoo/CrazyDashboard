//
//  PTVehicleTwin.swift
//  CrazyDashboard
//
//  EN: Read-only Build 76A projection for the XP400 Digital Twin.
//  ES: Proyección de solo lectura de Build 76A para el Digital Twin de XP400.
//  中文：Build 76A 的 XP400 数字孪生只读状态投影。
//

import Foundation

// EN: The renderer uses an explicit four-step freshness vocabulary instead of hiding stale values.
// ES: El renderizador usa una frescura explícita de cuatro estados y no oculta valores obsoletos.
// 中文：渲染器使用明确的四级新鲜度，不会把过期值伪装成正常值。
enum PTVehicleTwinFreshness: String, Equatable, Sendable {
    case fresh
    case aging
    case stale
    case unavailable
}

// EN: Every displayed metric keeps its source and capture time for trustworthy UI decisions.
// ES: Cada métrica conserva su fuente y hora de captura para decisiones fiables de interfaz.
// 中文：每个展示指标都保留来源和采集时间，保证界面判断可追溯。
struct PTVehicleTwinMetric<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value
    let source: PTVehicleTelemetrySource
    let capturedAt: Date
    let freshness: PTVehicleTwinFreshness
    let isSynthetic: Bool

    init(
        value: Value,
        source: PTVehicleTelemetrySource,
        capturedAt: Date,
        freshness: PTVehicleTwinFreshness,
        isSynthetic: Bool = false
    ) {
        self.value = value
        self.source = source
        self.capturedAt = capturedAt
        self.freshness = freshness
        self.isSynthetic = isSynthetic || source.isMock || source == .replay
    }
}

enum PTVehicleTwinTCSState: String, Equatable, Sendable {
    case off
    case mode1
    case mode2
    case unknown
}

enum PTVehicleTwinABSState: String, Equatable, Sendable {
    case ready
    case warning
}

enum PTVehicleTwinEngineState: String, Equatable, Sendable {
    case off
    case starting
    case running
    case stopping
    case unknown
}

struct PTVehicleTwinCoordinateSnapshot: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
}

struct PTVehicleTwinConfiguration: Equatable, Sendable {
    enum Model: String, Equatable, Sendable {
        case xp400
        case xp400GT
    }

    let model: Model
    let supportsKickstand: Bool
    let supportsLights: Bool

    static let xp400 = PTVehicleTwinConfiguration(
        model: .xp400,
        supportsKickstand: true,
        supportsLights: true
    )

    static let xp400GT = PTVehicleTwinConfiguration(
        model: .xp400GT,
        supportsKickstand: true,
        supportsLights: true
    )
}

// EN: This is the shared renderer input for the future 2D and 3D twins.
// ES: Esta es la entrada común del renderizador para los Digital Twins 2D y 3D futuros.
// 中文：这是未来 2D 与 3D 数字孪生共用的渲染器输入。
struct PTVehicleTwinSnapshot: Equatable, Sendable {
    let updatedAt: Date
    let speedKmh: PTVehicleTwinMetric<Double>?
    let rpm: PTVehicleTwinMetric<Double>?
    let fuelPercent: PTVehicleTwinMetric<Double>?
    let voltage: PTVehicleTwinMetric<Double>?
    let leanDegrees: PTVehicleTwinMetric<Double>?
    let pitchDegrees: PTVehicleTwinMetric<Double>?
    let longitudinalG: PTVehicleTwinMetric<Double>?
    let lateralG: PTVehicleTwinMetric<Double>?
    let kickstandDown: PTVehicleTwinMetric<Bool>?
    let engineState: PTVehicleTwinMetric<PTVehicleTwinEngineState>?
    let leftIndicatorOn: PTVehicleTwinMetric<Bool>?
    let rightIndicatorOn: PTVehicleTwinMetric<Bool>?
    let hazardOn: PTVehicleTwinMetric<Bool>?
    let lowBeamOn: PTVehicleTwinMetric<Bool>?
    let highBeamOn: PTVehicleTwinMetric<Bool>?
    let tcsState: PTVehicleTwinMetric<PTVehicleTwinTCSState>?
    let absState: PTVehicleTwinMetric<PTVehicleTwinABSState>?
    let coordinate: PTVehicleTwinCoordinateSnapshot?
    let dashboardConnected: Bool
    let obdConnected: Bool
    let freshness: PTVehicleTwinFreshness
    let isSynthetic: Bool

    static let empty = PTVehicleTwinSnapshot(
        updatedAt: .distantPast,
        speedKmh: nil,
        rpm: nil,
        fuelPercent: nil,
        voltage: nil,
        leanDegrees: nil,
        pitchDegrees: nil,
        longitudinalG: nil,
        lateralG: nil,
        kickstandDown: nil,
        engineState: nil,
        leftIndicatorOn: nil,
        rightIndicatorOn: nil,
        hazardOn: nil,
        lowBeamOn: nil,
        highBeamOn: nil,
        tcsState: nil,
        absState: nil,
        coordinate: nil,
        dashboardConnected: false,
        obdConnected: false,
        freshness: .unavailable,
        isSynthetic: false
    )
}

// EN: Maps existing read-only projections; it never subscribes to or commands a transport.
// ES: Mapea proyecciones existentes de solo lectura; nunca se suscribe ni ordena un transporte.
// 中文：只映射现有只读投影，不订阅也不控制任何传输层。
enum PTVehicleTwinStateMapper {
    static func makeCurrent(now: Date = Date()) -> PTVehicleTwinSnapshot {
        let coordinator = PTVehicleConnectivityCoordinator.shared
        let control = coordinator.snapshot.dashboard.state == .connected
            ? PTBluetoothServerManager.shared.latestControl
            : nil
        return make(
            unified: PTVehicleTelemetryConsumerHub.shared.latestSnapshot,
            connection: coordinator.snapshot,
            control: control,
            now: now
        )
    }

    static func make(
        unified: PTUnifiedVehicleTelemetrySnapshot,
        connection: PTVehicleSnapshot,
        control: PTDashboardControl?,
        now: Date = Date()
    ) -> PTVehicleTwinSnapshot {
        let speed: PTVehicleTwinMetric<Double>? = metric(unified, signal: .speed, connection: connection, now: now) { value in
            guard case .double(let value) = value else { return nil }
            return value
        }
        let rpm: PTVehicleTwinMetric<Double>? = metric(unified, signal: .rpm, connection: connection, now: now) { value in
            guard case .integer(let value) = value else { return nil }
            return Double(value)
        }
        let fuel: PTVehicleTwinMetric<Double>? = metric(unified, signal: .fuel, connection: connection, now: now) { value in
            guard case .integer(let value) = value else { return nil }
            return Double(value)
        }
        let voltage: PTVehicleTwinMetric<Double>? = metric(unified, signal: .batteryVoltage, connection: connection, now: now) { value in
            guard case .double(let value) = value else { return nil }
            return value
        }
        let lean: PTVehicleTwinMetric<Double>? = metric(unified, signal: .lean, connection: connection, now: now) { value in
            guard case .double(let value) = value else { return nil }
            return value
        }
        let pitch: PTVehicleTwinMetric<Double>? = metric(unified, signal: .pitch, connection: connection, now: now) { value in
            guard case .double(let value) = value else { return nil }
            return value
        }
        let longitudinalG: PTVehicleTwinMetric<Double>? = metric(unified, signal: .gForceX, connection: connection, now: now) { value in
            guard case .double(let value) = value else { return nil }
            return value
        }
        let lateralG: PTVehicleTwinMetric<Double>? = metric(unified, signal: .gForceY, connection: connection, now: now) { value in
            guard case .double(let value) = value else { return nil }
            return value
        }
        let kickstand: PTVehicleTwinMetric<Bool>? = metric(unified, signal: .kickstandDown, connection: connection, now: now) { value in
            guard case .boolean(let value) = value else { return nil }
            return value
        }
        let engine: PTVehicleTwinMetric<PTVehicleTwinEngineState>? = metric(unified, signal: .engineStatus, connection: connection, now: now) { value in
            guard case .integer(let value) = value else { return nil }
            return engineState(for: value)
        }
        let abs: PTVehicleTwinMetric<PTVehicleTwinABSState>? = metric(unified, signal: .abs, connection: connection, now: now) { value in
            guard case .boolean(let value) = value else { return nil }
            return value ? .warning : .ready
        }

        let controlCaptureDate = controlCaptureDate(unified: unified, connection: connection, now: now)
        let controlSource: PTVehicleTelemetrySource = connection.dashboard.transport == .dashboardMock
            ? .dashboardMock
            : .xp400BLE
        let controlFreshness = connection.dashboard.state == .connected
            ? freshness(capturedAt: controlCaptureDate, signal: .lights, now: now)
            : .unavailable
        let controlSynthetic = controlSource.isMock

        let tcs: PTVehicleTwinMetric<PTVehicleTwinTCSState>?
        let left: PTVehicleTwinMetric<Bool>?
        let right: PTVehicleTwinMetric<Bool>?
        let hazard: PTVehicleTwinMetric<Bool>?
        let lowBeam: PTVehicleTwinMetric<Bool>?
        let highBeam: PTVehicleTwinMetric<Bool>?

        if let control, connection.dashboard.state == .connected {
            tcs = PTVehicleTwinMetric(
                value: mapTCS(control.tcsMode),
                source: controlSource,
                capturedAt: controlCaptureDate,
                freshness: controlFreshness,
                isSynthetic: controlSynthetic
            )
            left = controlMetric(control.isLeftTurnOn, source: controlSource, capturedAt: controlCaptureDate, freshness: controlFreshness)
            right = controlMetric(control.isRightTurnOn, source: controlSource, capturedAt: controlCaptureDate, freshness: controlFreshness)
            hazard = controlMetric(control.isHazardOn, source: controlSource, capturedAt: controlCaptureDate, freshness: controlFreshness)
            lowBeam = controlMetric(control.isLowBeamOn, source: controlSource, capturedAt: controlCaptureDate, freshness: controlFreshness)
            highBeam = controlMetric(control.isHighBeamOn, source: controlSource, capturedAt: controlCaptureDate, freshness: controlFreshness)
        } else {
            tcs = nil
            left = nil
            right = nil
            hazard = nil
            lowBeam = nil
            highBeam = nil
        }

        let coordinate = unified.location.map {
            PTVehicleTwinCoordinateSnapshot(latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude)
        }
        let metrics: [PTVehicleTwinFreshness] = [
            speed?.freshness,
            rpm?.freshness,
            fuel?.freshness,
            voltage?.freshness,
            lean?.freshness,
            pitch?.freshness,
            kickstand?.freshness,
            engine?.freshness,
            tcs?.freshness,
            abs?.freshness,
            left?.freshness,
            right?.freshness,
            lowBeam?.freshness,
            highBeam?.freshness
        ].compactMap { $0 }

        let freshness = overallFreshness(metrics: metrics)
        let synthetic = unified.containsSyntheticData
            || (control != nil && controlSynthetic)
            || speed?.isSynthetic == true
            || rpm?.isSynthetic == true
            || fuel?.isSynthetic == true
            || voltage?.isSynthetic == true
            || lean?.isSynthetic == true
            || pitch?.isSynthetic == true
            || longitudinalG?.isSynthetic == true
            || lateralG?.isSynthetic == true
            || kickstand?.isSynthetic == true
            || engine?.isSynthetic == true
            || abs?.isSynthetic == true

        return PTVehicleTwinSnapshot(
            updatedAt: unified.updatedAt == .distantPast ? now : unified.updatedAt,
            speedKmh: speed,
            rpm: rpm,
            fuelPercent: fuel,
            voltage: voltage,
            leanDegrees: lean,
            pitchDegrees: pitch,
            longitudinalG: longitudinalG,
            lateralG: lateralG,
            kickstandDown: kickstand,
            engineState: engine,
            leftIndicatorOn: left,
            rightIndicatorOn: right,
            hazardOn: hazard,
            lowBeamOn: lowBeam,
            highBeamOn: highBeam,
            tcsState: tcs,
            absState: abs,
            coordinate: coordinate,
            dashboardConnected: connection.isDashboardConnected,
            obdConnected: connection.isOBDConnected,
            freshness: freshness,
            isSynthetic: synthetic
        )
    }

    private static func metric<Value: Equatable & Sendable>(
        _ snapshot: PTUnifiedVehicleTelemetrySnapshot,
        signal: PTVehicleTelemetrySignal,
        connection: PTVehicleSnapshot,
        now: Date,
        transform: (PTVehicleTelemetryValue) -> Value?
    ) -> PTVehicleTwinMetric<Value>? {
        guard let resolved = snapshot.value(for: signal), let value = transform(resolved.value) else {
            return nil
        }
        return PTVehicleTwinMetric(
            value: value,
            source: resolved.source,
            capturedAt: resolved.capturedAt,
            freshness: freshness(for: resolved, connection: connection, now: now),
            isSynthetic: resolved.isSynthetic
        )
    }

    private static func controlMetric<Value: Equatable & Sendable>(
        _ value: Value,
        source: PTVehicleTelemetrySource,
        capturedAt: Date,
        freshness: PTVehicleTwinFreshness
    ) -> PTVehicleTwinMetric<Value> {
        PTVehicleTwinMetric(
            value: value,
            source: source,
            capturedAt: capturedAt,
            freshness: freshness,
            isSynthetic: source.isMock
        )
    }

    private static func freshness(
        for resolved: PTVehicleTelemetryResolvedValue,
        connection: PTVehicleSnapshot,
        now: Date
    ) -> PTVehicleTwinFreshness {
        guard sourceIsAvailable(resolved.source, connection: connection) else {
            return resolved.freshness == .missing ? .unavailable : .stale
        }
        return freshness(
            capturedAt: resolved.capturedAt,
            signal: resolved.signal,
            resolvedFreshness: resolved.freshness,
            now: now
        )
    }

    private static func sourceIsAvailable(
        _ source: PTVehicleTelemetrySource,
        connection: PTVehicleSnapshot
    ) -> Bool {
        if source.isDashboardSource {
            return connection.isDashboardConnected
        }
        if source.isOBDSource {
            return connection.isOBDConnected
        }
        return true
    }

    private static func freshness(
        capturedAt: Date,
        signal: PTVehicleTelemetrySignal,
        now: Date
    ) -> PTVehicleTwinFreshness {
        freshness(
            capturedAt: capturedAt,
            signal: signal,
            resolvedFreshness: .fresh,
            now: now
        )
    }

    private static func freshness(
        capturedAt: Date,
        signal: PTVehicleTelemetrySignal,
        resolvedFreshness: PTTelemetryFreshness,
        now: Date
    ) -> PTVehicleTwinFreshness {
        guard resolvedFreshness != .missing,
              capturedAt.timeIntervalSinceReferenceDate.isFinite,
              capturedAt <= now else {
            return .unavailable
        }
        let age = now.timeIntervalSince(capturedAt)
        let maximumAge = PTVehicleTelemetryFreshnessPolicy.maximumAge(for: signal)
        if age <= maximumAge * 0.5 {
            return .fresh
        }
        if age <= maximumAge {
            return .aging
        }
        return .stale
    }

    private static func controlCaptureDate(
        unified: PTUnifiedVehicleTelemetrySnapshot,
        connection: PTVehicleSnapshot,
        now: Date
    ) -> Date {
        let dates = [
            PTVehicleTelemetrySignal.speed,
            .rpm,
            .tcs,
            .lights,
            .leftTurn,
            .rightTurn,
            .hazard
        ].compactMap { unified.value(for: $0)?.capturedAt }
        return dates.max() ?? (connection.dashboard.updatedAt == .distantPast ? now : connection.dashboard.updatedAt)
    }

    private static func mapTCS(_ mode: PTTCSMode) -> PTVehicleTwinTCSState {
        switch mode {
        case .off:
            return .off
        case .mode1:
            return .mode1
        case .mode2:
            return .mode2
        case .unknown:
            return .unknown
        }
    }

    private static func engineState(for rawValue: Int) -> PTVehicleTwinEngineState {
        switch rawValue {
        case 0:
            return .off
        case 1:
            return .starting
        case 2:
            return .running
        case 3:
            return .stopping
        default:
            return .unknown
        }
    }

    private static func overallFreshness(metrics: [PTVehicleTwinFreshness]) -> PTVehicleTwinFreshness {
        guard !metrics.isEmpty else {
            return .unavailable
        }
        if metrics.contains(.fresh) {
            return .fresh
        }
        if metrics.contains(.aging) {
            return .aging
        }
        if metrics.contains(.stale) {
            return .stale
        }
        return .unavailable
    }
}

// EN: The store reuses the existing consumer hub so every screen receives the same snapshot.
// ES: El almacén reutiliza el concentrador existente para que todas las pantallas reciban la misma instantánea.
// 中文：Store 复用现有消费者 Hub，确保所有页面使用同一份快照。
@MainActor
final class PTVehicleTwinStore: PTVehicleTelemetryConsumer {
    private(set) var snapshot: PTVehicleTwinSnapshot = .empty
    private var isRegistered = false
    var onChange: ((PTVehicleTwinSnapshot) -> Void)?

    init() {
        snapshot = PTVehicleTwinStateMapper.makeCurrent()
    }

    func start() {
        guard !isRegistered else { return }
        isRegistered = true
        PTVehicleTelemetryConsumerHub.shared.register(self)
    }

    func stop() {
        guard isRegistered else { return }
        isRegistered = false
        PTVehicleTelemetryConsumerHub.shared.unregister(self)
    }

    // EN: Re-project the latest immutable inputs after a connection or lifecycle transition.
    // ES: Vuelve a proyectar las entradas inmutables más recientes tras un cambio de conexión o ciclo de vida.
    // 中文：连接状态或页面生命周期变化后，重新投影最近的不可变输入。
    func refresh(now: Date = Date()) {
        let next = PTVehicleTwinStateMapper.makeCurrent(now: now)
        guard snapshot != next else { return }
        snapshot = next
        onChange?(next)
    }

    func vehicleTelemetryDidUpdate(_ snapshot: PTUnifiedVehicleTelemetrySnapshot) {
        let coordinator = PTVehicleConnectivityCoordinator.shared
        let next = PTVehicleTwinStateMapper.make(
            unified: snapshot,
            connection: coordinator.snapshot,
            control: coordinator.snapshot.dashboard.state == .connected
                ? PTBluetoothServerManager.shared.latestControl
                : nil
        )
        guard self.snapshot != next else { return }
        self.snapshot = next
        onChange?(next)
    }
}
