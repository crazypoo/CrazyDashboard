//
//  PTRideSafetyFeatures.swift
//  CrazyDashboard
//
//  EN: Bounded local safety timeline and expiring fleet points for the ride center.
//  ES: Línea temporal local acotada y puntos de grupo con caducidad para el centro de ruta.
//  中文：为骑行中心提供有界本地安全时间轴和自动过期的车队点位。
//

import CoreLocation
import Foundation

public enum PTRideSecurityEventKind: String, Codable, CaseIterable, Sendable {
    case monitoringArmed
    case monitoringDisarmed
    case connectionLost
    case connectionRestored
    case alarmTriggered
    case disconnectCleared
    case parkingSaved
}

public enum PTRideSecuritySeverity: String, Codable, Sendable {
    case info
    case warning
    case critical
}

public struct PTRideSecurityEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: PTRideSecurityEventKind
    public let severity: PTRideSecuritySeverity
    public let message: String
    public let coordinate: PTRideCoordinate?
    public let timestamp: Date
    public var isAcknowledged: Bool

    public init(
        id: UUID = UUID(),
        kind: PTRideSecurityEventKind,
        severity: PTRideSecuritySeverity,
        message: String,
        coordinate: PTRideCoordinate? = nil,
        timestamp: Date = Date(),
        isAcknowledged: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.isAcknowledged = isAcknowledged
    }
}

// EN: The timeline is a bounded local audit trail, not a remote security guarantee.
// ES: La línea temporal es una auditoría local acotada, no una garantía de seguridad remota.
// 中文：时间轴只是有界本地审计记录，不代表远程安全保证。
@MainActor
public final class PTSecurityEventTimelineStore {
    public static let shared = PTSecurityEventTimelineStore()
    public static let storageKey = "PTRideSecurityEventTimeline.v1"
    public static let maximumEventCount = 300
    public static let retention: TimeInterval = 90 * 24 * 60 * 60

    private let userDefaults: UserDefaults
    public private(set) var events: [PTRideSecurityEvent]

    public init(userDefaults: UserDefaults = .standard, referenceDate: Date = Date()) {
        self.userDefaults = userDefaults
        let decoded = userDefaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([PTRideSecurityEvent].self, from: $0) }
            ?? []
        self.events = decoded
            .filter { referenceDate.timeIntervalSince($0.timestamp) <= Self.retention }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(Self.maximumEventCount)
            .map { $0 }
        persist()
    }

    @discardableResult
    public func record(
        kind: PTRideSecurityEventKind,
        severity: PTRideSecuritySeverity,
        message: String,
        coordinate: PTRideCoordinate? = nil,
        timestamp: Date = Date()
    ) -> PTRideSecurityEvent {
        purgeExpired(referenceDate: timestamp)
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = events.first(where: {
            $0.kind == kind &&
            $0.message == normalizedMessage &&
            abs($0.timestamp.timeIntervalSince(timestamp)) <= 5
        }) {
            return existing
        }

        let event = PTRideSecurityEvent(
            kind: kind,
            severity: severity,
            message: normalizedMessage,
            coordinate: coordinate,
            timestamp: timestamp
        )
        events.insert(event, at: 0)
        events = Array(events.prefix(Self.maximumEventCount))
        persist()
        return event
    }

    @discardableResult
    public func acknowledge(id: UUID) -> Bool {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return false }
        events[index].isAcknowledged = true
        persist()
        return true
    }

    public func purgeExpired(referenceDate: Date = Date()) {
        let retained = events.filter { referenceDate.timeIntervalSince($0.timestamp) <= Self.retention }
        guard retained.count != events.count else { return }
        events = retained
        persist()
    }

    public func clear() {
        events.removeAll(keepingCapacity: true)
        persist()
    }

    public func exportJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(events)
    }

    public func exportCSVData() -> Data {
        var rows = ["id,kind,severity,message,latitude,longitude,timestamp,acknowledged"]
        rows.append(contentsOf: events.map { event in
            let latitude = event.coordinate.map { String($0.latitude) } ?? ""
            let longitude = event.coordinate.map { String($0.longitude) } ?? ""
            return [
                event.id.uuidString,
                event.kind.rawValue,
                event.severity.rawValue,
                event.message,
                latitude,
                longitude,
                ISO8601DateFormatter().string(from: event.timestamp),
                event.isAcknowledged ? "true" : "false"
            ].map(Self.csvField).joined(separator: ",")
        })
        return Data(rows.joined(separator: "\n").utf8)
    }

    public func exportURL(format: PTRideSafetyExportFormat) throws -> URL {
        let fileName = "ride-security-\(Int(Date().timeIntervalSince1970)).\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let data = format == .json ? try exportJSONData() : exportCSVData()
        try data.write(to: url, options: .atomic)
        return url
    }
}

