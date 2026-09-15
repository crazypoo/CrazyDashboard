//
//  PTBuild66SpeedIntegrationTests.swift
//  PTSpeedTests
//
//  EN: Covers Build 66 trace compatibility without starting a location or vehicle transport.
//  ES: Cubre la compatibilidad de trazas de Build 66 sin iniciar ubicación ni transporte del vehículo.
//  中文：覆盖 Build66 轨迹兼容性，不启动定位或车辆传输。
//

import XCTest
@testable import XP400Ride

final class PTBuild66SpeedIntegrationTests: XCTestCase {
    func testTraceLocationRoundTripPreservesAValidZeroSpeed() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let event = PTCrazyTraceEvent(
            sequence: 0,
            timestamp: date,
            elapsed: 0,
            domain: .location,
            direction: .state,
            source: .live,
            payload: .location(
                PTTraceLocationPayload(
                    latitude: 48.8566,
                    longitude: 2.3522,
                    speedKmh: 0
                )
            )
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(PTCrazyTraceEvent.self, from: data)
        guard case .location(let payload) = decoded.payload else {
            return XCTFail("Expected a location trace payload")
        }
        XCTAssertEqual(payload.speedKmh, 0)
        XCTAssertTrue(decoded.isDomainConsistent)
    }

    func testInstrumentSnapshotWithoutBuild66SpeedFieldRemainsReadable() throws {
        let encoded = try JSONEncoder().encode(PTCrazyDashboardInstrumentSnapshot())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "speed")
        let snapshot = try JSONDecoder().decode(
            PTCrazyDashboardInstrumentSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(snapshot.speed.resolvedSpeedKPH)
        XCTAssertEqual(snapshot.speed.resolutionReason, "noValidSource")
    }
}
