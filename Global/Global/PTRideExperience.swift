//
//  PTRideExperience.swift
//  CrazyDashboard
//
//  EN: Small, deterministic ride-experience calculations shared by the read-only cockpit.
//  ES: Cálculos pequeños y deterministas de la experiencia de conducción compartidos por el cockpit de solo lectura.
//  中文：为只读骑行座舱提供小而确定的计算能力。
//

import Foundation

public enum PTRideRangeSource: String, Codable, Sendable {
    case dashboard
    case estimated
    case liveConsumption
    case rideHistory
}

public struct PTRideRangeEstimate: Codable, Equatable, Sendable {
    public let remainingKm: Double
    public let source: PTRideRangeSource
    public let isLowFuel: Bool
    public let confidence: Double?
    public let sampleCount: Int

    public init(
        remainingKm: Double,
        source: PTRideRangeSource,
        isLowFuel: Bool,
        confidence: Double? = nil,
        sampleCount: Int = 0
    ) {
        self.remainingKm = max(remainingKm, 0)
        self.source = source
        self.isLowFuel = isLowFuel
        self.confidence = confidence.map { min(max($0, 0), 1) }
        self.sampleCount = max(sampleCount, 0)
    }

    private enum CodingKeys: String, CodingKey {
        case remainingKm, source, isLowFuel, confidence, sampleCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            remainingKm: try container.decode(Double.self, forKey: .remainingKm),
            source: try container.decode(PTRideRangeSource.self, forKey: .source),
            isLowFuel: try container.decode(Bool.self, forKey: .isLowFuel),
            confidence: try container.decodeIfPresent(Double.self, forKey: .confidence),
            sampleCount: try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 0
        )
    }
}

public enum PTRideRangeEstimator {
    /// EN: Prefer the dashboard's own range and calculate only when a tank profile is explicitly available.
    /// ES: Prefiere la autonomía del tablero y calcula solo cuando existe un perfil de depósito explícito.
    /// 中文：优先使用仪表原生续航，只有在明确配置油箱参数时才自行估算。
    public static func estimate(
        dashboardAutonomyKm: Double?,
        fuelLevelPercent: Int?,
        averageConsumptionLitersPer100Km: Double?,
        tankCapacityLiters: Double? = nil,
        reservePercent: Int = 10,
        lowFuelPercent: Int = 15,
        estimatedSource: PTRideRangeSource = .estimated,
        sampleCount: Int = 0,
        confidence: Double? = nil
    ) -> PTRideRangeEstimate? {
        let safeFuelPercent = fuelLevelPercent.map { min(max($0, 0), 100) }
        let isLowFuel = (safeFuelPercent ?? 100) <= min(max(lowFuelPercent, 0), 100)

        if let dashboardAutonomyKm,
           dashboardAutonomyKm.isFinite,
           dashboardAutonomyKm >= 0 {
            return PTRideRangeEstimate(
                remainingKm: dashboardAutonomyKm,
                source: .dashboard,
                isLowFuel: isLowFuel,
                confidence: 1,
                sampleCount: 1
            )
        }

        guard let safeFuelPercent,
              let averageConsumptionLitersPer100Km,
              let tankCapacityLiters,
              averageConsumptionLitersPer100Km.isFinite,
              tankCapacityLiters.isFinite,
              (1...15).contains(averageConsumptionLitersPer100Km),
              (1...50).contains(tankCapacityLiters) else {
            return nil
        }

        let safeReservePercent = min(max(reservePercent, 0), 100)
        let usableFuelPercent = max(safeFuelPercent - safeReservePercent, 0)
        let usableFuelLiters = tankCapacityLiters * Double(usableFuelPercent) / 100
        let remainingKm = usableFuelLiters / averageConsumptionLitersPer100Km * 100
        guard remainingKm.isFinite else { return nil }

        return PTRideRangeEstimate(
            remainingKm: remainingKm,
            source: estimatedSource == .dashboard ? .estimated : estimatedSource,
            isLowFuel: isLowFuel,
            confidence: confidence,
            sampleCount: sampleCount
        )
    }

