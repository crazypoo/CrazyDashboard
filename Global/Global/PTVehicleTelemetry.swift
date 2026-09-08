//
//  PTVehicleTelemetry.swift
//  CrazyDashboard
//
//  EN: Read-only telemetry value types for reliable data fusion outside the transport cores.
//  ES: Tipos de telemetría de solo lectura para fusionar datos fuera de los núcleos de transporte.
//  中文：用于在传输核心之外可靠融合只读遥测数据的值类型。
//

import Foundation

// EN: A source label makes every displayed value auditable and prevents Mock data from looking real.
// ES: La fuente hace auditable cada valor y evita que los datos simulados parezcan reales.
// 中文：来源标签让每个数值都可追溯，并防止 Mock 数据伪装成真实数据。
public enum PTVehicleTelemetrySource: String, Codable, Equatable, Sendable {
    case unknown
    case dashboardBluetooth
    case dashboardMock
    case obdBluetooth
    case obdWiFi
    case obdMock
    case gps

    public var isMock: Bool {
        switch self {
        case .dashboardMock, .obdMock:
            return true
        case .dashboardBluetooth, .obdBluetooth, .obdWiFi, .gps:
            return false
        case .unknown:
            return false
        }
    }

    public var isVerifiedReal: Bool {
        switch self {
        case .dashboardBluetooth, .obdBluetooth, .obdWiFi, .gps:
            return true
        case .unknown, .dashboardMock, .obdMock:
            return false
        }
    }

    // EN: These helpers let lifecycle cleanup preserve a value owned by the other transport.
    // ES: Estos auxiliares permiten que la limpieza del ciclo de vida conserve el valor del otro transporte.
    // 中文：这些辅助属性让生命周期清理保留另一传输来源仍然拥有的数值。
    public var isDashboardSource: Bool {
        switch self {
        case .dashboardBluetooth, .dashboardMock:
            return true
        case .unknown, .obdBluetooth, .obdWiFi, .obdMock, .gps:
            return false
        }
    }

    public var isOBDSource: Bool {
        switch self {
        case .obdBluetooth, .obdWiFi, .obdMock:
            return true
        case .unknown, .dashboardBluetooth, .dashboardMock, .gps:
            return false
        }
    }
}

public enum PTTelemetryFreshness: String, Codable, Equatable, Sendable {
    case fresh
    case stale
    case missing
}

// EN: Samples are immutable so they can safely cross actor and queue boundaries.
// ES: Las muestras son inmutables para cruzar de forma segura actores y colas.
// 中文：采样值不可变，因此可以安全地跨越 actor 和队列边界。
public struct PTTelemetrySample<Value: Sendable>: Sendable {
    public let value: Value
    public let source: PTVehicleTelemetrySource
    public let capturedAt: Date

    public init(value: Value, source: PTVehicleTelemetrySource, capturedAt: Date = Date()) {
        self.value = value
        self.source = source
        self.capturedAt = capturedAt
    }

    public func freshness(at now: Date = Date(), maximumAge: TimeInterval) -> PTTelemetryFreshness {
        guard capturedAt <= now else { return .stale }
        return now.timeIntervalSince(capturedAt) <= maximumAge ? .fresh : .stale
    }

    public func isFresh(at now: Date = Date(), maximumAge: TimeInterval) -> Bool {
        freshness(at: now, maximumAge: maximumAge) == .fresh
    }
}

// EN: This snapshot is a projection, not a second transport cache; the coordinator owns its lifetime.
// ES: Esta instantánea es una proyección, no otra caché de transporte; el coordinador controla su ciclo de vida.
// 中文：该快照只是投影，不是第二套传输缓存；它的生命周期由协调器负责。
public struct PTVehicleTelemetrySnapshot: Sendable {
    public let dashboardSpeedKmh: PTTelemetrySample<Double>?
    public let obdSpeedKmh: PTTelemetrySample<Double>?
    public let frontWheelSpeedKmh: PTTelemetrySample<Double>?
    public let engineRPM: PTTelemetrySample<Int>?
    public let fuelPercent: PTTelemetrySample<Int>?
    public let tripKm: PTTelemetrySample<Double>?
    public let odometerKm: PTTelemetrySample<Double>?
    public let batteryVoltage: PTTelemetrySample<Double>?
    public let engineStatus: PTTelemetrySample<Int>?
    public let kickstandDown: PTTelemetrySample<Bool>?
    public let leftTurnOn: PTTelemetrySample<Bool>?
    public let rightTurnOn: PTTelemetrySample<Bool>?
    public let hazardOn: PTTelemetrySample<Bool>?
    public let absLightOn: PTTelemetrySample<Bool>?
    public let rangeKm: PTTelemetrySample<Double>?
    public let maintenanceDistanceKm: PTTelemetrySample<Int>?
    public let maintenanceFlag: PTTelemetrySample<Int>?
    public let updatedAt: Date

