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
    // EN: Keep the App Group identifier beside the shared keys used by every status consumer.
    // ES: Conserva el identificador del App Group junto a las claves compartidas de todos los consumidores.
    // 中文：将所有状态消费者共用的 App Group 标识与共享键集中维护。
    nonisolated public static let appGroupID = "group.com.yd.PTSpeed.xp400"
    nonisolated public static let fuelLevel = "widget_fuelLevel"
    nonisolated public static let tripKm = "widget_tripKm"
    nonisolated public static let isConnected = "widget_isConnected"
    nonisolated public static let parkedLat = "widget_parkedLat"
    nonisolated public static let parkedLon = "widget_parkedLon"
    nonisolated public static let address = "widget_parkedAddress"
    nonisolated public static let lastUpdateTime = "widget_lastUpdateTime"
    nonisolated public static let languageIdentifier = "widget_languageIdentifier"
}

public struct PTWidgetSharedStatus: Codable, Equatable, Sendable {
    public let fuelLevel: Int
    public let tripKm: Double
    public let isConnected: Bool
    public let parkedLat: Double
    public let parkedLon: Double
    public let address: String
    public let lastUpdateTime: Date
    /// EN: Optional for backward compatibility with snapshots written before app-language sync.
    /// ES: Opcional para mantener la compatibilidad con instantáneas anteriores a la sincronización del idioma.
    /// 中文：为兼容语言同步之前写入的快照，该字段必须允许缺失。
    public let languageIdentifier: String?

    nonisolated public init(
        fuelLevel: Int,
        tripKm: Double,
        isConnected: Bool,
        parkedLat: Double,
        parkedLon: Double,
        address: String,
        lastUpdateTime: Date,
        languageIdentifier: String? = nil
    ) {
        self.fuelLevel = fuelLevel
        self.tripKm = tripKm
        self.isConnected = isConnected
        self.parkedLat = parkedLat
        self.parkedLon = parkedLon
        self.address = address
        self.lastUpdateTime = lastUpdateTime
        self.languageIdentifier = languageIdentifier
    }

    nonisolated public static let placeholder = PTWidgetSharedStatus(
        fuelLevel: 0,
        tripKm: 0,
        isConnected: false,
        parkedLat: 0,
        parkedLon: 0,
        address: "",
        lastUpdateTime: .distantPast,
        languageIdentifier: nil
    )

    nonisolated public init?(applicationContext: [String: Any]) {
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
            lastUpdateTime: Date(timeIntervalSince1970: timestamp),
            languageIdentifier: applicationContext[PTWidgetDataKeys.languageIdentifier] as? String
        )
    }

    nonisolated public init?(defaults: UserDefaults?) {
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
            lastUpdateTime: Date(timeIntervalSince1970: defaults.double(forKey: PTWidgetDataKeys.lastUpdateTime)),
            languageIdentifier: defaults.string(forKey: PTWidgetDataKeys.languageIdentifier)
        )
    }

    nonisolated public static func read(from defaults: UserDefaults?) -> PTWidgetSharedStatus {
        PTWidgetSharedStatus(defaults: defaults) ?? .placeholder
    }

    nonisolated public func write(to defaults: UserDefaults) {
        defaults.set(fuelLevel, forKey: PTWidgetDataKeys.fuelLevel)
        defaults.set(tripKm, forKey: PTWidgetDataKeys.tripKm)
        defaults.set(isConnected, forKey: PTWidgetDataKeys.isConnected)
        defaults.set(parkedLat, forKey: PTWidgetDataKeys.parkedLat)
        defaults.set(parkedLon, forKey: PTWidgetDataKeys.parkedLon)
        defaults.set(address, forKey: PTWidgetDataKeys.address)
        defaults.set(lastUpdateTime.timeIntervalSince1970, forKey: PTWidgetDataKeys.lastUpdateTime)
        if let languageIdentifier {
            defaults.set(languageIdentifier, forKey: PTWidgetDataKeys.languageIdentifier)
        } else {
            defaults.removeObject(forKey: PTWidgetDataKeys.languageIdentifier)
        }
    }

    nonisolated public var applicationContext: [String: Any] {
        var values: [String: Any] = [
            PTWidgetDataKeys.fuelLevel: fuelLevel,
            PTWidgetDataKeys.tripKm: tripKm,
            PTWidgetDataKeys.isConnected: isConnected,
            PTWidgetDataKeys.parkedLat: parkedLat,
            PTWidgetDataKeys.parkedLon: parkedLon,
            PTWidgetDataKeys.address: address,
            PTWidgetDataKeys.lastUpdateTime: lastUpdateTime.timeIntervalSince1970
        ]
        if let languageIdentifier {
            values[PTWidgetDataKeys.languageIdentifier] = languageIdentifier
        }
        return values
    }

    nonisolated private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    nonisolated private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    nonisolated private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }
}

// EN: Resolve Widget and Watch copy independently from the selected iPhone locale.
// ES: Resuelve el texto del Widget y del Watch independientemente del locale seleccionado en el iPhone.
// 中文：让 Widget 和 Watch 根据 iPhone 选择的语言独立解析界面文案。
public enum PTWidgetLocalized {
    nonisolated public static func string(_ key: String, languageIdentifier: String?) -> String {
        let identifier = languageIdentifier.flatMap { normalized($0) }
        let locale = identifier.map(Locale.init(identifier:)) ?? .current
        let value = String(
            localized: String.LocalizationValue(key),
            table: "Localizable",
            bundle: .main,
            locale: locale
        )
        return value == key ? key : value
    }

    nonisolated private static func normalized(_ identifier: String) -> String? {
        let value = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