public enum PTRideSafetyExportFormat: String, Sendable {
    case json
    case csv

    public var fileExtension: String { rawValue }
}

public enum PTRideSharedPointKind: String, Codable, CaseIterable, Sendable {
    case roadblock
    case slippery
    case construction
    case fuel
    case meeting
    case parking
}

public struct PTRideSharedPoint: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let senderID: String
    public let senderName: String
    public let kind: PTRideSharedPointKind
    public let title: String
    public let note: String
    public let coordinate: PTRideCoordinate
    public let address: String
    public let createdAt: Date
    public let expiresAt: Date
    public let ttl: Int

    public init(
        id: UUID = UUID(),
        senderID: String,
        senderName: String,
        kind: PTRideSharedPointKind,
        title: String,
        note: String = "",
        coordinate: PTRideCoordinate,
        address: String = "",
        createdAt: Date = Date(),
        expiresAt: Date,
        ttl: Int = 3
    ) {
        self.id = id
        self.senderID = senderID
        self.senderName = senderName
        self.kind = kind
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        self.coordinate = coordinate
        self.address = String(address.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.ttl = min(max(ttl, 0), 6)
    }

    public var isExpired: Bool {
        isExpired(at: Date())
    }

    public func isExpired(at date: Date) -> Bool {
        date >= expiresAt
    }

    public var isValid: Bool {
        !senderID.isEmpty && !title.isEmpty && coordinate.isValid && expiresAt > createdAt && ttl >= 0
    }

    public var decrementedTTL: PTRideSharedPoint? {
        guard ttl > 0 else { return nil }
        return PTRideSharedPoint(
            id: id,
            senderID: senderID,
            senderName: senderName,
            kind: kind,
            title: title,
            note: note,
            coordinate: coordinate,
            address: address,
            createdAt: createdAt,
            expiresAt: expiresAt,
            ttl: ttl - 1
        )
    }
}

// EN: Shared points expire and stay local until the existing PTT session accepts them.
// ES: Los puntos compartidos caducan y permanecen locales hasta que la sesión PTT existente los acepta.
// 中文：共享点位自动过期，并且只有现有 PTT 会话接受后才保存。
@MainActor
public final class PTRideSharedPointStore {
    public static let shared = PTRideSharedPointStore()
    public static let storageKey = "PTRideSharedPoints.v1"
    public static let maximumPointCount = 100
    public static let defaultExpiration: TimeInterval = 2 * 60 * 60

    private let userDefaults: UserDefaults
    public private(set) var points: [PTRideSharedPoint]

    public init(userDefaults: UserDefaults = .standard, referenceDate: Date = Date()) {
        self.userDefaults = userDefaults
        let decoded = userDefaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([PTRideSharedPoint].self, from: $0) }
            ?? []
        self.points = decoded
            .filter { $0.isValid && !$0.isExpired(at: referenceDate) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(Self.maximumPointCount)
            .map { $0 }
        persist()
    }

    @discardableResult
    public func record(_ point: PTRideSharedPoint) -> Bool {
        guard point.isValid, !point.isExpired else { return false }
        purgeExpired()
        guard !points.contains(where: { $0.id == point.id }) else { return false }
        points.insert(point, at: 0)
        points = Array(points.prefix(Self.maximumPointCount))
        persist()
        return true
    }