    public init(
        dashboardSpeedKmh: PTTelemetrySample<Double>? = nil,
        obdSpeedKmh: PTTelemetrySample<Double>? = nil,
        frontWheelSpeedKmh: PTTelemetrySample<Double>? = nil,
        engineRPM: PTTelemetrySample<Int>? = nil,
        fuelPercent: PTTelemetrySample<Int>? = nil,
        tripKm: PTTelemetrySample<Double>? = nil,
        odometerKm: PTTelemetrySample<Double>? = nil,
        batteryVoltage: PTTelemetrySample<Double>? = nil,
        engineStatus: PTTelemetrySample<Int>? = nil,
        kickstandDown: PTTelemetrySample<Bool>? = nil,
        leftTurnOn: PTTelemetrySample<Bool>? = nil,
        rightTurnOn: PTTelemetrySample<Bool>? = nil,
        hazardOn: PTTelemetrySample<Bool>? = nil,
        absLightOn: PTTelemetrySample<Bool>? = nil,
        rangeKm: PTTelemetrySample<Double>? = nil,
        maintenanceDistanceKm: PTTelemetrySample<Int>? = nil,
        maintenanceFlag: PTTelemetrySample<Int>? = nil,
        updatedAt: Date = Date()
    ) {
        self.dashboardSpeedKmh = dashboardSpeedKmh
        self.obdSpeedKmh = obdSpeedKmh
        self.frontWheelSpeedKmh = frontWheelSpeedKmh
        self.engineRPM = engineRPM
        self.fuelPercent = fuelPercent
        self.tripKm = tripKm
        self.odometerKm = odometerKm
        self.batteryVoltage = batteryVoltage
        self.engineStatus = engineStatus
        self.kickstandDown = kickstandDown
        self.leftTurnOn = leftTurnOn
        self.rightTurnOn = rightTurnOn
        self.hazardOn = hazardOn
        self.absLightOn = absLightOn
        self.rangeKm = rangeKm
        self.maintenanceDistanceKm = maintenanceDistanceKm
        self.maintenanceFlag = maintenanceFlag
        self.updatedAt = updatedAt
    }

    public static let empty = PTVehicleTelemetrySnapshot(updatedAt: .distantPast)

    public var containsMockData: Bool {
        [
            dashboardSpeedKmh?.source,
            obdSpeedKmh?.source,
            frontWheelSpeedKmh?.source,
            engineRPM?.source,
            fuelPercent?.source,
            tripKm?.source,
            odometerKm?.source,
            batteryVoltage?.source,
            engineStatus?.source,
            kickstandDown?.source,
            leftTurnOn?.source,
            rightTurnOn?.source,
            hazardOn?.source,
            absLightOn?.source,
            rangeKm?.source,
            maintenanceDistanceKm?.source,
            maintenanceFlag?.source
        ].contains(where: { $0?.isMock == true })
    }
}

// EN: This small mutable engine is owned by the MainActor coordinator and has no transport side effects.
// ES: Este pequeño motor mutable pertenece al coordinador MainActor y no tiene efectos de transporte.
// 中文：这个小型可变引擎由 MainActor 协调器持有，不产生任何传输副作用。
public struct PTVehicleTelemetryFusionEngine: Sendable {
    private var current = PTVehicleTelemetrySnapshot.empty

    public init() {}

    public var snapshot: PTVehicleTelemetrySnapshot { current }

    public mutating func updateDashboardSpeed(_ value: Double, source: PTVehicleTelemetrySource, at date: Date = Date()) {
        guard value.isFinite, value >= 0 else { return }
        current = current.replacing(dashboardSpeedKmh: PTTelemetrySample(value: value, source: source, capturedAt: date), updatedAt: date)
    }

