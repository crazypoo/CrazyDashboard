//
//  PTRideBlackBox.swift
//  CrazyDashboard
//
//  EN: Local event-window storage built on the existing ride telemetry.
//  ES: Almacenamiento local de ventanas de eventos basado en la telemetría existente.
//  中文：基于现有骑行遥测的本地事件窗口存储。
//

import Foundation

public nonisolated enum PTRideBlackBoxEventSource: String, Codable, Hashable, Sendable {
    case review
    case offRoad
    case manual
}

public nonisolated struct PTRideBlackBoxEvent: Codable, Hashable, Sendable {
    public let id: UUID
    public let rideStartTime: Date
    public let timestamp: Date
    public let source: PTRideBlackBoxEventSource
    public let title: String
    public let latitude: Double
    public let longitude: Double
    public let peakValue: Double
    public let speedKmh: Double
    public let severity: Double

    public nonisolated init(
        id: UUID = UUID(),
        rideStartTime: Date,
        timestamp: Date,
        source: PTRideBlackBoxEventSource,
        title: String,
        latitude: Double,
        longitude: Double,
        peakValue: Double = 0,
        speedKmh: Double = 0,
        severity: Double = 1
    ) {
        self.id = id
        self.rideStartTime = rideStartTime
        self.timestamp = timestamp
        self.source = source
        self.title = title
        self.latitude = latitude
        self.longitude = longitude
        self.peakValue = peakValue
        self.speedKmh = speedKmh
        self.severity = severity
    }

    public nonisolated init(rideStartTime: Date, reviewEvent: PTRideReviewEvent) {
        let eventTitle: String
        switch reviewEvent.type {
        case .hardBraking: eventTitle = "急刹"
        case .hardAcceleration: eventTitle = "突加速"
        case .heavyBump: eventTitle = "重颠簸"
        case .highLean: eventTitle = "高倾角"
        case .suspectedSlip: eventTitle = "疑似打滑"
        }
        self.init(
            rideStartTime: rideStartTime,
            timestamp: reviewEvent.timestamp,
            source: .review,
            title: eventTitle,
            latitude: reviewEvent.latitude,
            longitude: reviewEvent.longitude,
            peakValue: reviewEvent.peakValue,
            speedKmh: reviewEvent.speedKmh,
            severity: reviewEvent.severity
        )
    }

    public nonisolated init(rideStartTime: Date, offRoadEvent: PTTripOffRoadEvent) {
        self.init(
            rideStartTime: rideStartTime,
            timestamp: offRoadEvent.timestamp,
            source: .offRoad,
            title: offRoadEvent.info,
            latitude: offRoadEvent.latitude,
            longitude: offRoadEvent.longitude,
            peakValue: offRoadEvent.slipRatio,
            speedKmh: 0,
            severity: 1
        )
    }
}

public nonisolated struct PTRideBlackBoxClip: Codable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let event: PTRideBlackBoxEvent
    public let windowStart: Date
    public let windowEnd: Date
    public let requestedBeforeSeconds: TimeInterval
    public let requestedAfterSeconds: TimeInterval
    public let availableBeforeSeconds: TimeInterval
    public let availableAfterSeconds: TimeInterval
    public let points: [PTRoutePoint]
    public let createdAt: Date

    public nonisolated init(
        id: UUID = UUID(),
        event: PTRideBlackBoxEvent,
        windowStart: Date,
        windowEnd: Date,
        requestedBeforeSeconds: TimeInterval,
        requestedAfterSeconds: TimeInterval,
        availableBeforeSeconds: TimeInterval,
        availableAfterSeconds: TimeInterval,
        points: [PTRoutePoint],
        createdAt: Date = Date()
    ) {
        self.schemaVersion = 1
        self.id = id
        self.event = event
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.requestedBeforeSeconds = max(requestedBeforeSeconds, 0)
        self.requestedAfterSeconds = max(requestedAfterSeconds, 0)
        self.availableBeforeSeconds = max(availableBeforeSeconds, 0)
        self.availableAfterSeconds = max(availableAfterSeconds, 0)
        self.points = points
        self.createdAt = createdAt
    }

    public var hasCompleteRequestedWindow: Bool {
        availableBeforeSeconds + 0.001 >= requestedBeforeSeconds &&
            availableAfterSeconds + 0.001 >= requestedAfterSeconds
    }
}

public enum PTRideBlackBoxBuilder {
    /// EN: Build bounded clips from the route points already collected by PTTripManager.
    /// ES: Construye clips acotados usando los puntos ya recopilados por PTTripManager.
    /// 中文：利用 PTTripManager 已采集的轨迹点生成有边界的事件片段。
    public nonisolated static func makeClips(
        rideStartTime: Date,
        reviewEvents: [PTRideReviewEvent],
        offRoadEvents: [PTTripOffRoadEvent],
        manualEvents: [PTRideBlackBoxEvent],
        points: [PTRoutePoint],
        beforeSeconds: TimeInterval = 60,
        afterSeconds: TimeInterval = 30,
        createdAt: Date = Date()
    ) -> [PTRideBlackBoxClip] {
        let before = max(beforeSeconds.isFinite ? beforeSeconds : 0, 0)
        let after = max(afterSeconds.isFinite ? afterSeconds : 0, 0)
        let events = reviewEvents.map { PTRideBlackBoxEvent(rideStartTime: rideStartTime, reviewEvent: $0) } +
            offRoadEvents.map { PTRideBlackBoxEvent(rideStartTime: rideStartTime, offRoadEvent: $0) } +
            manualEvents

        return events
            .sorted { $0.timestamp < $1.timestamp }
            .map {
                makeClip(
                    event: $0,
                    points: points,
                    beforeSeconds: before,
                    afterSeconds: after,
                    createdAt: createdAt
                )
            }
    }

