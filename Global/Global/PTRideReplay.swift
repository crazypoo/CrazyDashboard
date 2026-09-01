//
//  PTRideReplay.swift
//  CrazyDashboard
//
//  EN: Offline ride replay models and a main-actor playback clock.
//  ES: Modelos de reproducción offline y reloj de reproducción aislado al actor principal.
//  中文：离线骑行回放模型与主 actor 播放时钟。
//

import Foundation
import CoreLocation

// EN: Replay errors stay explicit so a missing GPX never becomes a blank or misleading map.
// ES: Los errores de reproducción son explícitos para que un GPX ausente nunca genere un mapa engañoso.
// 中文：回放错误显式返回，避免缺少 GPX 时显示空白或误导性地图。
nonisolated public enum PTRideReplayError: Error, Equatable, LocalizedError, Sendable {
    case missingTrack
    case invalidTrack

    public var errorDescription: String? {
        switch self {
        case .missingTrack:
            return "该行程没有可回放的 GPX 轨迹"
        case .invalidTrack:
            return "该行程的 GPX 轨迹无效"
        }
    }
}

// EN: One sample is the synchronized unit for map position and telemetry.
// ES: Una muestra es la unidad sincronizada para la posición del mapa y la telemetría.
// 中文：一个样本同时承载地图位置和遥测数据，作为同步回放的最小单位。
nonisolated public struct PTRideReplaySample: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let timestamp: Date
    public let altitude: Double?
    public let speedKmh: Double
    public let rpm: Int
    public let leanAngle: Double
    public let gForceX: Double
    public let gForceY: Double
    public let gForceZ: Double
    public let slipRatio: Double

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public init(latitude: Double,
                longitude: Double,
                timestamp: Date,
                altitude: Double? = nil,
                speedKmh: Double = 0,
                rpm: Int = 0,
                leanAngle: Double = 0,
                gForceX: Double = 0,
                gForceY: Double = 0,
                gForceZ: Double = 0,
                slipRatio: Double = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.altitude = altitude
        self.speedKmh = speedKmh
        self.rpm = rpm
        self.leanAngle = leanAngle
        self.gForceX = gForceX
        self.gForceY = gForceY
        self.gForceZ = gForceZ
        self.slipRatio = slipRatio
    }
}

// EN: Events are normalized from the existing review and off-road records.
// ES: Los eventos se normalizan desde los registros existentes de revisión y fuera de carretera.
// 中文：事件统一来源于现有的复盘事件和越野事件记录。
nonisolated public enum PTRideReplayEventKind: String, Codable, Hashable, Sendable {
    case review
    case offRoad
}

nonisolated public struct PTRideReplayEvent: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: PTRideReplayEventKind
    public let titleKey: String
    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double
    public let severity: Double

    public init(id: UUID = UUID(),
                kind: PTRideReplayEventKind,
                titleKey: String,
                timestamp: Date,
                latitude: Double,
                longitude: Double,
                severity: Double = 0) {
        self.id = id
        self.kind = kind
        self.titleKey = titleKey
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.severity = severity
    }
}

