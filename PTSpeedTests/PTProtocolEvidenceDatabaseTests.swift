//
//  PTProtocolEvidenceDatabaseTests.swift
//  PTSpeedTests
//
//  EN: Verifies SQLite schema, migration safety, deduplication, indexed reads, and large evidence batches.
//  ES: Verifica el esquema SQLite, la seguridad de migración, la deduplicación, las lecturas indexadas y los lotes grandes.
//  中文：验证 SQLite Schema、迁移安全、去重、索引读取和大批量证据写入。
//

import Foundation
import SQLite3
import XCTest
@testable import XP400Ride

final class PTProtocolEvidenceDatabaseTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var defaultsSuite: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PTProtocolEvidenceDatabaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testEmptyDatabaseCreatesVersionedSchema() throws {
        let repository = try makeRepository()
        XCTAssertEqual(repository.database.schemaVersion, PTProtocolEvidenceDatabase.currentSchemaVersion)
        XCTAssertEqual(try repository.count(), 0)
        XCTAssertTrue(repository.database.storageSizeInBytes > 0)
    }

    func testLegacyMigrationIsIdempotentAndKeepsOldBlob() throws {
        defaultsSuite = "PTProtocolEvidenceDatabaseTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let record = PTProtocolEvidenceRecord(
            domain: .uds,
            kind: .response,
            direction: .rx,
            source: .migrated,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            confidence: 0.9,
            value: "62F190 redacted"
        )
        let state = PTProtocolEvidenceV2PersistedState(schemaVersion: 2, records: [record], canCandidates: [])
        let legacyData = try PTProtocolEvidenceV2StateCodec.encode(state)
        defaults.set(legacyData, forKey: "PTProtocolEvidenceV2.state")

        let repository = try makeRepository()
        let coordinator = PTProtocolEvidenceMigrationCoordinator(defaults: defaults, repository: repository)
        let first = try coordinator.migrateIfNeeded()
        let second = try coordinator.migrateIfNeeded()

        XCTAssertTrue(first.didMigrate)
        XCTAssertFalse(second.didMigrate)
        XCTAssertEqual(try repository.count(), 1)
        XCTAssertEqual(defaults.data(forKey: "PTProtocolEvidenceV2.state"), legacyData)
        XCTAssertTrue(defaults.bool(forKey: PTProtocolEvidenceMigrationCoordinator.completionKey))
    }

    func testDuplicateEvidenceIsMergedWithoutIncreasingRowCount() throws {
        let repository = try makeRepository()
        let record = evidenceRecord(index: 1)
        let first = try repository.insert(records: [record])
        let second = try repository.insert(records: [record])

        XCTAssertEqual(first.insertedCount, 1)
        XCTAssertEqual(second.insertedCount, 0)
        XCTAssertEqual(second.repeatedCount, 1)
        XCTAssertEqual(try repository.count(), 1)
        XCTAssertEqual(try repository.records().first?.id, record.id)
    }

    func testMigrationDecodeFailureLeavesDatabaseEmptyAndRecordsFailure() throws {
        defaultsSuite = "PTProtocolEvidenceDatabaseTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let legacyData = Data("not a valid evidence snapshot".utf8)
        defaults.set(legacyData, forKey: "PTProtocolEvidenceV2.state")
        let repository = try makeRepository()
        let coordinator = PTProtocolEvidenceMigrationCoordinator(defaults: defaults, repository: repository)

        XCTAssertThrowsError(try coordinator.migrateIfNeeded())
        XCTAssertEqual(try repository.count(), 0)
        XCTAssertFalse(defaults.bool(forKey: PTProtocolEvidenceMigrationCoordinator.completionKey))
        XCTAssertNotNil(defaults.string(forKey: PTProtocolEvidenceMigrationCoordinator.failureKey))
        XCTAssertEqual(defaults.data(forKey: "PTProtocolEvidenceV2.state"), legacyData)
    }

    func testMigrationVerificationFailureRollsBackTheWholeBatch() throws {
        defaultsSuite = "PTProtocolEvidenceDatabaseTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        let stableID = UUID()
        let existing = PTProtocolEvidenceRecord(
            id: stableID,
            domain: .obd,
            kind: .response,
            direction: .rx,
            source: .live,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            confidence: 0.4,
            value: "old-value"
        )
        let incoming = PTProtocolEvidenceRecord(
            id: stableID,
            domain: .obd,
            kind: .response,
            direction: .rx,
            source: .live,
            timestamp: Date(timeIntervalSince1970: 1_700_000_001),
            confidence: 1,
            value: "new-value"
        )
        let state = PTProtocolEvidenceV2PersistedState(schemaVersion: 2, records: [incoming], canCandidates: [])
        defaults.set(try PTProtocolEvidenceV2StateCodec.encode(state), forKey: "PTProtocolEvidenceV2.state")

        let repository = try makeRepository()
        _ = try repository.insert(records: [existing])
        let coordinator = PTProtocolEvidenceMigrationCoordinator(defaults: defaults, repository: repository)

        XCTAssertThrowsError(try coordinator.migrateIfNeeded())
        XCTAssertEqual(try repository.count(), 1)
        XCTAssertEqual(try repository.records().first?.value, "old-value")
        XCTAssertFalse(defaults.bool(forKey: PTProtocolEvidenceMigrationCoordinator.completionKey))
    }

    func testCorruptedDatabaseDoesNotLookLikeAnEmptyValidStore() throws {
        let url = temporaryDirectory.appendingPathComponent("corrupted.sqlite")
        try Data("not sqlite".utf8).write(to: url)
        XCTAssertThrowsError(try PTProtocolEvidenceDatabase(url: url))
    }

    func testSchemaUpgradeAddsBuild62Columns() throws {
        let url = temporaryDirectory.appendingPathComponent("schema-v1.sqlite")
        var connection: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil),
            SQLITE_OK
        )
        guard let connection else { return XCTFail("cannot open schema fixture") }
        defer { sqlite3_close(connection) }

        let legacySQL = """
        CREATE TABLE evidence (
            id TEXT PRIMARY KEY NOT NULL,
            domain TEXT NOT NULL,
            kind TEXT NOT NULL,
            direction TEXT NOT NULL,
            source TEXT NOT NULL,
            vehicle_id TEXT,
            ecu_id TEXT,
            session_id TEXT,
            capture_id TEXT,
            event_id TEXT,
            request TEXT,
            response TEXT,
            summary TEXT NOT NULL,
            raw_hash TEXT NOT NULL,
            confidence REAL NOT NULL,
            first_seen_at REAL NOT NULL,
            last_seen_at REAL NOT NULL,
            repetition_count INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            fingerprint TEXT,
            reference_id TEXT,
            reference TEXT,
            note TEXT,
            dedup_key TEXT NOT NULL UNIQUE
        );
        PRAGMA user_version = 1;
        """
        XCTAssertEqual(sqlite3_exec(connection, legacySQL, nil, nil, nil), SQLITE_OK)

        let repository = try PTProtocolEvidenceRepository(databaseURL: url)
        XCTAssertEqual(repository.database.schemaVersion, PTProtocolEvidenceDatabase.currentSchemaVersion)
        let record = evidenceRecord(index: 7)
        _ = try repository.insert(records: [record])
        XCTAssertEqual(try repository.records().first?.id, record.id)
    }

    func testRetentionRemovesOnlyExpiredCaptureBundleFiles() throws {
        let repository = try makeRepository()
        let captureDirectory = temporaryDirectory.appendingPathComponent("captures", isDirectory: true)
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        let oldFiles = [
            captureDirectory.appendingPathComponent("old.jsonl"),
            captureDirectory.appendingPathComponent("old.metadata")
        ]
        for url in oldFiles {
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data("old".utf8)))
        }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let oldDate = now.addingTimeInterval(-3 * 24 * 60 * 60)
        for url in oldFiles {
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
        }

        let result = try PTProtocolEvidenceRetentionCoordinator(repository: repository).maintain(
            policy: PTProtocolEvidenceRetentionPolicy(
                lowValueRecordAge: 30 * 24 * 60 * 60,
                maximumLowValueRecordsToDelete: 0,
                rawCaptureMaximumAge: 24 * 60 * 60,
                rawCaptureMaximumBytes: 10 * 1024 * 1024
            ),
            now: now,
            captureDirectoryURL: captureDirectory
        )

        XCTAssertEqual(result.deletedRawCaptureFileCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFiles[0].path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFiles[1].path))
    }

    func testLargeEvidenceBatchAndIndexedLookup() throws {
        let repository = try makeRepository()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let records = (0..<100_000).map { index in
            PTProtocolEvidenceRecord(
                domain: index.isMultiple(of: 2) ? .obd : .xp400BLE,
                kind: .frame,
                direction: .rx,
                source: .imported,
                timestamp: baseDate.addingTimeInterval(Double(index)),
                confidence: 0.5,
                value: "fixture-\(index)",
                fingerprint: "batch-\(index)"
            )
        }
        _ = try repository.insert(records: records)
        XCTAssertEqual(try repository.count(), 100_000)

        let start = Date()
        let result = try repository.records(domain: .obd, limit: 100)
        let duration = Date().timeIntervalSince(start)
        XCTAssertEqual(result.count, 100)
        XCTAssertLessThan(duration, 1.0)
    }

    private func makeRepository() throws -> PTProtocolEvidenceRepository {
        let url = temporaryDirectory.appendingPathComponent("evidence.sqlite")
        return try PTProtocolEvidenceRepository(databaseURL: url)
    }

    private func evidenceRecord(index: Int) -> PTProtocolEvidenceRecord {
        PTProtocolEvidenceRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", index))")!,
            domain: .obd,
            kind: .response,
            direction: .rx,
            source: .live,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            confidence: 0.8,
            value: "response-\(index)",
            fingerprint: "response-\(index)"
        )
    }
}