    public nonisolated static func makeClip(
        event: PTRideBlackBoxEvent,
        points: [PTRoutePoint],
        beforeSeconds: TimeInterval = 60,
        afterSeconds: TimeInterval = 30,
        createdAt: Date = Date()
    ) -> PTRideBlackBoxClip {
        let before = max(beforeSeconds.isFinite ? beforeSeconds : 0, 0)
        let after = max(afterSeconds.isFinite ? afterSeconds : 0, 0)
        let windowStart = event.timestamp.addingTimeInterval(-before)
        let windowEnd = event.timestamp.addingTimeInterval(after)
        let sortedPoints = points
            .filter { $0.timestamp >= windowStart && $0.timestamp <= windowEnd }
            .sorted { $0.timestamp < $1.timestamp }

        let firstBeforePoint = sortedPoints.first { $0.timestamp <= event.timestamp }
        let lastAfterPoint = sortedPoints.last { $0.timestamp >= event.timestamp }
        let availableBefore = firstBeforePoint.map {
            max(event.timestamp.timeIntervalSince($0.timestamp), 0)
        } ?? 0
        let availableAfter = lastAfterPoint.map {
            max($0.timestamp.timeIntervalSince(event.timestamp), 0)
        } ?? 0

        return PTRideBlackBoxClip(
            event: event,
            windowStart: windowStart,
            windowEnd: windowEnd,
            requestedBeforeSeconds: before,
            requestedAfterSeconds: after,
            availableBeforeSeconds: availableBefore,
            availableAfterSeconds: availableAfter,
            points: sortedPoints,
            createdAt: createdAt
        )
    }
}

private nonisolated struct PTRideBlackBoxDocument: Codable, Sendable {
    let schemaVersion: Int
    let clips: [PTRideBlackBoxClip]
}

/// EN: The black box is local-only and capped so event analysis cannot grow without bounds.
/// ES: La caja negra es solo local y tiene un límite para que el análisis no crezca sin control.
/// 中文：黑匣子只保存在本地并限制数量，避免事件分析无限增长。
public actor PTRideBlackBoxStore {
    public static let shared = PTRideBlackBoxStore()

    private let fileName: String
    private let maximumClipCount: Int
    private let persistence: PTDataPersistenceActor
    private var clips: [PTRideBlackBoxClip] = []
    private var didLoad = false
    private var writeRevision: Int64 = 0

    public init(
        fileName: String = "PTRideBlackBox.json",
        maximumClipCount: Int = 60,
        persistence: PTDataPersistenceActor = .shared
    ) {
        self.fileName = fileName
        self.maximumClipCount = min(max(maximumClipCount, 1), 200)
        self.persistence = persistence
    }

    public func load() async throws -> [PTRideBlackBoxClip] {
        try await loadIfNeeded()
        return clips
    }

    @discardableResult
    public func append(_ newClips: [PTRideBlackBoxClip]) async throws -> [PTRideBlackBoxClip] {
        guard !newClips.isEmpty else {
            try await loadIfNeeded()
            return clips
        }

        try await loadIfNeeded()
        var byID = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) })
        for clip in newClips {
            byID[clip.id] = clip
        }
        clips = byID.values
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(maximumClipCount)
            .map { $0 }
        try await persist()
        return clips
    }

    public func deleteAll() async throws {
        clips.removeAll()
        didLoad = true
        writeRevision &+= 1
        _ = try await persistence.delete(
            fileName: fileName,
            deleteFromICloud: false
        )
    }

    @discardableResult
    public func deleteClips(forRideStartTime startTime: Date) async throws -> Int {
        try await loadIfNeeded()
        let originalCount = clips.count
        clips.removeAll { $0.event.rideStartTime == startTime }
        guard clips.count != originalCount else { return 0 }
        try await persist()
        return originalCount - clips.count
    }

    private func loadIfNeeded() async throws {
        guard !didLoad else { return }
        didLoad = true

        do {
            let data = try await persistence.readData(
                fileName: fileName,
                restoreFromICloud: false
            )
            let decoder = JSONDecoder()
            decoder.nonConformingFloatDecodingStrategy = .convertFromString(
                positiveInfinity: "INF",
                negativeInfinity: "-INF",
                nan: "NaN"
            )
            if let document = try? decoder.decode(PTRideBlackBoxDocument.self, from: data) {
                clips = document.clips
            } else {
                clips = try decoder.decode([PTRideBlackBoxClip].self, from: data)
            }
            clips = clips
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(maximumClipCount)
                .map { $0 }
        } catch let error as PTDataPersistenceError {
            if case .fileNotFound = error {
                clips = []
                return
            }
            throw error
        }
    }

    private func persist() async throws {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "INF",
            negativeInfinity: "-INF",
            nan: "NaN"
        )
        let data = try encoder.encode(PTRideBlackBoxDocument(schemaVersion: 1, clips: clips))
        writeRevision &+= 1
        _ = try await persistence.writeData(
            data,
            fileName: fileName,
            revision: writeRevision,
            syncToICloud: false
        )
    }
}
