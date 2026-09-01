//
//  PTRouteWeatherRisk.swift
//  CrazyDashboard
//
//  EN: Read-only route weather risk analysis built on WeatherKit.
//  ES: Análisis de riesgo meteorológico de rutas de solo lectura basado en WeatherKit.
//  中文：基于 WeatherKit 的只读路线天气风险分析。
//

import CoreLocation
import Foundation
import WeatherKit

// EN: The risk level is intentionally small so the route UI can explain it quickly.
// ES: El nivel de riesgo es deliberadamente pequeño para que la interfaz lo explique rápidamente.
// 中文：风险等级保持简单，便于路线界面快速解释。
public enum PTRouteWeatherRiskLevel: String, Codable, Comparable, Sendable {
    case clear
    case caution
    case hazardous

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    public var rank: Int {
        switch self {
        case .clear: return 0
        case .caution: return 1
        case .hazardous: return 2
        }
    }
}

public enum PTRouteWeatherRiskFactor: String, Codable, CaseIterable, Sendable {
    case precipitation
    case wind
    case cold
    case heat
    case lowVisibility
    case storm
}

// EN: Thresholds are explicit and testable instead of being hidden in a view controller.
// ES: Los umbrales son explícitos y comprobables, no están ocultos en un controlador de vista.
// 中文：阈值明确可测试，不把业务规则隐藏在视图控制器中。
public struct PTRouteWeatherRiskPolicy: Codable, Equatable, Sendable {
    public let cautionPrecipitationProbability: Double
    public let hazardousPrecipitationProbability: Double
    public let cautionWindKmh: Double
    public let hazardousWindKmh: Double
    public let cautionColdCelsius: Double
    public let hazardousColdCelsius: Double
    public let cautionHeatCelsius: Double
    public let hazardousHeatCelsius: Double
    public let cautionVisibilityKm: Double
    public let hazardousVisibilityKm: Double

    public init(
        cautionPrecipitationProbability: Double = 0.45,
        hazardousPrecipitationProbability: Double = 0.75,
        cautionWindKmh: Double = 45,
        hazardousWindKmh: Double = 60,
        cautionColdCelsius: Double = 5,
        hazardousColdCelsius: Double = 0,
        cautionHeatCelsius: Double = 32,
        hazardousHeatCelsius: Double = 38,
        cautionVisibilityKm: Double = 5,
        hazardousVisibilityKm: Double = 2
    ) {
        self.cautionPrecipitationProbability = cautionPrecipitationProbability
        self.hazardousPrecipitationProbability = hazardousPrecipitationProbability
        self.cautionWindKmh = cautionWindKmh
        self.hazardousWindKmh = hazardousWindKmh
        self.cautionColdCelsius = cautionColdCelsius
        self.hazardousColdCelsius = hazardousColdCelsius
        self.cautionHeatCelsius = cautionHeatCelsius
        self.hazardousHeatCelsius = hazardousHeatCelsius
        self.cautionVisibilityKm = cautionVisibilityKm
        self.hazardousVisibilityKm = hazardousVisibilityKm
    }

    nonisolated public static let `default` = PTRouteWeatherRiskPolicy()
}

public struct PTRouteWeatherSample: Codable, Equatable, Sendable {
    public let coordinate: PTRideCoordinate
    public let forecastDate: Date
    public let condition: String
    public let temperatureCelsius: Double
    public let precipitationProbability: Double
    public let windKmh: Double
    public let visibilityKm: Double?

    public init(
        coordinate: PTRideCoordinate,
        forecastDate: Date,
        condition: String,
        temperatureCelsius: Double,
        precipitationProbability: Double,
        windKmh: Double,
        visibilityKm: Double?
    ) {
        self.coordinate = coordinate
        self.forecastDate = forecastDate
        self.condition = condition
        self.temperatureCelsius = temperatureCelsius
        self.precipitationProbability = min(max(precipitationProbability, 0), 1)
        self.windKmh = max(windKmh.isFinite ? windKmh : 0, 0)
        self.visibilityKm = visibilityKm?.isFinite == true ? max(visibilityKm ?? 0, 0) : nil
    }
}