    // EN: History uses only plausible, completed trips and weights consumption by distance.
    // ES: El historial solo usa viajes completados plausibles y pondera el consumo por distancia.
    // 中文：历史估算只使用合理的已完成行程，并按距离对油耗加权。
    public static func weightedConsumption(
        from trips: [PTTripReport],
        maximumTripCount: Int = 10
    ) -> (litersPer100Km: Double, sampleCount: Int, confidence: Double)? {
        guard maximumTripCount > 0 else { return nil }
        let candidates = trips
            .filter {
                $0.distanceKm >= 5 &&
                    $0.distanceKm.isFinite &&
                    $0.avgConsumption.isFinite &&
                    (1...15).contains($0.avgConsumption)
            }
            .prefix(maximumTripCount)
        guard !candidates.isEmpty else { return nil }
        let totalDistance = candidates.reduce(0) { $0 + $1.distanceKm }
        guard totalDistance > 0 else { return nil }
        let weighted = candidates.reduce(0) { $0 + $1.avgConsumption * $1.distanceKm } / totalDistance
        let confidence = min(1, Double(candidates.count) / 10)
        return (weighted, candidates.count, confidence)
    }
}

public enum PTRideMaintenanceState: String, Codable, Sendable {
    case unknown
    case normal
    case dueSoon
    case required
}

public struct PTRideMaintenanceAdvice: Codable, Equatable, Sendable {
    public let state: PTRideMaintenanceState
    public let distanceToMaintenanceKm: Int?

    public init(state: PTRideMaintenanceState, distanceToMaintenanceKm: Int?) {
        self.state = state
        self.distanceToMaintenanceKm = distanceToMaintenanceKm
    }
}

public enum PTRideMaintenanceAdvisor {
    /// EN: Convert raw dashboard maintenance fields into a safe, read-only recommendation.
    /// ES: Convierte los campos de mantenimiento del tablero en una recomendación segura y de solo lectura.
    /// 中文：把仪表原始保养字段转换为安全的只读建议。
    public static func advise(
        distanceToMaintenanceKm: Int?,
        rawMaintenanceFlag: Int?,
        warningThresholdKm: Int = 500
    ) -> PTRideMaintenanceAdvice {
        // EN: Only the dashboard's maintenance bits count; unrelated low bits must not create a false alarm.
        // ES: Solo cuentan los bits de mantenimiento del tablero; los bits bajos ajenos no deben crear una falsa alarma.
        // 中文：只有仪表保养位才算需要保养，其他低位不能制造误报。
        if rawMaintenanceFlag.map({ ($0 & 0xE0) != 0 }) == true {
            return PTRideMaintenanceAdvice(
                state: .required,
                distanceToMaintenanceKm: distanceToMaintenanceKm
            )
        }

        if let distanceToMaintenanceKm,
           distanceToMaintenanceKm > 0,
           distanceToMaintenanceKm <= max(warningThresholdKm, 0) {
            return PTRideMaintenanceAdvice(
                state: .dueSoon,
                distanceToMaintenanceKm: distanceToMaintenanceKm
            )
        }

        if distanceToMaintenanceKm.map({ $0 > 0 }) == true {
            return PTRideMaintenanceAdvice(
                state: .normal,
                distanceToMaintenanceKm: distanceToMaintenanceKm
            )
        }

        return PTRideMaintenanceAdvice(
            state: .unknown,
            distanceToMaintenanceKm: distanceToMaintenanceKm
        )
    }
}

