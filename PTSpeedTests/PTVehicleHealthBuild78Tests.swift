//
//  PTVehicleHealthBuild78Tests.swift
//  CrazyDashboard
//
//  EN: Pure Build 78 tests for health filtering, trends, and diagnostic severity.
//  ES: Pruebas puras de Build 78 para filtros, tendencias y severidad diagnóstica.
//  中文：Build 78 健康数据过滤、趋势和诊断严重程度的纯逻辑测试。
//

import XCTest
@testable import XP400Ride

final class PTVehicleHealthBuild78Tests: XCTestCase {
    func testSummarySeparatesSyntheticPointsFromRealPoints() {
        let vehicleID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let points = [
            PTVehicleHealthPoint(
                vehicleID: vehicleID,
                capturedAt: now.addingTimeInterval(-86_400),
                source: .liveTelemetry,
                isSynthetic: true,
                batteryVoltage: 12.4,
                mileageKm: 100
            ),
            PTVehicleHealthPoint(
                vehicleID: vehicleID,
                capturedAt: now,
                source: .liveTelemetry,
                batteryVoltage: 12.6,
                mileageKm: 120
            )
        ]

        let summary = PTVehicleHealthAnalyzer.summarize(
            points: points,
            vehicleID: vehicleID,
            includeSynthetic: false,
            now: now
        )

        XCTAssertEqual(summary.totalPointCount, 1)
        XCTAssertEqual(summary.realPointCount, 1)
        XCTAssertFalse(summary.isSyntheticOnly)
        XCTAssertEqual(summary.battery.latest, 12.6)
        XCTAssertEqual(summary.mileage.slopePerDay, nil)
    }

    func testChartValuesFilterVehicleAndSyntheticData() {
        let vehicleID = UUID()
        let otherVehicleID = UUID()
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
        let points = [
            PTVehicleHealthPoint(
                vehicleID: vehicleID,
                capturedAt: firstDate,
                source: .liveTelemetry,
                batteryVoltage: 12.1
            ),
            PTVehicleHealthPoint(
                vehicleID: vehicleID,
                capturedAt: firstDate.addingTimeInterval(60),
                source: .liveTelemetry,
                isSynthetic: true,
                batteryVoltage: 13.1
            ),
            PTVehicleHealthPoint(
                vehicleID: otherVehicleID,
                capturedAt: firstDate.addingTimeInterval(120),
                source: .liveTelemetry,
                batteryVoltage: 14.1
            )
        ]

        let realValues = PTVehicleHealthAnalyzer.chartValues(
            for: .battery,
            points: points,
            vehicleID: vehicleID,
            includeSynthetic: false
        )
        let allValues = PTVehicleHealthAnalyzer.chartValues(
            for: .battery,
            points: points,
            vehicleID: vehicleID,
            includeSynthetic: true
        )

        XCTAssertEqual(realValues.map(\.value), [12.1])
        XCTAssertEqual(allValues.map(\.value), [12.1, 13.1])
    }

    func testConfirmedDiagnosticCodeMarksHealthCritical() {
        let vehicleID = UUID()
        let point = PTVehicleHealthPoint(
            vehicleID: vehicleID,
            source: .diagnostic,
            confirmedDTCCount: 1
        )

        let summary = PTVehicleHealthAnalyzer.summarize(
            points: [point],
            vehicleID: vehicleID
        )

        XCTAssertEqual(summary.overallState, .critical)
    }
}
