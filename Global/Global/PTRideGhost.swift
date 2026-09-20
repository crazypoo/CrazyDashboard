//
//  PTRideGhost.swift
//  CrazyDashboard
//
//  EN: Build 81 read-only Ghost Ride route alignment and comparison primitives.
//  ES: Primitivas de alineación y comparación de rutas Ghost Ride de solo lectura para Build 81.
//  中文：Build81 只读 Ghost Ride 路线对齐与对比基础模型。
//

import Foundation
import CoreLocation

// EN: Availability is explicit so an incomplete or mismatched route never renders stale ghost data.
// ES: La disponibilidad es explícita para que una ruta incompleta o distinta nunca muestre datos obsoletos.
// 中文：显式表达可用状态，避免不完整或不匹配的路线继续显示旧 Ghost 数据。
nonisolated enum PTRideGhostAvailability: Equatable, Sendable {
    case ready
    case noCurrentRoute
    case noHistoricalRoute
    case insufficientOverlap
    case outsideOverlap
}

nonisolated enum PTRideGhostFallbackAction: Equatable, Sendable {
    case none
    case hideUntilRejoin
}

// EN: This route sample adds cumulative distance without duplicating telemetry fields.
// ES: Esta muestra añade distancia acumulada sin duplicar los campos de telemetría.
// 中文：路线样本只增加累计距离，不重复定义遥测字段。
nonisolated struct PTRideGhostRouteSample: Equatable, Sendable {
    let sample: PTRideReplaySample
    let elapsed: TimeInterval
    let distanceKm: Double

    var coordinate: CLLocationCoordinate2D {
        sample.coordinate
    }

    // EN: Reuse Build79's road-surface scoring on historical replay signals; this is synthetic and read-only.
    // ES: Reutiliza la puntuación de superficie de Build79 sobre señales históricas; es sintética y de solo lectura.
    // 中文：复用 Build79 的路面评分处理历史回放信号；结果为合成且只读。
    func roadSurfaceQuality(vehicleID: UUID?) -> PTRoadSurfaceQuality {
        let surfaceSample = PTRoadSurfaceSample(
            vehicleID: vehicleID ?? UUID(),
            capturedAt: sample.timestamp,
            latitude: sample.latitude,
            longitude: sample.longitude,
            speedKmh: sample.speedKmh,
            verticalG: sample.gForceZ,
            lateralG: sample.gForceY,
            longitudinalG: sample.gForceX,
            leanDegrees: sample.leanAngle,
            isSynthetic: true
        )
        return PTRoadSurfaceAnalyzer.quality(for: PTRoadSurfaceAnalyzer.score(for: surfaceSample))
    }
}

nonisolated struct PTRideGhostRoute: Equatable, Sendable {
    let reportID: String
    let vehicleID: UUID?
    let samples: [PTRideGhostRouteSample]
    let totalDistanceKm: Double
    let duration: TimeInterval

    var isUsable: Bool {
        !samples.isEmpty && duration >= 0
    }

    // EN: Binary search keeps replay comparison independent from sample count.
    // ES: La búsqueda binaria mantiene la comparación independiente de la cantidad de muestras.
    // 中文：二分查找让回放对比不随样本数量线性变慢。
    func sample(atElapsed elapsed: TimeInterval) -> PTRideGhostRouteSample? {
        guard let first = samples.first else { return nil }
        guard samples.count > 1 else { return first }
        let target = min(max(elapsed, 0), duration)
        if target <= first.elapsed { return first }
        guard let last = samples.last else { return first }
        if target >= last.elapsed { return last }

        var lower = 0
        var upper = samples.count - 1
        while lower + 1 < upper {
            let middle = (lower + upper) / 2
            if samples[middle].elapsed < target {
                lower = middle
            } else {
                upper = middle
            }
        }
        return interpolate(samples[lower], samples[upper], fraction: fraction(
            target,
            lower: samples[lower].elapsed,
            upper: samples[upper].elapsed
        ))
    }

    func sample(atDistance distanceKm: Double) -> PTRideGhostRouteSample? {
        guard let first = samples.first else { return nil }
        guard samples.count > 1 else { return first }
        let target = min(max(distanceKm, 0), totalDistanceKm)
        if target <= first.distanceKm { return first }
        guard let last = samples.last else { return first }
        if target >= last.distanceKm { return last }

        var lower = 0
        var upper = samples.count - 1
        while lower + 1 < upper {
            let middle = (lower + upper) / 2
            if samples[middle].distanceKm < target {
                lower = middle
            } else {
                upper = middle
            }
        }
        return interpolate(samples[lower], samples[upper], fraction: fraction(
            target,
            lower: samples[lower].distanceKm,
            upper: samples[upper].distanceKm
        ))
    }

    private func fraction(_ target: Double, lower: Double, upper: Double) -> Double {
        guard upper > lower else { return 0 }
        return min(max((target - lower) / (upper - lower), 0), 1)
    }

    private func interpolate(_ lower: PTRideGhostRouteSample,
                             _ upper: PTRideGhostRouteSample,
                             fraction: Double) -> PTRideGhostRouteSample {
        func value(_ first: Double, _ second: Double) -> Double {
            first + (second - first) * fraction
        }

        let lowerSample = lower.sample
        let upperSample = upper.sample
        let altitude: Double?
        switch (lowerSample.altitude, upperSample.altitude) {
        case let (.some(first), .some(second)):
            altitude = value(first, second)
        case let (.some(first), .none):
            altitude = first
        case let (.none, .some(second)):
            altitude = second
        case (.none, .none):
            altitude = nil
        }

        let timestamp = lowerSample.timestamp.addingTimeInterval(
            upperSample.timestamp.timeIntervalSince(lowerSample.timestamp) * fraction
        )
        let sample = PTRideReplaySample(
            latitude: value(lowerSample.latitude, upperSample.latitude),
            longitude: value(lowerSample.longitude, upperSample.longitude),
            timestamp: timestamp,
            altitude: altitude,
            speedKmh: value(lowerSample.speedKmh, upperSample.speedKmh),
            rpm: Int(value(Double(lowerSample.rpm), Double(upperSample.rpm)).rounded()),
            leanAngle: value(lowerSample.leanAngle, upperSample.leanAngle),
            gForceX: value(lowerSample.gForceX, upperSample.gForceX),
            gForceY: value(lowerSample.gForceY, upperSample.gForceY),
            gForceZ: value(lowerSample.gForceZ, upperSample.gForceZ),
            slipRatio: value(lowerSample.slipRatio, upperSample.slipRatio)
        )
        return PTRideGhostRouteSample(
            sample: sample,
            elapsed: value(lower.elapsed, upper.elapsed),
            distanceKm: value(lower.distanceKm, upper.distanceKm)
        )
    }
}

