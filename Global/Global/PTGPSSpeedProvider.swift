//
//  PTGPSSpeedProvider.swift
//  CrazyDashboard
//
//  EN: Converts validated CLLocation speed samples into the unified speed domain.
//  ES: Convierte muestras de velocidad CLLocation validadas al dominio unificado de velocidad.
//  中文：将经过验证的 CLLocation 速度样本转换为统一车速领域。
//

import CoreLocation
import Foundation

public nonisolated enum PTGPSSpeedProviderStatus: String, Codable, Equatable, Sendable {
    case idle
    case available
    case invalidSpeed
    case poorHorizontalAccuracy
    case poorSpeedAccuracy
    case stale
    case futureTimestamp
}

public nonisolated struct PTGPSSpeedDiagnostics: Codable, Equatable, Sendable {
    public let status: PTGPSSpeedProviderStatus
    public let rawSpeedMetersPerSecond: Double?
    public let filteredSpeedKPH: Double?
    public let horizontalAccuracyMeters: Double?
    public let speedAccuracyMetersPerSecond: Double?
    public let sampleAgeSeconds: TimeInterval?
    public let lastSampleAt: Date?

    public init(
        status: PTGPSSpeedProviderStatus = .idle,
        rawSpeedMetersPerSecond: Double? = nil,
        filteredSpeedKPH: Double? = nil,
        horizontalAccuracyMeters: Double? = nil,
        speedAccuracyMetersPerSecond: Double? = nil,
        sampleAgeSeconds: TimeInterval? = nil,
        lastSampleAt: Date? = nil
    ) {
        self.status = status
        self.rawSpeedMetersPerSecond = rawSpeedMetersPerSecond
        self.filteredSpeedKPH = filteredSpeedKPH
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.speedAccuracyMetersPerSecond = speedAccuracyMetersPerSecond
        self.sampleAgeSeconds = sampleAgeSeconds
        self.lastSampleAt = lastSampleAt
    }
}