// EN: A replay session keeps the report summary, ordered samples and normalized events together.
// ES: Una sesión conserva juntos el resumen, las muestras ordenadas y los eventos normalizados.
// 中文：回放会话统一保存报告摘要、有序样本和标准化事件。
nonisolated public struct PTRideReplaySession: Sendable {
    public let report: PTTripReport
    public let samples: [PTRideReplaySample]
    public let events: [PTRideReplayEvent]

    public var startTime: Date { report.startTime }

    public var endTime: Date {
        max(report.endTime, samples.last?.timestamp ?? report.endTime)
    }

    public var duration: TimeInterval {
        max(endTime.timeIntervalSince(startTime), 0)
    }

    public init(report: PTTripReport,
                samples: [PTRideReplaySample],
                events: [PTRideReplayEvent]) {
        self.report = report
        self.samples = samples
        self.events = events.sorted { $0.timestamp < $1.timestamp }
    }

    // EN: Interpolate between neighboring samples so the marker and metrics move smoothly at 30 FPS.
    // ES: Interpola entre muestras vecinas para que el marcador y las métricas se muevan suavemente a 30 FPS.
    // 中文：在相邻样本间插值，让地图标记和遥测数据以 30 FPS 平滑变化。
    public func sample(at elapsed: TimeInterval) -> PTRideReplaySample? {
        guard let first = samples.first else { return nil }
        guard samples.count > 1 else { return first }

        let clampedElapsed = min(max(elapsed, 0), duration)
        let date = startTime.addingTimeInterval(clampedElapsed)
        guard date > first.timestamp else { return first }
        guard let last = samples.last else { return first }
        guard date < last.timestamp else { return last }

        var lowerIndex = 0
        var upperIndex = samples.count - 1
        while lowerIndex + 1 < upperIndex {
            let middleIndex = (lowerIndex + upperIndex) / 2
            if samples[middleIndex].timestamp < date {
                lowerIndex = middleIndex
            } else {
                upperIndex = middleIndex
            }
        }

        let lower = samples[lowerIndex]
        let upper = samples[upperIndex]
        let interval = upper.timestamp.timeIntervalSince(lower.timestamp)
        let fraction = interval > 0
            ? min(max(date.timeIntervalSince(lower.timestamp) / interval, 0), 1)
            : 0
        return interpolate(lower, upper, fraction: fraction, timestamp: date)
    }

    public func progress(for elapsed: TimeInterval) -> Float {
        guard duration > 0 else { return 0 }
        return Float(min(max(elapsed / duration, 0), 1))
    }

    private func interpolate(_ lower: PTRideReplaySample,
                             _ upper: PTRideReplaySample,
                             fraction: Double,
                             timestamp: Date) -> PTRideReplaySample {
        func value(_ first: Double, _ second: Double) -> Double {
            first + (second - first) * fraction
        }

        let altitude: Double?
        switch (lower.altitude, upper.altitude) {
        case let (.some(first), .some(second)):
            altitude = value(first, second)
        case let (.some(first), .none):
            altitude = first
        case let (.none, .some(second)):
            altitude = second
        case (.none, .none):
            altitude = nil
        }

        return PTRideReplaySample(
            latitude: value(lower.latitude, upper.latitude),
            longitude: value(lower.longitude, upper.longitude),
            timestamp: timestamp,
            altitude: altitude,
            speedKmh: value(lower.speedKmh, upper.speedKmh),
            rpm: Int(value(Double(lower.rpm), Double(upper.rpm)).rounded()),
            leanAngle: value(lower.leanAngle, upper.leanAngle),
            gForceX: value(lower.gForceX, upper.gForceX),
            gForceY: value(lower.gForceY, upper.gForceY),
            gForceZ: value(lower.gForceZ, upper.gForceZ),
            slipRatio: value(lower.slipRatio, upper.slipRatio)
        )
    }
}

// EN: Builds replay data from the recorded GPX and falls back to report traces for older files.
// ES: Construye la reproducción desde el GPX grabado y usa las trazas del informe para archivos antiguos.
// 中文：优先从录制 GPX 构建回放，旧文件缺少扩展数据时回退到报告轨迹。
nonisolated public enum PTRideReplayBuilder {
    public static func makeSession(report: PTTripReport,
                                   trackPoints: [PTGPXTrackPoint]) throws -> PTRideReplaySession {
        let validPoints = trackPoints.filter {
            $0.latitude.isFinite && $0.longitude.isFinite &&
            (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude)
        }
        guard !validPoints.isEmpty else { throw PTRideReplayError.missingTrack }

        let sampleCount = validPoints.count
        let fallbackDuration = max(report.endTime.timeIntervalSince(report.startTime),
                                   Double(max(sampleCount - 1, 1)))
        let reportWindowIsValid = report.endTime > report.startTime
        var previousTimestamp = report.startTime
        var samples: [PTRideReplaySample] = []
        samples.reserveCapacity(sampleCount)

        for (index, point) in validPoints.enumerated() {
            let fraction = sampleCount > 1
                ? Double(index) / Double(sampleCount - 1)
                : 0
            let fallbackTimestamp = report.startTime.addingTimeInterval(fallbackDuration * fraction)
            let rawTimestamp = point.timestamp ?? fallbackTimestamp
            let boundedTimestamp: Date
            if reportWindowIsValid {
                boundedTimestamp = min(max(rawTimestamp, report.startTime), report.endTime)
            } else {
                boundedTimestamp = rawTimestamp
            }
            let timestamp = max(previousTimestamp, boundedTimestamp)
            previousTimestamp = timestamp

            samples.append(PTRideReplaySample(
                latitude: point.latitude,
                longitude: point.longitude,
                timestamp: timestamp,
                altitude: point.altitude,
                speedKmh: finite(point.speedKmh) ?? traceValue(report.speedTrace, index: index, sampleCount: sampleCount),
                rpm: point.rpm ?? safeRPM(traceValue(report.rpmTrace.map(Double.init), index: index, sampleCount: sampleCount)),
                leanAngle: finite(point.leanAngle) ?? traceValue(report.leanAngleTrace, index: index, sampleCount: sampleCount),
                gForceX: finite(point.gForceX) ?? traceValue(report.gForceXTrace, index: index, sampleCount: sampleCount),
                gForceY: finite(point.gForceY) ?? traceValue(report.gForceYTrace, index: index, sampleCount: sampleCount),
                gForceZ: finite(point.gForceZ) ?? traceValue(report.gForceZTrace, index: index, sampleCount: sampleCount),
                slipRatio: finite(point.slipRatio) ?? traceValue(report.slipRatioTrace, index: index, sampleCount: sampleCount)
            ))
        }

        let reviewEvents = report.reviewEvents.map { event in
            PTRideReplayEvent(
                kind: .review,
                titleKey: event.type.rawValue,
                timestamp: event.timestamp,
                latitude: event.latitude,
                longitude: event.longitude,
                severity: event.severity
            )
        }
        let offRoadEvents = report.offRoadEvents.map { event in
            PTRideReplayEvent(
                kind: .offRoad,
                titleKey: "offRoad",
                timestamp: event.timestamp,
                latitude: event.latitude,
                longitude: event.longitude,
                severity: min(max(abs(event.slipRatio) / 100, 0), 1)
            )
        }
        return PTRideReplaySession(
            report: report,
            samples: samples,
            events: reviewEvents + offRoadEvents
        )
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func traceValue(_ values: [Double], index: Int, sampleCount: Int) -> Double {
        guard let first = values.first else { return 0 }
        guard values.count > 1, sampleCount > 1 else { return finite(first) ?? 0 }
        let position = Double(index) / Double(sampleCount - 1) * Double(values.count - 1)
        let value = values[Int(position.rounded())]
        return finite(value) ?? 0
    }

    private static func safeRPM(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(max(value.rounded(), 0), 1_000_000))
    }
}

