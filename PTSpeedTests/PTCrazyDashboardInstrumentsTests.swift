//
//  PTCrazyDashboardInstrumentsTests.swift
//  PTSpeedTests
//
//  EN: Covers the bounded history, rate windows, and export-safe value models used by Build 59.
//  ES: Cubre el historial acotado, las ventanas de frecuencia y los modelos seguros de exportación de Build 59.
//  中文：覆盖 Build 59 使用的有界历史、速率窗口和安全导出值模型。
//

import XCTest
@testable import XP400Ride

final class PTCrazyDashboardInstrumentsTests: XCTestCase {
    func testHistoryRemainsBoundedAndKeepsNewestValues() {
        var history = PTCrazyDashboardInstrumentHistory<Int>(maximumCount: 3)
        for value in 0..<10_000 {
            history.append(value)
        }

        XCTAssertEqual(history.elements.count, 3)
        XCTAssertEqual(history.elements, [9_997, 9_998, 9_999])
    }

    func testRateWindowReportsObservedSamplesOnly() {
        var window = PTCrazyDashboardInstrumentRateWindow(window: 10)
        let start = Date(timeIntervalSince1970: 1_000)
        for offset in 0...9 {
            window.record(at: start.addingTimeInterval(TimeInterval(offset)))
        }

        XCTAssertEqual(window.count, 10)
        XCTAssertEqual(window.rate(at: start.addingTimeInterval(10)) ?? 0, 1, accuracy: 0.001)
        XCTAssertNil(window.rate(at: start.addingTimeInterval(21)))
    }

    func testCSVEscapingKeepsTimelineFieldsParseable() {
        XCTAssertEqual(
            PTCrazyDashboardInstrumentCSV.escape("a,b\n\"c\""),
            "\"a,b\n\"\"c\"\"\""
        )
        XCTAssertEqual(PTCrazyDashboardInstrumentCSV.escape("plain"), "plain")
    }

    func testInstrumentSnapshotRoundTripsWithoutTransportObjects() throws {
        let snapshot = PTCrazyDashboardInstrumentSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            xp400BLE: PTCrazyDashboardXP400BLEMetrics(isConnected: true, rxPerSecond: 12.5),
            obd: PTCrazyDashboardOBDMetrics(isConnected: true, elmState: "polling"),
            ymobdAdapter: PTCrazyDashboardAdapterMetrics(vendor: "YMOBD", isOfficialYMOBD: true),
            adapterOTA: PTCrazyDashboardOTAMetrics(isVisible: true, state: "upgrading", progress: 0.5),
            can: PTCrazyDashboardCANMetrics(state: "recording", totalFrameCount: 12),
            telemetry: PTCrazyDashboardTelemetryMetrics(mode: "live", valueCount: 4),
            gps: PTCrazyDashboardGPSMetrics(isTracking: true, horizontalAccuracyMeters: 3),
            motion: PTCrazyDashboardMotionMetrics(roll: 4.2),
            system: PTCrazyDashboardSystemMetrics(buildVersion: "59")
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PTCrazyDashboardInstrumentSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertTrue(decoded.system.isReadOnly)
    }
}
