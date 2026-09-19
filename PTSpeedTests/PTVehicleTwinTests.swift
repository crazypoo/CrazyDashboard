//
//  PTVehicleTwinTests.swift
//  PTSpeedTests
//
//  EN: Pure mapping tests for the Build 76A Digital Twin boundary.
//  ES: Pruebas puras del límite de mapeo del Digital Twin de Build 76A.
//  中文：Build 76A 数字孪生映射边界的纯数据测试。
//

import XCTest
@testable import XP400Ride

@MainActor
final class PTVehicleTwinTests: XCTestCase {
    func testFreshnessMovesFromFreshToAgingToStale() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let resolved = PTVehicleTelemetryResolvedValue(
            signal: .speed,
            value: .double(42),
            source: .xp400BLE,
            capturedAt: capturedAt,
            freshness: .fresh,
            confidence: 1,
            isSynthetic: false
        )
        let connection = PTVehicleSnapshot(
            dashboard: PTVehicleLinkSnapshot(state: .connected, transport: .dashboardBluetooth, updatedAt: capturedAt),
            updatedAt: capturedAt
        )

        let fresh = PTVehicleTwinStateMapper.make(
            unified: PTUnifiedVehicleTelemetrySnapshot(values: [resolved], updatedAt: capturedAt),
            connection: connection,
            control: nil,
            now: capturedAt
        )
        let aging = PTVehicleTwinStateMapper.make(
            unified: PTUnifiedVehicleTelemetrySnapshot(values: [resolved], updatedAt: capturedAt),
            connection: connection,
            control: nil,
            now: capturedAt.addingTimeInterval(1.2)
        )
        let stale = PTVehicleTwinStateMapper.make(
            unified: PTUnifiedVehicleTelemetrySnapshot(values: [resolved], updatedAt: capturedAt),
            connection: connection,
            control: nil,
            now: capturedAt.addingTimeInterval(3)
        )

        XCTAssertEqual(fresh.speedKmh?.freshness, .fresh)
        XCTAssertEqual(aging.speedKmh?.freshness, .aging)
        XCTAssertEqual(stale.speedKmh?.freshness, .stale)
        XCTAssertEqual(stale.speedKmh?.value, 42)
    }

    func testMockSourceIsMarkedSyntheticWithoutChangingTheValue() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let fuel = PTVehicleTelemetryResolvedValue(
            signal: .fuel,
            value: .integer(68),
            source: .dashboardMock,
            capturedAt: date,
            freshness: .fresh,
            confidence: 1,
            isSynthetic: true
        )
        let snapshot = PTVehicleTwinStateMapper.make(
            unified: PTUnifiedVehicleTelemetrySnapshot(values: [fuel], updatedAt: date),
            connection: PTVehicleSnapshot(
                dashboard: PTVehicleLinkSnapshot(state: .connected, transport: .dashboardMock, updatedAt: date),
                updatedAt: date
            ),
            control: nil,
            now: date
        )

        XCTAssertEqual(snapshot.fuelPercent?.value, 68)
        XCTAssertTrue(snapshot.fuelPercent?.isSynthetic == true)
        XCTAssertTrue(snapshot.isSynthetic)
    }

    func testUnavailableDoesNotBecomeNumericZero() {
        let snapshot = PTVehicleTwinStateMapper.make(
            unified: .empty,
            connection: .initial,
            control: nil,
            now: Date()
        )

        XCTAssertNil(snapshot.speedKmh)
        XCTAssertNil(snapshot.rpm)
        XCTAssertNil(snapshot.fuelPercent)
        XCTAssertNil(snapshot.voltage)
        XCTAssertEqual(snapshot.freshness, .unavailable)
    }

    func testDisconnectedTransportDowngradesCachedTransportValue() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let speed = PTVehicleTelemetryResolvedValue(
            signal: .speed,
            value: .double(42),
            source: .xp400BLE,
            capturedAt: date,
            freshness: .fresh,
            confidence: 1,
            isSynthetic: false
        )
        let snapshot = PTVehicleTwinStateMapper.make(
            unified: PTUnifiedVehicleTelemetrySnapshot(values: [speed], updatedAt: date),
            connection: .initial,
            control: nil,
            now: date
        )

        XCTAssertEqual(snapshot.speedKmh?.value, 42)
        XCTAssertEqual(snapshot.speedKmh?.freshness, .stale)
        XCTAssertEqual(snapshot.dashboardConnected, false)
    }

    func testMotionAndEngineSignalsRemainSeparated() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let values = [
            PTVehicleTelemetryResolvedValue(signal: .lean, value: .double(-7.5), source: .motion, capturedAt: date, freshness: .fresh, confidence: 1, isSynthetic: false),
            PTVehicleTelemetryResolvedValue(signal: .pitch, value: .double(2.5), source: .motion, capturedAt: date, freshness: .fresh, confidence: 1, isSynthetic: false),
            PTVehicleTelemetryResolvedValue(signal: .gForceX, value: .double(0.12), source: .motion, capturedAt: date, freshness: .fresh, confidence: 1, isSynthetic: false),
            PTVehicleTelemetryResolvedValue(signal: .engineStatus, value: .integer(2), source: .xp400BLE, capturedAt: date, freshness: .fresh, confidence: 1, isSynthetic: false)
        ]
        let snapshot = PTVehicleTwinStateMapper.make(
            unified: PTUnifiedVehicleTelemetrySnapshot(values: values, updatedAt: date),
            connection: PTVehicleSnapshot.initial,
            control: nil,
            now: date
        )

        XCTAssertEqual(snapshot.leanDegrees?.value, -7.5)
        XCTAssertEqual(snapshot.pitchDegrees?.value, 2.5)
        XCTAssertEqual(snapshot.longitudinalG?.value, 0.12)
        XCTAssertEqual(snapshot.engineState?.value, .running)
    }
}
