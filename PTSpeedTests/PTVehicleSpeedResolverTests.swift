//
//  PTVehicleSpeedResolverTests.swift
//  PTSpeedTests
//
//  EN: Verifies deterministic source priority, freshness, hysteresis, and replay override.
//  ES: Verifica prioridad de fuentes, frescura, histéresis y sobrescritura de reproducción deterministas.
//  中文：验证来源优先级、新鲜度、滞回切换和回放覆盖的确定性。
//

import XCTest
@testable import XP400Ride

final class PTVehicleSpeedResolverTests: XCTestCase {
    func testValidZeroIsDifferentFromUnavailable() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var resolver = PTVehicleSpeedResolver()
        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 0,
                    source: .gps,
                    timestamp: date
                )
            )
        )

        let zero = resolver.resolve(at: date)
        XCTAssertEqual(zero.speedKPH, 0)
        XCTAssertEqual(zero.source, .gps)
        XCTAssertTrue(zero.isFresh)

        resolver.reset()
        let unavailable = resolver.resolve(at: date)
        XCTAssertNil(unavailable.speedKPH)
        XCTAssertNil(unavailable.source)
        XCTAssertFalse(unavailable.isFresh)
        XCTAssertEqual(unavailable.reason, .noValidSource)
    }

    func testHigherPrioritySourceNeedsTwoConsecutiveSamples() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var resolver = PTVehicleSpeedResolver()
        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 20,
                    source: .gps,
                    timestamp: date
                )
            )
        )
        XCTAssertEqual(resolver.resolve(at: date).source, .gps)

        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 21,
                    source: .xp400,
                    timestamp: date.addingTimeInterval(0.1)
                )
            )
        )
        let pending = resolver.resolve(at: date.addingTimeInterval(0.1))
        XCTAssertEqual(pending.source, .gps)
        XCTAssertEqual(pending.reason, .higherPriorityPending)

        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 22,
                    source: .xp400,
                    timestamp: date.addingTimeInterval(0.2)
                )
            )
        )
        let takeover = resolver.resolve(at: date.addingTimeInterval(0.2))
        XCTAssertEqual(takeover.source, .xp400)
        XCTAssertEqual(takeover.speedKPH, 22)
        XCTAssertEqual(takeover.reason, .higherPriorityTakeover)
        XCTAssertEqual(takeover.switchCount, 1)
    }

    func testFreshLowerPrioritySourceTakesOverImmediatelyAfterHigherSourceExpires() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var resolver = PTVehicleSpeedResolver()
        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 80,
                    source: .xp400,
                    timestamp: date
                )
            )
        )
        XCTAssertEqual(resolver.resolve(at: date).source, .xp400)

        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 48,
                    source: .obd,
                    timestamp: date.addingTimeInterval(1.6)
                )
            )
        )
        let fallback = resolver.resolve(at: date.addingTimeInterval(1.6))
        XCTAssertEqual(fallback.source, .obd)
        XCTAssertEqual(fallback.speedKPH, 48)
        XCTAssertEqual(fallback.reason, .fallbackAfterStale)
    }

    func testObdFallsBackToGPSAfterObdExpires() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var resolver = PTVehicleSpeedResolver()
        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 46,
                    source: .obd,
                    timestamp: date
                )
            )
        )
        XCTAssertEqual(resolver.resolve(at: date).source, .obd)

        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 42,
                    source: .gps,
                    timestamp: date.addingTimeInterval(2.1)
                )
            )
        )

        let fallback = resolver.resolve(at: date.addingTimeInterval(2.1))
        XCTAssertEqual(fallback.source, .gps)
        XCTAssertEqual(fallback.speedKPH, 42)
        XCTAssertEqual(fallback.reason, .fallbackAfterStale)
    }

    func testGpsFallsBackToObdAfterGpsExpires() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var resolver = PTVehicleSpeedResolver()
        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 35,
                    source: .gps,
                    timestamp: date
                )
            )
        )
        XCTAssertEqual(resolver.resolve(at: date).source, .gps)

        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 34,
                    source: .obd,
                    timestamp: date.addingTimeInterval(3.1)
                )
            )
        )
        let fallback = resolver.resolve(at: date.addingTimeInterval(3.1))
        XCTAssertEqual(fallback.source, .obd)
        XCTAssertEqual(fallback.reason, .fallbackAfterStale)
    }

    func testXp400FallsBackDirectlyToGPSWhenObdIsUnavailable() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var resolver = PTVehicleSpeedResolver()
        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 72,
                    source: .xp400,
                    timestamp: date
                )
            )
        )
        XCTAssertEqual(resolver.resolve(at: date).source, .xp400)

        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 20,
                    source: .gps,
                    timestamp: date.addingTimeInterval(1.6)
                )
            )
        )
        let fallback = resolver.resolve(at: date.addingTimeInterval(1.6))
        XCTAssertEqual(fallback.source, .gps)
        XCTAssertEqual(fallback.reason, .fallbackAfterStale)
    }

    func testXp400TakesOverObdOnlyAfterTwoFreshSamples() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var resolver = PTVehicleSpeedResolver()
        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 54,
                    source: .obd,
                    timestamp: date
                )
            )
        )
        XCTAssertEqual(resolver.resolve(at: date).source, .obd)

        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 55,
                    source: .xp400,
                    timestamp: date.addingTimeInterval(0.1)
                )
            )
        )
        XCTAssertEqual(
            resolver.resolve(at: date.addingTimeInterval(0.1)).reason,
            .higherPriorityPending
        )

        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 56,
                    source: .xp400,
                    timestamp: date.addingTimeInterval(0.2)
                )
            )
        )
        let takeover = resolver.resolve(at: date.addingTimeInterval(0.2))
        XCTAssertEqual(takeover.source, .xp400)
        XCTAssertEqual(takeover.reason, .higherPriorityTakeover)
    }

    func testUnavailableBecomesGPSWithoutConnectionState() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var resolver = PTVehicleSpeedResolver()
        XCTAssertEqual(resolver.resolve(at: date).reason, .noValidSource)

        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 18,
                    source: .gps,
                    timestamp: date.addingTimeInterval(0.5)
                )
            )
        )
        let gps = resolver.resolve(at: date.addingTimeInterval(0.5))
        XCTAssertEqual(gps.source, .gps)
        XCTAssertEqual(gps.speedKPH, 18)
        XCTAssertEqual(gps.reason, .initial)
    }

    func testReplayExplicitlyOverridesLiveSources() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var resolver = PTVehicleSpeedResolver()
        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 60,
                    source: .xp400,
                    timestamp: date
                )
            )
        )
        XCTAssertEqual(resolver.resolve(at: date).source, .xp400)

        resolver.ingest(
            try XCTUnwrap(
                PTVehicleSpeedSample(
                    speedKPH: 12,
                    source: .replay,
                    timestamp: date.addingTimeInterval(0.1),
                    isSynthetic: true
                )
            )
        )
        let replay = resolver.resolve(at: date.addingTimeInterval(0.1), replayActive: true)
        XCTAssertEqual(replay.source, .replay)
        XCTAssertEqual(replay.speedKPH, 12)
        XCTAssertEqual(replay.reason, .replayOverride)
        XCTAssertTrue(replay.isSynthetic)
    }
}