// EN: Normalize timestamp order and cumulative WGS84 distance once before any comparison.
// ES: Normaliza una vez el orden temporal y la distancia WGS84 acumulada antes de comparar.
// 中文：在所有对比前只做一次时间排序和 WGS84 累计距离归一化。
nonisolated enum PTRideGhostRouteNormalizer {
    static func make(session: PTRideReplaySession) -> PTRideGhostRoute {
        let validSamples = session.samples.filter {
            $0.latitude.isFinite && $0.longitude.isFinite &&
            (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude)
        }.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.latitude < rhs.latitude
            }
            return lhs.timestamp < rhs.timestamp
        }
        guard !validSamples.isEmpty else {
            return PTRideGhostRoute(
                reportID: session.report.id,
                vehicleID: session.report.vehicleID,
                samples: [],
                totalDistanceKm: 0,
                duration: 0
            )
        }

        var previousTimestamp = session.startTime
        var previousLocation: CLLocation?
        var cumulativeDistanceKm = 0.0
        var normalized: [PTRideGhostRouteSample] = []
        normalized.reserveCapacity(validSamples.count)

        for sample in validSamples {
            let timestamp = max(previousTimestamp, sample.timestamp)
            previousTimestamp = timestamp
            let location = CLLocation(latitude: sample.latitude, longitude: sample.longitude)
            if let previousLocation {
                let meters = location.distance(from: previousLocation)
                if meters.isFinite, meters >= 0, meters <= 2_000 {
                    cumulativeDistanceKm += meters / 1_000
                }
            }
            previousLocation = location
            normalized.append(PTRideGhostRouteSample(
                sample: sample,
                elapsed: max(timestamp.timeIntervalSince(session.startTime), 0),
                distanceKm: cumulativeDistanceKm
            ))
        }

        let duration = max(
            session.duration,
            normalized.last?.elapsed ?? 0
        )
        return PTRideGhostRoute(
            reportID: session.report.id,
            vehicleID: session.report.vehicleID,
            samples: normalized,
            totalDistanceKm: cumulativeDistanceKm,
            duration: duration
        )
    }
}

