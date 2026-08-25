//
//  PTCoreTests.swift
//  CrazyDashboard
//
//  中文：覆盖共享状态、CAN 抓包、骑行复盘和只读 OBD 查找的纯数据契约。
//  Español: Cubre los contratos de datos puros del estado compartido, CAN, revisión de ruta y OBD de solo lectura.
//

import XCTest
@testable import XP400Ride

final class PTCoreTests: XCTestCase {
    func testWidgetApplicationContextRoundTrip() {
        let source = PTWidgetSharedStatus(
            fuelLevel: 72,
            tripKm: 128.4,
            isConnected: true,
            parkedLat: 31.2304,
            parkedLon: 121.4737,
            address: "上海外滩",
            lastUpdateTime: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let restored = PTWidgetSharedStatus(applicationContext: source.applicationContext)

        XCTAssertEqual(restored, source)
    }

    func testDiagnosticAddressNormalizesHeaders() {
        let address = PTOBDDiagnosticAddress(tx: " 7a0 ", rx: "7a8")

        XCTAssertEqual(address?.tx, "7A0")
        XCTAssertEqual(address?.rx, "7A8")
        XCTAssertNil(PTOBDDiagnosticAddress(tx: "70", rx: "7A8"))
    }

    func testUDSPositiveAndNegativeResponses() throws {
        let address = try XCTUnwrap(PTOBDiagnosticAddress(tx: "7A0", rx: "7A8"))

        let positive = try PTUDSReadService.parseDIDResponse(
            address: address,
            did: "F190",
            response: "7A8 06 62 F1 90 31 32 33"
        )
        XCTAssertEqual(positive.status, .success)
        XCTAssertEqual(positive.payloadHex, "313233")

        let negative = try PTUDSReadService.parseDIDResponse(
            address: address,
            did: "F190",
            response: "7A8 03 7F 22 31"
        )
        XCTAssertEqual(negative.status, .negativeResponse)
        XCTAssertEqual(negative.negativeResponseCode, "31")
    }

    func testELM327DLCIsNotStoredAsPayload() {
        let recorder = PTCANRecorder.shared
        recorder.cancel()
        recorder.maxInMemoryFrames = 16
        recorder.start(name: "OBD-CAN-Parser-Test")
        recorder.append(
            rawLine: "7E8 06 41 0C 1A F8 00 00 00",
            timestamp: 1_700_000_000
        )

        let session = recorder.stop()

        XCTAssertEqual(session?.frames.count, 1)
        XCTAssertEqual(session?.frames.first?.header, "7E8")
        XCTAssertEqual(session?.frames.first?.dlc, 6)
        XCTAssertEqual(session?.frames.first?.dataHex, "410C1AF80000")
    }

    func testCaptureDiffAndBitDiff() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let leftFrame = PTCANFrame(
            timestamp: date.timeIntervalSince1970,
            sequence: 1,
            direction: .rx,
            rawLine: "7E8 02 10 01",
            header: "7E8",
            dataHex: "1001",
            dlc: 2
        )
        let rightFrame = PTCANFrame(
            timestamp: date.timeIntervalSince1970 + 1,
            sequence: 1,
            direction: .rx,
            rawLine: "7E8 02 10 03",
            header: "7E8",
            dataHex: "1003",
            dlc: 2
        )

        let left = PTCANCaptureSession(
            id: UUID(),
            name: "左侧",
            startedAt: date,
            endedAt: date.addingTimeInterval(1),
            filterHeader: nil,
            frames: [leftFrame]
        )
        let right = PTCANCaptureSession(
            id: UUID(),
            name: "右侧",
            startedAt: date,
            endedAt: date.addingTimeInterval(1),
            filterHeader: nil,
            frames: [rightFrame]
        )

        let captureDiff = PTCANCaptureAnalyzer.diff(left: left, right: right)
        let payloadDiff = PTCANCaptureAnalyzer.byteDiff(left: left, right: right)

        XCTAssertEqual(captureDiff.deltas.first?.kind, .changed)
        XCTAssertEqual(payloadDiff.first?.changedByteCount, 1)
        XCTAssertEqual(payloadDiff.first?.changedBitCount, 1)
    }

    func testRideReviewUsesCooldownAndReportsHardBraking() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            makeRoutePoint(timestamp: start, brakingG: -0.8),
            makeRoutePoint(timestamp: start.addingTimeInterval(2), brakingG: -0.9),
            makeRoutePoint(timestamp: start.addingTimeInterval(6), brakingG: -0.7)
        ]

        let events = PTRideReviewAnalyzer.analyze(points: points)

        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy { $0.type == .hardBraking })
    }

    func testStableOBDCommandLookupIsReadOnly() {
        let command = OBDCommand.from(command: "010C")

        XCTAssertNotNil(command)
        XCTAssertEqual(PTDTCManager.determineSeverity(for: "P0300"), .high)
    }

    private func makeRoutePoint(timestamp: Date, brakingG: Double) -> PTRoutePoint {
        PTRoutePoint(
            lat: 31.2304,
            lon: 121.4737,
            altitude: 4,
            timestamp: timestamp,
            speed: 60,
            rpm: 4_000,
            leanAngle: 10,
            gForceY: brakingG,
            gForceX: 0,
            gForceZ: 0,
            slipRatio: 0
        )
    }
}
