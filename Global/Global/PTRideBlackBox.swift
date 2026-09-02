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

public nonisolated enum PTRideBlackBoxClipOrigin: String, Codable, Sendable {
    case captured
    case recovered
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
    public let origin: PTRideBlackBoxClipOrigin

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
        createdAt: Date = Date(),
        origin: PTRideBlackBoxClipOrigin = .captured
    ) {
        self.schemaVersion = 2
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
        self.origin = origin
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, event, windowStart, windowEnd
        case requestedBeforeSeconds, requestedAfterSeconds
        case availableBeforeSeconds, availableAfterSeconds, points, createdAt, origin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            event: try container.decode(PTRideBlackBoxEvent.self, forKey: .event),
            windowStart: try container.decode(Date.self, forKey: .windowStart),
            windowEnd: try container.decode(Date.self, forKey: .windowEnd),
            requestedBeforeSeconds: try container.decode(TimeInterval.self, forKey: .requestedBeforeSeconds),
            requestedAfterSeconds: try container.decode(TimeInterval.self, forKey: .requestedAfterSeconds),
            availableBeforeSeconds: try container.decode(TimeInterval.self, forKey: .availableBeforeSeconds),
            availableAfterSeconds: try container.decode(TimeInterval.self, forKey: .availableAfterSeconds),
            points: try container.decode([PTRoutePoint].self, forKey: .points),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            origin: try container.decodeIfPresent(PTRideBlackBoxClipOrigin.self, forKey: .origin) ?? .captured
        )
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
        createdAt: Date = Date(),
        origin: PTRideBlackBoxClipOrigin = .captured
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
                    createdAt: createdAt,
                    origin: origin
                )
            }
    }

    public nonisolated static func makeClip(
        event: PTRideBlackBoxEvent,
        points: [PTRoutePoint],
        beforeSeconds: TimeInterval = 60,
        afterSeconds: TimeInterval = 30,
        createdAt: Date = Date(),
        origin: PTRideBlackBoxClipOrigin = .captured
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
            createdAt: createdAt,
            origin: origin
        )
    }
}

public nonisolated enum PTRideBlackBoxExportFormat: String, Sendable {
    case json
    case csv
    case gpx

    public var fileExtension: String { rawValue }
}

// EN: Export helpers are pure and operate on an already loaded clip, keeping file I/O outside analysis code.
// ES: Los exportadores son puros y trabajan con un clip ya cargado, manteniendo el I/O fuera del análisis.
// 中文：导出工具只处理已加载的片段，文件 I/O 与分析逻辑分离。
nonisolated public enum PTRideBlackBoxExporter {
    public static func data(
        for clips: [PTRideBlackBoxClip],
        format: PTRideBlackBoxExportFormat
    ) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(clips)
        case .csv:
            let header = "clip_id,event_id,event_title,event_source,timestamp,latitude,longitude,speed_kmh,peak_value,severity,point_timestamp,point_latitude,point_longitude,point_speed_kmh,point_rpm"
            var rows = [header]
            let formatter = ISO8601DateFormatter()
            for clip in clips {
                for point in clip.points {
                    rows.append([
                        clip.id.uuidString,
                        clip.event.id.uuidString,
                        clip.event.title,
                        clip.event.source.rawValue,
                        formatter.string(from: clip.event.timestamp),
                        String(clip.event.latitude),
                        String(clip.event.longitude),
                        String(clip.event.speedKmh),
                        String(clip.event.peakValue),
                        String(clip.event.severity),
                        formatter.string(from: point.timestamp),
                        String(point.lat),
                        String(point.lon),
                        String(point.speed),
                        String(point.rpm)
                    ].map(csvField).joined(separator: ","))
                }
            }
            return Data(rows.joined(separator: "\n").utf8)
        case .gpx:
            let formatter = ISO8601DateFormatter()
            var output = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"PTSpeed\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n<trk><name>Moto Black Box</name><trkseg>\n"
            for clip in clips {
                for point in clip.points {
                    output += "<trkpt lat=\"\(point.lat)\" lon=\"\(point.lon)\"><time>\(formatter.string(from: point.timestamp))</time><extensions><speed>\(point.speed)</speed><rpm>\(point.rpm)</rpm><lean>\(point.leanAngle)</lean><gforce_x>\(point.gForceX)</gforce_x><gforce_y>\(point.gForceY)</gforce_y><gforce_z>\(point.gForceZ)</gforce_z></extensions></trkpt>\n"
                }
            }
            output += "</trkseg></trk>\n</gpx>\n"
            return Data(output.utf8)
        }
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private nonisolated struct PTRideBlackBoxDocument: Codable, Sendable {
    let schemaVersion: Int
    let clips: [PTRideBlackBoxClip]
}

public nonisolated enum PTRideBlackBoxLoadState: String, Sendable {
    case empty
    case loaded
    case recoveredCorruption
}