// EN: A coarse spatial index avoids an O(n²) route comparison on long rides.
// ES: Un índice espacial grueso evita una comparación O(n²) en viajes largos.
// 中文：粗粒度空间索引避免长途路线对比退化为 O(n²)。
nonisolated struct PTRideGhostProgressIndex: Sendable {
    private let route: PTRideGhostRoute
    private let buckets: [String: [Int]]
    private let bucketScale = 1_000.0

    init(route: PTRideGhostRoute) {
        self.route = route
        var buckets: [String: [Int]] = [:]
        for (index, point) in route.samples.enumerated() {
            let key = Self.key(latitude: point.sample.latitude,
                               longitude: point.sample.longitude,
                               scale: bucketScale)
            buckets[key, default: []].append(index)
        }
        self.buckets = buckets
    }

    func match(coordinate: CLLocationCoordinate2D,
               toleranceMeters: CLLocationDistance = 90) -> (index: Int, distanceMeters: CLLocationDistance)? {
        guard coordinate.latitude.isFinite,
              coordinate.longitude.isFinite,
              (-90...90).contains(coordinate.latitude),
              (-180...180).contains(coordinate.longitude) else { return nil }

        let latitudeCell = Int(floor(coordinate.latitude * bucketScale))
        let longitudeCell = Int(floor(coordinate.longitude * bucketScale))
        var candidateIndices: [Int] = []
        candidateIndices.reserveCapacity(12)
        for latitudeOffset in -1...1 {
            for longitudeOffset in -1...1 {
                let key = "\(latitudeCell + latitudeOffset):\(longitudeCell + longitudeOffset)"
                candidateIndices.append(contentsOf: buckets[key] ?? [])
            }
        }
        guard !candidateIndices.isEmpty else { return nil }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return candidateIndices.compactMap { index -> (Int, CLLocationDistance)? in
            guard route.samples.indices.contains(index) else { return nil }
            let point = route.samples[index].sample
            let distance = location.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
            guard distance <= toleranceMeters else { return nil }
            return (index, distance)
        }.min { $0.1 < $1.1 }
    }

    private static func key(latitude: Double, longitude: Double, scale: Double) -> String {
        "\(Int(floor(latitude * scale))):\(Int(floor(longitude * scale)))"
    }
}

nonisolated struct PTRideGhostOverlap: Equatable, Sendable {
    let currentStartDistanceKm: Double
    let currentEndDistanceKm: Double
    let historicalStartDistanceKm: Double
    let historicalEndDistanceKm: Double
    let matchedSampleCount: Int
    let score: Double

    var currentDistanceSpanKm: Double {
        abs(currentEndDistanceKm - currentStartDistanceKm)
    }

    func contains(currentDistanceKm: Double) -> Bool {
        let lower = min(currentStartDistanceKm, currentEndDistanceKm)
        let upper = max(currentStartDistanceKm, currentEndDistanceKm)
        return currentDistanceKm >= lower && currentDistanceKm <= upper
    }

    func historicalDistance(for currentDistanceKm: Double) -> Double {
        let denominator = currentEndDistanceKm - currentStartDistanceKm
        guard abs(denominator) > 0.000001 else { return historicalStartDistanceKm }
        let fraction = min(max((currentDistanceKm - currentStartDistanceKm) / denominator, 0), 1)
        return historicalStartDistanceKm + (historicalEndDistanceKm - historicalStartDistanceKm) * fraction
    }
}

// EN: Only a meaningful route span enables Ghost Ride; a single nearby point is not enough.
// ES: Ghost Ride solo se activa con un tramo de ruta significativo; un punto cercano no basta.
// 中文：只有足够长的路线重叠区才允许 Ghost Ride，单个附近点不能触发对比。
nonisolated enum PTRideGhostOverlapAnalyzer {
    static func make(current: PTRideGhostRoute,
                     historical: PTRideGhostRoute,
                     toleranceMeters: CLLocationDistance = 90) -> PTRideGhostOverlap? {
        guard current.isUsable, historical.isUsable else { return nil }
        let index = PTRideGhostProgressIndex(route: historical)
        var matches: [(current: PTRideGhostRouteSample, historical: PTRideGhostRouteSample)] = []
        for point in current.samples {
            guard let match = index.match(coordinate: point.coordinate, toleranceMeters: toleranceMeters),
                  historical.samples.indices.contains(match.index) else { continue }
            matches.append((point, historical.samples[match.index]))
        }

        guard matches.count >= 3,
              let first = matches.first,
              let last = matches.last else { return nil }
        let currentSpan = abs(last.current.distanceKm - first.current.distanceKm)
        let historicalSpan = abs(last.historical.distanceKm - first.historical.distanceKm)
        let minimumSpan = min(0.25, max(current.totalDistanceKm, historical.totalDistanceKm) * 0.1)
        guard max(currentSpan, historicalSpan) >= max(minimumSpan, 0.05) else { return nil }

        let denominator = max(min(current.samples.count, historical.samples.count), 1)
        let score = min(max(Double(matches.count) / Double(denominator), 0), 1)
        return PTRideGhostOverlap(
            currentStartDistanceKm: first.current.distanceKm,
            currentEndDistanceKm: last.current.distanceKm,
            historicalStartDistanceKm: first.historical.distanceKm,
            historicalEndDistanceKm: last.historical.distanceKm,
            matchedSampleCount: matches.count,
            score: score
        )
    }
}

