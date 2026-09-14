//
//  PTUnifiedVehicleTelemetry.swift
//  CrazyDashboard
//
//  EN: Build 58 keeps vehicle signals independent from transport and adapter state.
//  ES: Build 58 mantiene las señales del vehículo separadas del transporte y del estado del adaptador.
//  中文：Build 58 将车辆信号与传输层、适配器状态严格分离。
//

import Foundation
import CoreLocation
import PooTools

public nonisolated enum PTVehicleTelemetrySignal: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case speed
    case rpm
    case fuel
    case batteryVoltage
    case engineTemperature
    case abs
    case tcs
    case lights
    case leftTurn
    case rightTurn
    case hazard
    case lean
    case pitch
    case yaw
    case location
    case trip
    case odometer
    case range
    case maintenanceDistance
    case engineStatus
    case kickstandDown
    case frontWheelSpeed
    case gForceX
    case gForceY
    case gForceZ

    public func accepts(_ value: PTVehicleTelemetryValue) -> Bool {
        switch (self, value) {
        case (.speed, .double(let value)),
             (.frontWheelSpeed, .double(let value)):
            return value.isFinite && (0...400).contains(value)
        case (.rpm, .integer(let value)):
            return (0...30_000).contains(value)
        case (.fuel, .integer(let value)):
            return (0...100).contains(value)
        case (.batteryVoltage, .double(let value)):
            return value.isFinite && (0...20).contains(value)
        case (.engineTemperature, .double(let value)):
            return value.isFinite && (-50...220).contains(value)
        case (.lean, .double(let value)),
             (.pitch, .double(let value)),
             (.yaw, .double(let value)):
            return value.isFinite && Swift.abs(value) <= 360
        case (.gForceX, .double(let value)),
             (.gForceY, .double(let value)),
             (.gForceZ, .double(let value)):
            return value.isFinite && Swift.abs(value) <= 50
        case (.trip, .double(let value)),
             (.odometer, .double(let value)),
             (.range, .double(let value)):
            return value.isFinite && value >= 0
        case (.maintenanceDistance, .integer(let value)):
            return value >= 0
        case (.engineStatus, .integer(let value)):
            return (0...3).contains(value)
        case (.abs, .boolean(_)),
             (.tcs, .boolean(_)),
             (.lights, .boolean(_)),
             (.leftTurn, .boolean(_)),
             (.rightTurn, .boolean(_)),
             (.hazard, .boolean(_)),
             (.kickstandDown, .boolean(_)):
            return true
        case (.location, .location(let latitude, let longitude, let altitude)):
            return latitude.isFinite
                && longitude.isFinite
                && altitude.isFinite
                && (-90...90).contains(latitude)
                && (-180...180).contains(longitude)
        default:
            return false
        }
    }
}

public nonisolated enum PTVehicleTelemetryValue: Codable, Equatable, Sendable {
    case double(Double)
    case integer(Int)
    case boolean(Bool)
    case location(latitude: Double, longitude: Double, altitude: Double)

    private enum CodingKeys: String, CodingKey {
        case kind
        case doubleValue
        case integerValue
        case booleanValue
        case latitude
        case longitude
        case altitude
    }

    private enum Kind: String, Codable {
        case double
        case integer
        case boolean
        case location
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .double:
            self = .double(try container.decode(Double.self, forKey: .doubleValue))
        case .integer:
            self = .integer(try container.decode(Int.self, forKey: .integerValue))
        case .boolean:
            self = .boolean(try container.decode(Bool.self, forKey: .booleanValue))
        case .location:
            self = .location(
                latitude: try container.decode(Double.self, forKey: .latitude),
                longitude: try container.decode(Double.self, forKey: .longitude),
                altitude: try container.decode(Double.self, forKey: .altitude)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .double(let value):
            try container.encode(Kind.double, forKey: .kind)
            try container.encode(value, forKey: .doubleValue)
        case .integer(let value):
            try container.encode(Kind.integer, forKey: .kind)
            try container.encode(value, forKey: .integerValue)
        case .boolean(let value):
            try container.encode(Kind.boolean, forKey: .kind)
            try container.encode(value, forKey: .booleanValue)
        case .location(let latitude, let longitude, let altitude):
            try container.encode(Kind.location, forKey: .kind)
            try container.encode(latitude, forKey: .latitude)
            try container.encode(longitude, forKey: .longitude)
            try container.encode(altitude, forKey: .altitude)
        }
    }
}

