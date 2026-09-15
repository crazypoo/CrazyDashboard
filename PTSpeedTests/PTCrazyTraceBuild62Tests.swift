//
//  PTCrazyTraceBuild62Tests.swift
//  PTSpeedTests
//
//  EN: Verifies the versioned trace package and deterministic replay result platform.
//  ES: Verifica el paquete de trazas versionado y la plataforma de resultados deterministas.
//  中文：验证版本化轨迹数据包和确定性回放结果平台。
//

import Foundation
import XCTest
@testable import XP400Ride

final class PTCrazyTraceBuild62Tests: XCTestCase {
    func testAllBuild62FixtureGroupsReplayDeterministically() {
        XCTAssertFalse(PTReplayFixtureCatalog.allFixtureIDs.isEmpty)
        for fixtureID in PTReplayFixtureCatalog.allFixtureIDs {
            let document = PTReplayFixtureCatalog.document(for: fixtureID)
            let expected = PTReplayFixtureCatalog.expectedResult(for: fixtureID)
            let first = PTCrazyTraceReplayRegression.evaluate(document: document, expected: expected)
            let second = PTCrazyTraceReplayRegression.evaluate(document: document, expected: expected)

            XCTAssertTrue(first.passed, "fixture \(fixtureID): \(first.failures)")
            XCTAssertEqual(first, second, "fixture \(fixtureID) changed between deterministic runs")
            XCTAssertTrue(document.events.map(\.elapsed).isSortedNonDecreasing)
        }
    }

    func testCrazyTracePackageRoundTripAndChecksums() throws {
        let document = PTReplayFixtureCatalog.document(for: "normal_connect")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("normal-connect-\(UUID().uuidString).crazytrace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try PTCrazyTracePackageWriter.write(
            document: document,
            to: directory,
            appVersion: "2.0.8",
            buildNumber: "62",
            device: "Test Device",
            iosVersion: "iOS Test",
            privacyLevel: "raw"
        )
        let package = try PTCrazyTracePackageReader.load(from: directory)

        XCTAssertEqual(package.manifest.formatVersion, 2)
        XCTAssertEqual(package.manifest.buildNumber, "62")
        XCTAssertEqual(package.document.traceID, document.traceID)
        XCTAssertEqual(package.document.events, document.events)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("attachments").path))
    }

    func testRedactedPackageRemovesIdentityAndPreciseLocation() throws {
        let document = PTReplayFixtureCatalog.document(for: "normal_connect")
        let location = PTCrazyTraceEvent(
            sequence: 20,
            timestamp: document.startedAt.addingTimeInterval(2),
            elapsed: 2,
            domain: .location,
            direction: .state,
            source: .live,
            payload: .location(
                PTTraceLocationPayload(latitude: 31.2304, longitude: 121.4737, altitude: 8)
            )
        )
        let protocolEvent = PTCrazyTraceEvent(
            sequence: 21,
            timestamp: document.startedAt.addingTimeInterval(2.1),
            elapsed: 2.1,
            domain: .xp400BLE,
            direction: .input,
            source: .live,
            payload: .protocolMessage(
                PTTraceProtocolPayload(
                    raw: "VIN=VF12345678901234567",
                    metadata: ["vin": "VF12345678901234567", "safe": "kept"]
                )
            )
        )
        let input = PTCrazyTraceDocument(
            traceID: document.traceID,
            name: document.name,
            vehicleID: "vehicle-secret",
            startedAt: document.startedAt,
            endedAt: document.endedAt,
            events: document.events + [location, protocolEvent]
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("redacted-\(UUID().uuidString).crazytrace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try PTCrazyTracePackageWriter.write(document: input, to: directory, privacyLevel: "redacted")
        let package = try PTCrazyTracePackageReader.load(from: directory)

        XCTAssertNil(package.manifest.vehicleID)
        XCTAssertNil(package.document.vehicleID)
        guard let redactedLocationEvent = package.document.events.first(where: { $0.sequence == 20 }),
              case .location(let redactedLocation) = redactedLocationEvent.payload else {
            return XCTFail("missing redacted location")
        }
        XCTAssertEqual(redactedLocation.latitude, 0)
        XCTAssertEqual(redactedLocation.longitude, 0)
        guard let redactedProtocolEvent = package.document.events.first(where: { $0.sequence == 21 }),
              case .protocolMessage(let redactedProtocol) = redactedProtocolEvent.payload else {
            return XCTFail("missing redacted protocol event")
        }
        XCTAssertTrue(redactedProtocol.raw.contains("<redacted>"))
        XCTAssertEqual(redactedProtocol.metadata["safe"], "kept")
        XCTAssertEqual(redactedProtocol.metadata["vin"], "<redacted>")
    }

    func testFailedSnapshotAssertionIsReportedWithoutDeviceAccess() {
        let document = PTReplayFixtureCatalog.document(for: "normal_connect")
        let expected = PTCrazyTraceExpectedResult(
            fixtureID: "failure",
            assertions: [
                PTReplayAssertion(timestamp: 0, path: "telemetry.speed", expected: .double(99))
            ]
        )
        let result = PTCrazyTraceReplayRegression.evaluate(document: document, expected: expected)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.failures.first?.path, "telemetry.speed")
        XCTAssertEqual(result.failures.first?.actual, .double(0))
    }

    func testCrazyTraceReaderRejectsAnIncompletePackage() throws {
        let document = PTReplayFixtureCatalog.document(for: "normal_connect")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("incomplete-\(UUID().uuidString).crazytrace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try PTCrazyTracePackageWriter.write(document: document, to: directory, buildNumber: "62")
        try FileManager.default.removeItem(at: directory.appendingPathComponent("obd.jsonl"))

        XCTAssertThrowsError(try PTCrazyTracePackageReader.load(from: directory)) { error in
            XCTAssertEqual(error as? PTCrazyTracePackageError, .missingFile("obd.jsonl"))
        }
    }

    func testReplayLoaderAcceptsTheSchema2Package() async throws {
        let document = PTReplayFixtureCatalog.document(for: "normal_connect")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("replay-loader-\(UUID().uuidString).crazytrace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try PTCrazyTracePackageWriter.write(document: document, to: directory, buildNumber: "62", privacyLevel: "raw")
        let loaded = try await PTCrazyTraceRecorder.load(from: directory)
        XCTAssertEqual(loaded, document)
    }
}

private extension Collection where Element: Comparable {
    var isSortedNonDecreasing: Bool {
        zip(self, dropFirst()).allSatisfy { $0 <= $1 }
    }
}