nonisolated struct PTRideGhostComparison: Sendable {
    let availability: PTRideGhostAvailability
    let currentSample: PTRideReplaySample?
    let historicalSample: PTRideReplaySample?
    let currentProgress: Double?
    let historicalProgress: Double?
    let timeDeltaSeconds: TimeInterval?
    let speedDeltaKmh: Double?
    let rpmDelta: Int?
    let verticalGDelta: Double?
    let historicalRoadQuality: PTRoadSurfaceQuality?
    let fallbackAction: PTRideGhostFallbackAction

    static let unavailable = PTRideGhostComparison(
        availability: .insufficientOverlap,
        currentSample: nil,
        historicalSample: nil,
        currentProgress: nil,
        historicalProgress: nil,
        timeDeltaSeconds: nil,
        speedDeltaKmh: nil,
        rpmDelta: nil,
        verticalGDelta: nil,
        historicalRoadQuality: nil,
        fallbackAction: .hideUntilRejoin
    )
}

// EN: One compare session maps current route distance to historical route distance, not array indexes.
// ES: Una sesión mapea la distancia de la ruta actual a la histórica, no los índices de los arrays.
// 中文：对比会话按路线距离映射，而不是错误地按数组下标对齐。
nonisolated struct PTRideGhostSession: Sendable {
    let currentRoute: PTRideGhostRoute
    let historicalRoute: PTRideGhostRoute
    let overlap: PTRideGhostOverlap?
    let availability: PTRideGhostAvailability

    init(currentRoute: PTRideGhostRoute,
         historicalRoute: PTRideGhostRoute,
         toleranceMeters: CLLocationDistance = 90) {
        self.currentRoute = currentRoute
        self.historicalRoute = historicalRoute
        self.overlap = PTRideGhostOverlapAnalyzer.make(
            current: currentRoute,
            historical: historicalRoute,
            toleranceMeters: toleranceMeters
        )
        if !currentRoute.isUsable {
            self.availability = .noCurrentRoute
        } else if !historicalRoute.isUsable {
            self.availability = .noHistoricalRoute
        } else if self.overlap == nil {
            self.availability = .insufficientOverlap
        } else {
            self.availability = .ready
        }
    }

    func comparison(at elapsed: TimeInterval) -> PTRideGhostComparison {
        guard currentRoute.isUsable else {
            return PTRideGhostComparison(
                availability: .noCurrentRoute,
                currentSample: nil,
                historicalSample: nil,
                currentProgress: nil,
                historicalProgress: nil,
                timeDeltaSeconds: nil,
                speedDeltaKmh: nil,
                rpmDelta: nil,
                verticalGDelta: nil,
                historicalRoadQuality: nil,
                fallbackAction: .hideUntilRejoin
            )
        }
        guard historicalRoute.isUsable else {
            return PTRideGhostComparison(
                availability: .noHistoricalRoute,
                currentSample: currentRoute.sample(atElapsed: elapsed)?.sample,
                historicalSample: nil,
                currentProgress: nil,
                historicalProgress: nil,
                timeDeltaSeconds: nil,
                speedDeltaKmh: nil,
                rpmDelta: nil,
                verticalGDelta: nil,
                historicalRoadQuality: nil,
                fallbackAction: .hideUntilRejoin
            )
        }
        guard let overlap else { return .unavailable }
        guard let current = currentRoute.sample(atElapsed: elapsed) else { return .unavailable }
        guard overlap.contains(currentDistanceKm: current.distanceKm) else {
            return PTRideGhostComparison(
                availability: .outsideOverlap,
                currentSample: current.sample,
                historicalSample: nil,
                currentProgress: progress(distance: current.distanceKm, total: currentRoute.totalDistanceKm),
                historicalProgress: nil,
                timeDeltaSeconds: nil,
                speedDeltaKmh: nil,
                rpmDelta: nil,
                verticalGDelta: nil,
                historicalRoadQuality: nil,
                fallbackAction: .hideUntilRejoin
            )
        }
        guard let historical = historicalRoute.sample(
            atDistance: overlap.historicalDistance(for: current.distanceKm)
        ) else { return .unavailable }

        return PTRideGhostComparison(
            availability: .ready,
            currentSample: current.sample,
            historicalSample: historical.sample,
            currentProgress: progress(distance: current.distanceKm, total: currentRoute.totalDistanceKm),
            historicalProgress: progress(distance: historical.distanceKm, total: historicalRoute.totalDistanceKm),
            timeDeltaSeconds: current.elapsed - historical.elapsed,
            speedDeltaKmh: current.sample.speedKmh - historical.sample.speedKmh,
            rpmDelta: current.sample.rpm - historical.sample.rpm,
            verticalGDelta: abs(current.sample.gForceZ) - abs(historical.sample.gForceZ),
            historicalRoadQuality: historical.roadSurfaceQuality(vehicleID: historicalRoute.vehicleID),
            fallbackAction: .none
        )
    }

    private func progress(distance: Double, total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(max(distance / total, 0), 1)
    }
}

