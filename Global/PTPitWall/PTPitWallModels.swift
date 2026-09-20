//
//  PTPitWallModels.swift
//  CrazyDashboard
//
//  EN: Read-only, privacy-filtered models for the Build 84 Pit Wall.
//  ES: Modelos de solo lectura y filtrados por privacidad para el Pit Wall de Build 84.
//  中文：Build 84 Pit Wall 使用的只读、隐私过滤数据模型。
//

import Foundation

// EN: Coordinates are deliberately reduced to a map point; no vehicle identity is carried here.
// ES: Las coordenadas se reducen deliberadamente a un punto del mapa; aquí no se transporta identidad del vehículo.
// 中文：坐标有意缩减为地图点，这里不携带任何车辆身份信息。
public nonisolated struct PTPitWallCoordinate: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public nonisolated struct PTPitWallSample: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let speedKmh: Double?
    public let rpm: Int?
    public let coordinate: PTPitWallCoordinate?

    public init(
        capturedAt: Date,
        speedKmh: Double?,
        rpm: Int?,
        coordinate: PTPitWallCoordinate?
    ) {
        self.capturedAt = capturedAt
        self.speedKmh = speedKmh
        self.rpm = rpm
        self.coordinate = coordinate
    }
}

// EN: Events describe only safe state transitions, never raw protocol traffic or error payloads.
// ES: Los eventos solo describen transiciones de estado seguras, nunca tráfico de protocolo ni cargas de error.
// 中文：事件只描述安全的状态变化，绝不包含原始协议流量或错误载荷。
public nonisolated struct PTPitWallEvent: Codable, Equatable, Sendable {
    public let occurredAt: Date
    public let kind: String
    public let context: String

    public init(occurredAt: Date, kind: String, context: String) {
        self.occurredAt = occurredAt
        self.kind = kind
        self.context = context
    }
}

public nonisolated struct PTPitWallRollingSeries: Codable, Equatable, Sendable {
    public let maximumCount: Int
    public private(set) var samples: [PTPitWallSample]

    public init(maximumCount: Int = 60, samples: [PTPitWallSample] = []) {
        self.maximumCount = max(1, maximumCount)
        self.samples = Array(samples.suffix(max(1, maximumCount)))
    }

    public mutating func append(_ sample: PTPitWallSample) {
        samples.append(sample)
        if samples.count > maximumCount {
            samples.removeFirst(samples.count - maximumCount)
        }
    }
}

public nonisolated struct PTPitWallSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let updatedAt: Date
    public let dashboardConnected: Bool
    public let obdConnected: Bool
    public let context: String
    public let speedKmh: Double?
    public let rpm: Int?
    public let fuelPercent: Double?
    public let voltage: Double?
    public let leanDegrees: Double?
    public let tcsState: String?
    public let absState: String?
    public let kickstandDown: Bool?
    public let engineState: String?
    public let freshness: String
    public let isSynthetic: Bool
    public let coordinate: PTPitWallCoordinate?
    public let samples: [PTPitWallSample]
    public let events: [PTPitWallEvent]

    public init(
        schemaVersion: Int = PTPitWallSnapshot.currentSchemaVersion,
        generatedAt: Date = Date(),
        updatedAt: Date,
        dashboardConnected: Bool,
        obdConnected: Bool,
        context: String,
        speedKmh: Double?,
        rpm: Int?,
        fuelPercent: Double?,
        voltage: Double?,
        leanDegrees: Double?,
        tcsState: String?,
        absState: String?,
        kickstandDown: Bool?,
        engineState: String?,
        freshness: String,
        isSynthetic: Bool,
        coordinate: PTPitWallCoordinate?,
        samples: [PTPitWallSample],
        events: [PTPitWallEvent]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.updatedAt = updatedAt
        self.dashboardConnected = dashboardConnected
        self.obdConnected = obdConnected
        self.context = context
        self.speedKmh = speedKmh
        self.rpm = rpm
        self.fuelPercent = fuelPercent
        self.voltage = voltage
        self.leanDegrees = leanDegrees
        self.tcsState = tcsState
        self.absState = absState
        self.kickstandDown = kickstandDown
        self.engineState = engineState
        self.freshness = freshness
        self.isSynthetic = isSynthetic
        self.coordinate = coordinate
        self.samples = Array(samples.suffix(60))
        self.events = Array(events.suffix(24))
    }

    public static let empty = PTPitWallSnapshot(
        updatedAt: .distantPast,
        dashboardConnected: false,
        obdConnected: false,
        context: "parked",
        speedKmh: nil,
        rpm: nil,
        fuelPercent: nil,
        voltage: nil,
        leanDegrees: nil,
        tcsState: nil,
        absState: nil,
        kickstandDown: nil,
        engineState: nil,
        freshness: "unavailable",
        isSynthetic: false,
        coordinate: nil,
        samples: [],
        events: []
    )
}

// EN: The serializer is the privacy boundary for the browser; it rounds location and emits only this model.
// ES: El serializador es el límite de privacidad del navegador; redondea la ubicación y solo emite este modelo.
// 中文：序列化器是浏览器侧的隐私边界，会舍入位置并且只输出本模型。
public enum PTPitWallSnapshotSerializer {
    public static func data(from snapshot: PTPitWallSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(sanitized(snapshot))
    }

    public static func sanitized(_ snapshot: PTPitWallSnapshot) -> PTPitWallSnapshot {
        PTPitWallSnapshot(
            schemaVersion: snapshot.schemaVersion,
            generatedAt: snapshot.generatedAt,
            updatedAt: snapshot.updatedAt,
            dashboardConnected: snapshot.dashboardConnected,
            obdConnected: snapshot.obdConnected,
            context: snapshot.context,
            speedKmh: rounded(snapshot.speedKmh, places: 1),
            rpm: snapshot.rpm,
            fuelPercent: rounded(snapshot.fuelPercent, places: 1),
            voltage: rounded(snapshot.voltage, places: 2),
            leanDegrees: rounded(snapshot.leanDegrees, places: 1),
            tcsState: snapshot.tcsState,
            absState: snapshot.absState,
            kickstandDown: snapshot.kickstandDown,
            engineState: snapshot.engineState,
            freshness: snapshot.freshness,
            isSynthetic: snapshot.isSynthetic,
            coordinate: snapshot.coordinate.map { coordinate in
                PTPitWallCoordinate(
                    latitude: rounded(coordinate.latitude, places: 5) ?? 0,
                    longitude: rounded(coordinate.longitude, places: 5) ?? 0
                )
            },
            samples: snapshot.samples.map { sample in
                PTPitWallSample(
                    capturedAt: sample.capturedAt,
                    speedKmh: rounded(sample.speedKmh, places: 1),
                    rpm: sample.rpm,
                    coordinate: sample.coordinate.map { coordinate in
                        PTPitWallCoordinate(
                            latitude: rounded(coordinate.latitude, places: 5) ?? 0,
                            longitude: rounded(coordinate.longitude, places: 5) ?? 0
                        )
                    }
                )
            },
            events: snapshot.events
        )
    }

    private static func rounded(_ value: Double?, places: Int) -> Double? {
        guard let value, value.isFinite else { return nil }
        let factor = pow(10, Double(places))
        return (value * factor).rounded() / factor
    }
}