public nonisolated struct PTRideBlackBoxLoadResult: Sendable {
    public let clips: [PTRideBlackBoxClip]
    public let state: PTRideBlackBoxLoadState
    public let preservedCorruptFileURL: URL?

    public init(
        clips: [PTRideBlackBoxClip],
        state: PTRideBlackBoxLoadState,
        preservedCorruptFileURL: URL? = nil
    ) {
        self.clips = clips
        self.state = state
        self.preservedCorruptFileURL = preservedCorruptFileURL
    }
}

private nonisolated struct PTRideBlackBoxJournal: Codable, Sendable {
    let schemaVersion: Int
    let rideStartTime: Date
    let checkpointAt: Date
    let points: [PTRoutePoint]
    let manualEvents: [PTRideBlackBoxEvent]
}

/// EN: The black box is local-only and capped so event analysis cannot grow without bounds.
/// ES: La caja negra es solo local y tiene un límite para que el análisis no crezca sin control.
/// 中文：黑匣子只保存在本地并限制数量，避免事件分析无限增长。
public actor PTRideBlackBoxStore {
    public static let shared = PTRideBlackBoxStore()
    public static let journalFileName = "PTRideBlackBoxJournal.json"
    public static let retention: TimeInterval = 90 * 24 * 60 * 60
    public static let maximumJournalPointCount = 120
    public static let maximumJournalEventCount = 60

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

    // EN: Recovery preserves malformed input before replacing it with a valid empty document.
    // ES: La recuperación conserva los datos dañados antes de reemplazarlos por un documento vacío válido.
    // 中文：恢复时先保留损坏文件，再用有效空文档替换，避免数据静默丢失。
    public func loadRecoveringCorruption() async throws -> PTRideBlackBoxLoadResult {
        do {
            try await loadIfNeeded()
            return PTRideBlackBoxLoadResult(
                clips: clips,
                state: clips.isEmpty ? .empty : .loaded
            )
        } catch {
            guard let data = try? await persistence.readData(
                fileName: fileName,
                restoreFromICloud: false
            ) else {
                throw error
            }

            let backupURL = try? await persistence.preserveCorruptData(
                data,
                fileName: fileName
            )
            clips = []
            didLoad = true
            try await persist()
            return PTRideBlackBoxLoadResult(
                clips: [],
                state: .recoveredCorruption,
                preservedCorruptFileURL: backupURL
            )
        }
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

    // EN: The journal is a bounded local checkpoint for an active ride, not a second ride database.
    // ES: El diario es un punto de control local limitado para un viaje activo, no una segunda base de datos.
    // 中文：日志只是活动行程的有界本地检查点，不会成为第二套行程数据库。
    public func checkpoint(
        rideStartTime: Date,
        points: [PTRoutePoint],
        manualEvents: [PTRideBlackBoxEvent],
        checkpointAt: Date = Date()
    ) async throws {
        let journal = PTRideBlackBoxJournal(
            schemaVersion: 1,
            rideStartTime: rideStartTime,
            checkpointAt: checkpointAt,
            points: Array(points.sorted { $0.timestamp < $1.timestamp }.suffix(Self.maximumJournalPointCount)),
            manualEvents: Array(manualEvents.sorted { $0.timestamp < $1.timestamp }.suffix(Self.maximumJournalEventCount))
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(journal)
        _ = try await persistence.writeData(
            data,
            fileName: Self.journalFileName,
            revision: Int64(checkpointAt.timeIntervalSince1970 * 1_000),
            syncToICloud: false
        )
    }

    public func recoverJournal() async throws -> (rideStartTime: Date, checkpointAt: Date, points: [PTRoutePoint], manualEvents: [PTRideBlackBoxEvent])? {
        do {
            let data = try await persistence.readData(
                fileName: Self.journalFileName,
                restoreFromICloud: false
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let journal = try decoder.decode(PTRideBlackBoxJournal.self, from: data)
            return (journal.rideStartTime, journal.checkpointAt, journal.points, journal.manualEvents)
        } catch let error as PTDataPersistenceError {
            if case .fileNotFound = error { return nil }
            throw error
        }
    }

    public func clearJournal() async throws {
        _ = try await persistence.delete(
            fileName: Self.journalFileName,
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
            let cutoff = Date().addingTimeInterval(-Self.retention)
            clips = clips
                .filter { $0.createdAt >= cutoff }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(maximumClipCount)
                .map { $0 }
        } catch let error as PTDataPersistenceError {
            if case .fileNotFound = error {
                clips = []
                return
            }
            didLoad = false
            throw error
        } catch {
            didLoad = false
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
        let data = try encoder.encode(PTRideBlackBoxDocument(schemaVersion: 2, clips: clips))
        writeRevision &+= 1
        _ = try await persistence.writeData(
            data,
            fileName: fileName,
            revision: writeRevision,
            syncToICloud: false
        )
    }
}
