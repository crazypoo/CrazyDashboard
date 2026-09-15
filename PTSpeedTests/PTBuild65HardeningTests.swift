//
//  PTBuild65HardeningTests.swift
//  CrazyDashboard
//
//  EN: Verifies Build 65 ownership metadata, privacy defaults, bounded storage, and atomic trace publication.
//  ES: Verifica los metadatos de propiedad, la privacidad, el almacenamiento acotado y la publicación atómica de trazas de Build 65.
//  中文：验证 Build 65 的归属元数据、隐私默认值、有界存储和 Trace 原子发布。
//

import XCTest
@testable import XP400Ride

final class PTBuild65HardeningTests: XCTestCase {
    func testConcurrencyOwnershipMatrixCoversProtectedDomains() {
        let domains = Set(PTBuild65ConcurrencyOwnershipMatrix.entries.map(\.domain))

        XCTAssertTrue(domains.contains("XP400 BLE session"))
        XCTAssertTrue(domains.contains("ELM327 / OBD session"))
        XCTAssertTrue(
            PTBuild65ConcurrencyOwnershipMatrix.entries
                .filter(\.protectedCore)
                .allSatisfy { $0.owner == .xp400SerialOwnership || $0.owner == .elmSessionActor }
        )
        XCTAssertEqual(PTBuild65ConcurrencyOwnershipMatrix.protectedCoreFiles.count, 3)
    }

    func testBuild65ValueModelsRemainSendable() {
        let evidence = PTProtocolEvidenceRecord(
            domain: .obd,
            kind: .response,
            source: .live,
            confidence: 1,
            value: "01 0C"
        )
        let candidate = PTProtocolCANBitCandidate(
            captureID: UUID(),
            eventID: UUID(),
            header: "321",
            changedByteIndexes: [3],
            changedBits: [5],
            dominantBeforePayload: "00",
            dominantAfterPayload: "20",
            changedFrameCount: 2,
            firstChangeRelativeTimestamp: 0,
            lastChangeRelativeTimestamp: 1,
            score: 10,
            source: .live,
            timestamp: Date(),
            confidence: 0.8
        )
        let definition = PTVehicleSignalDefinition(
            id: "xp400.leftIndicator",
            name: "Left indicator",
            vehicleModel: "XP400 GT",
            transport: .can,
            frameIdentifier: "321",
            byteIndex: 3,
            bitIndex: 5,
            encoding: .boolean,
            confidence: .capturedRepeatable,
            evidenceIDs: [evidence.id]
        )
        let traceEvent = PTCrazyTraceEvent(
            sequence: 0,
            timestamp: Date(),
            elapsed: 0,
            domain: .obd,
            direction: .input,
            source: .live,
            payload: .protocolMessage(PTTraceProtocolPayload(raw: "01 0C"))
        )

        assertSendable(PTVehicleTelemetrySnapshot.empty)
        assertSendable(PTVehicleTelemetrySignal.speed)
        assertSendable(PTCrazyDashboardInstrumentSnapshot.empty)
        assertSendable(evidence)
        assertSendable(candidate)
        assertSendable(definition)
        assertSendable(
            PTElectronicControlUnit(
                role: .dashboard,
                diagnosticAddress: nil,
                hardwareVersion: .unavailable(),
                softwareVersion: .unavailable(),
                bootVersion: .unavailable(),
                calibrationID: .unavailable(),
                serialNumber: .unavailable()
            )
        )
        assertSendable(traceEvent)
    }

    func testReleaseSafetyPolicyIsClosedByDefault() {
        let policy = PTBuild65ReleaseSafetyPolicy.publicReleaseDefault

        XCTAssertTrue(policy.isSafePublicBaseline)
        XCTAssertFalse(policy.developerSurfaceVisible)
        XCTAssertFalse(policy.unknownUDSMutationAllowed)
        XCTAssertFalse(policy.canInjectionAllowed)
        XCTAssertFalse(policy.securityAccessAutomationAllowed)
        XCTAssertTrue(policy.firmwareResearchReadOnly)
        XCTAssertTrue(policy.allowsJieliOTA(for: "YMOBD"))
        XCTAssertFalse(policy.allowsJieliOTA(for: "XP400"))
    }

    func testPrivacyPolicyCoversReleaseSensitiveFields() {
        XCTAssertTrue(PTBuild65PrivacyPolicy.isSensitiveKey("notificationText"))
        XCTAssertTrue(PTBuild65PrivacyPolicy.isSensitiveKey("PTT_audio"))
        XCTAssertTrue(PTBuild65PrivacyPolicy.isSensitiveKey("homeLocation"))
        XCTAssertFalse(PTBuild65PrivacyPolicy.isSensitiveKey("frameIdentifier"))
        XCTAssertEqual(PTBuild65PrivacyPolicy.redactFreeText("private notification"), "<redacted-text>")
        XCTAssertEqual(
            PTBuild65PrivacyPolicy.redactProtocolText("VIN=VF1234567890ABCDE"),
            "VIN=<redacted>"
        )
    }