public struct PTRideExperienceSummary: Codable, Equatable, Sendable {
    public let vehicle: PTVehicleSnapshot
    public let fuelLevelPercent: Int?
    public let tripKm: Double?
    public let odometerKm: Double?
    public let averageConsumptionLitersPer100Km: Double?
    public let dashboardAutonomyKm: Double?
    public let batteryVoltage: Double?
    public let outsideTemperatureCelsius: Int?
    public let maintenanceDistanceKm: Int?
    public let maintenanceFlag: Int?
    public let maintenanceWarningDistanceKm: Int
    public let parkedLatitude: Double
    public let parkedLongitude: Double
    public let parkedAddress: String
    public let pttPeerCount: Int
    public let tankCapacityLiters: Double?
    public let reserveFuelPercent: Int?
    public let rangeConsumptionSource: PTRideRangeSource?
    public let updatedAt: Date

    public init(
        vehicle: PTVehicleSnapshot,
        fuelLevelPercent: Int?,
        tripKm: Double?,
        odometerKm: Double?,
        averageConsumptionLitersPer100Km: Double?,
        dashboardAutonomyKm: Double?,
        batteryVoltage: Double?,
        outsideTemperatureCelsius: Int?,
        maintenanceDistanceKm: Int?,
        maintenanceFlag: Int?,
        maintenanceWarningDistanceKm: Int = 2_500,
        parkedLatitude: Double,
        parkedLongitude: Double,
        parkedAddress: String,
        pttPeerCount: Int,
        tankCapacityLiters: Double? = nil,
        reserveFuelPercent: Int? = nil,
        rangeConsumptionSource: PTRideRangeSource? = nil,
        updatedAt: Date = Date()
    ) {
        self.vehicle = vehicle
        self.fuelLevelPercent = fuelLevelPercent
        self.tripKm = tripKm
        self.odometerKm = odometerKm
        self.averageConsumptionLitersPer100Km = averageConsumptionLitersPer100Km
        self.dashboardAutonomyKm = dashboardAutonomyKm
        self.batteryVoltage = batteryVoltage
        self.outsideTemperatureCelsius = outsideTemperatureCelsius
        self.maintenanceDistanceKm = maintenanceDistanceKm
        self.maintenanceFlag = maintenanceFlag
        self.maintenanceWarningDistanceKm = max(maintenanceWarningDistanceKm, 0)
        self.parkedLatitude = parkedLatitude
        self.parkedLongitude = parkedLongitude
        self.parkedAddress = parkedAddress
        self.pttPeerCount = max(pttPeerCount, 0)
        self.tankCapacityLiters = tankCapacityLiters
        self.reserveFuelPercent = reserveFuelPercent
        self.rangeConsumptionSource = rangeConsumptionSource
        self.updatedAt = updatedAt
    }

    public var rangeEstimate: PTRideRangeEstimate? {
        PTRideRangeEstimator.estimate(
            dashboardAutonomyKm: dashboardAutonomyKm,
            fuelLevelPercent: fuelLevelPercent,
            averageConsumptionLitersPer100Km: averageConsumptionLitersPer100Km,
            tankCapacityLiters: tankCapacityLiters,
            reservePercent: reserveFuelPercent ?? 10,
            estimatedSource: rangeConsumptionSource ?? .liveConsumption,
            sampleCount: rangeConsumptionSource == .rideHistory ? 10 : 1,
            confidence: rangeConsumptionSource == .rideHistory ? 0.6 : 0.8
        )
    }

    public var maintenanceAdvice: PTRideMaintenanceAdvice {
        PTRideMaintenanceAdvisor.advise(
            distanceToMaintenanceKm: maintenanceDistanceKm,
            rawMaintenanceFlag: maintenanceFlag,
            warningThresholdKm: maintenanceWarningDistanceKm
        )
    }
}

// EN: Readiness is a conservative summary of cached app data, never a mechanical safety guarantee.
// ES: La preparación es un resumen conservador de datos almacenados y nunca una garantía de seguridad mecánica.
// 中文：准备度只是缓存数据的保守摘要，绝不等同于机械安全保证。
public enum PTRideReadinessState: String, Codable, Equatable, Sendable {
    case ready
    case attention
    case unavailable
}

