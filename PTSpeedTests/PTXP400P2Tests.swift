//
//  PTXP400P2Tests.swift
//  PTSpeedTests
//
//  EN: P2 BLE reliability tests for session generations, transport limits, backpressure, and diagnostics.
//  ES: Pruebas P2 de fiabilidad BLE para generaciones de sesión, límites de transporte, backpressure y diagnóstico.
//  中文：覆盖会话代次、传输上限、背压和诊断的 P2 BLE 可靠性测试。
//

import XCTest
@testable import XP400Ride

final class PTXP400P2Tests: XCTestCase {
    func testSessionTokenAlwaysAdvancesAcrossConnectionGenerations() {
        let initial = PTXP400BLESessionToken(generation: 0)
        let next = initial.next()
        let following = next.next()

        XCTAssertNotEqual(initial.id, next.id)
        XCTAssertNotEqual(next.id, following.id)
        XCTAssertEqual(next.generation, 1)
        XCTAssertEqual(following.generation, 2)
    }

    func testTransportPolicyRespectsProtocolAndTransportMaximums() {
        XCTAssertEqual(
            PTXP400BLETransportPolicy.effectiveChunkLength(
                maximumUpdateValueLength: nil
            ),
            20
        )
        XCTAssertEqual(
            PTXP400BLETransportPolicy.effectiveChunkLength(
                maximumUpdateValueLength: 15
            ),
            15
        )
        XCTAssertEqual(
            PTXP400BLETransportPolicy.effectiveChunkLength(
                maximumUpdateValueLength: 512
            ),
            20
        )
        XCTAssertEqual(
            PTXP400BLETransportPolicy.effectiveChunkLength(
                protocolMaximum: 0,
                maximumUpdateValueLength: nil
            ),
            1
        )
    }

    func testRemoteCreditValidationRejectsMalformedAndOverflowingWrites() {
        XCTAssertEqual(
            PTXP400BLEWriteValidator.validateRemoteCredits(nil, currentCredits: 0),
            .missingValue
        )
        XCTAssertEqual(
            PTXP400BLEWriteValidator.validateRemoteCredits(Data([0x01, 0x02]), currentCredits: 0),
            .invalidLength(actual: 2)
        )
        XCTAssertEqual(
            PTXP400BLEWriteValidator.validateRemoteCredits(Data([0x00]), currentCredits: 0),
            .invalidAmount(actual: 0)
        )
        XCTAssertEqual(
            PTXP400BLEWriteValidator.validateRemoteCredits(Data([0x19]), currentCredits: 1),
            .balanceOverflow(current: 1, adding: 25)
        )
        XCTAssertEqual(
            PTXP400BLEWriteValidator.validateRemoteCredits(Data([0x04]), currentCredits: 0),
            .accepted(amount: 4)
        )
    }

    func testAdvertisementProfileDoesNotInventAnOfficialLocalName() {
        let profile = PTXP400BLEAdvertisementProfile.confirmedXP400

        XCTAssertTrue(profile.matches(advertisedServiceUUIDs: ["fEfB"], localName: "XP400"))
        XCTAssertEqual(profile.expectedLocalName, nil)
        XCTAssertEqual(profile.localNameParity(observedLocalName: "XP400"), .unknown)
        XCTAssertFalse(profile.matches(advertisedServiceUUIDs: ["180D"], localName: nil))
    }

    func testStallDetectorReportsOneEventUntilProgress() {
        var detector = PTXP400BLESendQueueStallDetector(timeoutNanoseconds: 5)
        detector.enqueue(at: 0)
        detector.markBackpressure(at: 1)

        XCTAssertNil(detector.poll(at: 4))
        XCTAssertEqual(detector.poll(at: 5), .stalled(pendingCount: 1))
        XCTAssertNil(detector.poll(at: 6))

        detector.markProgress(at: 7)
        XCTAssertEqual(detector.state, .idle)
        XCTAssertEqual(detector.pendingCount, 0)
    }

    @MainActor
    func testReliabilityMonitorKeepsBoundedEventsAndExportsJSON() throws {
        let monitor = PTXP400BLEReliabilityMonitor(maximumEventCount: 2)
        let token = PTXP400BLESessionToken(generation: 1)

        monitor.beginSession(token)
        monitor.record(.backpressure, token: token)
        monitor.record(.queueStall, token: token)

        XCTAssertEqual(monitor.snapshot.recentEvents.count, 2)
        XCTAssertEqual(monitor.snapshot.droppedEventCount, 1)
        XCTAssertEqual(monitor.snapshot.totalEventCount, 3)
        XCTAssertEqual(monitor.snapshot.eventCounts[PTXP400BLEReliabilityEventKind.queueStall.rawValue], 1)

        let data = try monitor.exportJSONData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(PTXP400BLEReliabilitySnapshot.self, from: data)
        XCTAssertEqual(exported, monitor.snapshot)

        XCTAssertTrue(monitor.endSession(token, kind: .sessionDisconnected, detail: "test"))
        XCTAssertFalse(monitor.endSession(token, kind: .sessionDisconnected, detail: "duplicate"))
        XCTAssertNil(monitor.snapshot.activeSessionID)
    }
}