// EN: This provider never starts location services; it only validates values received from PTLocationEngine/AMap.
// ES: Este proveedor nunca inicia servicios de ubicación; solo valida valores recibidos de PTLocationEngine/AMap.
// 中文：Provider 不启动定位服务，只验证 PTLocationEngine/AMap 已经提供的值。
public nonisolated struct PTGPSSpeedProvider: Sendable {
    public let policy: PTVehicleSpeedPolicy
    public private(set) var diagnostics = PTGPSSpeedDiagnostics()

    private var recentRawSpeedsKPH: [Double] = []
    private var exponentialSpeedKPH: Double?

    public init(policy: PTVehicleSpeedPolicy = .production) {
        self.policy = policy
    }

    public mutating func ingest(
        location: CLLocation,
        now: Date = Date()
    ) -> PTVehicleSpeedSample? {
        ingest(
            speedMetersPerSecond: location.speed,
            timestamp: location.timestamp,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            speedAccuracyMetersPerSecond: location.speedAccuracy,
            now: now
        )
    }

    public mutating func ingest(
        speedMetersPerSecond: Double,
        timestamp: Date,
        horizontalAccuracyMeters: Double,
        speedAccuracyMetersPerSecond: Double,
        now: Date = Date()
    ) -> PTVehicleSpeedSample? {
        guard speedMetersPerSecond.isFinite, speedMetersPerSecond >= 0 else {
            diagnostics = PTGPSSpeedDiagnostics(
                status: .invalidSpeed,
                rawSpeedMetersPerSecond: speedMetersPerSecond.isFinite ? speedMetersPerSecond : nil,
                horizontalAccuracyMeters: normalized(horizontalAccuracyMeters),
                speedAccuracyMetersPerSecond: normalized(speedAccuracyMetersPerSecond)
            )
            return nil
        }

        guard timestamp <= now else {
            diagnostics = PTGPSSpeedDiagnostics(
                status: .futureTimestamp,
                rawSpeedMetersPerSecond: speedMetersPerSecond,
                horizontalAccuracyMeters: normalized(horizontalAccuracyMeters),
                speedAccuracyMetersPerSecond: normalized(speedAccuracyMetersPerSecond),
                sampleAgeSeconds: 0,
                lastSampleAt: timestamp
            )
            return nil
        }

        let age = now.timeIntervalSince(timestamp)
        guard age <= policy.gpsMaximumAge else {
            diagnostics = PTGPSSpeedDiagnostics(
                status: .stale,
                rawSpeedMetersPerSecond: speedMetersPerSecond,
                horizontalAccuracyMeters: normalized(horizontalAccuracyMeters),
                speedAccuracyMetersPerSecond: normalized(speedAccuracyMetersPerSecond),
                sampleAgeSeconds: age,
                lastSampleAt: timestamp
            )
            return nil
        }

        guard horizontalAccuracyMeters.isFinite,
              horizontalAccuracyMeters > 0,
              horizontalAccuracyMeters <= policy.maximumHorizontalAccuracyMeters else {
            diagnostics = PTGPSSpeedDiagnostics(
                status: .poorHorizontalAccuracy,
                rawSpeedMetersPerSecond: speedMetersPerSecond,
                horizontalAccuracyMeters: normalized(horizontalAccuracyMeters),
                speedAccuracyMetersPerSecond: normalized(speedAccuracyMetersPerSecond),
                sampleAgeSeconds: age,
                lastSampleAt: timestamp
            )
            return nil
        }

        // EN: Core Location uses a negative speedAccuracy when it is unavailable; keep that sample usable but mark it as unknown.
        // ES: Core Location usa un speedAccuracy negativo cuando no está disponible; conservamos la muestra y la marcamos desconocida.
        // 中文：Core Location 在 speedAccuracy 不可用时会返回负数；保留样本，但将该精度标为未知。
        if speedAccuracyMetersPerSecond.isNaN || speedAccuracyMetersPerSecond.isInfinite {
            diagnostics = PTGPSSpeedDiagnostics(
                status: .poorSpeedAccuracy,
                rawSpeedMetersPerSecond: speedMetersPerSecond,
                horizontalAccuracyMeters: horizontalAccuracyMeters,
                sampleAgeSeconds: age,
                lastSampleAt: timestamp
            )
            return nil
        }
        if speedAccuracyMetersPerSecond >= 0,
           speedAccuracyMetersPerSecond > policy.maximumSpeedAccuracyMetersPerSecond {
            diagnostics = PTGPSSpeedDiagnostics(
                status: .poorSpeedAccuracy,
                rawSpeedMetersPerSecond: speedMetersPerSecond,
                horizontalAccuracyMeters: horizontalAccuracyMeters,
                speedAccuracyMetersPerSecond: speedAccuracyMetersPerSecond,
                sampleAgeSeconds: age,
                lastSampleAt: timestamp
            )
            return nil
        }

        let rawKPH = speedMetersPerSecond * 3.6
        guard rawKPH.isFinite, rawKPH <= 400 else {
            diagnostics = PTGPSSpeedDiagnostics(
                status: .invalidSpeed,
                rawSpeedMetersPerSecond: speedMetersPerSecond,
                horizontalAccuracyMeters: horizontalAccuracyMeters,
                speedAccuracyMetersPerSecond: normalized(speedAccuracyMetersPerSecond),
                sampleAgeSeconds: age,
                lastSampleAt: timestamp
            )
            return nil
        }

        recentRawSpeedsKPH.append(rawKPH)
        if recentRawSpeedsKPH.count > policy.medianWindowSize {
            recentRawSpeedsKPH.removeFirst(recentRawSpeedsKPH.count - policy.medianWindowSize)
        }
        let median = median(of: recentRawSpeedsKPH)
        let filtered = exponentialSpeedKPH.map {
            policy.emaAlpha * median + (1 - policy.emaAlpha) * $0
        } ?? median
        let stationary = filtered < policy.stationaryThresholdKPH ? 0 : filtered
        exponentialSpeedKPH = stationary

        diagnostics = PTGPSSpeedDiagnostics(
            status: .available,
            rawSpeedMetersPerSecond: speedMetersPerSecond,
            filteredSpeedKPH: stationary,
            horizontalAccuracyMeters: horizontalAccuracyMeters,
            speedAccuracyMetersPerSecond: normalized(speedAccuracyMetersPerSecond),
            sampleAgeSeconds: age,
            lastSampleAt: timestamp
        )

        return PTVehicleSpeedSample(
            speedKPH: stationary,
            source: .gps,
            timestamp: timestamp,
            quality: PTVehicleSpeedQuality(
                isValid: true,
                horizontalAccuracyMeters: horizontalAccuracyMeters,
                speedAccuracyMetersPerSecond: normalized(speedAccuracyMetersPerSecond),
                rawSpeedMetersPerSecond: speedMetersPerSecond,
                sampleAgeSeconds: age
            )
        )
    }

    public mutating func reset() {
        recentRawSpeedsKPH.removeAll(keepingCapacity: true)
        exponentialSpeedKPH = nil
        diagnostics = PTGPSSpeedDiagnostics()
    }

    private func median(of values: [Double]) -> Double {
        let sorted = values.sorted()
        let middleIndex = sorted.count / 2
        guard sorted.indices.contains(middleIndex) else { return 0 }
        let middle = sorted[middleIndex]
        if sorted.count.isMultiple(of: 2) {
            let lowerIndex = middleIndex - 1
            guard sorted.indices.contains(lowerIndex) else { return middle }
            let lower = sorted[lowerIndex]
            return (lower + middle) / 2
        }
        return middle
    }

    private func normalized(_ value: Double) -> Double? {
        guard value.isFinite, value >= 0 else { return nil }
        return value
    }
}