public nonisolated struct PTVehicleTelemetryObservation: Codable, Equatable, Sendable {
    public let signal: PTVehicleTelemetrySignal
    public let value: PTVehicleTelemetryValue
    public let source: PTVehicleTelemetrySource
    public let capturedAt: Date
    public let confidence: Double
    public let isSynthetic: Bool

    public init(
        signal: PTVehicleTelemetrySignal,
        value: PTVehicleTelemetryValue,
        source: PTVehicleTelemetrySource,
        capturedAt: Date = Date(),
        confidence: Double = 1,
        isSynthetic: Bool = false
    ) {
        self.signal = signal
        self.value = value
        self.source = source
        self.capturedAt = capturedAt
        self.confidence = confidence.isFinite ? min(max(confidence, 0), 1) : 0
        self.isSynthetic = isSynthetic || source.isMock || source == .replay
    }

    public var isValid: Bool {
        signal.accepts(value)
    }
}

public nonisolated enum PTVehicleTelemetryMode: String, Codable, Equatable, Sendable {
    case live
    case replay
}

public nonisolated struct PTVehicleTelemetryResolvedValue: Codable, Equatable, Sendable {
    public let signal: PTVehicleTelemetrySignal
    public let value: PTVehicleTelemetryValue
    public let source: PTVehicleTelemetrySource
    public let capturedAt: Date
    public let freshness: PTTelemetryFreshness
    public let confidence: Double
    public let isSynthetic: Bool

    public init(
        signal: PTVehicleTelemetrySignal,
        value: PTVehicleTelemetryValue,
        source: PTVehicleTelemetrySource,
        capturedAt: Date,
        freshness: PTTelemetryFreshness,
        confidence: Double,
        isSynthetic: Bool
    ) {
        self.signal = signal
        self.value = value
        self.source = source
        self.capturedAt = capturedAt
        self.freshness = freshness
        self.confidence = confidence.isFinite ? min(max(confidence, 0), 1) : 0
        self.isSynthetic = isSynthetic || source.isMock || source == .replay
    }
}

public nonisolated struct PTUnifiedVehicleTelemetrySnapshot: Codable, Equatable, Sendable {
    public let values: [PTVehicleTelemetryResolvedValue]
    public let updatedAt: Date
    public let mode: PTVehicleTelemetryMode

    public init(
        values: [PTVehicleTelemetryResolvedValue] = [],
        updatedAt: Date = Date(),
        mode: PTVehicleTelemetryMode = .live
    ) {
        self.values = values.sorted { $0.signal.rawValue < $1.signal.rawValue }
        self.updatedAt = updatedAt
        self.mode = mode
    }

    public static let empty = PTUnifiedVehicleTelemetrySnapshot(updatedAt: .distantPast)

    public func value(for signal: PTVehicleTelemetrySignal) -> PTVehicleTelemetryResolvedValue? {
        values.first { $0.signal == signal }
    }

    public func double(for signal: PTVehicleTelemetrySignal) -> Double? {
        guard case .double(let value) = value(for: signal)?.value else { return nil }
        return value
    }

    public func integer(for signal: PTVehicleTelemetrySignal) -> Int? {
        guard case .integer(let value) = value(for: signal)?.value else { return nil }
        return value
    }

    public func boolean(for signal: PTVehicleTelemetrySignal) -> Bool? {
        guard case .boolean(let value) = value(for: signal)?.value else { return nil }
        return value
    }

    public var location: (latitude: Double, longitude: Double, altitude: Double)? {
        guard case .location(let latitude, let longitude, let altitude) = value(for: .location)?.value else {
            return nil
        }
        return (latitude, longitude, altitude)
    }

    public var speedKmh: Double? { double(for: .speed) }
    public var rpm: Int? { integer(for: .rpm) }
    public var fuelPercent: Int? { integer(for: .fuel) }
    public var batteryVoltage: Double? { double(for: .batteryVoltage) }
    public var engineTemperatureC: Double? { double(for: .engineTemperature) }
    public var absLightOn: Bool? { boolean(for: .abs) }
    public var tcsOn: Bool? { boolean(for: .tcs) }
    public var lightsOn: Bool? { boolean(for: .lights) }
    public var leftTurnOn: Bool? { boolean(for: .leftTurn) }
    public var rightTurnOn: Bool? { boolean(for: .rightTurn) }
    public var hazardOn: Bool? { boolean(for: .hazard) }
    public var leanAngle: Double? { double(for: .lean) }
    public var pitchAngle: Double? { double(for: .pitch) }
    public var containsSyntheticData: Bool { values.contains(where: \.isSynthetic) }
}