public struct PTRouteWeatherRiskPoint: Codable, Equatable, Sendable {
    public let sample: PTRouteWeatherSample
    public let level: PTRouteWeatherRiskLevel
    public let factors: [PTRouteWeatherRiskFactor]

    public init(
        sample: PTRouteWeatherSample,
        level: PTRouteWeatherRiskLevel,
        factors: [PTRouteWeatherRiskFactor]
    ) {
        self.sample = sample
        self.level = level
        self.factors = factors
    }
}

public struct PTRouteWeatherRiskReport: Codable, Equatable, Sendable {
    public let createdAt: Date
    public let startDate: Date
    public let points: [PTRouteWeatherRiskPoint]

    public init(createdAt: Date = Date(), startDate: Date, points: [PTRouteWeatherRiskPoint]) {
        self.createdAt = createdAt
        self.startDate = startDate
        self.points = points
    }

    public var worstLevel: PTRouteWeatherRiskLevel {
        points.map(\.level).max() ?? .clear
    }

    public var riskyPointCount: Int {
        points.count(where: { $0.level != .clear })
    }
}

public enum PTRouteWeatherRiskError: Error, Equatable, LocalizedError, Sendable {
    case invalidRoute
    case noForecast
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidRoute:
            return "The route does not contain valid coordinates."
        case .noForecast:
            return "WeatherKit returned no hourly forecast for the route."
        case .cancelled:
            return "The route weather analysis was cancelled."
        }
    }
}

// EN: Pure risk calculation keeps weather policy deterministic and independent from networking.
// ES: El cálculo puro mantiene la política meteorológica determinista e independiente de la red.
// 中文：纯风险计算让天气规则确定且不依赖网络。
public enum PTRouteWeatherRiskAnalyzer {
    public static func analyze(
        sample: PTRouteWeatherSample,
        policy: PTRouteWeatherRiskPolicy = .default
    ) -> PTRouteWeatherRiskPoint {
        let condition = sample.condition.lowercased()
        var factors: [PTRouteWeatherRiskFactor] = []
        var level: PTRouteWeatherRiskLevel = .clear

        func register(_ factor: PTRouteWeatherRiskFactor, _ candidate: PTRouteWeatherRiskLevel) {
            if !factors.contains(factor) {
                factors.append(factor)
            }
            level = max(level, candidate)
        }

        if sample.precipitationProbability >= policy.cautionPrecipitationProbability ||
            condition.contains("rain") || condition.contains("snow") || condition.contains("sleet") {
            let precipitationLevel = sample.precipitationProbability >= policy.hazardousPrecipitationProbability
                ? PTRouteWeatherRiskLevel.hazardous
                : .caution
            register(.precipitation, precipitationLevel)
        }

        if sample.windKmh >= policy.cautionWindKmh {
            register(.wind, sample.windKmh >= policy.hazardousWindKmh ? .hazardous : .caution)
        }

        if sample.temperatureCelsius <= policy.cautionColdCelsius {
            register(.cold, sample.temperatureCelsius <= policy.hazardousColdCelsius ? .hazardous : .caution)
        } else if sample.temperatureCelsius >= policy.cautionHeatCelsius {
            register(.heat, sample.temperatureCelsius >= policy.hazardousHeatCelsius ? .hazardous : .caution)
        }

        if let visibilityKm = sample.visibilityKm,
           visibilityKm <= policy.cautionVisibilityKm {
            register(.lowVisibility, visibilityKm <= policy.hazardousVisibilityKm ? .hazardous : .caution)
        }

        if condition.contains("thunder") || condition.contains("storm") ||
            condition.contains("tornado") || condition.contains("hurricane") {
            register(.storm, .hazardous)
        }

        return PTRouteWeatherRiskPoint(sample: sample, level: level, factors: factors)
    }

    public static func analyze(
        samples: [PTRouteWeatherSample],
        policy: PTRouteWeatherRiskPolicy = .default
    ) -> [PTRouteWeatherRiskPoint] {
        samples.map { analyze(sample: $0, policy: policy) }
    }
}

// EN: WeatherKit access is isolated here so roadbook UI never owns forecast requests.
// ES: El acceso a WeatherKit se aísla aquí para que la interfaz Roadbook no gestione solicitudes.
// 中文：WeatherKit 访问集中在此处，路线界面不直接管理天气请求。
@MainActor
public final class PTRouteWeatherRiskService {
    public static let shared = PTRouteWeatherRiskService()

