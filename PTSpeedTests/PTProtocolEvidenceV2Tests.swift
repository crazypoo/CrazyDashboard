//
//  PTProtocolEvidenceV2Tests.swift
//  PTSpeedTests
//
//  EN: Verifies Build 60 evidence domains, passive CAN discovery, migration, and exports.
//  ES: Verifica los dominios de evidencia, el descubrimiento CAN pasivo, la migración y las exportaciones de Build 60.
//  中文：验证 Build 60 的证据域、被动 CAN Discovery、迁移和导出。
//

import XCTest
@testable import XP400Ride

final class PTProtocolEvidenceV2Tests: XCTestCase {
    func testEvidenceDomainSeparatesYMOBDVendorAndOTA() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let versionEvent = PTCrazyTraceEvent(
            sequence: 0,
            timestamp: date,
            elapsed: 0,
            domain: .obd,
            direction: .input,
            source: .live,
            payload: .protocolMessage(
                PTTraceProtocolPayload(raw: "AT+VERSION", command: "AT+VERSION")
            )
        )
        let versionRecord = PTProtocolEvidenceV2Migration.from(versionEvent)
        XCTAssertEqual(versionRecord?.domain, .ymobdVendorExtension)

        let otaEvent = PTCrazyTraceEvent(
            sequence: 1,
            timestamp: date.addingTimeInterval(1),
            elapsed: 1,
            domain: .adapterOTA,
            direction: .output,
            source: .live,
            payload: .protocolMessage(PTTraceProtocolPayload(raw: "RCSP OTA callback"))
        )
        let otaRecord = PTProtocolEvidenceV2Migration.from(otaEvent)
        XCTAssertEqual(otaRecord?.domain, .ymobdFirmwareOTA)
        XCTAssertNotEqual(versionRecord?.domain, otaRecord?.domain)
    }

    func testCANDiscoveryProducesByteAndBitCandidatesWithoutOTA() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let session = PTCANCaptureSession(
            id: UUID(),
            name: "CAN event",
            startedAt: date.addingTimeInterval(-1),
            endedAt: date.addingTimeInterval(2),
            filterHeader: nil,
            frames: [
                frame(timestamp: 999.0, sequence: 0, payload: "0000000000000000"),
                frame(timestamp: 999.5, sequence: 1, payload: "0000000000000000"),
                frame(timestamp: 1000.1, sequence: 2, payload: "0000000000000001"),
                frame(timestamp: 1000.5, sequence: 3, payload: "0000000000000001")
            ],
            events: [PTCANCaptureEvent(name: "menu-change", timestamp: 1000.0)]
        )

        let candidates = PTProtocolEvidenceV2CANDiscovery.discover(in: session)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.header, "100")
        XCTAssertEqual(candidates.first?.changedByteIndexes, [7])
        XCTAssertTrue(candidates.first?.changedBits.contains(0) == true)
        XCTAssertEqual(candidates.first?.evidenceDomain, .can)
        XCTAssertFalse(candidates.contains { $0.note.localizedCaseInsensitiveContains("OTA") })
    }

    func testCaptureTemplatesAreReadOnlyAndEventTemplateRequiresMarker() {
        XCTAssertFalse(PTProtocolEvidenceCaptureTemplateCatalog.templates.isEmpty)
        XCTAssertTrue(PTProtocolEvidenceCaptureTemplateCatalog.templates.allSatisfy(\.readOnly))
        let canTemplate = PTProtocolEvidenceCaptureTemplateCatalog.templates.first { $0.id == .canEventWindow }
        XCTAssertEqual(canTemplate?.domain, .can)
        XCTAssertTrue(canTemplate?.requiresUserMarker == true)
    }

    @MainActor
    func testStoreBoundsConfidenceAndEscapesCSV() throws {
        let defaults = UserDefaults(suiteName: "PTProtocolEvidenceV2Tests.\(UUID().uuidString)")!
        let store = PTProtocolEvidenceV2Store(defaults: defaults)
        let record = PTProtocolEvidenceRecord(
            domain: .obd,
            kind: .response,
            source: .live,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            confidence: 4,
            value: "value, with \"quotes\""
        )

        XCTAssertEqual(store.merge([record]), 1)
        XCTAssertEqual(store.records.first?.confidence, 1)
        let csv = String(decoding: store.exportCSVData(), as: UTF8.self)
        XCTAssertTrue(csv.contains("\"value, with \"\"quotes\"\"\""))
        XCTAssertTrue(csv.contains(",obd,"))
    }

    private func frame(timestamp: TimeInterval, sequence: Int, payload: String) -> PTCANFrame {
        PTCANFrame(
            timestamp: timestamp,
            sequence: sequence,
            direction: .bus,
            rawLine: "100 8 \(payload)",
            header: "100",
            dataHex: payload,
            dlc: 8
        )
    }
}