    @discardableResult
    public func receive(_ point: PTRideSharedPoint) -> Bool {
        record(point)
    }

    @discardableResult
    public func remove(id: UUID) -> Bool {
        let originalCount = points.count
        points.removeAll { $0.id == id }
        guard points.count != originalCount else { return false }
        persist()
        return true
    }

    public func purgeExpired(referenceDate: Date = Date()) {
        let retained = points.filter { !$0.isExpired(at: referenceDate) }
        guard retained.count != points.count else { return }
        points = retained
        persist()
    }

    public func clear() {
        points.removeAll(keepingCapacity: true)
        persist()
    }

    @discardableResult
    public func shareParking() -> Bool {
        guard let coordinate = PTMOTOParkingManager.shared.getLastParkedLocation() else { return false }
        let point = makePoint(
            kind: .parking,
            title: PTDashboardConfig.languageFunc(text: "safety_parking_shared"),
            note: ""
        ) { coordinate }
        return broadcastAndRecord(point)
    }

    @discardableResult
    public func shareHazard(
        kind: PTRideSharedPointKind,
        title: String,
        note: String = "",
        ttl: Int = 3
    ) -> Bool {
        guard kind != .parking,
              let coordinate = PTLocationEngine.shared.lastLocation?.coordinate else {
            return false
        }
        let point = makePoint(kind: kind, title: title, note: note, ttl: ttl) { coordinate }
        return broadcastAndRecord(point)
    }

    public func exportJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(points)
    }

    public func exportCSVData() -> Data {
        var rows = ["id,senderID,senderName,kind,title,note,latitude,longitude,address,createdAt,expiresAt,ttl"]
        rows.append(contentsOf: points.map { point in
            [
                point.id.uuidString,
                point.senderID,
                point.senderName,
                point.kind.rawValue,
                point.title,
                point.note,
                String(point.coordinate.latitude),
                String(point.coordinate.longitude),
                point.address,
                ISO8601DateFormatter().string(from: point.createdAt),
                ISO8601DateFormatter().string(from: point.expiresAt),
                String(point.ttl)
            ].map(Self.csvField).joined(separator: ",")
        })
        return Data(rows.joined(separator: "\n").utf8)
    }

    public func exportURL(format: PTRideSafetyExportFormat) throws -> URL {
        let fileName = "ride-shared-points-\(Int(Date().timeIntervalSince1970)).\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let data = format == .json ? try exportJSONData() : exportCSVData()
        try data.write(to: url, options: .atomic)
        return url
    }
}

private extension PTSecurityEventTimelineStore {
    func persist() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    static func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

private extension PTRideSharedPointStore {
    func persist() {
        guard let data = try? JSONEncoder().encode(points) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    func makePoint(
        kind: PTRideSharedPointKind,
        title: String,
        note: String,
        ttl: Int = 3,
        coordinate: () -> CLLocationCoordinate2D
    ) -> PTRideSharedPoint {
        let location = coordinate()
        let widgetStatus = PTWidgetSharedStatus.read(
            from: UserDefaults(suiteName: PTWidgetDataKeys.appGroupID)
        )
        let address = widgetStatus.address == PTWidgetSharedStatus.placeholder.address ? "" : widgetStatus.address
        let now = Date()
        return PTRideSharedPoint(
            senderID: PTLocalIntercomManager.shared.localIdentifier,
            senderName: PTLocalIntercomManager.shared.customUserName,
            kind: kind,
            title: title,
            note: note,
            coordinate: PTRideCoordinate(latitude: location.latitude, longitude: location.longitude),
            address: address,
            createdAt: now,
            expiresAt: now.addingTimeInterval(Self.defaultExpiration),
            ttl: ttl
        )
    }

    func broadcastAndRecord(_ point: PTRideSharedPoint) -> Bool {
        guard PTLocalIntercomManager.shared.isRunning,
              PTLocalIntercomManager.shared.connectedPeersCount > 0,
              PTLocalIntercomManager.shared.broadcastSharedPoint(point) else {
            return false
        }
        return record(point)
    }

    static func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