    func testEvidenceExportsUseRedactedDefaults() throws {
        let record = PTProtocolEvidenceRecord(
            domain: .xp400BLE,
            kind: .identity,
            source: .live,
            confidence: 1,
            value: "VIN=VF1234567890ABCDE MAC=AA:BB:CC:DD:EE:FF",
            note: "notification private message"
        )
        let document = PTProtocolEvidenceV2Document(
            records: [record],
            canCandidates: [],
            correlations: [],
            passport: PTVehiclePassport(
                vehicleID: UUID(),
                vehicleFields: [
                    PTVehiclePassportField(
                        key: "vin",
                        value: "VF1234567890ABCDE",
                        source: .live,
                        timestamp: Date(),
                        confidence: 1
                    )
                ],
                adapterFields: []
            )
        )

        let json = try String(decoding: PTProtocolEvidenceV2Exporter.jsonData(for: document), as: UTF8.self)
        let csv = String(decoding: PTProtocolEvidenceV2Exporter.csvData(for: [record]), as: UTF8.self)
        XCTAssertFalse(json.contains("VF1234567890ABCDE"))
        XCTAssertFalse(json.contains("AA:BB:CC:DD:EE:FF"))
        XCTAssertFalse(json.contains("private message"))
        XCTAssertFalse(csv.contains("VF1234567890ABCDE"))
        XCTAssertFalse(csv.contains("AA:BB:CC:DD:EE:FF"))
        XCTAssertTrue(csv.contains("<redacted-text>"))
    }

    func testTracePackagePublishesAtomicallyAndRedactsFreeText() throws {
		let rootURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("build65-trace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let document = PTCrazyTraceDocument(
            name: "privacy-check",
            vehicleID: "VF1234567890ABCDE",
            startedAt: date,
            endedAt: date.addingTimeInterval(1),
            events: [
                PTCrazyTraceEvent(
                    sequence: 0,
                    timestamp: date,
                    elapsed: 0,
                    domain: .obd,
                    direction: .input,
                    source: .live,
                    payload: .protocolMessage(
                        PTTraceProtocolPayload(
                            raw: "VIN=VF1234567890ABCDE",
                            metadata: ["mac": "AA:BB:CC:DD:EE:FF", "notificationText": "private message"]
                        )
                    )
                ),
                PTCrazyTraceEvent(
                    sequence: 1,
                    timestamp: date.addingTimeInterval(1),
                    elapsed: 1,
                    domain: .system,
                    direction: .state,
                    source: .system,
                    payload: .text("private notification body")
                )
            ]
        )

        _ = try PTCrazyTracePackageWriter.write(
            document: document,
            to: rootURL,
            appVersion: "2.0.8",
            buildNumber: "65",
            device: "test",
            iosVersion: "test",
            privacyLevel: "redacted"
        )

        let restored = try PTCrazyTracePackageReader.load(from: rootURL)
        XCTAssertNil(restored.document.vehicleID)
        let timeline = try String(contentsOf: rootURL.appendingPathComponent("timeline.jsonl"), encoding: .utf8)
        XCTAssertFalse(timeline.contains("VF1234567890ABCDE"))
        XCTAssertFalse(timeline.contains("AA:BB:CC:DD:EE:FF"))
        XCTAssertFalse(timeline.contains("private message"))
        XCTAssertTrue(timeline.contains("<redacted-text>"))

        var batches: [[PTCrazyTraceEvent]] = []
        let streamedCount = try PTCrazyTracePackageReader.streamEvents(
            from: rootURL,
            batchSize: 1
        ) { batch in
            batches.append(batch)
        }
        XCTAssertEqual(streamedCount, 2)
        XCTAssertEqual(batches.flatMap { $0 }.count, 2)
    }

    func testTraceRecoveryRemovesOnlyOrphanedStagingDirectories() throws {
        let parentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("build65-recovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parentURL) }
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let orphanURL = parentURL.appendingPathComponent(".trace.staging", isDirectory: true)
        let regularURL = parentURL.appendingPathComponent("regular.staging", isDirectory: true)
        let temporaryFileURL = parentURL.appendingPathComponent(".not-a-directory.staging", isDirectory: false)
        try FileManager.default.createDirectory(at: orphanURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: regularURL, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: temporaryFileURL)

        XCTAssertEqual(
            try PTCrazyTracePackageWriter.recoverIncompletePackages(in: parentURL),
            1
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: regularURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryFileURL.path))
    }