nonisolated struct PTRideGhostLiveSnapshot: Sendable {
    let availability: PTRideGhostAvailability
    let routeProgress: Double?
    let timeDeltaSeconds: TimeInterval?
    let speedDeltaKmh: Double?
    let rpmDelta: Int?
    let historicalSpeedKmh: Double?
    let historicalRPM: Int?
    let historicalRoadQuality: PTRoadSurfaceQuality?
    let fallbackAction: PTRideGhostFallbackAction

    static let unavailable = PTRideGhostLiveSnapshot(
        availability: .noHistoricalRoute,
        routeProgress: nil,
        timeDeltaSeconds: nil,
        speedDeltaKmh: nil,
        rpmDelta: nil,
        historicalSpeedKmh: nil,
        historicalRPM: nil,
        historicalRoadQuality: nil,
        fallbackAction: .hideUntilRejoin
    )
}

// EN: Live matching is stateful only for monotonic progress and never sends a vehicle command.
// ES: El emparejamiento en vivo solo mantiene progreso monotónico y nunca envía comandos al vehículo.
// 中文：实时匹配只保存单调进度，绝不发送任何车辆指令。
nonisolated struct PTRideGhostLiveResolver: Sendable {
    private let route: PTRideGhostRoute?
    private let index: PTRideGhostProgressIndex?
    private var lastMatchedIndex = 0
    private var startDate: Date?

    init(route: PTRideGhostRoute?) {
        self.route = route
        self.index = route.map(PTRideGhostProgressIndex.init(route:))
    }

    mutating func reset() {
        lastMatchedIndex = 0
        startDate = nil
    }

    mutating func update(coordinate: CLLocationCoordinate2D,
                         speedKmh: Double,
                         rpm: Int,
                         timestamp: Date = Date()) -> PTRideGhostLiveSnapshot {
        guard let route, route.isUsable else { return .unavailable }
        guard let index,
              let match = index.match(coordinate: coordinate, toleranceMeters: 110),
              route.samples.indices.contains(match.index) else {
            return PTRideGhostLiveSnapshot(
                availability: .outsideOverlap,
                routeProgress: nil,
                timeDeltaSeconds: nil,
                speedDeltaKmh: nil,
                rpmDelta: nil,
                historicalSpeedKmh: nil,
                historicalRPM: nil,
                historicalRoadQuality: nil,
                fallbackAction: .hideUntilRejoin
            )
        }

        lastMatchedIndex = max(lastMatchedIndex, match.index)
        if startDate == nil { startDate = timestamp }
        let historical = route.samples[lastMatchedIndex]
        let currentElapsed = max(timestamp.timeIntervalSince(startDate ?? timestamp), 0)
        return PTRideGhostLiveSnapshot(
            availability: .ready,
            routeProgress: route.totalDistanceKm > 0
                ? min(max(historical.distanceKm / route.totalDistanceKm, 0), 1)
                : 0,
            timeDeltaSeconds: currentElapsed - historical.elapsed,
            speedDeltaKmh: speedKmh - historical.sample.speedKmh,
            rpmDelta: rpm - historical.sample.rpm,
            historicalSpeedKmh: historical.sample.speedKmh,
            historicalRPM: historical.sample.rpm,
            historicalRoadQuality: historical.roadSurfaceQuality(vehicleID: route.vehicleID),
            fallbackAction: .none
        )
    }
}

// EN: The dashboard uses the newest same-vehicle completed route as an optional read-only reference.
// ES: El dashboard usa la ruta completada más reciente del mismo vehículo como referencia opcional de solo lectura.
// 中文：Dashboard 默认使用同一车辆最近完成的路线作为可选只读参考。
@MainActor
final class PTRideGhostLiveStore {
    private var resolver = PTRideGhostLiveResolver(route: nil)
    private var loadTask: Task<Void, Never>?
    private(set) var snapshot = PTRideGhostLiveSnapshot.unavailable
    var onChange: ((PTRideGhostLiveSnapshot) -> Void)?

    func start() {
        guard loadTask == nil else { return }
        let selectedVehicleID = PTMotorcycleGarageStore.shared.selectedVehicleID
        let report = PTTripManager.shared.tripHistory
            .filter { candidate in
                guard candidate.gpxFileName != nil else { return false }
                guard let selectedVehicleID else { return true }
                return candidate.vehicleID == selectedVehicleID
            }
            .sorted { $0.startTime > $1.startTime }
            .first
        guard let report, let fileName = report.gpxFileName else { return }

        loadTask = Task { [weak self] in
            do {
                let data = try await PTDataPersistenceActor.shared.readData(
                    fileName: fileName,
                    restoreFromICloud: true
                )
                try Task.checkCancellation()
                let points = try await Task.detached(priority: .utility) {
                    try PTGPXParser.parseTrack(data: data)
                }.value
                let session = try PTRideReplayBuilder.makeSession(report: report, trackPoints: points)
                let route = PTRideGhostRouteNormalizer.make(session: session)
                guard !Task.isCancelled else { return }
                self?.resolver = PTRideGhostLiveResolver(route: route)
                self?.loadTask = nil
            } catch is CancellationError {
                self?.loadTask = nil
            } catch {
                self?.loadTask = nil
                self?.publish(.unavailable)
            }
        }
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        resolver = PTRideGhostLiveResolver(route: nil)
        publish(.unavailable)
    }

