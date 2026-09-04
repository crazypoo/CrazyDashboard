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
import QWeatherSDK

// EN: The risk level is intentionally small so the route UI can explain it quickly.
// ES: El nivel de riesgo es deliberadamente pequeño para que la interfaz lo explique rápidamente.
// 中文：风险等级保持简单，便于路线界面快速解释。
nonisolated public enum PTRouteWeatherRiskLevel: String, Codable, Comparable, Sendable {
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

nonisolated public enum PTRouteWeatherRiskFactor: String, Codable, CaseIterable, Sendable {
    case precipitation
    case wind
    case cold
    case heat
    case lowVisibility
    case storm
}

// EN: The report records the single provider that produced every route sample.
// ES: El informe registra el único proveedor que produjo todas las muestras de la ruta.
// 中文：报告记录为整条路线生成全部采样点的唯一天气提供方。
nonisolated public enum PTRouteWeatherProvider: String, Codable, Sendable {
    case weatherKit
    case qWeather
}

// EN: Thresholds are explicit and testable instead of being hidden in a view controller.
// ES: Los umbrales son explícitos y comprobables, no están ocultos en un controlador de vista.
// 中文：阈值明确可测试，不把业务规则隐藏在视图控制器中。
nonisolated public struct PTRouteWeatherRiskPolicy: Codable, Equatable, Sendable {
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

nonisolated public struct PTRouteWeatherSample: Codable, Equatable, Sendable {
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

nonisolated public struct PTRouteWeatherRiskPoint: Codable, Equatable, Sendable {
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

nonisolated public struct PTRouteWeatherRiskReport: Codable, Equatable, Sendable {
    public let createdAt: Date
    public let startDate: Date
    public let provider: PTRouteWeatherProvider
    public let points: [PTRouteWeatherRiskPoint]

    public init(
        createdAt: Date = Date(),
        startDate: Date,
        provider: PTRouteWeatherProvider = .weatherKit,
        points: [PTRouteWeatherRiskPoint]
    ) {
        self.createdAt = createdAt
        self.startDate = startDate
        self.provider = provider
        self.points = points
    }

    private enum CodingKeys: String, CodingKey {
        case createdAt
        case startDate
        case provider
        case points
    }

    // EN: Older saved reports default to WeatherKit when they do not contain a provider field.
    // ES: Los informes guardados antiguos usan WeatherKit si no contienen el campo del proveedor.
    // 中文：旧版保存的报告没有提供方字段时，默认兼容为 WeatherKit。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        startDate = try container.decode(Date.self, forKey: .startDate)
        provider = try container.decodeIfPresent(PTRouteWeatherProvider.self, forKey: .provider) ?? .weatherKit
        points = try container.decode([PTRouteWeatherRiskPoint].self, forKey: .points)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(provider, forKey: .provider)
        try container.encode(points, forKey: .points)
    }

    public var worstLevel: PTRouteWeatherRiskLevel {
        points.map(\.level).max() ?? .clear
    }

    public var riskyPointCount: Int {
        points.count(where: { $0.level != .clear })
    }
}

// EN: This factor list extends weather risk with route geometry and time-of-day without offering speed advice.
// ES: Esta lista amplía el riesgo meteorológico con geometría y hora del día sin ofrecer consejos de velocidad.
// 中文：该因素列表把路线几何和时段加入天气风险，但不提供速度建议。
nonisolated public enum PTRouteRidingRiskFactor: String, Codable, Equatable, Sendable {
    case precipitation
    case wind
    case cold
    case heat
    case lowVisibility
    case storm
    case night
    case continuousCurves
    case weatherUnavailable
}

nonisolated public struct PTRouteRidingRiskPoint: Codable, Equatable, Sendable {
    public let coordinate: PTRideCoordinate
    public let forecastDate: Date
    public let level: PTRouteWeatherRiskLevel
    public let factors: [PTRouteRidingRiskFactor]
    public let curveAngleDegrees: Double

    public init(
        coordinate: PTRideCoordinate,
        forecastDate: Date,
        level: PTRouteWeatherRiskLevel,
        factors: [PTRouteRidingRiskFactor],
        curveAngleDegrees: Double = 0
    ) {
        self.coordinate = coordinate
        self.forecastDate = forecastDate
        self.level = level
        self.factors = factors
        self.curveAngleDegrees = max(curveAngleDegrees.isFinite ? curveAngleDegrees : 0, 0)
    }
}

nonisolated public struct PTRouteRidingRiskReport: Codable, Equatable, Sendable {
    public let createdAt: Date
    public let startDate: Date
    public let weatherProvider: PTRouteWeatherProvider?
    public let points: [PTRouteRidingRiskPoint]
    public let missingData: [PTRouteRidingRiskFactor]

    public init(
        createdAt: Date = Date(),
        startDate: Date,
        weatherProvider: PTRouteWeatherProvider?,
        points: [PTRouteRidingRiskPoint],
        missingData: [PTRouteRidingRiskFactor] = []
    ) {
        self.createdAt = createdAt
        self.startDate = startDate
        self.weatherProvider = weatherProvider
        self.points = points
        self.missingData = missingData
    }

    public var worstLevel: PTRouteWeatherRiskLevel {
        points.map(\.level).max() ?? (missingData.isEmpty ? .clear : .caution)
    }

    public var riskyPointCount: Int {
        points.count(where: { $0.level != .clear })
    }
}

// EN: Geometry analysis is deterministic and bounded, so long GPX routes cannot monopolize the UI.
// ES: El análisis geométrico es determinista y limitado, por lo que una ruta GPX larga no monopoliza la UI.
// 中文：几何分析是确定且有边界的，长 GPX 路线不会独占 UI 资源。
nonisolated public enum PTRouteRidingRiskAnalyzer {
    nonisolated public static func analyze(
        coordinates: [CLLocationCoordinate2D],
        weatherReport: PTRouteWeatherRiskReport?,
        startDate: Date,
        estimatedDuration: TimeInterval?,
        now: Date = Date()
    ) -> PTRouteRidingRiskReport {
        let validCoordinates = coordinates.filter(Self.isValidCoordinate)
        guard !validCoordinates.isEmpty else {
            return PTRouteRidingRiskReport(
                startDate: startDate,
                weatherProvider: weatherReport?.provider,
                points: [],
                missingData: [.weatherUnavailable]
            )
        }

        let routeCoordinates = sampledCoordinates(validCoordinates)
        let routeDuration = estimatedDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ??
            max(routeDistance(validCoordinates) / (40.0 / 3.6), 60)
        let denominator = max(routeCoordinates.count - 1, 1)
        let curveAngles = routeCoordinates.indices.map { index in
            guard index > 0, index + 1 < routeCoordinates.count else { return 0.0 }
            return turnAngle(
                from: routeCoordinates[index - 1],
                through: routeCoordinates[index],
                to: routeCoordinates[index + 1]
            )
        }

        var curveRun = 0
        var curveRunLengths = Array(repeating: 0, count: routeCoordinates.count)
        for index in routeCoordinates.indices {
            if curveAngles[index] >= 35 {
                curveRun += 1
            } else {
                curveRun = 0
            }
            curveRunLengths[index] = curveRun
        }

        let hasWeather = !(weatherReport?.points.isEmpty ?? true)
        let missingData: [PTRouteRidingRiskFactor] = hasWeather ? [] : [.weatherUnavailable]
        let points = routeCoordinates.enumerated().map { index, coordinate in
            let fraction = Double(index) / Double(denominator)
            let forecastDate = startDate.addingTimeInterval(routeDuration * fraction)
            let weatherPoint = weatherReport?.points.min {
                distanceMeters($0.sample.coordinate, coordinate) < distanceMeters($1.sample.coordinate, coordinate)
            }

            var factors: [PTRouteRidingRiskFactor] = []
            var level = weatherPoint?.level ?? .clear
            if let weatherPoint {
                for factor in weatherPoint.factors {
                    let mapped = PTRouteRidingRiskFactor(rawValue: factor.rawValue)
                    if let mapped, !factors.contains(mapped) {
                        factors.append(mapped)
                    }
                }
            } else {
                factors.append(.weatherUnavailable)
                level = max(level, .caution)
            }

            let hour = Calendar.current.component(.hour, from: forecastDate)
            if hour >= 21 || hour < 6 {
                factors.append(.night)
                level = max(level, .caution)
            }
            if curveRunLengths[index] >= 3 {
                factors.append(.continuousCurves)
                level = max(level, .caution)
            }

            return PTRouteRidingRiskPoint(
                coordinate: PTRideCoordinate(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                ),
                forecastDate: forecastDate,
                level: level,
                factors: factors,
                curveAngleDegrees: curveAngles[index]
            )
        }

        return PTRouteRidingRiskReport(
            createdAt: now,
            startDate: startDate,
            weatherProvider: weatherReport?.provider,
            points: points,
            missingData: missingData
        )
    }

    nonisolated private static func sampledCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 240 else { return coordinates }
        let stride = max(1, Int(ceil(Double(coordinates.count) / 240)))
        var result = Array(coordinates.enumerated().filter { $0.offset % stride == 0 }.map(\.element))
        if result.last?.latitude != coordinates.last?.latitude || result.last?.longitude != coordinates.last?.longitude {
            result.append(coordinates.last!)
        }
        return result
    }

    nonisolated private static func isValidCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(coordinate) &&
            coordinate.latitude.isFinite && coordinate.longitude.isFinite
    }

    nonisolated private static func distanceMeters(_ lhs: PTRideCoordinate, _ rhs: CLLocationCoordinate2D) -> Double {
        let first = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
        let second = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        return first.distance(from: second)
    }

    nonisolated private static func routeDistance(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count > 1 else { return 0 }
        return zip(coordinates, coordinates.dropFirst()).reduce(0) { total, pair in
            total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }
    }

    nonisolated private static func turnAngle(
        from previous: CLLocationCoordinate2D,
        through current: CLLocationCoordinate2D,
        to next: CLLocationCoordinate2D
    ) -> Double {
        let incoming = bearing(from: previous, to: current)
        let outgoing = bearing(from: current, to: next)
        let difference = abs(outgoing - incoming).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    nonisolated private static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let latitude1 = from.latitude * .pi / 180
        let latitude2 = to.latitude * .pi / 180
        let deltaLongitude = (to.longitude - from.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(latitude2)
        let x = cos(latitude1) * sin(latitude2) -
            sin(latitude1) * cos(latitude2) * cos(deltaLongitude)
        return atan2(y, x) * 180 / .pi
    }
}

nonisolated public enum PTRouteWeatherRiskError: Error, Equatable, LocalizedError, Sendable {
    case invalidRoute
    case noForecast
    case fallbackUnavailable
    case allProvidersFailed
    case forecastOutsideSupportedRange
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidRoute:
            return "The route does not contain valid coordinates."
        case .noForecast:
            return "No hourly forecast was available for the route."
        case .fallbackUnavailable:
            return "The fallback weather provider is unavailable."
        case .allProvidersFailed:
            return "Apple WeatherKit and QWeather could not provide route forecasts."
        case .forecastOutsideSupportedRange:
            return "The route extends beyond the supported hourly forecast range."
        case .cancelled:
            return "The route weather analysis was cancelled."
        }
    }
}

