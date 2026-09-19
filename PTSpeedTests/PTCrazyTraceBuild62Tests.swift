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

// EN: Build 77 tests the structured package, bounded incident capture, and legacy migration path.
// ES: Build 77 prueba el paquete estructurado, la captura limitada de incidentes y la migración heredada.
// 中文：Build 77 测试结构化数据包、有界事件采集和旧格式迁移路径。
@MainActor
final class PTBuild77CrazyBlackBoxTests: XCTestCase {
    func testStructuredPackageContainsBuild77StreamsAndSummary() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let telemetry = PTUnifiedVehicleTelemetrySnapshot(
            values: [
                PTVehicleTelemetryResolvedValue(
                    signal: .speed,
                    value: .double(42),
                    source: .replay,
                    capturedAt: date,
                    freshness: .fresh,
                    confidence: 1,
                    isSynthetic: true
                )
            ],
            updatedAt: date,
            mode: .replay
        )
        let document = PTCrazyTraceDocument(
            name: "build77",
            startedAt: date,
            endedAt: date.addingTimeInterval(2),
            events: [
                PTCrazyTraceEvent(
                    sequence: 0,
                    timestamp: date,
                    elapsed: 0,
                    domain: .vehicleTelemetry,
                    direction: .state,
                    source: .replay,
                    payload: .telemetry(telemetry)
                ),
                PTCrazyTraceEvent(
                    sequence: 1,
                    timestamp: date.addingTimeInterval(1),
                    elapsed: 1,
                    domain: .motion,
                    direction: .state,
                    source: .live,
                    payload: .motion(
                        PTTraceMotionPayload(roll: 1, pitch: 2, yaw: 3, gForceX: 0, gForceY: 0, gForceZ: 1)
                    )
                ),
                PTCrazyTraceEvent(
                    sequence: 2,
                    timestamp: date.addingTimeInterval(2),
                    elapsed: 2,
                    domain: .system,
                    direction: .marker,
                    source: .system,
                    payload: .marker(PTTraceMarkerPayload(name: "incident"))
                )
            ]
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("build77-(UUID().uuidString).crazytrace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try PTCrazyTracePackageWriter.write(
            document: document,
            to: directory,
            appVersion: "2.0.8",
            buildNumber: "77",
            device: "test",
            iosVersion: "test",
            privacyLevel: "raw"
        )

        for name in PTCrazyTracePackageWriter.structuredFileNames {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path),
                "Missing structured trace file: \(name)"
            )
        }
        let summaryData = try Data(contentsOf: directory.appendingPathComponent("diagnostics/summary.json"))
        let summary = try JSONDecoder.crazyTraceDecoder.decode(PTCrazyTraceDiagnosticsSummary.self, from: summaryData)
        XCTAssertEqual(summary.vehicleSampleCount, 1)
        XCTAssertEqual(summary.motionSampleCount, 1)
        XCTAssertEqual(summary.markerCount, 1)

        let package = try PTCrazyTracePackageReader.load(from: directory)
        XCTAssertEqual(package.document.events, document.events)
        XCTAssertEqual(package.manifest.buildNumber, "77")
    }

    func testLegacyPackageWithoutStructuredStreamsStillLoads() throws {
        let document = PTReplayFixtureCatalog.document(for: "normal_connect")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("build77-legacy-(UUID().uuidString).crazytrace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try PTCrazyTracePackageWriter.write(document: document, to: directory, privacyLevel: "raw")
        for name in PTCrazyTracePackageWriter.structuredFileNames {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let oldManifest = try JSONDecoder.crazyTraceDecoder.decode(
            PTCrazyTracePackageManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let legacyChecksums = oldManifest.checksums.filter {
            !PTCrazyTracePackageWriter.structuredFileNames.contains($0.key)
        }
        let legacyManifest = PTCrazyTracePackageManifest(
            formatVersion: 2,
            appVersion: oldManifest.appVersion,
            buildNumber: oldManifest.buildNumber,
            createdAt: oldManifest.createdAt,
            device: oldManifest.device,
            iosVersion: oldManifest.iosVersion,
            vehicleID: oldManifest.vehicleID,
            domains: oldManifest.domains,
            startTime: oldManifest.startTime,
            endTime: oldManifest.endTime,
            privacyLevel: oldManifest.privacyLevel,
            checksums: legacyChecksums
        )
        try JSONEncoder.crazyTraceEncoder.encode(legacyManifest).write(to: manifestURL, options: .atomic)

        let loaded = try PTCrazyTracePackageReader.load(from: directory)
        XCTAssertEqual(loaded.document, document)
    }

    func testBlackBoxKeepsPreRollAndCreatesIncidentDocument() async throws {
        let recorder = PTCrazyTraceRecorder.shared
        recorder.stop()
        recorder.disarmBlackBox()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(recorder.armBlackBox(at: date))
        recorder.mark("before_incident", at: date.addingTimeInterval(10))
        recorder.recordTelemetry(.empty, source: .mock, at: date.addingTimeInterval(20))

        let capturedDocument = await recorder.triggerIncident(
            name: "incident",
            preRoll: 60,
            postRoll: 0,
            at: date.addingTimeInterval(21)
        )
        let document = try XCTUnwrap(capturedDocument)

        XCTAssertTrue(document.events.contains { event in
            if case .marker(let marker) = event.payload {
                return marker.name == "before_incident"
            }
            return false
        })
        XCTAssertTrue(document.events.contains { event in
            if case .marker(let marker) = event.payload {
                return marker.name == "incident_triggered"
            }
            return false
        })
        XCTAssertEqual(document.schemaVersion, PTCrazyTraceDocument.currentSchemaVersion)
        recorder.disarmBlackBox()
    }
}