public enum PTRideReadinessIssue: String, Codable, Equatable, Sendable, CaseIterable {
    case dashboardDisconnected
    case obdDisconnected
    case lowFuel
    case rangeUnavailable
    case maintenanceRequired
    case batteryLow
    case staleData
    case pttLocationSharingDisabled
}

public struct PTRideReadinessReport: Codable, Equatable, Sendable {
    public let state: PTRideReadinessState
    public let vehicleName: String
    public let issues: [PTRideReadinessIssue]
    public let checkedAt: Date

    public init(
        state: PTRideReadinessState,
        vehicleName: String,
        issues: [PTRideReadinessIssue],
        checkedAt: Date = Date()
    ) {
        self.state = state
        self.vehicleName = vehicleName
        // EN: Keep issue order stable while removing duplicates without Foundation collection bridging.
        // ES: Mantiene estable el orden de los problemas y elimina duplicados sin puentes de colecciones de Foundation.
        // 中文：保持问题顺序稳定，并在不依赖 Foundation 集合桥接的情况下去重。
        var uniqueIssues: [PTRideReadinessIssue] = []
        for issue in issues where !uniqueIssues.contains(issue) {
            uniqueIssues.append(issue)
        }
        self.issues = uniqueIssues
        self.checkedAt = checkedAt
    }

    public var isActionable: Bool {
        state != .ready || !issues.isEmpty
    }
}

// EN: Keep the evaluator pure so UI, Watch and tests use exactly the same thresholds.
// ES: Mantiene el evaluador puro para que la UI, el Watch y las pruebas usen los mismos umbrales.
// 中文：保持评估器纯函数化，让 UI、Watch 和测试使用完全相同的阈值。
public enum PTRideReadinessEvaluator {
    public static func evaluate(
        vehicleName: String,
        vehicle: PTVehicleSnapshot,
        fuelLevelPercent: Int?,
        rangeEstimate: PTRideRangeEstimate?,
        batteryVoltage: Double?,
        maintenanceAdvice: PTRideMaintenanceAdvice,
        pttPeerCount: Int,
        pttLocationSharingEnabled: Bool,
        dataUpdatedAt: Date,
        now: Date = Date()
    ) -> PTRideReadinessReport {
        var issues: [PTRideReadinessIssue] = []
        if !vehicle.isDashboardConnected {
            issues.append(.dashboardDisconnected)
        }
        if !vehicle.isOBDConnected {
            issues.append(.obdDisconnected)
        }
        if let fuelLevelPercent, fuelLevelPercent <= 15 {
            issues.append(.lowFuel)
        }
        if fuelLevelPercent != nil, rangeEstimate == nil {
            issues.append(.rangeUnavailable)
        }
        if maintenanceAdvice.state == .required || maintenanceAdvice.state == .dueSoon {
            issues.append(.maintenanceRequired)
        }
        if let batteryVoltage, batteryVoltage.isFinite, batteryVoltage < 12.0 {
            issues.append(.batteryLow)
        }
        let dataAge = now.timeIntervalSince(dataUpdatedAt)
        if dataUpdatedAt == .distantPast || dataAge > 900 || dataAge < -30 {
            issues.append(.staleData)
        }
        if pttPeerCount > 0 && !pttLocationSharingEnabled {
            issues.append(.pttLocationSharingDisabled)
        }

        let hasVehicleLink = vehicle.isDashboardConnected || vehicle.isOBDConnected
        let state: PTRideReadinessState
        if !hasVehicleLink || (issues.contains(.staleData) && !hasVehicleLink) {
            state = .unavailable
        } else if issues.isEmpty {
            state = .ready
        } else {
            state = .attention
        }

        return PTRideReadinessReport(
            state: state,
            vehicleName: vehicleName,
            issues: issues,
            checkedAt: now
        )
    }
}
