//
//  PTWidgetSharedStatus.swift
//  CrazyDashboard
//
//  Shared read-only vehicle status used by the iOS app, Widget extension and
//  Watch app. Keep the keys stable because older installed versions already
//  use them in the App Group defaults.
//

import Foundation

public enum PTWidgetDataKeys {
    public static let fuelLevel = "widget_fuelLevel"
    public static let tripKm = "widget_tripKm"
    public static let isConnected = "widget_isConnected"
    public static let parkedLat = "widget_parkedLat"
    public static let parkedLon = "widget_parkedLon"
    public static let address = "widget_parkedAddress"
    public static let lastUpdateTime = "widget_lastUpdateTime"
}

public struct PTWidgetSharedStatus: Codable, Equatable, Sendable {
    public let fuelLevel: Int
    public let tripKm: Double
    public let isConnected: Bool
    public let parkedLat: Double
    public let parkedLon: Double
    public let address: String
    public let lastUpdateTime: Date

    public init(
        fuelLevel: Int,
        tripKm: Double,
        isConnected: Bool,
        parkedLat: Double,
        parkedLon: Double,
        address: String,
        lastUpdateTime: Date
    ) {
        self.fuelLevel = fuelLevel
        self.tripKm = tripKm
        self.isConnected = isConnected
        self.parkedLat = parkedLat
        self.parkedLon = parkedLon
        self.address = address
        self.lastUpdateTime = lastUpdateTime
    }

    public static let placeholder = PTWidgetSharedStatus(
        fuelLevel: 0,
        tripKm: 0,
        isConnected: false,
        parkedLat: 0,
        parkedLon: 0,
        address: "暂无停车位置记录",
        lastUpdateTime: .distantPast
    )

    public init?(applicationContext: [String: Any]) {
        guard
            let fuelLevel = Self.intValue(applicationContext[PTWidgetDataKeys.fuelLevel]),
            let tripKm = Self.doubleValue(applicationContext[PTWidgetDataKeys.tripKm]),
            let isConnected = Self.boolValue(applicationContext[PTWidgetDataKeys.isConnected]),
            let parkedLat = Self.doubleValue(applicationContext[PTWidgetDataKeys.parkedLat]),
            let parkedLon = Self.doubleValue(applicationContext[PTWidgetDataKeys.parkedLon]),
            let address = applicationContext[PTWidgetDataKeys.address] as? String,
            let timestamp = Self.doubleValue(applicationContext[PTWidgetDataKeys.lastUpdateTime])
        else {
            return nil
        }

        self.init(
            fuelLevel: fuelLevel,
            tripKm: tripKm,
            isConnected: isConnected,
            parkedLat: parkedLat,
            parkedLon: parkedLon,
            address: address,
            lastUpdateTime: Date(timeIntervalSince1970: timestamp)
        )
    }

    public init?(defaults: UserDefaults?) {
        guard let defaults,
              defaults.object(forKey: PTWidgetDataKeys.lastUpdateTime) != nil else {
            return nil
        }

        self.init(
            fuelLevel: defaults.integer(forKey: PTWidgetDataKeys.fuelLevel),
            tripKm: defaults.double(forKey: PTWidgetDataKeys.tripKm),
            isConnected: defaults.bool(forKey: PTWidgetDataKeys.isConnected),
            parkedLat: defaults.double(forKey: PTWidgetDataKeys.parkedLat),
            parkedLon: defaults.double(forKey: PTWidgetDataKeys.parkedLon),
            address: defaults.string(forKey: PTWidgetDataKeys.address) ?? PTWidgetSharedStatus.placeholder.address,
            lastUpdateTime: Date(timeIntervalSince1970: defaults.double(forKey: PTWidgetDataKeys.lastUpdateTime))
        )
    }

    public static func read(from defaults: UserDefaults?) -> PTWidgetSharedStatus {
        PTWidgetSharedStatus(defaults: defaults) ?? .placeholder
    }

    public func write(to defaults: UserDefaults) {
        defaults.set(fuelLevel, forKey: PTWidgetDataKeys.fuelLevel)
        defaults.set(tripKm, forKey: PTWidgetDataKeys.tripKm)
        defaults.set(isConnected, forKey: PTWidgetDataKeys.isConnected)
        defaults.set(parkedLat, forKey: PTWidgetDataKeys.parkedLat)
        defaults.set(parkedLon, forKey: PTWidgetDataKeys.parkedLon)
        defaults.set(address, forKey: PTWidgetDataKeys.address)
        defaults.set(lastUpdateTime.timeIntervalSince1970, forKey: PTWidgetDataKeys.lastUpdateTime)
    }

    public var applicationContext: [String: Any] {
        [
            PTWidgetDataKeys.fuelLevel: fuelLevel,
            PTWidgetDataKeys.tripKm: tripKm,
            PTWidgetDataKeys.isConnected: isConnected,
            PTWidgetDataKeys.parkedLat: parkedLat,
            PTWidgetDataKeys.parkedLon: parkedLon,
            PTWidgetDataKeys.address: address,
            PTWidgetDataKeys.lastUpdateTime: lastUpdateTime.timeIntervalSince1970
        ]
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }
}
