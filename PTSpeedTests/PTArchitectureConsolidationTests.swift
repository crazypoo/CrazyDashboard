//
//  PTArchitectureConsolidationTests.swift
//  PTSpeedTests
//
//  EN: Verifies the Build 61 consumer, projection, discovery, and persistence boundaries.
//  ES: Verifica los límites de consumidor, proyección, descubrimiento y persistencia de Build 61.
//  中文：验证 Build 61 的消费者、投影、Discovery 和持久化边界。
//

import XCTest
@testable import XP400Ride

@MainActor
final class PTArchitectureConsolidationTests: XCTestCase {
    func testProjectionRejectsStaleValuesByDefault() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let stale = PTVehicleTelemetryResolvedValue(
            signal: .speed,
            value: .double(42),
            source: .xp400BLE,
            capturedAt: date.addingTimeInterval(-10),
            freshness: .stale,
            confidence: 1,
            isSynthetic: false
        )
        let projection = PTVehicleTelemetryProjections.dashboard(
            from: PTUnifiedVehicleTelemetrySnapshot(values: [stale], updatedAt: date)
        )

        XCTAssertNil(projection.speedKmh)
        XCTAssertEqual(projection.double(for: .speed, allowingStale: true), 42)
    }

    func testCANScoreAndConfidenceKeepExistingBounds() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let frame = PTCANFrame(
            timestamp: 1000,
            sequence: 0,
            direction: .bus,
            rawLine: "100 8 0000000000000000",
            header: "100",
            dataHex: "0000000000000000",
            dlc: 8
        )
        let session = PTCANCaptureSession(
            id: UUID(),
            name: "empty-event",
            startedAt: date,
            endedAt: date.addingTimeInterval(1),
            filterHeader: nil,
            frames: [frame],
            events: [PTCANCaptureEvent(name: "marker", timestamp: 1000)]
        )
        let candidates = PTProtocolCANDiscoveryEngine.discover(in: session)

        XCTAssertTrue(candidates.allSatisfy { (0.1...0.95).contains($0.confidence) })
        XCTAssertEqual(PTProtocolEvidenceConfidence.forCANScore(10), 0.1, accuracy: 0.001)
        XCTAssertEqual(PTProtocolEvidenceConfidence.forCANScore(200), 0.95, accuracy: 0.001)
    }

    func testPersistenceCodecRoundTripsSchemaAndRecords() throws {
        let record = PTProtocolEvidenceRecord(
            domain: .obd,
            kind: .response,
            source: .live,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            confidence: 2,
            value: "62F190"
        )
        let state = PTProtocolEvidenceV2PersistedState(
            schemaVersion: PTProtocolEvidenceV2Document.currentSchemaVersion,
            records: [record],
            canCandidates: []
        )

        let data = try PTProtocolEvidenceV2StateCodec.encode(state)
        let decoded = try PTProtocolEvidenceV2StateCodec.decode(data)

        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.records, [record])
        XCTAssertEqual(decoded.records.first?.confidence, 1)
    }

    func testVehicleAndAdapterPassportResolversRemainSeparate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let vehicleFields = PTVehicleIdentityResolver.resolve(
            PTVehicleIdentityResolutionInput(
                name: "XP400 GT",
                brand: "Peugeot",
                model: "XP400 GT",
                year: 2026,
                vin: "VF1234567890ABCDE",
                dashboardReference: "DASHBOARD-123456",
                dashboardSource: .live,
                vehicleTimestamp: date,
                ecuAddress: "700->708",
                ecuSource: .live,
                ecuTimestamp: date,
                ecuCalibration: "cal-1",
                ecuCalibrationSource: .live
            )
        )
        let adapterFields = PTDiagnosticAdapterIdentityResolver.resolve(
            PTDiagnosticAdapterIdentityResolutionInput(
                vendor: "YMOBD",
                model: "Jieli",
                firmware: "2.5.0",
                transport: "obdBluetooth",
                supportedCommandCount: 4,
                isOfficialYMOBD: true,
                identifier: "AA:BB:CC:DD",
                source: .live,
                timestamp: date,
                otaSupported: true
            )
        )

        XCTAssertNotNil(vehicleFields.first { $0.key == "vehicle.vin" })
        XCTAssertNil(vehicleFields.first { $0.key.hasPrefix("adapter.") })
        XCTAssertEqual(adapterFields.first { $0.key == "adapter.vendor" }?.value, "YMOBD")
        XCTAssertNil(adapterFields.first { $0.key == "vehicle.vin" })
    }
}