    public mutating func updateOBDSpeed(_ value: Double, source: PTVehicleTelemetrySource, at date: Date = Date()) {
        guard value.isFinite, value >= 0 else { return }
        current = current.replacing(obdSpeedKmh: PTTelemetrySample(value: value, source: source, capturedAt: date), updatedAt: date)
    }

    public mutating func updateFrontWheelSpeed(_ value: Double, source: PTVehicleTelemetrySource, at date: Date = Date()) {
        guard value.isFinite, value >= 0 else { return }
        current = current.replacing(frontWheelSpeedKmh: PTTelemetrySample(value: value, source: source, capturedAt: date), updatedAt: date)
    }

    public mutating func updateRPM(_ value: Int, source: PTVehicleTelemetrySource, at date: Date = Date()) {
        guard (0...30_000).contains(value) else { return }
        current = current.replacing(engineRPM: PTTelemetrySample(value: value, source: source, capturedAt: date), updatedAt: date)
    }

    public mutating func updateFuel(_ value: Int, source: PTVehicleTelemetrySource, at date: Date = Date()) {
        guard (0...100).contains(value) else { return }
        current = current.replacing(fuelPercent: PTTelemetrySample(value: value, source: source, capturedAt: date), updatedAt: date)
    }

    public mutating func updateTrip(_ value: Double, source: PTVehicleTelemetrySource, at date: Date = Date()) {
        guard value.isFinite, value >= 0 else { return }
        current = current.replacing(tripKm: PTTelemetrySample(value: value, source: source, capturedAt: date), updatedAt: date)
    }

    public mutating func updateOdometer(_ value: Double, source: PTVehicleTelemetrySource, at date: Date = Date()) {
        guard value.isFinite, value >= 0 else { return }
        current = current.replacing(odometerKm: PTTelemetrySample(value: value, source: source, capturedAt: date), updatedAt: date)
    }

    public mutating func updateBatteryVoltage(_ value: Double, source: PTVehicleTelemetrySource, at date: Date = Date()) {
        guard value.isFinite, (0...20).contains(value) else { return }
        current = current.replacing(batteryVoltage: PTTelemetrySample(value: value, source: source, capturedAt: date), updatedAt: date)
    }

    public mutating func updateEngineStatus(_ value: Int, source: PTVehicleTelemetrySource, at date: Date = Date()) {
        guard (0...3).contains(value) else { return }
        current = current.replacing(engineStatus: PTTelemetrySample(value: value, source: source, capturedAt: date), updatedAt: date)
    }

    public mutating func updateKickstand(_ value: Bool, source: PTVehicleTelemetrySource, at date: Date = Date()) {
        current = current.replacing(kickstandDown: PTTelemetrySample(value: value, source: source, capturedAt: date), updatedAt: date)
    }

    public mutating func updateIndicators(
        left: Bool,
        right: Bool,
        hazard: Bool,
        source: PTVehicleTelemetrySource,
        at date: Date = Date()
    ) {
        current = current.replacing(
            leftTurnOn: PTTelemetrySample(value: left, source: source, capturedAt: date),
            rightTurnOn: PTTelemetrySample(value: right, source: source, capturedAt: date),
            hazardOn: PTTelemetrySample(value: hazard, source: source, capturedAt: date),
            updatedAt: date
        )
    }

    public mutating func updateABS(lightOn: Bool, source: PTVehicleTelemetrySource, at date: Date = Date()) {
        current = current.replacing(absLightOn: PTTelemetrySample(value: lightOn, source: source, capturedAt: date), updatedAt: date)
    }

    public mutating func updateRange(_ value: Double, source: PTVehicleTelemetrySource, at date: Date = Date()) {
        guard value.isFinite, value >= 0 else { return }
        current = current.replacing(rangeKm: PTTelemetrySample(value: value, source: source, capturedAt: date), updatedAt: date)
    }

    public mutating func updateMaintenanceDistance(_ value: Int, source: PTVehicleTelemetrySource, at date: Date = Date()) {
        guard value >= 0 else { return }
        current = current.replacing(maintenanceDistanceKm: PTTelemetrySample(value: value, source: source, capturedAt: date), updatedAt: date)
    }

    public mutating func updateMaintenanceFlag(_ value: Int, source: PTVehicleTelemetrySource, at date: Date = Date()) {
        current = current.replacing(maintenanceFlag: PTTelemetrySample(value: value, source: source, capturedAt: date), updatedAt: date)
    }