    func update(coordinate: CLLocationCoordinate2D,
                speedKmh: Double,
                rpm: Int,
                timestamp: Date = Date()) {
        let next = resolver.update(
            coordinate: coordinate,
            speedKmh: speedKmh.isFinite ? max(speedKmh, 0) : 0,
            rpm: max(rpm, 0),
            timestamp: timestamp
        )
        publish(next)
    }

    private func publish(_ next: PTRideGhostLiveSnapshot) {
        guard snapshot.availability != next.availability ||
                snapshot.routeProgress != next.routeProgress ||
                snapshot.timeDeltaSeconds != next.timeDeltaSeconds ||
                snapshot.speedDeltaKmh != next.speedDeltaKmh ||
                snapshot.rpmDelta != next.rpmDelta else { return }
        snapshot = next
        onChange?(next)
    }
}

// EN: Replay samples are mapped to the existing XP400 Twin renderer; no second vehicle model is introduced.
// ES: Las muestras se mapean al renderizador Twin XP400 existente; no se introduce otro modelo.
// 中文：回放样本直接映射到现有 XP400 Twin 渲染器，不创建第二套车辆模型。
@MainActor
enum PTRideGhostTwinMapper {
    static func snapshot(for sample: PTRideReplaySample) -> PTVehicleTwinSnapshot {
        let source = PTVehicleTelemetrySource.replay
        let capturedAt = sample.timestamp
        func metric<Value: Equatable & Sendable>(_ value: Value) -> PTVehicleTwinMetric<Value> {
            PTVehicleTwinMetric(
                value: value,
                source: source,
                capturedAt: capturedAt,
                freshness: .fresh,
                isSynthetic: true
            )
        }

        return PTVehicleTwinSnapshot(
            updatedAt: capturedAt,
            speedKmh: metric(sample.speedKmh),
            rpm: metric(Double(sample.rpm)),
            fuelPercent: nil,
            voltage: nil,
            leanDegrees: metric(sample.leanAngle),
            pitchDegrees: nil,
            longitudinalG: metric(sample.gForceX),
            lateralG: metric(sample.gForceY),
            kickstandDown: nil,
            engineState: metric(sample.rpm > 0 ? PTVehicleTwinEngineState.running : .off),
            leftIndicatorOn: nil,
            rightIndicatorOn: nil,
            hazardOn: nil,
            lowBeamOn: nil,
            highBeamOn: nil,
            tcsState: nil,
            absState: nil,
            coordinate: PTVehicleTwinCoordinateSnapshot(
                latitude: sample.latitude,
                longitude: sample.longitude,
                altitude: sample.altitude ?? 0
            ),
            dashboardConnected: false,
            obdConnected: false,
            freshness: .fresh,
            isSynthetic: true
        )
    }
}

// EN: Local fallback copy keeps the new screen usable before every String Catalog locale is exported.
// ES: El texto de respaldo mantiene usable la pantalla antes de exportar todos los locales del catálogo.
// 中文：在所有 String Catalog 语言完成导出前，保留本地回退文案保证页面可用。
@MainActor
enum PTRideGhostCopy {
    enum Key: String {
        case title = "ride_ghost_title"
        case compare = "ride_ghost_compare"
        case live = "ride_ghost_live"
        case enable = "ride_ghost_enable"
        case disable = "ride_ghost_disable"
        case current = "ride_ghost_current"
        case historical = "ride_ghost_historical"
        case loading = "ride_ghost_loading"
        case ready = "ride_ghost_ready"
        case noCurrentRoute = "ride_ghost_no_current_route"
        case noHistoricalRoute = "ride_ghost_no_historical_route"
        case insufficientOverlap = "ride_ghost_insufficient_overlap"
        case outsideOverlap = "ride_ghost_outside_overlap"
        case progress = "ride_ghost_progress"
        case timeDelta = "ride_ghost_time_delta"
        case speedDelta = "ride_ghost_speed_delta"
        case rpmDelta = "ride_ghost_rpm_delta"
        case historicalRPM = "ride_ghost_historical_rpm"
        case selectHistory = "ride_ghost_select_history"
        case noHistory = "ride_ghost_no_history"
        case fallback = "ride_ghost_fallback"
        case roadSurface = "ride_ghost_road_surface"
    }

    private static let englishValues: [Key: String] = [
        .title: "Ghost Ride",
        .compare: "Compare historical ride",
        .live: "Live Ghost",
        .enable: "Show Ghost",
        .disable: "Hide Ghost",
        .current: "Current",
        .historical: "Historical",
        .loading: "Loading Ghost…",
        .ready: "Route aligned",
        .noCurrentRoute: "Current route unavailable",
        .noHistoricalRoute: "No historical route available",
        .insufficientOverlap: "Insufficient route overlap; Ghost disabled",
        .outsideOverlap: "Outside comparison route; waiting to rejoin",
        .progress: "Route progress",
        .timeDelta: "Time delta",
        .speedDelta: "Speed delta",
        .rpmDelta: "RPM delta",
        .historicalRPM: "Historical RPM",
        .selectHistory: "Select historical route",
        .noHistory: "No compatible historical route",
        .fallback: "Ghost appears only after confirmed route overlap and never changes navigation",
        .roadSurface: "Historical road"
    ]