// EN: Pure risk calculation keeps weather policy deterministic and independent from networking.
// ES: El cálculo puro mantiene la política meteorológica determinista e independiente de la red.
// 中文：纯风险计算让天气规则确定且不依赖网络。
nonisolated public enum PTRouteWeatherRiskAnalyzer {
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
        } else if sample.visibilityKm == nil &&
                    (condition.contains("fog") || condition.contains("mist") ||
                     condition.contains("haze") || condition.contains("dust") ||
                     condition.contains("sand")) {
            // EN: QWeather may omit visibility; fog-like conditions still warrant a cautious riding notice.
            // ES: QWeather puede omitir la visibilidad; las condiciones de niebla aún requieren cautela al conducir.
            // 中文：QWeather 可能不提供能见度，雾霾类天气仍应提示谨慎骑行。
            register(.lowVisibility, .caution)
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

// EN: Both providers use the same route requests, and only a complete provider result is published.
// ES: Ambos proveedores usan las mismas solicitudes de ruta y solo se publica un resultado completo.
// 中文：两个提供方使用完全相同的路线请求，只有整条路线成功后才发布结果。
typealias PTRouteWeatherSampleLoader = @MainActor @Sendable (
    CLLocationCoordinate2D,
    Date
) async throws -> PTRouteWeatherSample

// EN: Weather access is isolated here so the roadbook UI never owns forecast requests.
// ES: El acceso meteorológico se aísla aquí para que la interfaz Roadbook no gestione solicitudes.
// 中文：天气访问集中在此处，路线界面不直接管理请求。
@MainActor
public final class PTRouteWeatherRiskService {
    public static let shared = PTRouteWeatherRiskService(weatherKitLoader: { coordinate, date in
        try await fetchWeatherKitRouteSample(at: coordinate, date: date)
    })

    private let weatherKitLoader: PTRouteWeatherSampleLoader
    private var qWeatherLoader: PTRouteWeatherSampleLoader?
    private let maximumRouteSamples = 12
    private let maximumForecastDifference: TimeInterval = 90 * 60
    private let qWeatherForecastHorizon: TimeInterval = 168 * 60 * 60
    private let defaultSpeedMetersPerSecond = 40.0 / 3.6

    // EN: Injectable loaders make provider fallback deterministic without introducing another network layer.
    // ES: Los cargadores inyectables hacen determinista la reserva sin introducir otra capa de red.
    // 中文：可注入的数据加载器让提供方回退可确定测试，同时不引入第二套网络层。
    init(
        weatherKitLoader: @escaping PTRouteWeatherSampleLoader,
        qWeatherLoader: PTRouteWeatherSampleLoader? = nil
    ) {
        self.weatherKitLoader = weatherKitLoader
        self.qWeatherLoader = qWeatherLoader
    }

    // EN: Share the already initialized QWeather actor with route-risk analysis.
    // ES: Comparte el actor de QWeather ya inicializado con el análisis de riesgo de la ruta.
    // 中文：将已经初始化的 QWeather actor 注入路线风险分析服务。
    public func configureQWeather(_ service: QWeather) {
        let maximumDifference = maximumForecastDifference
        qWeatherLoader = { coordinate, date in
            try await fetchQWeatherRouteSample(
                using: service,
                at: coordinate,
                date: date,
                maximumDifference: maximumDifference
            )
        }
    }

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
        let requests = samplesCoordinates.enumerated().map { index, coordinate in
            let fraction = Double(index) / Double(denominator)
            return (coordinate: coordinate, date: startDate.addingTimeInterval(duration * fraction))
        }

        let result: (provider: PTRouteWeatherProvider, points: [PTRouteWeatherRiskPoint])
        do {
            result = (
                provider: .weatherKit,
                points: try await loadPoints(requests: requests, policy: policy, loader: weatherKitLoader)
            )
        } catch is CancellationError {
            throw PTRouteWeatherRiskError.cancelled
        } catch {
            if Task.isCancelled {
                throw PTRouteWeatherRiskError.cancelled
            }

            guard let qWeatherLoader else {
                throw PTRouteWeatherRiskError.fallbackUnavailable
            }
            let now = Date()
            guard requests.allSatisfy({
                isRouteWeatherDateWithinQWeatherHorizon(
                    $0.date,
                    now: now,
                    horizon: qWeatherForecastHorizon
                )
            }) else {
                throw PTRouteWeatherRiskError.forecastOutsideSupportedRange
            }

            do {
                result = (
                    provider: .qWeather,
                    points: try await loadPoints(requests: requests, policy: policy, loader: qWeatherLoader)
                )
            } catch is CancellationError {
                throw PTRouteWeatherRiskError.cancelled
            } catch {
                throw PTRouteWeatherRiskError.allProvidersFailed
            }
        }

        guard !Task.isCancelled else {
            throw PTRouteWeatherRiskError.cancelled
        }
        // EN: Progress is emitted only after the selected provider completes every point.
        // ES: El progreso se emite solo después de que el proveedor elegido completa todos los puntos.
        // 中文：只有选定的提供方完成全部采样点后才发送进度，避免展示已丢弃的半成品。
        for (index, point) in result.points.enumerated() {
            guard !Task.isCancelled else {
                throw PTRouteWeatherRiskError.cancelled
            }
            progress?(index + 1, result.points.count, point)
        }

        return PTRouteWeatherRiskReport(
            startDate: startDate,
            provider: result.provider,
            points: result.points
        )
    }

    // EN: Add geometry and night checks after the existing provider fallback has produced a weather report.
    // ES: Añade geometría y noche después de que la reserva existente haya producido el informe meteorológico.
    // 中文：沿用现有天气回退结果，再叠加路线几何和夜间检查。
    public func analyzeRiding(
        roadbook: PTRoadbook,
        startDate: Date = Date(),
        estimatedDuration: TimeInterval? = nil,
        policy: PTRouteWeatherRiskPolicy = .default,
        progress: (@MainActor @Sendable (Int, Int, PTRouteWeatherRiskPoint) -> Void)? = nil
    ) async throws -> PTRouteRidingRiskReport {
        let weatherReport = try await analyze(
            coordinates: roadbook.waypoints.map(\.coordinate),
            startDate: startDate,
            estimatedDuration: estimatedDuration,
            policy: policy,
            progress: nil
        )
        let report = PTRouteRidingRiskAnalyzer.analyze(
            coordinates: roadbook.waypoints.map(\.coordinate),
            weatherReport: weatherReport,
            startDate: startDate,
            estimatedDuration: estimatedDuration
        )
        if let progress {
            for (index, point) in weatherReport.points.enumerated() {
                progress(index + 1, weatherReport.points.count, point)
            }
        }
        return report
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

    func loadPoints(
        requests: [(coordinate: CLLocationCoordinate2D, date: Date)],
        policy: PTRouteWeatherRiskPolicy,
        loader: PTRouteWeatherSampleLoader
    ) async throws -> [PTRouteWeatherRiskPoint] {
        var points: [PTRouteWeatherRiskPoint] = []
        points.reserveCapacity(requests.count)

        for request in requests {
            try Task.checkCancellation()
            let sample = try await loader(request.coordinate, request.date)
            points.append(PTRouteWeatherRiskAnalyzer.analyze(sample: sample, policy: policy))
        }
        return points
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

// EN: WeatherKit route samples are normalized into the provider-neutral model.
// ES: Las muestras de ruta de WeatherKit se normalizan al modelo independiente del proveedor.
// 中文：将 WeatherKit 路线采样结果统一转换为与提供方无关的模型。
@MainActor
private func fetchWeatherKitRouteSample(
    at coordinate: CLLocationCoordinate2D,
    date: Date,
    maximumDifference: TimeInterval = 90 * 60
) async throws -> PTRouteWeatherSample {
    let weather = try await WeatherService.shared.weather(
        for: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    )
    guard let hour = weather.hourlyForecast.forecast.min(by: {
        abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
    }), isRouteWeatherForecastWithinTolerance(
        actualDate: hour.date,
        requestedDate: date,
        maximumDifference: maximumDifference
    ) else {
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

// EN: Provider parsing failures stay private and are converted into one public route-level error.
// ES: Los fallos de análisis del proveedor permanecen privados y se convierten en un error público de ruta.
// 中文：提供方解析失败保持为私有错误，最终统一转换为公开的路线级错误。
private enum PTRouteWeatherProviderError: Error, Sendable {
    case invalidResponse
    case invalidData
}

// EN: QWeather's 168-hour feed supplies the shared route fields without changing the transport layer.
// ES: El feed de 168 horas de QWeather suministra los campos compartidos sin cambiar la capa de transporte.
// 中文：使用 QWeather 的 168 小时预报提供共享路线字段，不改变现有传输层。
@MainActor
private func fetchQWeatherRouteSample(
    using service: QWeather,
    at coordinate: CLLocationCoordinate2D,
    date: Date,
    maximumDifference: TimeInterval
) async throws -> PTRouteWeatherSample {
    let locale = Locale(identifier: "en_US_POSIX")
    let longitude = String(format: "%.2f", locale: locale, coordinate.longitude)
    let latitude = String(format: "%.2f", locale: locale, coordinate.latitude)
    let parameter = WeatherParameter(
        location: "\(longitude),\(latitude)",
        lang: .EN,
        unit: .METRIC
    )
    let response = try await service.weather168h(parameter)
    guard response.code == "200", !response.hourly.isEmpty else {
        throw PTRouteWeatherProviderError.invalidResponse
    }

    guard let hour = response.hourly.compactMap({ hourly in
        qWeatherHourlyDate(hourly.fxTime).map { (hourly, $0) }
    }).min(by: {
        abs($0.1.timeIntervalSince(date)) < abs($1.1.timeIntervalSince(date))
    }), isRouteWeatherForecastWithinTolerance(
        actualDate: hour.1,
        requestedDate: date,
        maximumDifference: maximumDifference
    ) else {
        throw PTRouteWeatherRiskError.noForecast
    }

    guard
        let temperature = Double(hour.0.temp), temperature.isFinite,
        let windKmh = Double(hour.0.windSpeed), windKmh.isFinite,
        let precipitationPercent = Double(hour.0.pop), precipitationPercent.isFinite,
        (0...100).contains(precipitationPercent)
    else {
        throw PTRouteWeatherProviderError.invalidData
    }

    return PTRouteWeatherSample(
        coordinate: PTRideCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ),
        forecastDate: hour.1,
        condition: qWeatherCondition(text: hour.0.text, iconCode: hour.0.icon),
        temperatureCelsius: temperature,
        precipitationProbability: precipitationPercent / 100,
        windKmh: windKmh,
        visibilityKm: nil
    )
}

// EN: QWeather text is preferred; icon ranges are only a conservative fallback for empty text.
// ES: Se prefiere el texto de QWeather; los rangos de iconos solo sirven como reserva conservadora.
// 中文：优先使用 QWeather 文本，图标编码范围只作为文本为空时的保守备用判断。
func qWeatherCondition(text: String, iconCode: String) -> String {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedText.isEmpty else { return trimmedText }
    guard let code = Int(iconCode) else { return "unknown" }

    switch code {
    case 302...304: return "thunderstorm"
    case 310...318: return "rainstorm"
    case 403: return "snowstorm"
    case 507...508: return "duststorm"
    case 300...399: return "rain"
    case 400...499: return "snow"
    case 500...515: return "fog"
    case 900: return "hot"
    case 901: return "cold"
    default: return "unknown"
    }
}

// EN: QWeather timestamps may include or omit fractional seconds.
// ES: Las marcas de tiempo de QWeather pueden incluir o no segundos fraccionarios.
// 中文：QWeather 时间戳可能带有或不带有小数秒。
private func qWeatherHourlyDate(_ value: String) -> Date? {
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractionalFormatter.date(from: value) {
        return date
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

// EN: Forecast boundaries are shared by both providers so edge behavior stays identical.
// ES: Ambos proveedores comparten los límites de pronóstico para mantener idéntico el comportamiento.
// 中文：两个提供方共用预报边界判断，保证边界行为一致。
func isRouteWeatherForecastWithinTolerance(
    actualDate: Date,
    requestedDate: Date,
    maximumDifference: TimeInterval
) -> Bool {
    maximumDifference.isFinite && maximumDifference >= 0 &&
        abs(actualDate.timeIntervalSince(requestedDate)) <= maximumDifference
}

// EN: QWeather's supported horizon is inclusive at exactly 168 hours.
// ES: El horizonte compatible de QWeather incluye exactamente las 168 horas.
// 中文：QWeather 支持的预报范围包含恰好 168 小时的边界。
func isRouteWeatherDateWithinQWeatherHorizon(
    _ date: Date,
    now: Date,
    horizon: TimeInterval = 168 * 60 * 60
) -> Bool {
    horizon.isFinite && horizon >= 0 && date <= now.addingTimeInterval(horizon)
}
