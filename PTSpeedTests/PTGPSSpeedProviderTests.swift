//
//  PTGPSSpeedProviderTests.swift
//  PTSpeedTests
//
//  EN: Verifies GPS speed validation, unit conversion, smoothing, and zero-speed handling.
//  ES: Verifica la validación GPS, la conversión de unidades, el suavizado y la gestión de velocidad cero.
//  中文：验证 GPS 车速校验、单位换算、平滑和合法零速处理。
//

import XCTest
@testable import XP400Ride

final class PTGPSSpeedProviderTests: XCTestCase {
    func testConvertsMetersPerSecondAndAcceptsUnknownSpeedAccuracy() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var provider = PTGPSSpeedProvider()

        let sample = try XCTUnwrap(
            provider.ingest(
                speedMetersPerSecond: 10,
                timestamp: date,
                horizontalAccuracyMeters: 5,
                speedAccuracyMetersPerSecond: -1,
                now: date
            )
        )

        XCTAssertEqual(sample.speedKPH, 36, accuracy: 0.001)
        XCTAssertEqual(sample.source, .gps)
        XCTAssertNil(sample.quality.speedAccuracyMetersPerSecond)
        XCTAssertEqual(provider.diagnostics.status, .available)
    }

    func testMedianAndEMALimitOneGPSSpike() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var provider = PTGPSSpeedProvider()

        for offset in 0..<3 {
            _ = try XCTUnwrap(
                provider.ingest(
                    speedMetersPerSecond: 10,
                    timestamp: date.addingTimeInterval(Double(offset)),
                    horizontalAccuracyMeters: 5,
                    speedAccuracyMetersPerSecond: 1,
                    now: date.addingTimeInterval(Double(offset))
                )
            )
        }
        let spike = try XCTUnwrap(
            provider.ingest(
                speedMetersPerSecond: 30,
                timestamp: date.addingTimeInterval(3),
                horizontalAccuracyMeters: 5,
                speedAccuracyMetersPerSecond: 1,
                now: date.addingTimeInterval(3)
            )
        )

        XCTAssertEqual(spike.speedKPH, 36, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(provider.diagnostics.filteredSpeedKPH), 36, accuracy: 0.001)
    }

    func testStationaryThresholdPreservesAValidZeroSample() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var provider = PTGPSSpeedProvider()
        let sample = try XCTUnwrap(
            provider.ingest(
                speedMetersPerSecond: 0,
                timestamp: date,
                horizontalAccuracyMeters: 5,
                speedAccuracyMetersPerSecond: 1,
                now: date
            )
        )

        XCTAssertEqual(sample.speedKPH, 0)
        XCTAssertEqual(provider.diagnostics.filteredSpeedKPH, 0)
    }

    func testRejectsInvalidSpeedStaleLocationAndPoorAccuracy() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var provider = PTGPSSpeedProvider()

        XCTAssertNil(
            provider.ingest(
                speedMetersPerSecond: -1,
                timestamp: date,
                horizontalAccuracyMeters: 5,
                speedAccuracyMetersPerSecond: 1,
                now: date
            )
        )
        XCTAssertEqual(provider.diagnostics.status, .invalidSpeed)

        XCTAssertNil(
            provider.ingest(
                speedMetersPerSecond: 10,
                timestamp: date.addingTimeInterval(-4),
                horizontalAccuracyMeters: 5,
                speedAccuracyMetersPerSecond: 1,
                now: date
            )
        )
        XCTAssertEqual(provider.diagnostics.status, .stale)

        XCTAssertNil(
            provider.ingest(
                speedMetersPerSecond: 10,
                timestamp: date,
                horizontalAccuracyMeters: 31,
                speedAccuracyMetersPerSecond: 1,
                now: date
            )
        )
        XCTAssertEqual(provider.diagnostics.status, .poorHorizontalAccuracy)

        XCTAssertNil(
            provider.ingest(
                speedMetersPerSecond: 10,
                timestamp: date,
                horizontalAccuracyMeters: 5,
                speedAccuracyMetersPerSecond: 4,
                now: date
            )
        )
        XCTAssertEqual(provider.diagnostics.status, .poorSpeedAccuracy)
    }
}