public nonisolated enum PTVehicleTelemetryFreshnessPolicy {
    public static func maximumAge(for signal: PTVehicleTelemetrySignal) -> TimeInterval {
        switch signal {
        case .speed, .frontWheelSpeed, .lean, .pitch, .yaw, .gForceX, .gForceY, .gForceZ:
            return 2
        case .rpm, .engineTemperature, .abs, .tcs, .lights, .leftTurn, .rightTurn, .hazard, .engineStatus, .kickstandDown:
            return 5
        case .fuel, .batteryVoltage, .location:
            return 15
        case .trip, .odometer, .range, .maintenanceDistance:
            return 120
        }
    }
}

public nonisolated struct PTVehicleTelemetryResolver: Sendable {
    private struct CandidateKey: Hashable, Sendable {
        let source: PTVehicleTelemetrySource
        let isSynthetic: Bool
    }

    private var candidates: [PTVehicleTelemetrySignal: [CandidateKey: PTVehicleTelemetryObservation]] = [:]

    public init() {}

    public mutating func ingest(_ observations: [PTVehicleTelemetryObservation]) {
        for observation in observations where observation.isValid {
            var sourceCandidates = candidates[observation.signal] ?? [:]
            let key = CandidateKey(source: observation.source, isSynthetic: observation.isSynthetic)
            if let existing = sourceCandidates[key], existing.capturedAt > observation.capturedAt {
                continue
            }
            sourceCandidates[key] = observation
            candidates[observation.signal] = sourceCandidates
        }
    }

    public mutating func remove(source: PTVehicleTelemetrySource) {
        for signal in candidates.keys {
            candidates[signal] = candidates[signal]?.filter { $0.key.source != source }
            if candidates[signal]?.isEmpty == true {
                candidates[signal] = nil
            }
        }
    }

    public mutating func remove(domain: PTVehicleTelemetrySourceDomain) {
        for signal in candidates.keys {
            candidates[signal] = candidates[signal]?.filter { $0.key.source.domain != domain }
            if candidates[signal]?.isEmpty == true {
                candidates[signal] = nil
            }
        }
    }

    public mutating func reset() {
        candidates.removeAll(keepingCapacity: true)
    }

    public func snapshot(
        at date: Date = Date(),
        mode: PTVehicleTelemetryMode = .live
    ) -> PTUnifiedVehicleTelemetrySnapshot {
        let resolved = candidates.compactMap { signal, sourceCandidates -> PTVehicleTelemetryResolvedValue? in
            guard let observation = sourceCandidates.values.sorted(by: { lhs, rhs in
                let lhsFresh = lhs.capturedAt <= date
                    && date.timeIntervalSince(lhs.capturedAt) <= PTVehicleTelemetryFreshnessPolicy.maximumAge(for: signal)
                let rhsFresh = rhs.capturedAt <= date
                    && date.timeIntervalSince(rhs.capturedAt) <= PTVehicleTelemetryFreshnessPolicy.maximumAge(for: signal)
                if lhs.source.domain == rhs.source.domain,
                   lhs.isSynthetic != rhs.isSynthetic {
                    return !lhs.isSynthetic
                }
                if lhsFresh != rhsFresh { return lhsFresh }
                let lhsPriority = Self.priority(for: lhs.source)
                let rhsPriority = Self.priority(for: rhs.source)
                if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
                if lhs.isSynthetic != rhs.isSynthetic { return !lhs.isSynthetic }
                if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
                return lhs.capturedAt > rhs.capturedAt
            }).first else {
                return nil
            }

            let freshness: PTTelemetryFreshness
            if observation.capturedAt <= date,
               date.timeIntervalSince(observation.capturedAt) <= PTVehicleTelemetryFreshnessPolicy.maximumAge(for: signal) {
                freshness = .fresh
            } else {
                freshness = .stale
            }

            return PTVehicleTelemetryResolvedValue(
                signal: signal,
                value: observation.value,
                source: observation.source,
                capturedAt: observation.capturedAt,
                freshness: freshness,
                confidence: observation.confidence,
                isSynthetic: observation.isSynthetic
            )
        }
        return PTUnifiedVehicleTelemetrySnapshot(values: resolved, updatedAt: date, mode: mode)
    }

    private static func priority(for source: PTVehicleTelemetrySource) -> Int {
        switch source.domain {
        case .xp400BLE:
            return 500
        case .obd:
            return 400
        case .gps, .motion:
            return 300
        case .calculated:
            return 200
        case .replay:
            return 100
        case .unknown:
            return 0
        }
    }
}

