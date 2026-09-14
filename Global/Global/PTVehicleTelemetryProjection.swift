//
//  PTVehicleTelemetryProjection.swift
//  CrazyDashboard
//
//  EN: Centralizes freshness and source-aware reads for every read-only presentation surface.
//  ES: Centraliza las lecturas conscientes de frescura y fuente para cada superficie de presentación.
//  中文：集中管理所有只读展示面的新鲜度和来源感知读取规则。
//

import Foundation

public nonisolated struct PTVehicleTelemetryProjection: Equatable, Sendable {
    public let snapshot: PTUnifiedVehicleTelemetrySnapshot
    public let scope: Scope

    public enum Scope: String, Codable, Equatable, Sendable {
        case dashboard
        case ride
        case widget
        case watch
        case carPlay
        case instrument
    }

    public init(snapshot: PTUnifiedVehicleTelemetrySnapshot, scope: Scope) {
        self.snapshot = snapshot
        self.scope = scope
    }

    public func value(
        for signal: PTVehicleTelemetrySignal,
        allowingStale: Bool = false
    ) -> PTVehicleTelemetryResolvedValue? {
        guard let resolved = snapshot.value(for: signal) else { return nil }
        guard allowingStale || resolved.freshness == .fresh else { return nil }
        return resolved
    }

    public func double(for signal: PTVehicleTelemetrySignal, allowingStale: Bool = false) -> Double? {
        guard case .double(let value) = value(for: signal, allowingStale: allowingStale)?.value else { return nil }
        return value
    }

    public func integer(for signal: PTVehicleTelemetrySignal, allowingStale: Bool = false) -> Int? {
        guard case .integer(let value) = value(for: signal, allowingStale: allowingStale)?.value else { return nil }
        return value
    }

    public func boolean(for signal: PTVehicleTelemetrySignal, allowingStale: Bool = false) -> Bool? {
        guard case .boolean(let value) = value(for: signal, allowingStale: allowingStale)?.value else { return nil }
        return value
    }

    public var speedKmh: Double? { double(for: .speed) }
    public var fuelPercent: Int? { integer(for: .fuel) }
    public var tripKm: Double? { double(for: .trip) }
    public var odometerKm: Double? { double(for: .odometer) }
    public var rangeKm: Double? { double(for: .range) }
    public var maintenanceDistanceKm: Int? { integer(for: .maintenanceDistance) }
    public var isSynthetic: Bool { snapshot.containsSyntheticData }
}

// EN: Type aliases preserve the plan's domain vocabulary without creating duplicate data models.
// ES: Los alias conservan el vocabulario por dominio sin crear modelos de datos duplicados.
// 中文：类型别名保留各业务域的术语，同时避免创建重复数据模型。
public typealias PTDashboardProjection = PTVehicleTelemetryProjection
public typealias PTRideProjection = PTVehicleTelemetryProjection
public typealias PTWidgetProjection = PTVehicleTelemetryProjection
public typealias PTWatchProjection = PTVehicleTelemetryProjection
public typealias PTCarPlayProjection = PTVehicleTelemetryProjection
public typealias PTInstrumentProjection = PTVehicleTelemetryProjection

public enum PTVehicleTelemetryProjections {
    public static func dashboard(from snapshot: PTUnifiedVehicleTelemetrySnapshot) -> PTDashboardProjection {
        PTVehicleTelemetryProjection(snapshot: snapshot, scope: .dashboard)
    }

    public static func ride(from snapshot: PTUnifiedVehicleTelemetrySnapshot) -> PTRideProjection {
        PTVehicleTelemetryProjection(snapshot: snapshot, scope: .ride)
    }

    public static func widget(from snapshot: PTUnifiedVehicleTelemetrySnapshot) -> PTWidgetProjection {
        PTVehicleTelemetryProjection(snapshot: snapshot, scope: .widget)
    }

    public static func watch(from snapshot: PTUnifiedVehicleTelemetrySnapshot) -> PTWatchProjection {
        PTVehicleTelemetryProjection(snapshot: snapshot, scope: .watch)
    }

    public static func carPlay(from snapshot: PTUnifiedVehicleTelemetrySnapshot) -> PTCarPlayProjection {
        PTVehicleTelemetryProjection(snapshot: snapshot, scope: .carPlay)
    }

    public static func instrument(from snapshot: PTUnifiedVehicleTelemetrySnapshot) -> PTInstrumentProjection {
        PTVehicleTelemetryProjection(snapshot: snapshot, scope: .instrument)
    }
}

