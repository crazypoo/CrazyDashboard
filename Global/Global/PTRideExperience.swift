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
}

public struct PTRideRangeEstimate: Codable, Equatable, Sendable {
    public let remainingKm: Double
    public let source: PTRideRangeSource
    public let isLowFuel: Bool

    public init(remainingKm: Double, source: PTRideRangeSource, isLowFuel: Bool) {
        self.remainingKm = max(remainingKm, 0)
        self.source = source
        self.isLowFuel = isLowFuel
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
        lowFuelPercent: Int = 15
    ) -> PTRideRangeEstimate? {
        let safeFuelPercent = fuelLevelPercent.map { min(max($0, 0), 100) }
        let isLowFuel = (safeFuelPercent ?? 100) <= min(max(lowFuelPercent, 0), 100)

        if let dashboardAutonomyKm,
           dashboardAutonomyKm.isFinite,
           dashboardAutonomyKm >= 0 {
            return PTRideRangeEstimate(
                remainingKm: dashboardAutonomyKm,
                source: .dashboard,
                isLowFuel: isLowFuel
            )
        }

        guard let safeFuelPercent,
              let averageConsumptionLitersPer100Km,
              let tankCapacityLiters,
              averageConsumptionLitersPer100Km.isFinite,
              tankCapacityLiters.isFinite,
              averageConsumptionLitersPer100Km > 0,
              tankCapacityLiters > 0 else {
            return nil
        }

        let safeReservePercent = min(max(reservePercent, 0), 100)
        let usableFuelPercent = max(safeFuelPercent - safeReservePercent, 0)
        let usableFuelLiters = tankCapacityLiters * Double(usableFuelPercent) / 100
        let remainingKm = usableFuelLiters / averageConsumptionLitersPer100Km * 100
        guard remainingKm.isFinite else { return nil }

        return PTRideRangeEstimate(
            remainingKm: remainingKm,
            source: .estimated,
            isLowFuel: isLowFuel
        )
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
        if rawMaintenanceFlag.map({ $0 != 0 }) == true {
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
    public let parkedLatitude: Double
    public let parkedLongitude: Double
    public let parkedAddress: String
    public let pttPeerCount: Int
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
        parkedLatitude: Double,
        parkedLongitude: Double,
        parkedAddress: String,
        pttPeerCount: Int,
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
        self.parkedLatitude = parkedLatitude
        self.parkedLongitude = parkedLongitude
        self.parkedAddress = parkedAddress
        self.pttPeerCount = max(pttPeerCount, 0)
        self.updatedAt = updatedAt
    }

    public var rangeEstimate: PTRideRangeEstimate? {
        PTRideRangeEstimator.estimate(
            dashboardAutonomyKm: dashboardAutonomyKm,
            fuelLevelPercent: fuelLevelPercent,
            averageConsumptionLitersPer100Km: averageConsumptionLitersPer100Km
        )
    }

    public var maintenanceAdvice: PTRideMaintenanceAdvice {
        PTRideMaintenanceAdvisor.advise(
            distanceToMaintenanceKm: maintenanceDistanceKm,
            rawMaintenanceFlag: maintenanceFlag
        )
    }
}