    static func text(_ key: Key) -> String {
        let resolved = PTDashboardConfig.languageFunc(text: key.rawValue)
        guard resolved == key.rawValue else { return resolved }
        let language = PTDashboardConfig.selectedLanguageIdentifier
        let values: [Key: [String: String]] = [
            .title: ["zh-Hans": "Ghost Ride", "zh-Hant": "Ghost Ride", "es": "Ghost Ride", "fr": "Ghost Ride", "de": "Ghost Ride", "it": "Ghost Ride", "ja": "Ghost Ride", "ru": "Ghost Ride", "tr": "Ghost Ride"],
            .compare: ["zh-Hans": "对比历史骑行", "zh-Hant": "對比歷史騎行", "es": "Comparar ruta", "fr": "Comparer le trajet", "de": "Fahrt vergleichen", "it": "Confronta giro", "ja": "走行を比較", "ru": "Сравнить поездки", "tr": "Sürüşü karşılaştır"],
            .live: ["zh-Hans": "实时 Ghost", "zh-Hant": "即時 Ghost", "es": "Ghost en vivo", "fr": "Ghost en direct", "de": "Live-Ghost", "it": "Ghost live", "ja": "ライブ Ghost", "ru": "Ghost в реальном времени", "tr": "Canlı Ghost"],
            .enable: ["zh-Hans": "显示 Ghost", "zh-Hant": "顯示 Ghost", "es": "Mostrar Ghost", "fr": "Afficher Ghost", "de": "Ghost anzeigen", "it": "Mostra Ghost", "ja": "Ghost を表示", "ru": "Показать Ghost", "tr": "Ghost'u göster"],
            .disable: ["zh-Hans": "隐藏 Ghost", "zh-Hant": "隱藏 Ghost", "es": "Ocultar Ghost", "fr": "Masquer Ghost", "de": "Ghost ausblenden", "it": "Nascondi Ghost", "ja": "Ghost を隠す", "ru": "Скрыть Ghost", "tr": "Ghost'u gizle"],
            .current: ["zh-Hans": "当前", "zh-Hant": "目前", "es": "Actual", "fr": "Actuel", "de": "Aktuell", "it": "Attuale", "ja": "現在", "ru": "Текущая", "tr": "Güncel"],
            .historical: ["zh-Hans": "历史", "zh-Hant": "歷史", "es": "Histórica", "fr": "Historique", "de": "Historisch", "it": "Storica", "ja": "履歴", "ru": "Историческая", "tr": "Geçmiş"],
            .loading: ["zh-Hans": "正在加载 Ghost…", "zh-Hant": "正在載入 Ghost…", "es": "Cargando Ghost…", "fr": "Chargement de Ghost…", "de": "Ghost wird geladen…", "it": "Caricamento Ghost…", "ja": "Ghost を読み込み中…", "ru": "Загрузка Ghost…", "tr": "Ghost yükleniyor…"],
            .ready: ["zh-Hans": "路线已对齐", "zh-Hant": "路線已對齊", "es": "Ruta alineada", "fr": "Itinéraire aligné", "de": "Route ausgerichtet", "it": "Percorso allineato", "ja": "ルートを同期", "ru": "Маршрут выровнен", "tr": "Rota hizalandı"],
            .noCurrentRoute: ["zh-Hans": "当前路线不可用", "zh-Hant": "目前路線不可用", "es": "Ruta actual no disponible", "fr": "Trajet actuel indisponible", "de": "Aktuelle Route nicht verfügbar", "it": "Percorso attuale non disponibile", "ja": "現在のルートは利用できません", "ru": "Текущий маршрут недоступен", "tr": "Geçerli rota kullanılamıyor"],
            .noHistoricalRoute: ["zh-Hans": "没有可用历史路线", "zh-Hant": "沒有可用歷史路線", "es": "No hay ruta histórica", "fr": "Aucun trajet historique", "de": "Keine historische Route", "it": "Nessun percorso storico", "ja": "履歴ルートがありません", "ru": "Нет исторического маршрута", "tr": "Geçmiş rota yok"],
            .insufficientOverlap: ["zh-Hans": "路线重叠不足，已安全停用", "zh-Hant": "路線重疊不足，已安全停用", "es": "Superposición insuficiente; Ghost desactivado", "fr": "Chevauchement insuffisant ; Ghost désactivé", "de": "Zu wenig Überlappung; Ghost deaktiviert", "it": "Sovrapposizione insufficiente; Ghost disattivato", "ja": "重複区間が不足するため無効", "ru": "Недостаточное совпадение; Ghost отключён", "tr": "Örtüşme yetersiz; Ghost kapatıldı"],
            .outsideOverlap: ["zh-Hans": "已离开对比路线，等待重新进入", "zh-Hant": "已離開對比路線，等待重新進入", "es": "Fuera de la ruta; esperando reentrada", "fr": "Hors trajet ; attente de retour", "de": "Außerhalb der Route; warte auf Rückkehr", "it": "Fuori percorso; attendo rientro", "ja": "比較ルート外です。復帰を待機中", "ru": "Вне маршрута; ожидание возвращения", "tr": "Rota dışında; yeniden giriş bekleniyor"],
            .progress: ["zh-Hans": "路线进度", "zh-Hant": "路線進度", "es": "Progreso", "fr": "Progression", "de": "Routenfortschritt", "it": "Avanzamento", "ja": "進行状況", "ru": "Прогресс", "tr": "İlerleme"],
            .timeDelta: ["zh-Hans": "时间差", "zh-Hant": "時間差", "es": "Diferencia de tiempo", "fr": "Écart de temps", "de": "Zeitdifferenz", "it": "Differenza tempo", "ja": "時間差", "ru": "Разница времени", "tr": "Zaman farkı"],
            .speedDelta: ["zh-Hans": "速度差", "zh-Hant": "速度差", "es": "Diferencia de velocidad", "fr": "Écart de vitesse", "de": "Geschwindigkeitsdifferenz", "it": "Differenza velocità", "ja": "速度差", "ru": "Разница скорости", "tr": "Hız farkı"],
            .rpmDelta: ["zh-Hans": "转速差", "zh-Hant": "轉速差", "es": "Diferencia de RPM", "fr": "Écart de régime", "de": "Drehzahldifferenz", "it": "Differenza RPM", "ja": "回転数差", "ru": "Разница оборотов", "tr": "Devir farkı"],
            .historicalRPM: ["zh-Hans": "历史转速", "zh-Hant": "歷史轉速", "es": "RPM histórica", "fr": "Régime historique", "de": "Historische Drehzahl", "it": "RPM storici", "ja": "過去の回転数", "ru": "Исторические обороты", "tr": "Geçmiş devir"],
            .selectHistory: ["zh-Hans": "选择历史路线", "zh-Hant": "選擇歷史路線", "es": "Elegir ruta histórica", "fr": "Choisir un trajet historique", "de": "Historische Route wählen", "it": "Scegli percorso storico", "ja": "履歴ルートを選択", "ru": "Выберите исторический маршрут", "tr": "Geçmiş rota seç"],
            .noHistory: ["zh-Hans": "暂无满足条件的历史路线", "zh-Hant": "暫無符合條件的歷史路線", "es": "No hay rutas históricas compatibles", "fr": "Aucun trajet historique compatible", "de": "Keine passende historische Route", "it": "Nessun percorso storico compatibile", "ja": "比較可能な履歴ルートがありません", "ru": "Нет подходящих исторических маршрутов", "tr": "Uygun geçmiş rota yok"],
            .fallback: ["zh-Hans": "Ghost 仅在确认路线重叠时显示，不会改变导航路线", "zh-Hant": "Ghost 僅在確認路線重疊時顯示，不會改變導航路線", "es": "Ghost solo se muestra con una ruta confirmada y no cambia la navegación", "fr": "Ghost s'affiche uniquement avec un trajet confirmé et ne modifie pas la navigation", "de": "Ghost erscheint nur bei bestätigter Überlappung und ändert die Navigation nicht", "it": "Ghost appare solo con sovrapposizione confermata e non modifica la navigazione", "ja": "Ghost はルート重複時だけ表示し、ナビを変更しません", "ru": "Ghost показывается только при подтверждённом совпадении и не меняет навигацию", "tr": "Ghost yalnızca doğrulanmış örtüşmede gösterilir ve navigasyonu değiştirmez"],
            .roadSurface: ["zh-Hans": "历史路况", "zh-Hant": "歷史路況", "es": "Superficie histórica", "fr": "Chaussée historique", "de": "Historischer Straßenbelag", "it": "Fondo storico", "ja": "過去の路面", "ru": "Историческое покрытие", "tr": "Geçmiş yol yüzeyi"]
        ]
        return values[key]?[language] ?? englishValues[key] ?? key.rawValue
    }

    static func roadSurfaceText(_ quality: PTRoadSurfaceQuality) -> String {
        let key: String
        switch quality {
        case .smooth: key = "road_surface_smooth"
        case .moderate: key = "road_surface_moderate"
        case .rough: key = "road_surface_rough"
        case .severe: key = "road_surface_severe"
        case .unknown: key = "road_surface_no_data"
        }
        return "\(text(.roadSurface)): \(PTDashboardConfig.languageFunc(text: key))"
    }
}