    public mutating func clearDashboard() {
        current = current.clearingDashboard(updatedAt: Date())
    }

    public mutating func clearOBD() {
        current = current.clearingOBD(updatedAt: Date())
    }
}

private extension PTVehicleTelemetrySnapshot {
    func replacing(
        dashboardSpeedKmh: PTTelemetrySample<Double>? = nil,
        obdSpeedKmh: PTTelemetrySample<Double>? = nil,
        frontWheelSpeedKmh: PTTelemetrySample<Double>? = nil,
        engineRPM: PTTelemetrySample<Int>? = nil,
        fuelPercent: PTTelemetrySample<Int>? = nil,
        tripKm: PTTelemetrySample<Double>? = nil,
        odometerKm: PTTelemetrySample<Double>? = nil,
        batteryVoltage: PTTelemetrySample<Double>? = nil,
        engineStatus: PTTelemetrySample<Int>? = nil,
        kickstandDown: PTTelemetrySample<Bool>? = nil,
        leftTurnOn: PTTelemetrySample<Bool>? = nil,
        rightTurnOn: PTTelemetrySample<Bool>? = nil,
        hazardOn: PTTelemetrySample<Bool>? = nil,
        absLightOn: PTTelemetrySample<Bool>? = nil,
        rangeKm: PTTelemetrySample<Double>? = nil,
        maintenanceDistanceKm: PTTelemetrySample<Int>? = nil,
        maintenanceFlag: PTTelemetrySample<Int>? = nil,
        updatedAt: Date
    ) -> PTVehicleTelemetrySnapshot {
        PTVehicleTelemetrySnapshot(
            dashboardSpeedKmh: dashboardSpeedKmh ?? self.dashboardSpeedKmh,
            obdSpeedKmh: obdSpeedKmh ?? self.obdSpeedKmh,
            frontWheelSpeedKmh: frontWheelSpeedKmh ?? self.frontWheelSpeedKmh,
            engineRPM: engineRPM ?? self.engineRPM,
            fuelPercent: fuelPercent ?? self.fuelPercent,
            tripKm: tripKm ?? self.tripKm,
            odometerKm: odometerKm ?? self.odometerKm,
            batteryVoltage: batteryVoltage ?? self.batteryVoltage,
            engineStatus: engineStatus ?? self.engineStatus,
            kickstandDown: kickstandDown ?? self.kickstandDown,
            leftTurnOn: leftTurnOn ?? self.leftTurnOn,
            rightTurnOn: rightTurnOn ?? self.rightTurnOn,
            hazardOn: hazardOn ?? self.hazardOn,
            absLightOn: absLightOn ?? self.absLightOn,
            rangeKm: rangeKm ?? self.rangeKm,
            maintenanceDistanceKm: maintenanceDistanceKm ?? self.maintenanceDistanceKm,
            maintenanceFlag: maintenanceFlag ?? self.maintenanceFlag,
            updatedAt: updatedAt
        )
    }

    func clearingDashboard(updatedAt: Date) -> PTVehicleTelemetrySnapshot {
        PTVehicleTelemetrySnapshot(
            dashboardSpeedKmh: nil,
            obdSpeedKmh: obdSpeedKmh,
            frontWheelSpeedKmh: nil,
            engineRPM: engineRPM?.source.isDashboardSource == true ? nil : engineRPM,
            fuelPercent: nil,
            tripKm: nil,
            odometerKm: nil,
            batteryVoltage: nil,
            engineStatus: nil,
            kickstandDown: nil,
            leftTurnOn: nil,
            rightTurnOn: nil,
            hazardOn: nil,
            absLightOn: nil,
            rangeKm: nil,
            maintenanceDistanceKm: nil,
            maintenanceFlag: nil,
            updatedAt: updatedAt
        )
    }

    func clearingOBD(updatedAt: Date) -> PTVehicleTelemetrySnapshot {
        PTVehicleTelemetrySnapshot(
            dashboardSpeedKmh: dashboardSpeedKmh,
            obdSpeedKmh: nil,
            frontWheelSpeedKmh: frontWheelSpeedKmh,
            engineRPM: engineRPM?.source.isOBDSource == true ? nil : engineRPM,
            fuelPercent: fuelPercent,
            tripKm: tripKm,
            odometerKm: odometerKm,
            batteryVoltage: batteryVoltage,
            engineStatus: engineStatus,
            kickstandDown: kickstandDown,
            leftTurnOn: leftTurnOn,
            rightTurnOn: rightTurnOn,
            hazardOn: hazardOn,
            absLightOn: absLightOn,
            rangeKm: rangeKm,
            maintenanceDistanceKm: maintenanceDistanceKm,
            maintenanceFlag: maintenanceFlag,
            updatedAt: updatedAt
        )
    }
}