    func testCANCaptureJSONLStreamsFramesInBoundedBatches() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("build65-can-\(UUID().uuidString).jsonl", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let frames = (0..<3).map { index in
            PTCANFrame(
                timestamp: 1_800_000_000 + Double(index),
                sequence: index + 1,
                direction: .bus,
                rawLine: "7E8 8 06 41 00 BE 3E B8 13 00",
                header: "7E8",
                dataHex: "064100BE3EB81300",
                dlc: 8
            )
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var jsonl = Data()
        for frame in frames {
            jsonl.append(try encoder.encode(frame))
            jsonl.append(0x0A)
        }
        jsonl.append(contentsOf: Data("not-json\n".utf8))
        try jsonl.write(to: fileURL, options: .withoutOverwriting)

        var batchSizes: [Int] = []
        let decodedCount = try PTCANCaptureStore.shared.streamFrames(from: fileURL, batchSize: 2) { batch in
            batchSizes.append(batch.count)
        }

        XCTAssertEqual(decodedCount, 3)
        XCTAssertEqual(batchSizes, [2, 1])
    }

    func testEvidenceDatabaseUsesBoundedPages() throws {
		let databaseURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("build65-evidence-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-wal")
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-shm")
        }

        let database = try PTProtocolEvidenceDatabase(url: databaseURL)
        let records = (0..<3).map { index in
            PTProtocolEvidenceRecord(
				id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-\(String(format: "%012d", index + 1))")!,
                domain: .obd,
                kind: .response,
                source: .live,
                timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)),
                confidence: 0.8,
				value: "record-\(index)"
            )
        }
        _ = try database.insert(records: records)

        XCTAssertEqual(PTProtocolEvidenceDatabase.maximumPageSize, 10_000)
        XCTAssertEqual(try database.records(limit: 100_000).count, 3)
        XCTAssertEqual(try database.records(limit: 100_000, offset: 1).count, 2)
        XCTAssertEqual(try database.records(limit: 1, offset: 2).count, 1)

        var pageSizes: [Int] = []
        let streamedCount = try database.forEachRecord(pageSize: 2) { page in
            pageSizes.append(page.count)
        }
        XCTAssertEqual(streamedCount, 3)
        XCTAssertEqual(pageSizes, [2, 1])
    }

    func testStressProfileAndLifecycleMatrixAreExplicit() {
        XCTAssertEqual(PTBuild65StorageStressProfile.releaseProfile.evidenceRecords, 100_000)
        XCTAssertEqual(PTBuild65StorageStressProfile.releaseProfile.canFrames, 1_000_000)
        XCTAssertEqual(PTBuild65StorageStressProfile.releaseProfile.crazyTraceHours, 4)
        XCTAssertEqual(PTBuild65StorageProfileCheck.requiredScenarioCount, 17)
        XCTAssertEqual(PTBuild65LifecycleMatrix.rows.count, PTBuild65StorageProfileCheck.requiredScenarioCount)
        XCTAssertEqual(PTBuild65SoakPlan.stages.map(\.durationMinutes), [30, 120, 240])
        XCTAssertTrue(PTBuild65SoakPlan.stages.allSatisfy { !$0.observedMetrics.isEmpty })
    }

    func testMalformedCorpusDoesNotCrashSafeParserBoundaries() throws {
        for malformed in PTBuild65MalformedInputCorpus.cases {
            XCTAssertFalse(malformed.id.isEmpty)
            _ = PTXP400BLEProtocol.isValidOutboundFrame(malformed.data)

            var parser = PTELM327Parser()
            _ = parser.append(malformed.data)

            _ = try? PTCANCaptureStorage.decode(malformed.data)
            _ = try? PTProtocolEvidenceV2StateCodec.decode(malformed.data)
            _ = try? PTUDSReadService.parseDIDResponse(
                address: PTOBDDiagnosticAddress(tx: "7E0", rx: "7E8")!,
                did: "F190",
                response: String(decoding: malformed.data, as: UTF8.self)
            )
        }
    }

    func testPersistenceRecoversOnlyOrphanedTemporaryFiles() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("build65-persistence-recovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let orphanURL = directoryURL.appendingPathComponent(".ride.temporary.tmp", isDirectory: false)
        let regularURL = directoryURL.appendingPathComponent("ride.tmp", isDirectory: false)
        try Data("orphan".utf8).write(to: orphanURL)
        try Data("keep".utf8).write(to: regularURL)

        let store = PTDataPersistenceActor(localDirectoryURL: directoryURL)
        let recoveredCount = try await store.recoverOrphanedTemporaryFiles()
        XCTAssertEqual(recoveredCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: regularURL.path))
    }

    nonisolated private func assertSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}

private enum PTBuild65StorageProfileCheck {
    static let requiredScenarioCount = PTBuild65LifecycleScenario.allCases.count
}