    private let weatherService = WeatherService.shared
    private let maximumRouteSamples = 12
    private let defaultSpeedMetersPerSecond = 40.0 / 3.6

    private init() {}

    public func analyze(
        roadbook: PTRoadbook,
        startDate: Date = Date(),
        estimatedDuration: TimeInterval? = nil,
        policy: PTRouteWeatherRiskPolicy = .default,
        progress: (@MainActor @Sendable (Int, Int, PTRouteWeatherRiskPoint) -> Void)? = nil
    ) async throws -> PTRouteWeatherRiskReport {
        try await analyze(
            coordinates: roadbook.waypoints.map(\.coordinate),
            startDate: startDate,
            estimatedDuration: estimatedDuration,
            policy: policy,
            progress: progress
        )
    }

    public func analyze(
        coordinates: [CLLocationCoordinate2D],
        startDate: Date = Date(),
        estimatedDuration: TimeInterval? = nil,
        policy: PTRouteWeatherRiskPolicy = .default,
        progress: (@MainActor @Sendable (Int, Int, PTRouteWeatherRiskPoint) -> Void)? = nil
    ) async throws -> PTRouteWeatherRiskReport {
        guard !coordinates.isEmpty, coordinates.allSatisfy(Self.isValidCoordinate) else {
            throw PTRouteWeatherRiskError.invalidRoute
        }

        let samplesCoordinates = sampledCoordinates(from: coordinates)
        let routeDistance = Self.routeDistance(coordinates)
        let duration = estimatedDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            ?? max(routeDistance / defaultSpeedMetersPerSecond, 60)
        let denominator = max(samplesCoordinates.count - 1, 1)
        var points: [PTRouteWeatherRiskPoint] = []
        points.reserveCapacity(samplesCoordinates.count)

        do {
            for (index, coordinate) in samplesCoordinates.enumerated() {
                try Task.checkCancellation()

                let fraction = Double(index) / Double(denominator)
                let forecastDate = startDate.addingTimeInterval(duration * fraction)
                let sample = try await fetchSample(at: coordinate, date: forecastDate)
                let point = PTRouteWeatherRiskAnalyzer.analyze(sample: sample, policy: policy)
                points.append(point)
                progress?(index + 1, samplesCoordinates.count, point)
            }
        } catch is CancellationError {
            throw PTRouteWeatherRiskError.cancelled
        }

        return PTRouteWeatherRiskReport(startDate: startDate, points: points)
    }
}

private extension PTRouteWeatherRiskService {
    func sampledCoordinates(from coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard coordinates.count > maximumRouteSamples else { return coordinates }
        let sampleCount = maximumRouteSamples
        return (0..<sampleCount).map { index in
            let ratio = Double(index) / Double(sampleCount - 1)
            let sourceIndex = Int((ratio * Double(coordinates.count - 1)).rounded())
            return coordinates[sourceIndex]
        }
    }

    func fetchSample(
        at coordinate: CLLocationCoordinate2D,
        date: Date
    ) async throws -> PTRouteWeatherSample {
        let weather = try await weatherService.weather(
            for: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
        guard let hour = weather.hourlyForecast.forecast.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) else {
            throw PTRouteWeatherRiskError.noForecast
        }

        let visibility = hour.visibility.converted(to: .kilometers).value
        return PTRouteWeatherSample(
            coordinate: PTRideCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ),
            forecastDate: hour.date,
            condition: String(describing: hour.condition),
            temperatureCelsius: hour.temperature.converted(to: .celsius).value,
            precipitationProbability: hour.precipitationChance,
            windKmh: hour.wind.speed.converted(to: .kilometersPerHour).value,
            visibilityKm: visibility.isFinite ? visibility : nil
        )
    }

    static func routeDistance(_ coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
        zip(coordinates, coordinates.dropFirst()).reduce(0) { distance, pair in
            distance + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }
    }

    static func isValidCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude.isFinite && coordinate.longitude.isFinite &&
            (-90...90).contains(coordinate.latitude) &&
            (-180...180).contains(coordinate.longitude)
    }
}