public enum PTWheelSpeedConsistencyState: String, Codable, Equatable, Sendable {
    case unavailable
    case normal
    case mismatch
}

public struct PTWheelSpeedConsistencyResult: Equatable, Sendable {
    public let state: PTWheelSpeedConsistencyState
    public let absoluteRatio: Double
    public let rearMinusFrontKmh: Double
    public let capturedAt: Date

    public init(
        state: PTWheelSpeedConsistencyState,
        absoluteRatio: Double = 0,
        rearMinusFrontKmh: Double = 0,
        capturedAt: Date = Date()
    ) {
        self.state = state
        self.absoluteRatio = absoluteRatio
        self.rearMinusFrontKmh = rearMinusFrontKmh
        self.capturedAt = capturedAt
    }
}

// EN: The tracker deliberately reports wheel-speed mismatch, never road type or traction intervention.
// ES: El rastreador informa solo de una diferencia de velocidad, nunca del tipo de carretera ni de una intervención de tracción.
// 中文：该跟踪器只报告轮速不一致，绝不推断路面类型或 TCS 介入。
public struct PTWheelSpeedConsistencyTracker: Sendable {
    public private(set) var state: PTWheelSpeedConsistencyState = .unavailable
    private var highCount = 0
    private var clearCount = 0

    public init() {}

    public mutating func update(
        rear: PTTelemetrySample<Double>?,
        front: PTTelemetrySample<Double>?,
        at now: Date = Date()
    ) -> PTWheelSpeedConsistencyResult {
        guard let rear, let front,
              rear.source.isVerifiedReal, front.source.isVerifiedReal,
              rear.value.isFinite, front.value.isFinite,
              rear.value >= 10, front.value >= 10,
              abs(rear.capturedAt.timeIntervalSince(front.capturedAt)) <= 0.3,
              rear.isFresh(at: now, maximumAge: 1),
              front.isFresh(at: now, maximumAge: 1) else {
            state = .unavailable
            highCount = 0
            clearCount = 0
            return PTWheelSpeedConsistencyResult(state: .unavailable, capturedAt: now)
        }

        let denominator = max(max(rear.value, front.value), 1)
        let signedDifference = rear.value - front.value
        let ratio = abs(signedDifference) / denominator

        if ratio >= 0.15 {
            highCount += 1
            clearCount = 0
            if highCount >= 3 { state = .mismatch }
        } else if ratio <= 0.08 {
            clearCount += 1
            highCount = 0
            if clearCount >= 5 { state = .normal }
        } else {
            clearCount = 0
        }

        if state == .unavailable { state = .normal }
        return PTWheelSpeedConsistencyResult(
            state: state,
            absoluteRatio: ratio,
            rearMinusFrontKmh: signedDifference,
            capturedAt: now
        )
    }
}

public enum PTEnginePhase: String, Codable, Equatable, Sendable {
    case resting
    case cranking
    case running
    case stopping
    case unavailable
}

public struct PTBatteryObservation: Codable, Equatable, Sendable {
    public let voltage: Double
    public let engineStatus: Int
    public let source: PTVehicleTelemetrySource
    public let capturedAt: Date

    public init(
        voltage: Double,
        engineStatus: Int,
        source: PTVehicleTelemetrySource,
        capturedAt: Date = Date()
    ) {
        self.voltage = voltage
        self.engineStatus = engineStatus
        self.source = source
        self.capturedAt = capturedAt
    }

    public var phase: PTEnginePhase {
        switch engineStatus {
        case 0: return .resting
        case 1: return .cranking
        case 2: return .running
        case 3: return .stopping
        default: return .unavailable
        }
    }
}

