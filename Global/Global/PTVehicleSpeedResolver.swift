//
//  PTVehicleSpeedResolver.swift
//  CrazyDashboard
//
//  EN: Defines the read-only speed domain and resolves XP400, OBD, GPS, and replay samples.
//  ES: Define el dominio de velocidad de solo lectura y resuelve muestras de XP400, OBD, GPS y reproducción.
//  中文：定义只读车速领域，并仲裁 XP400、OBD、GPS 与回放数据。
//

import Foundation

public nonisolated enum PTVehicleSpeedSource: String, Codable, CaseIterable, Equatable, Sendable {
    case xp400
    case obd
    case gps
    case replay
}

public nonisolated struct PTVehicleSpeedQuality: Codable, Equatable, Sendable {
    public let isValid: Bool
    public let horizontalAccuracyMeters: Double?
    public let speedAccuracyMetersPerSecond: Double?
    public let rawSpeedMetersPerSecond: Double?
    public let sampleAgeSeconds: TimeInterval

    public init(
        isValid: Bool = true,
        horizontalAccuracyMeters: Double? = nil,
        speedAccuracyMetersPerSecond: Double? = nil,
        rawSpeedMetersPerSecond: Double? = nil,
        sampleAgeSeconds: TimeInterval = 0
    ) {
        self.isValid = isValid
        self.horizontalAccuracyMeters = Self.normalizedNonNegative(horizontalAccuracyMeters)
        self.speedAccuracyMetersPerSecond = Self.normalizedNonNegative(speedAccuracyMetersPerSecond)
        self.rawSpeedMetersPerSecond = Self.normalizedNonNegative(rawSpeedMetersPerSecond)
        self.sampleAgeSeconds = sampleAgeSeconds.isFinite ? max(sampleAgeSeconds, 0) : 0
    }

    public static let valid = PTVehicleSpeedQuality()

    private static func normalizedNonNegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

public nonisolated struct PTVehicleSpeedSample: Codable, Equatable, Sendable {
    public let speedKPH: Double
    public let source: PTVehicleSpeedSource
    public let timestamp: Date
    public let quality: PTVehicleSpeedQuality
    public let isSynthetic: Bool

    public init?(
        speedKPH: Double,
        source: PTVehicleSpeedSource,
        timestamp: Date = Date(),
        quality: PTVehicleSpeedQuality = .valid,
        isSynthetic: Bool = false
    ) {
        guard speedKPH.isFinite, (0...400).contains(speedKPH) else { return nil }
        self.speedKPH = speedKPH
        self.source = source
        self.timestamp = timestamp
        self.quality = quality
        self.isSynthetic = isSynthetic
    }
}

public nonisolated struct PTVehicleSpeedPolicy: Codable, Equatable, Sendable {
    public let xp400MaximumAge: TimeInterval
    public let obdMaximumAge: TimeInterval
    public let gpsMaximumAge: TimeInterval
    public let replayMaximumAge: TimeInterval
    public let maximumHorizontalAccuracyMeters: Double
    public let maximumSpeedAccuracyMetersPerSecond: Double
    public let stationaryThresholdKPH: Double
    public let medianWindowSize: Int
    public let emaAlpha: Double
    public let takeoverSampleCount: Int

    public init(
        xp400MaximumAge: TimeInterval = 1.5,
        obdMaximumAge: TimeInterval = 2.0,
        gpsMaximumAge: TimeInterval = 3.0,
        replayMaximumAge: TimeInterval = 3.0,
        maximumHorizontalAccuracyMeters: Double = 30,
        maximumSpeedAccuracyMetersPerSecond: Double = 3.0,
        stationaryThresholdKPH: Double = 2.0,
        medianWindowSize: Int = 3,
        emaAlpha: Double = 0.45,
        takeoverSampleCount: Int = 2
    ) {
        self.xp400MaximumAge = max(xp400MaximumAge, 0.1)
        self.obdMaximumAge = max(obdMaximumAge, 0.1)
        self.gpsMaximumAge = max(gpsMaximumAge, 0.1)
        self.replayMaximumAge = max(replayMaximumAge, 0.1)
        self.maximumHorizontalAccuracyMeters = max(maximumHorizontalAccuracyMeters, 0.1)
        self.maximumSpeedAccuracyMetersPerSecond = max(maximumSpeedAccuracyMetersPerSecond, 0.1)
        self.stationaryThresholdKPH = max(stationaryThresholdKPH, 0)
        self.medianWindowSize = max(medianWindowSize, 1)
        self.emaAlpha = min(max(emaAlpha, 0), 1)
        self.takeoverSampleCount = max(takeoverSampleCount, 1)
    }

    public static let production = PTVehicleSpeedPolicy()

    public func maximumAge(for source: PTVehicleSpeedSource) -> TimeInterval {
        switch source {
        case .xp400: return xp400MaximumAge
        case .obd: return obdMaximumAge
        case .gps: return gpsMaximumAge
        case .replay: return replayMaximumAge
        }
    }

    public func priority(for source: PTVehicleSpeedSource) -> Int {
        switch source {
        case .xp400: return 400
        case .obd: return 300
        case .gps: return 200
        case .replay: return 500
        }
    }
}

public nonisolated enum PTVehicleSpeedResolutionReason: String, Codable, Equatable, Sendable {
    case initial
    case keptCurrent
    case higherPriorityPending
    case higherPriorityTakeover
    case fallbackAfterStale
    case sourceRemoved
    case replayOverride
    case noValidSource
}

public nonisolated struct PTResolvedVehicleSpeed: Codable, Equatable, Sendable {
    public let speedKPH: Double?
    public let source: PTVehicleSpeedSource?
    public let sampleTimestamp: Date?
    public let resolvedAt: Date
    public let candidateAgeSeconds: TimeInterval?
    public let isFresh: Bool
    public let isSynthetic: Bool
    public let reason: PTVehicleSpeedResolutionReason
    public let switchCount: Int

    public init(
        speedKPH: Double?,
        source: PTVehicleSpeedSource?,
        sampleTimestamp: Date?,
        resolvedAt: Date,
        candidateAgeSeconds: TimeInterval?,
        isFresh: Bool,
        isSynthetic: Bool = false,
        reason: PTVehicleSpeedResolutionReason,
        switchCount: Int
    ) {
        self.speedKPH = speedKPH
        self.source = source
        self.sampleTimestamp = sampleTimestamp
        self.resolvedAt = resolvedAt
        self.candidateAgeSeconds = candidateAgeSeconds
        self.isFresh = isFresh
        self.isSynthetic = isSynthetic
        self.reason = reason
        self.switchCount = max(switchCount, 0)
    }

    public static let unavailable = PTResolvedVehicleSpeed(
        speedKPH: nil,
        source: nil,
        sampleTimestamp: nil,
        resolvedAt: .distantPast,
        candidateAgeSeconds: nil,
        isFresh: false,
        isSynthetic: false,
        reason: .noValidSource,
        switchCount: 0
    )

    public var speedKmh: Double? { speedKPH }
}

public nonisolated struct PTVehicleSpeedCandidateDiagnostics: Codable, Equatable, Sendable {
    public let source: PTVehicleSpeedSource
    public let speedKPH: Double
    public let timestamp: Date
    public let ageSeconds: TimeInterval
    public let isFresh: Bool
    public let isSynthetic: Bool
    public let quality: PTVehicleSpeedQuality

    public init(
        source: PTVehicleSpeedSource,
        speedKPH: Double,
        timestamp: Date,
        ageSeconds: TimeInterval,
        isFresh: Bool,
        isSynthetic: Bool,
        quality: PTVehicleSpeedQuality
    ) {
        self.source = source
        self.speedKPH = speedKPH
        self.timestamp = timestamp
        self.ageSeconds = max(ageSeconds, 0)
        self.isFresh = isFresh
        self.isSynthetic = isSynthetic
        self.quality = quality
    }
}

public nonisolated struct PTVehicleSpeedResolverDiagnostics: Codable, Equatable, Sendable {
    public let resolved: PTResolvedVehicleSpeed
    public let candidates: [PTVehicleSpeedCandidateDiagnostics]
    public let currentSource: PTVehicleSpeedSource?
    public let switchCount: Int
    public let pendingSource: PTVehicleSpeedSource?
    public let pendingSampleCount: Int
    public let lastResolutionReason: PTVehicleSpeedResolutionReason

    public init(
        resolved: PTResolvedVehicleSpeed,
        candidates: [PTVehicleSpeedCandidateDiagnostics],
        currentSource: PTVehicleSpeedSource?,
        switchCount: Int,
        pendingSource: PTVehicleSpeedSource?,
        pendingSampleCount: Int,
        lastResolutionReason: PTVehicleSpeedResolutionReason
    ) {
        self.resolved = resolved
        self.candidates = candidates
        self.currentSource = currentSource
        self.switchCount = max(switchCount, 0)
        self.pendingSource = pendingSource
        self.pendingSampleCount = max(pendingSampleCount, 0)
        self.lastResolutionReason = lastResolutionReason
    }
}

// EN: The resolver is a value type owned by the MainActor bridge, so selection is deterministic and race-free.
// ES: El resolvedor es un tipo valor propiedad del puente MainActor, por lo que la selección es determinista y segura.
// 中文：Resolver 是由 MainActor Bridge 持有的值类型，保证选择过程确定且无数据竞争。
public nonisolated struct PTVehicleSpeedResolver: Sendable {
    public let policy: PTVehicleSpeedPolicy

    private var candidates: [PTVehicleSpeedSource: PTVehicleSpeedSample] = [:]
    private var pendingSource: PTVehicleSpeedSource?
    private var pendingSampleTimestamp: Date?
    private var pendingSampleCount = 0
    private var forcedReason: PTVehicleSpeedResolutionReason?

    public private(set) var currentSource: PTVehicleSpeedSource?
    public private(set) var switchCount = 0
    public private(set) var lastResolutionReason: PTVehicleSpeedResolutionReason = .noValidSource
    public private(set) var lastResolved: PTResolvedVehicleSpeed = .unavailable

    public init(policy: PTVehicleSpeedPolicy = .production) {
        self.policy = policy
    }

    public mutating func ingest(_ sample: PTVehicleSpeedSample) {
        guard sample.quality.isValid else { return }
        if let existing = candidates[sample.source], existing.timestamp > sample.timestamp {
            return
        }
        candidates[sample.source] = sample

        guard let currentSource else { return }
        if sample.source == currentSource {
            resetPending()
            return
        }
        guard policy.priority(for: sample.source) > policy.priority(for: currentSource) else { return }

        if pendingSource != sample.source {
            pendingSource = sample.source
            pendingSampleTimestamp = sample.timestamp
            pendingSampleCount = 1
        } else if pendingSampleTimestamp != sample.timestamp {
            pendingSampleTimestamp = sample.timestamp
            pendingSampleCount += 1
        }
    }

    public mutating func removeSource(_ source: PTVehicleSpeedSource) {
        candidates[source] = nil
        if currentSource == source {
            currentSource = nil
            forcedReason = .sourceRemoved
        }
        if pendingSource == source {
            resetPending()
        }
    }

    public mutating func reset() {
        candidates.removeAll(keepingCapacity: true)
        currentSource = nil
        switchCount = 0
        lastResolutionReason = .noValidSource
        lastResolved = .unavailable
        forcedReason = nil
        resetPending()
    }

    public mutating func resolve(
        at now: Date = Date(),
        replayActive: Bool = false
    ) -> PTResolvedVehicleSpeed {
        let available = freshCandidates(at: now, replayActive: replayActive)
        if replayActive {
            guard let replay = available.first(where: { $0.source == .replay }) else {
                return storeUnavailable(at: now, reason: .noValidSource)
            }
            let reason: PTVehicleSpeedResolutionReason = .replayOverride
            transition(to: .replay, at: now)
            return storeResult(for: replay, at: now, reason: reason)
        }

        guard let best = available.first else {
            let reason = forcedReason ?? .noValidSource
            currentSource = nil
            resetPending()
            return storeUnavailable(at: now, reason: reason)
        }

        if let currentSource,
           let current = available.first(where: { $0.source == currentSource }) {
            if best.source == current.source {
                resetPending()
                return storeResult(for: current, at: now, reason: .keptCurrent)
            }

            if policy.priority(for: best.source) > policy.priority(for: current.source) {
                guard pendingSource == best.source,
                      pendingSampleCount >= policy.takeoverSampleCount else {
                    return storeResult(for: current, at: now, reason: .higherPriorityPending)
                }
                transition(to: best.source, at: now)
                resetPending()
                return storeResult(for: best, at: now, reason: .higherPriorityTakeover)
            }

            resetPending()
            return storeResult(for: current, at: now, reason: .keptCurrent)
        }

        let wasSource = currentSource
        let reason: PTVehicleSpeedResolutionReason
        if let forcedReason {
            reason = forcedReason
            self.forcedReason = nil
        } else if wasSource != nil {
            reason = .fallbackAfterStale
        } else {
            reason = .initial
        }
        transition(to: best.source, at: now)
        resetPending()
        return storeResult(for: best, at: now, reason: reason)
    }

    public mutating func diagnostics(
        at now: Date = Date(),
        replayActive: Bool = false
    ) -> PTVehicleSpeedResolverDiagnostics {
        let resolved = resolve(at: now, replayActive: replayActive)
        let items = candidates.values
            .sorted { lhs, rhs in policy.priority(for: lhs.source) > policy.priority(for: rhs.source) }
            .map { sample in
                let age = max(0, now.timeIntervalSince(sample.timestamp))
                return PTVehicleSpeedCandidateDiagnostics(
                    source: sample.source,
                    speedKPH: sample.speedKPH,
                    timestamp: sample.timestamp,
                    ageSeconds: age,
                    isFresh: isFresh(sample, at: now, replayActive: replayActive),
                    isSynthetic: sample.isSynthetic,
                    quality: sample.quality
                )
            }
        return PTVehicleSpeedResolverDiagnostics(
            resolved: resolved,
            candidates: items,
            currentSource: currentSource,
            switchCount: switchCount,
            pendingSource: pendingSource,
            pendingSampleCount: pendingSampleCount,
            lastResolutionReason: lastResolutionReason
        )
    }

    private func freshCandidates(
        at now: Date,
        replayActive: Bool
    ) -> [PTVehicleSpeedSample] {
        candidates.values
            .filter { isFresh($0, at: now, replayActive: replayActive) }
            .sorted { lhs, rhs in
                let lhsPriority = policy.priority(for: lhs.source)
                let rhsPriority = policy.priority(for: rhs.source)
                if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
                return lhs.timestamp > rhs.timestamp
            }
    }

    private func isFresh(
        _ sample: PTVehicleSpeedSample,
        at now: Date,
        replayActive: Bool
    ) -> Bool {
        guard sample.quality.isValid,
              replayActive || sample.source != .replay,
              sample.timestamp <= now else {
            return false
        }
        return now.timeIntervalSince(sample.timestamp) <= policy.maximumAge(for: sample.source)
    }

    private mutating func transition(to source: PTVehicleSpeedSource, at _: Date) {
        if let currentSource, currentSource != source {
            switchCount += 1
        }
        currentSource = source
    }

    private mutating func storeResult(
        for sample: PTVehicleSpeedSample,
        at now: Date,
        reason: PTVehicleSpeedResolutionReason
    ) -> PTResolvedVehicleSpeed {
        let result = PTResolvedVehicleSpeed(
            speedKPH: sample.speedKPH,
            source: sample.source,
            sampleTimestamp: sample.timestamp,
            resolvedAt: now,
            candidateAgeSeconds: max(0, now.timeIntervalSince(sample.timestamp)),
            isFresh: true,
            isSynthetic: sample.isSynthetic,
            reason: reason,
            switchCount: switchCount
        )
        lastResolutionReason = reason
        lastResolved = result
        forcedReason = nil
        return result
    }

    private mutating func storeUnavailable(
        at now: Date,
        reason: PTVehicleSpeedResolutionReason
    ) -> PTResolvedVehicleSpeed {
        let result = PTResolvedVehicleSpeed(
            speedKPH: nil,
            source: nil,
            sampleTimestamp: nil,
            resolvedAt: now,
            candidateAgeSeconds: nil,
            isFresh: false,
            reason: reason,
            switchCount: switchCount
        )
        lastResolutionReason = reason
        lastResolved = result
        forcedReason = nil
        return result
    }

    private mutating func resetPending() {
        pendingSource = nil
        pendingSampleTimestamp = nil
        pendingSampleCount = 0
    }
}