public nonisolated enum PTXP400TelemetryAdapter {
    public static func observations(
        from snapshot: PTVehicleTelemetrySnapshot,
        at _: Date = Date()
    ) -> [PTVehicleTelemetryObservation] {
        var result: [PTVehicleTelemetryObservation] = []
        append(snapshot.dashboardSpeedKmh, signal: .speed, sourceDomain: .xp400BLE, to: &result)
        append(snapshot.frontWheelSpeedKmh, signal: .frontWheelSpeed, sourceDomain: .xp400BLE, to: &result)
        append(snapshot.engineRPM, signal: .rpm, sourceDomain: .xp400BLE, to: &result)
        append(snapshot.fuelPercent, signal: .fuel, sourceDomain: .xp400BLE, to: &result)
        append(snapshot.tripKm, signal: .trip, sourceDomain: .xp400BLE, to: &result)
        append(snapshot.odometerKm, signal: .odometer, sourceDomain: .xp400BLE, to: &result)
        append(snapshot.batteryVoltage, signal: .batteryVoltage, sourceDomain: .xp400BLE, to: &result)
        append(snapshot.engineStatus, signal: .engineStatus, sourceDomain: .xp400BLE, to: &result)
        append(snapshot.kickstandDown, signal: .kickstandDown, sourceDomain: .xp400BLE, to: &result)
        append(snapshot.leftTurnOn, signal: .leftTurn, sourceDomain: .xp400BLE, to: &result)
        append(snapshot.rightTurnOn, signal: .rightTurn, sourceDomain: .xp400BLE, to: &result)
        append(snapshot.hazardOn, signal: .hazard, sourceDomain: .xp400BLE, to: &result)
        append(snapshot.absLightOn, signal: .abs, sourceDomain: .xp400BLE, to: &result)
        append(snapshot.rangeKm, signal: .range, sourceDomain: .xp400BLE, to: &result)
        append(snapshot.maintenanceDistanceKm, signal: .maintenanceDistance, sourceDomain: .xp400BLE, to: &result)
        return result
    }

    private static func append<T: Sendable>(
        _ sample: PTTelemetrySample<T>?,
        signal: PTVehicleTelemetrySignal,
        sourceDomain: PTVehicleTelemetrySourceDomain,
        to result: inout [PTVehicleTelemetryObservation]
    ) {
        guard let sample, sample.source.domain == sourceDomain else { return }
        var convertedValue: PTVehicleTelemetryValue?
        switch sample.value {
        case let doubleValue as Double:
            convertedValue = .double(doubleValue)
        case let integerValue as Int:
            convertedValue = .integer(integerValue)
        case let booleanValue as Bool:
            convertedValue = .boolean(booleanValue)
        default:
            convertedValue = nil
        }
        guard let convertedValue else { return }
        result.append(
            PTVehicleTelemetryObservation(
                signal: signal,
                value: convertedValue,
                source: .xp400BLE,
                capturedAt: sample.capturedAt,
                isSynthetic: sample.source.isMock
            )
        )
    }
}

public nonisolated enum PTOBDTelemetryAdapter {
    public static func observations(
        from snapshot: PTVehicleTelemetrySnapshot,
        at _: Date = Date()
    ) -> [PTVehicleTelemetryObservation] {
        var result: [PTVehicleTelemetryObservation] = []
        append(snapshot.obdSpeedKmh, signal: .speed, to: &result)
        append(snapshot.engineRPM, signal: .rpm, to: &result)
        return result
    }

    private static func append<T: Sendable>(
        _ sample: PTTelemetrySample<T>?,
        signal: PTVehicleTelemetrySignal,
        to result: inout [PTVehicleTelemetryObservation]
    ) {
        guard let sample, sample.source.isOBDSource else { return }
        var convertedValue: PTVehicleTelemetryValue?
        switch sample.value {
        case let doubleValue as Double:
            convertedValue = .double(doubleValue)
        case let integerValue as Int:
            convertedValue = .integer(integerValue)
        case let booleanValue as Bool:
            convertedValue = .boolean(booleanValue)
        default:
            convertedValue = nil
        }
        guard let convertedValue else { return }
        result.append(
            PTVehicleTelemetryObservation(
                signal: signal,
                value: convertedValue,
                source: .obd,
                capturedAt: sample.capturedAt,
                isSynthetic: sample.source.isMock
            )
        )
    }
}