public struct PTBatteryHealthSummary: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let restingMedianVoltage: Double?
    public let crankingMinimumVoltage: Double?
    public let runningMedianVoltage: Double?
    public let confidence: Double
    public let observationCount: Int

    public init(
        capturedAt: Date = Date(),
        restingMedianVoltage: Double? = nil,
        crankingMinimumVoltage: Double? = nil,
        runningMedianVoltage: Double? = nil,
        confidence: Double = 0,
        observationCount: Int = 0
    ) {
        self.capturedAt = capturedAt
        self.restingMedianVoltage = restingMedianVoltage
        self.crankingMinimumVoltage = crankingMinimumVoltage
        self.runningMedianVoltage = runningMedianVoltage
        self.confidence = min(max(confidence, 0), 1)
        self.observationCount = max(0, observationCount)
    }
}

// EN: Battery analysis is advisory; it exposes measured medians instead of pretending to diagnose a battery brand.
// ES: El análisis de batería es orientativo; muestra medianas medidas y no pretende diagnosticar una marca concreta.
// 中文：电瓶分析仅作参考，展示实测中位数，不冒充对具体电瓶品牌的诊断。
public enum PTBatteryHealthAnalyzer {
    public static func summarize(
        observations: [PTBatteryObservation],
        capturedAt: Date = Date()
    ) -> PTBatteryHealthSummary {
        let valid = observations.filter {
            $0.source.isVerifiedReal && $0.voltage.isFinite && (6...20).contains($0.voltage)
        }
        let resting = valid.filter { $0.phase == .resting }.map(\.voltage)
        let cranking = valid.filter { $0.phase == .cranking }.map(\.voltage)
        let running = valid.filter { $0.phase == .running }.map(\.voltage)
        let phaseCount = [resting, cranking, running].filter { !$0.isEmpty }.count
        let confidence = min(1, Double(valid.count) / 12) * (phaseCount == 3 ? 1 : 0.7)

        return PTBatteryHealthSummary(
            capturedAt: capturedAt,
            restingMedianVoltage: median(resting),
            crankingMinimumVoltage: cranking.min(),
            runningMedianVoltage: median(running),
            confidence: confidence,
            observationCount: valid.count
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

// EN: These records are intentionally raw-value based so they do not depend on the protected BLE file's internal enums.
// ES: Estos registros usan valores crudos y no dependen de los enums internos del archivo BLE protegido.
// 中文：这些记录使用原始值，避免依赖受保护 BLE 文件中的内部枚举。
public struct PTDashboardConfigurationProfile: Codable, Equatable, Sendable {
    public let colorRawValue: UInt8
    public let unitRawValue: UInt8
    public let languageRawValue: UInt8
    public let updatedAt: Date

    public init(
        colorRawValue: UInt8,
        unitRawValue: UInt8,
        languageRawValue: UInt8,
        updatedAt: Date = Date()
    ) {
        self.colorRawValue = colorRawValue
        self.unitRawValue = unitRawValue
        self.languageRawValue = languageRawValue
        self.updatedAt = updatedAt
    }
}

// EN: Persist the last requested dashboard profile per motorcycle without coupling it to BLE transport state.
// ES: Guarda el último perfil solicitado por motocicleta sin acoplarlo al estado del transporte BLE.
// 中文：按摩托车保存最后一次请求的仪表配置，不与 BLE 传输状态耦合。
public final class PTDashboardConfigurationProfileStore: @unchecked Sendable {
    public static let shared = PTDashboardConfigurationProfileStore()

    private let defaults: UserDefaults
    private let keyPrefix = "PTDashboardConfigurationProfile."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func profile(for vehicleID: UUID?) -> PTDashboardConfigurationProfile? {
        guard let vehicleID,
              let data = defaults.data(forKey: keyPrefix + vehicleID.uuidString) else {
            return nil
        }
        return try? JSONDecoder().decode(PTDashboardConfigurationProfile.self, from: data)
    }

    public func save(_ profile: PTDashboardConfigurationProfile, for vehicleID: UUID?) {
        guard let vehicleID,
              let data = try? JSONEncoder().encode(profile) else {
            return
        }
        defaults.set(data, forKey: keyPrefix + vehicleID.uuidString)
    }
}

public struct PTMountCalibration: Codable, Equatable, Sendable {
    public let rollOffset: Double
    public let pitchOffset: Double
    public let yawOffset: Double
    public let updatedAt: Date

    public init(
        rollOffset: Double = 0,
        pitchOffset: Double = 0,
        yawOffset: Double = 0,
        updatedAt: Date = Date()
    ) {
        self.rollOffset = rollOffset
        self.pitchOffset = pitchOffset
        self.yawOffset = yawOffset
        self.updatedAt = updatedAt
    }
}