// EN: The player is main-actor isolated because it drives UIKit and map updates.
// ES: El reproductor está aislado al actor principal porque actualiza UIKit y el mapa.
// 中文：播放器隔离在主 actor 上，因为它直接驱动 UIKit 和地图刷新。
@MainActor
public final class PTRideReplayPlayer {
    public let session: PTRideReplaySession
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var isPlaying = false
    public var playbackRate: Double = 1
    public var onUpdate: ((PTRideReplaySample?, TimeInterval, Float) -> Void)?

    private var timer: Timer?
    private var lastTickDate: Date?

    public init(session: PTRideReplaySession) {
        self.session = session
    }

    deinit {
        timer?.invalidate()
    }

    public var currentSample: PTRideReplaySample? {
        session.sample(at: elapsed)
    }

    public var progress: Float {
        session.progress(for: elapsed)
    }

    public func play() {
        guard session.samples.count > 1, session.duration > 0 else {
            emitUpdate()
            return
        }
        if elapsed >= session.duration {
            elapsed = 0
        }
        isPlaying = true
        lastTickDate = Date()
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            let player = self
            Task { @MainActor [weak player] in
                player?.tick()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        emitUpdate()
    }

    public func pause() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
        lastTickDate = nil
        emitUpdate()
    }

    public func togglePlayback() {
        isPlaying ? pause() : play()
    }

    public func seek(progress: Float) {
        elapsed = TimeInterval(min(max(progress, 0), 1)) * session.duration
        lastTickDate = Date()
        emitUpdate()
    }

    public func stepForward() {
        seek(elapsed: elapsed + stepDuration)
    }

    public func stepBackward() {
        seek(elapsed: elapsed - stepDuration)
    }

    private var stepDuration: TimeInterval {
        max(session.duration / Double(max(session.samples.count - 1, 1)), 1)
    }

    private func seek(elapsed: TimeInterval) {
        self.elapsed = min(max(elapsed, 0), session.duration)
        lastTickDate = Date()
        emitUpdate()
    }

    private func tick() {
        guard isPlaying else { return }
        let now = Date()
        let delta = min(max(now.timeIntervalSince(lastTickDate ?? now), 0), 0.25)
        lastTickDate = now
        elapsed = min(session.duration, elapsed + delta * max(playbackRate, 0.1))
        if elapsed >= session.duration {
            pause()
        } else {
            emitUpdate()
        }
    }

    private func emitUpdate() {
        onUpdate?(currentSample, elapsed, progress)
    }
}