public nonisolated enum PTGPSMotionTelemetryAdapter {
    public static func observations(
        from location: CLLocation,
        capturedAt fallbackDate: Date = Date()
    ) -> [PTVehicleTelemetryObservation] {
        let coordinate = location.coordinate
        guard coordinate.latitude.isFinite,
              coordinate.longitude.isFinite,
              (-90...90).contains(coordinate.latitude),
              (-180...180).contains(coordinate.longitude) else {
            return []
        }

        let capturedAt = location.timestamp <= Date() ? location.timestamp : fallbackDate
        let altitude = location.altitude.isFinite ? location.altitude : 0
        let accuracy = location.horizontalAccuracy >= 0 ? 1.0 : 0.6
        var result = [
            PTVehicleTelemetryObservation(
                signal: .location,
                value: .location(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    altitude: altitude
                ),
                source: .gps,
                capturedAt: capturedAt,
                confidence: accuracy
            )
        ]

        let speedKmh = location.speed * 3.6
        if location.speed >= 0, speedKmh.isFinite {
            result.append(
                PTVehicleTelemetryObservation(
                    signal: .speed,
                    value: .double(speedKmh),
                    source: .gps,
                    capturedAt: capturedAt,
                    confidence: accuracy
                )
            )
        }
        return result
    }

    public static func observations(
        from motion: PTMotionData,
        capturedAt: Date = Date()
    ) -> [PTVehicleTelemetryObservation] {
        [
            make(.lean, motion.roll, capturedAt: capturedAt),
            make(.pitch, motion.pitch, capturedAt: capturedAt),
            make(.yaw, motion.yaw, capturedAt: capturedAt),
            make(.gForceX, motion.gForceX, capturedAt: capturedAt),
            make(.gForceY, motion.gForceY, capturedAt: capturedAt),
            make(.gForceZ, motion.gForceZ, capturedAt: capturedAt)
        ]
    }

    private static func make(
        _ signal: PTVehicleTelemetrySignal,
        _ value: Double,
        capturedAt: Date
    ) -> PTVehicleTelemetryObservation {
        PTVehicleTelemetryObservation(
            signal: signal,
            value: .double(value),
            source: .motion,
            capturedAt: capturedAt
        )
    }
}

public typealias PTOBDAdapterMode = PTYMOBDAdapterMode

public nonisolated struct PTOBDAdapterSnapshot: Codable, Equatable, Sendable {
    public let vendor: String?
    public let model: String?
    public let firmwareVersion: String?
    public let transport: PTOBDTransportKind
    public let isOfficialYMOBD: Bool
    public let mode: PTOBDAdapterMode

    public init(
        vendor: String? = nil,
        model: String? = nil,
        firmwareVersion: String? = nil,
        transport: PTOBDTransportKind = .unknown,
        isOfficialYMOBD: Bool = false,
        mode: PTOBDAdapterMode = .disconnected
    ) {
        self.vendor = Self.normalized(vendor)
        self.model = Self.normalized(model)
        self.firmwareVersion = Self.normalized(firmwareVersion)
        self.transport = transport
        self.isOfficialYMOBD = isOfficialYMOBD
        self.mode = mode
    }

    public init(
        capabilities: PTELM327Capabilities,
        mode: PTOBDAdapterMode = .disconnected,
        firmwareVersion: String? = nil
    ) {
        let vendorCapabilities = capabilities.vendor
        self.init(
            vendor: vendorCapabilities == nil ? nil : "YMOBD",
            model: vendorCapabilities?.deviceType,
            firmwareVersion: firmwareVersion,
            transport: capabilities.transportKind,
            isOfficialYMOBD: vendorCapabilities?.isOfficial == true,
            mode: mode
        )
    }

    public static let unavailable = PTOBDAdapterSnapshot()

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : String(normalized.prefix(128))
    }
}
