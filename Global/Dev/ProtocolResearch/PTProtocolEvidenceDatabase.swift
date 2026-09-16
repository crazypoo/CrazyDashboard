//
//  PTProtocolEvidenceDatabase.swift
//  CrazyDashboard
//
//  EN: Provides a small SQLite-backed research store without touching BLE or OBD transport code.
//  ES: Proporciona un almacén de investigación SQLite pequeño sin tocar el transporte BLE ni OBD.
//  中文：提供轻量 SQLite 研究存储，不触碰 BLE 或 OBD 传输代码。
//

import CryptoKit
import Foundation
import SQLite3

nonisolated public enum PTProtocolEvidenceDatabaseError: Error, LocalizedError, Equatable, Sendable {
    case cannotCreateDirectory(String)
    case cannotOpen(String)
    case cannotPrepare(String)
    case cannotBind(String)
    case cannotExecute(String)
    case schemaVersionUnsupported(Int)
    case invalidRow(String)
    case migrationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cannotCreateDirectory(let message): return "无法创建证据库目录：\(message)"
        case .cannotOpen(let message): return "无法打开证据库：\(message)"
        case .cannotPrepare(let message): return "证据库 SQL 准备失败：\(message)"
        case .cannotBind(let message): return "证据库参数绑定失败：\(message)"
        case .cannotExecute(let message): return "证据库执行失败：\(message)"
        case .schemaVersionUnsupported(let version): return "不支持的证据库版本：\(version)"
        case .invalidRow(let message): return "证据库记录无效：\(message)"
        case .migrationFailed(let message): return "证据库迁移失败：\(message)"
        }
    }
}

nonisolated public struct PTProtocolEvidenceDatabaseInsertResult: Equatable, Sendable {
    public let insertedCount: Int
    public let repeatedCount: Int

    public init(insertedCount: Int, repeatedCount: Int) {
        self.insertedCount = insertedCount
        self.repeatedCount = repeatedCount
    }
}

nonisolated public struct PTProtocolEvidenceDatabaseStatus: Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case database
        case legacyFallback
        case unavailable
    }

    public let state: State
    public let schemaVersion: Int?
    public let migrationCompleted: Bool
    public let message: String?

    public init(
        state: State,
        schemaVersion: Int? = nil,
        migrationCompleted: Bool = false,
        message: String? = nil
    ) {
        self.state = state
        self.schemaVersion = schemaVersion
        self.migrationCompleted = migrationCompleted
        self.message = message
    }
}

/// EN: The database is serialized on a utility queue so a large import never races with a reader.
/// ES: La base de datos se serializa en una cola de utilidad para que una importación grande no compita con lectores.
/// 中文：数据库操作统一串行到 utility 队列，避免大批量导入与读取发生数据竞争。
nonisolated public final class PTProtocolEvidenceDatabase: @unchecked Sendable {
    public static let currentSchemaVersion = 2
    public static let maximumPageSize = 10_000

    public static var defaultURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("CrazyDashboard", isDirectory: true)
            .appendingPathComponent("ProtocolResearch", isDirectory: true)
            .appendingPathComponent("PTProtocolEvidence.sqlite", isDirectory: false)
    }

    public let url: URL
    public private(set) var schemaVersion: Int = 0

    private let fileManager: FileManager
    private let queue: DispatchQueue
    private var connection: OpaquePointer?

    public init(url: URL = PTProtocolEvidenceDatabase.defaultURL,
                fileManager: FileManager = .default) throws {
        self.url = url.standardizedFileURL
        self.fileManager = fileManager
        self.queue = DispatchQueue(label: "com.yd.PTSpeed.protocol-evidence.sqlite", qos: .utility)

        do {
            try fileManager.createDirectory(
                at: self.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw PTProtocolEvidenceDatabaseError.cannotCreateDirectory(error.localizedDescription)
        }

        var openedConnection: OpaquePointer?
        let openResult = sqlite3_open_v2(
            self.url.path,
            &openedConnection,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let openedConnection else {
            let message = openedConnection.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let openedConnection { sqlite3_close(openedConnection) }
            throw PTProtocolEvidenceDatabaseError.cannotOpen(message)
        }
        self.connection = openedConnection
        sqlite3_busy_timeout(openedConnection, 5_000)

        do {
            try queue.sync {
                try configureAndMigrateLocked()
            }
        } catch {
            sqlite3_close(openedConnection)
            self.connection = nil
            throw error
        }
    }

    deinit {
        if let connection {
            sqlite3_close(connection)
        }
    }

    public func insert(records: [PTProtocolEvidenceRecord]) throws -> PTProtocolEvidenceDatabaseInsertResult {
        guard !records.isEmpty else { return PTProtocolEvidenceDatabaseInsertResult(insertedCount: 0, repeatedCount: 0) }
        return try withConnection { connection in
            try executeLocked("BEGIN IMMEDIATE TRANSACTION", on: connection)
            do {
                let result = try insertRecordsLocked(records, on: connection)
                try executeLocked("COMMIT", on: connection)
                return result
            } catch {
                try? executeLocked("ROLLBACK", on: connection)
                throw error
            }
        }
    }

    public func insert(candidates: [PTProtocolCANBitCandidate]) throws -> PTProtocolEvidenceDatabaseInsertResult {
        guard !candidates.isEmpty else { return PTProtocolEvidenceDatabaseInsertResult(insertedCount: 0, repeatedCount: 0) }
        return try withConnection { connection in
            try executeLocked("BEGIN IMMEDIATE TRANSACTION", on: connection)
            do {
                let result = try insertCandidatesLocked(candidates, on: connection)
                try executeLocked("COMMIT", on: connection)
                return result
            } catch {
                try? executeLocked("ROLLBACK", on: connection)
                throw error
            }
        }
    }

    /// EN: Migrates evidence and CAN candidates in one SQLite transaction.
    /// ES: Migra la evidencia y los candidatos CAN en una sola transacción SQLite.
    /// 中文：在同一个 SQLite 事务中迁移 Evidence 和 CAN 候选，避免半成功状态。
    @discardableResult
    public func insert(
        records: [PTProtocolEvidenceRecord],
        candidates: [PTProtocolCANBitCandidate]
    ) throws -> (records: PTProtocolEvidenceDatabaseInsertResult, candidates: PTProtocolEvidenceDatabaseInsertResult) {
        guard !records.isEmpty || !candidates.isEmpty else {
            return (
                PTProtocolEvidenceDatabaseInsertResult(insertedCount: 0, repeatedCount: 0),
                PTProtocolEvidenceDatabaseInsertResult(insertedCount: 0, repeatedCount: 0)
            )
        }
        return try withConnection { connection in
            try executeLocked("BEGIN IMMEDIATE TRANSACTION", on: connection)
            do {
                let recordResult = try insertRecordsLocked(records, on: connection)
                let candidateResult = try insertCandidatesLocked(candidates, on: connection)
                try executeLocked("COMMIT", on: connection)
                return (recordResult, candidateResult)
            } catch {
                try? executeLocked("ROLLBACK", on: connection)
                throw error
            }
        }
    }

    /// EN: Imports the legacy snapshot and verifies it before committing the transaction.
    /// ES: Importa la instantánea antigua y la verifica antes de confirmar la transacción.
    /// 中文：导入旧快照并在提交事务前完成校验，失败时整个迁移回滚。
    @discardableResult
    public func migrate(
        records: [PTProtocolEvidenceRecord],
        candidates: [PTProtocolCANBitCandidate]
    ) throws -> (records: PTProtocolEvidenceDatabaseInsertResult, candidates: PTProtocolEvidenceDatabaseInsertResult) {
        guard !records.isEmpty || !candidates.isEmpty else {
            return (
                PTProtocolEvidenceDatabaseInsertResult(insertedCount: 0, repeatedCount: 0),
                PTProtocolEvidenceDatabaseInsertResult(insertedCount: 0, repeatedCount: 0)
            )
        }
        return try withConnection { connection in
            try executeLocked("BEGIN IMMEDIATE TRANSACTION", on: connection)
            do {
                let recordResult = try insertRecordsLocked(records, on: connection)
                let candidateResult = try insertCandidatesLocked(candidates, on: connection)
                guard try verifyMigrationLocked(records: records, candidates: candidates, on: connection) else {
                    throw PTProtocolEvidenceDatabaseError.migrationFailed("migration verification failed")
                }
                try executeLocked("COMMIT", on: connection)
                return (recordResult, candidateResult)
            } catch {
                try? executeLocked("ROLLBACK", on: connection)
                throw error
            }
        }
    }

    public func records(domain: PTProtocolEvidenceDomain? = nil, limit: Int = 2_000) throws -> [PTProtocolEvidenceRecord] {
        try records(domain: domain, limit: limit, offset: 0)
    }

    /// EN: Page reads keep large evidence histories out of memory; callers can walk the database incrementally.
    /// ES: Las lecturas paginadas mantienen los historiales grandes fuera de memoria y permiten recorrer la base incrementalmente.
    /// 中文：分页读取避免大型 Evidence 历史一次性进入内存，调用方可以增量遍历数据库。
    public func records(
        domain: PTProtocolEvidenceDomain? = nil,
        limit: Int = 2_000,
        offset: Int
    ) throws -> [PTProtocolEvidenceRecord] {
        let safeLimit = min(max(limit, 1), Self.maximumPageSize)
        let safeOffset = max(offset, 0)
        return try withConnection { connection in
            var sql = "SELECT id, domain, kind, direction, source, timestamp, confidence, request, response, summary, fingerprint, vehicle_id, reference_id, reference, note FROM evidence"
            var values: [PTSQLiteValue] = []
            if let domain {
                sql += " WHERE domain = ?"
                values.append(.text(domain.rawValue))
            }
            sql += " ORDER BY last_seen_at DESC, id ASC LIMIT ? OFFSET ?"
            values.append(.integer(Int64(safeLimit)))
            values.append(.integer(Int64(safeOffset)))
            let rows = try queryLocked(sql, values: values, on: connection)
            return try rows.map(Self.decodeRecord)
        }
    }

    /// EN: Consume records page by page so large evidence sets never become one in-memory array.
    /// ES: Consume los registros página a página para que un conjunto grande nunca sea un único array en memoria.
    /// 中文：逐页消费记录，避免大型 Evidence 集合一次性成为内存数组。
    @discardableResult
    public func forEachRecord(
        domain: PTProtocolEvidenceDomain? = nil,
        pageSize: Int = 2_000,
        _ body: ([PTProtocolEvidenceRecord]) throws -> Void
    ) throws -> Int {
        let safePageSize = min(max(pageSize, 1), Self.maximumPageSize)
        var offset = 0
        var total = 0
        while true {
            let page = try records(domain: domain, limit: safePageSize, offset: offset)
            guard !page.isEmpty else { break }
            try body(page)
            total += page.count
            guard page.count == safePageSize else { break }
            offset += page.count
        }
        return total
    }

    public func candidates(limit: Int = 500) throws -> [PTProtocolCANBitCandidate] {
        let safeLimit = min(max(limit, 1), 100_000)
        return try withConnection { connection in
            let rows = try queryLocked(
                """
                SELECT id, capture_id, event_id, header, changed_byte_indexes, changed_bits,
                       dominant_before_payload, dominant_after_payload, changed_frame_count,
                       first_change_timestamp, last_change_timestamp, score, source, timestamp,
                       confidence, vehicle_id, note
                FROM can_candidates ORDER BY timestamp DESC, id ASC LIMIT ?
                """,
                values: [.integer(Int64(safeLimit))],
                on: connection
            )
            return try rows.map(Self.decodeCandidate)
        }
    }

    public func count(domain: PTProtocolEvidenceDomain? = nil) throws -> Int {
        try withConnection { connection in
            let rows: [[String?]]
            if let domain {
                rows = try queryLocked("SELECT COUNT(*) FROM evidence WHERE domain = ?", values: [.text(domain.rawValue)], on: connection)
            } else {
                rows = try queryLocked("SELECT COUNT(*) FROM evidence", values: [], on: connection)
            }
            return Int(rows.first?.first.flatMap { $0 }.flatMap(Int.init) ?? 0)
        }
    }

    public func containsEvidence(id: UUID) throws -> Bool {
        try withConnection { connection in
            let rows = try queryLocked("SELECT 1 FROM evidence WHERE id = ? LIMIT 1", values: [.text(id.uuidString)], on: connection)
            return !rows.isEmpty
        }
    }

    public func verifyMigration(records: [PTProtocolEvidenceRecord], candidates: [PTProtocolCANBitCandidate]) throws -> Bool {
        try withConnection { connection in
            try verifyMigrationLocked(records: records, candidates: candidates, on: connection)
        }
    }

    public func pruneLowValueRecords(before cutoff: Date, maximumCount: Int) throws -> Int {
        guard maximumCount >= 0 else { return 0 }
        return try withConnection { connection in
            let beforeCount = try countLocked(on: connection)
            try executeLocked(
                """
                DELETE FROM evidence
                WHERE id IN (
                    SELECT id FROM evidence
                    WHERE first_seen_at < ?
                      AND (domain IN ('ymobdVendorExtension', 'ymobdFirmwareOTA') OR kind = 'telemetry')
                    ORDER BY first_seen_at ASC
                    LIMIT ?
                )
                """,
                values: [.real(cutoff.timeIntervalSince1970), .integer(Int64(maximumCount))],
                on: connection
            )
            return max(0, beforeCount - (try countLocked(on: connection)))
        }
    }

    public func vacuum() throws {
        try withConnection { connection in
            try executeLocked("VACUUM", on: connection)
        }
    }

    public var storageSizeInBytes: Int64 {
        let urls = [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")]
        return urls.reduce(0) { partialResult, fileURL in
            partialResult + Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

nonisolated public final class PTProtocolEvidenceRepository: @unchecked Sendable {
    public let database: PTProtocolEvidenceDatabase

    public init(databaseURL: URL = PTProtocolEvidenceDatabase.defaultURL) throws {
        database = try PTProtocolEvidenceDatabase(url: databaseURL)
    }

    public init(database: PTProtocolEvidenceDatabase) {
        self.database = database
    }

    @discardableResult
    public func insert(records: [PTProtocolEvidenceRecord]) throws -> PTProtocolEvidenceDatabaseInsertResult {
        try database.insert(records: records)
    }

    @discardableResult
    public func insert(candidates: [PTProtocolCANBitCandidate]) throws -> PTProtocolEvidenceDatabaseInsertResult {
        try database.insert(candidates: candidates)
    }

    /// EN: Keeps the migration boundary atomic for evidence and CAN candidates.
    /// ES: Mantiene atómico el límite de migración para evidencia y candidatos CAN.
    /// 中文：为 Evidence 与 CAN 候选提供原子迁移边界。
    @discardableResult
    public func insert(
        records: [PTProtocolEvidenceRecord],
        candidates: [PTProtocolCANBitCandidate]
    ) throws -> (records: PTProtocolEvidenceDatabaseInsertResult, candidates: PTProtocolEvidenceDatabaseInsertResult) {
        try database.insert(records: records, candidates: candidates)
    }

    /// EN: Performs the verified legacy migration atomically.
    /// ES: Realiza atómicamente la migración antigua verificada.
    /// 中文：以原子方式执行带校验的旧数据迁移。
    @discardableResult
    public func migrate(
        records: [PTProtocolEvidenceRecord],
        candidates: [PTProtocolCANBitCandidate]
    ) throws -> (records: PTProtocolEvidenceDatabaseInsertResult, candidates: PTProtocolEvidenceDatabaseInsertResult) {
        try database.migrate(records: records, candidates: candidates)
    }

    public func records(domain: PTProtocolEvidenceDomain? = nil, limit: Int = 2_000) throws -> [PTProtocolEvidenceRecord] {
        try database.records(domain: domain, limit: limit)
    }

    /// EN: Exposes the page boundary without changing the legacy first-page API.
    /// ES: Expone el límite de página sin cambiar la API heredada de la primera página.
    /// 中文：暴露数据库分页边界，同时保持旧的第一页 API 不变。
    public func records(
        domain: PTProtocolEvidenceDomain? = nil,
        limit: Int = 2_000,
        offset: Int
    ) throws -> [PTProtocolEvidenceRecord] {
        try database.records(domain: domain, limit: limit, offset: offset)
    }

    /// EN: Keeps the repository facade bounded for exports and research reports.
    /// ES: Mantiene acotada la fachada del repositorio para exportaciones e informes de investigación.
    /// 中文：为导出和研究报告保持仓库门面的内存有界。
    @discardableResult
    public func forEachRecord(
        domain: PTProtocolEvidenceDomain? = nil,
        pageSize: Int = 2_000,
        _ body: ([PTProtocolEvidenceRecord]) throws -> Void
    ) throws -> Int {
        try database.forEachRecord(domain: domain, pageSize: pageSize, body)
    }

    public func candidates(limit: Int = 500) throws -> [PTProtocolCANBitCandidate] {
        try database.candidates(limit: limit)
    }

    public func count(domain: PTProtocolEvidenceDomain? = nil) throws -> Int {
        try database.count(domain: domain)
    }

    public func verifyMigration(records: [PTProtocolEvidenceRecord], candidates: [PTProtocolCANBitCandidate]) throws -> Bool {
        try database.verifyMigration(records: records, candidates: candidates)
    }
}

private enum PTSQLiteValue {
    case text(String?)
    case integer(Int64)
    case real(Double)
}

nonisolated private extension PTProtocolEvidenceDatabase {
    func withConnection<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        try queue.sync {
            guard let connection else {
                throw PTProtocolEvidenceDatabaseError.cannotOpen("connection closed")
            }
            return try operation(connection)
        }
    }

    func insertRecordsLocked(
        _ records: [PTProtocolEvidenceRecord],
        on connection: OpaquePointer
    ) throws -> PTProtocolEvidenceDatabaseInsertResult {
        var insertedCount = 0
        var repeatedCount = 0
        for record in records {
            let dedupKey = Self.dedupKey(for: record)
            let existing = try queryLocked(
                "SELECT id FROM evidence WHERE id = ? OR dedup_key = ? LIMIT 1",
                values: [.text(record.id.uuidString), .text(dedupKey)],
                on: connection
            )
            let now = Date().timeIntervalSince1970
            if existing.isEmpty {
                try executeLocked(
                    """
                    INSERT INTO evidence (
                        id, domain, kind, direction, source, vehicle_id, ecu_id, session_id,
                        capture_id, event_id, request, response, summary, raw_hash,
                        confidence, safety_classification, first_seen_at, last_seen_at,
                        repetition_count, created_at, updated_at, timestamp, fingerprint, reference_id,
                        reference, note, dedup_key
                    ) VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    values: [
                        .text(record.id.uuidString),
                        .text(record.domain.rawValue),
                        .text(record.kind.rawValue),
                        .text(record.direction.rawValue),
                        .text(record.source.rawValue),
                        .text(record.vehicleID?.uuidString),
                        .text(record.request),
                        .text(record.response),
                        .text(record.value),
                        .text(Self.rawHash(for: record)),
                        .real(record.confidence),
                        .text(Self.safetyClassification(for: record)),
                        .real(record.timestamp.timeIntervalSince1970),
                        .real(record.timestamp.timeIntervalSince1970),
                        .real(now),
                        .real(now),
                        .real(record.timestamp.timeIntervalSince1970),
                        .text(record.fingerprint),
                        .text(record.referenceID?.uuidString),
                        .text(record.reference),
                        .text(record.note),
                        .text(dedupKey)
                    ],
                    on: connection
                )
                insertedCount += 1
            } else {
                try executeLocked(
                    """
                    UPDATE evidence
                    SET confidence = MAX(confidence, ?),
                        first_seen_at = MIN(first_seen_at, ?),
                        last_seen_at = MAX(last_seen_at, ?),
                        repetition_count = repetition_count + 1,
                        updated_at = ?
                    WHERE id = ? OR dedup_key = ?
                    """,
                    values: [
                        .real(record.confidence),
                        .real(record.timestamp.timeIntervalSince1970),
                        .real(record.timestamp.timeIntervalSince1970),
                        .real(now),
                        .text(record.id.uuidString),
                        .text(dedupKey)
                    ],
                    on: connection
                )
                repeatedCount += 1
            }
        }
        return PTProtocolEvidenceDatabaseInsertResult(
            insertedCount: insertedCount,
            repeatedCount: repeatedCount
        )
    }

    func insertCandidatesLocked(
        _ candidates: [PTProtocolCANBitCandidate],
        on connection: OpaquePointer
    ) throws -> PTProtocolEvidenceDatabaseInsertResult {
        var insertedCount = 0
        var repeatedCount = 0
        for candidate in candidates {
            let dedupKey = Self.candidateDedupKey(for: candidate)
            let existing = try queryLocked(
                "SELECT id FROM can_candidates WHERE dedup_key = ? LIMIT 1",
                values: [.text(dedupKey)],
                on: connection
            )
            let now = Date().timeIntervalSince1970
            if existing.isEmpty {
                try executeLocked(
                    """
                    INSERT INTO can_candidates (
                        id, capture_id, event_id, header, changed_byte_indexes, changed_bits,
                        dominant_before_payload, dominant_after_payload, changed_frame_count,
                        first_change_timestamp, last_change_timestamp, score, source, timestamp,
                        confidence, vehicle_id, note, repetition_count, created_at, updated_at, dedup_key
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)
                    """,
                    values: [
                        .text(candidate.id.uuidString),
                        .text(candidate.captureID.uuidString),
                        .text(candidate.eventID.uuidString),
                        .text(candidate.header),
                        .text(Self.jsonString(candidate.changedByteIndexes)),
                        .text(Self.jsonString(candidate.changedBits)),
                        .text(candidate.dominantBeforePayload),
                        .text(candidate.dominantAfterPayload),
                        .integer(Int64(candidate.changedFrameCount)),
                        .real(candidate.firstChangeRelativeTimestamp ?? 0),
                        .real(candidate.lastChangeRelativeTimestamp ?? 0),
                        .integer(Int64(candidate.score)),
                        .text(candidate.source.rawValue),
                        .real(candidate.timestamp.timeIntervalSince1970),
                        .real(candidate.confidence),
                        .text(candidate.vehicleID?.uuidString),
                        .text(candidate.note),
                        .real(now),
                        .real(now),
                        .text(dedupKey)
                    ],
                    on: connection
                )
                insertedCount += 1
            } else {
                try executeLocked(
                    "UPDATE can_candidates SET confidence = MAX(confidence, ?), updated_at = ?, repetition_count = repetition_count + 1 WHERE dedup_key = ?",
                    values: [.real(candidate.confidence), .real(now), .text(dedupKey)],
                    on: connection
                )
                repeatedCount += 1
            }
        }
        return PTProtocolEvidenceDatabaseInsertResult(
            insertedCount: insertedCount,
            repeatedCount: repeatedCount
        )
    }

    func verifyMigrationLocked(
        records: [PTProtocolEvidenceRecord],
        candidates: [PTProtocolCANBitCandidate],
        on connection: OpaquePointer
    ) throws -> Bool {
        let storedRecordRows = try queryLocked(
            "SELECT id, raw_hash FROM evidence",
            values: [],
            on: connection
        )
        let storedRecordHashes = storedRecordRows.reduce(into: [UUID: String]()) { result, row in
            guard row.count >= 2,
                  let id = row[0].flatMap(UUID.init(uuidString:)),
                  let hash = row[1] else { return }
            result[id] = hash
        }
        let expectedRecordHashes = records.reduce(into: [UUID: String]()) { result, record in
            result[record.id] = Self.rawHash(for: record)
        }
        guard expectedRecordHashes.allSatisfy({ storedRecordHashes[$0.key] == $0.value }) else {
            return false
        }

        let candidateRows = try queryLocked(
            "SELECT dedup_key FROM can_candidates",
            values: [],
            on: connection
        )
        let candidateKeys = Set(candidateRows.compactMap { row in
            row.first ?? nil
        })
        return candidates.allSatisfy { candidateKeys.contains(Self.candidateDedupKey(for: $0)) }
    }

    func configureAndMigrateLocked() throws {
        guard let connection else { throw PTProtocolEvidenceDatabaseError.cannotOpen("connection closed") }
        try executeLocked("PRAGMA foreign_keys = ON", on: connection)
        try executeLocked("PRAGMA journal_mode = WAL", on: connection)
        // EN: FULL synchronous mode keeps committed Evidence transactions recoverable after an abrupt termination.
        // ES: El modo síncrono FULL mantiene recuperables las transacciones confirmadas tras una terminación abrupta.
        // 中文：FULL 同步模式确保应用异常终止后已提交的 Evidence 事务仍可恢复。
        try executeLocked("PRAGMA synchronous = FULL", on: connection)

        let version = try pragmaUserVersionLocked(on: connection)
        guard version <= Self.currentSchemaVersion else {
            throw PTProtocolEvidenceDatabaseError.schemaVersionUnsupported(version)
        }

        try executeLocked("BEGIN IMMEDIATE TRANSACTION", on: connection)
        do {
            try createSchemaLocked(on: connection)
            if version < 2 {
                let columns = try queryLocked("PRAGMA table_info(evidence)", values: [], on: connection)
                let hasSafetyClassification = columns.contains { $0.count > 1 && $0[1] == "safety_classification" }
                if !hasSafetyClassification {
                    try executeLocked(
                        "ALTER TABLE evidence ADD COLUMN safety_classification TEXT NOT NULL DEFAULT 'read-only'",
                        on: connection
                    )
                }
            }
            try executeLocked("PRAGMA user_version = 2", on: connection)
            try executeLocked("COMMIT", on: connection)
            schemaVersion = Self.currentSchemaVersion
        } catch {
            try? executeLocked("ROLLBACK", on: connection)
            throw PTProtocolEvidenceDatabaseError.migrationFailed(error.localizedDescription)
        }
    }

    func createSchemaLocked(on connection: OpaquePointer) throws {
        let statements = [
            "CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)",
            "CREATE TABLE IF NOT EXISTS vehicles (id TEXT PRIMARY KEY NOT NULL, name TEXT, model TEXT, vin TEXT, created_at REAL NOT NULL, updated_at REAL NOT NULL)",
            "CREATE TABLE IF NOT EXISTS ecus (id TEXT PRIMARY KEY NOT NULL, address TEXT, name TEXT, created_at REAL NOT NULL, updated_at REAL NOT NULL)",
            "CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY NOT NULL, vehicle_id TEXT, started_at REAL, ended_at REAL, source TEXT, created_at REAL NOT NULL)",
            "CREATE TABLE IF NOT EXISTS captures (id TEXT PRIMARY KEY NOT NULL, session_id TEXT, vehicle_id TEXT, name TEXT, started_at REAL, ended_at REAL, created_at REAL NOT NULL)",
            "CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY NOT NULL, session_id TEXT, capture_id TEXT, timestamp REAL, domain TEXT, summary TEXT)",
            """
            CREATE TABLE IF NOT EXISTS evidence (
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
                safety_classification TEXT NOT NULL DEFAULT 'read-only',
                first_seen_at REAL NOT NULL,
                last_seen_at REAL NOT NULL,
                repetition_count INTEGER NOT NULL DEFAULT 1,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                timestamp REAL NOT NULL,
                fingerprint TEXT,
                reference_id TEXT,
                reference TEXT,
                note TEXT,
                dedup_key TEXT NOT NULL UNIQUE
            )
            """,
            "CREATE TABLE IF NOT EXISTS evidence_links (id TEXT PRIMARY KEY NOT NULL, evidence_id TEXT NOT NULL, linked_type TEXT NOT NULL, linked_id TEXT NOT NULL, created_at REAL NOT NULL)",
            """
            CREATE TABLE IF NOT EXISTS can_candidates (
                id TEXT PRIMARY KEY NOT NULL,
                capture_id TEXT NOT NULL,
                event_id TEXT NOT NULL,
                header TEXT NOT NULL,
                changed_byte_indexes TEXT NOT NULL,
                changed_bits TEXT NOT NULL,
                dominant_before_payload TEXT,
                dominant_after_payload TEXT,
                changed_frame_count INTEGER NOT NULL,
                first_change_timestamp REAL,
                last_change_timestamp REAL,
                score INTEGER NOT NULL,
                source TEXT NOT NULL,
                timestamp REAL NOT NULL,
                confidence REAL NOT NULL,
                vehicle_id TEXT,
                note TEXT NOT NULL,
                repetition_count INTEGER NOT NULL DEFAULT 1,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                dedup_key TEXT NOT NULL UNIQUE
            )
            """,
            "CREATE TABLE IF NOT EXISTS can_experiments (id TEXT PRIMARY KEY NOT NULL, vehicle_id TEXT, name TEXT NOT NULL, status TEXT NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL)",
            "CREATE TABLE IF NOT EXISTS can_trials (id TEXT PRIMARY KEY NOT NULL, experiment_id TEXT NOT NULL, capture_id TEXT, outcome TEXT, created_at REAL NOT NULL)",
            "CREATE TABLE IF NOT EXISTS signal_definitions (id TEXT PRIMARY KEY NOT NULL, domain TEXT NOT NULL, name TEXT NOT NULL, definition TEXT NOT NULL, confidence REAL NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL)",
            "CREATE TABLE IF NOT EXISTS passport_fields (id TEXT PRIMARY KEY NOT NULL, vehicle_id TEXT, key TEXT NOT NULL, value TEXT, source TEXT, confidence REAL NOT NULL, timestamp REAL NOT NULL, created_at REAL NOT NULL)",
            "CREATE TABLE IF NOT EXISTS adapter_identities (id TEXT PRIMARY KEY NOT NULL, vehicle_id TEXT, vendor TEXT, model TEXT, firmware TEXT, identifier TEXT, source TEXT, created_at REAL NOT NULL, updated_at REAL NOT NULL)",
            "CREATE INDEX IF NOT EXISTS idx_evidence_domain ON evidence(domain)",
            "CREATE INDEX IF NOT EXISTS idx_evidence_vehicle ON evidence(vehicle_id)",
            "CREATE INDEX IF NOT EXISTS idx_evidence_ecu ON evidence(ecu_id)",
            "CREATE INDEX IF NOT EXISTS idx_evidence_session ON evidence(session_id)",
            "CREATE INDEX IF NOT EXISTS idx_evidence_capture ON evidence(capture_id)",
            "CREATE INDEX IF NOT EXISTS idx_evidence_confidence ON evidence(confidence)",
            "CREATE INDEX IF NOT EXISTS idx_evidence_first_seen ON evidence(first_seen_at)",
            "CREATE INDEX IF NOT EXISTS idx_evidence_raw_hash ON evidence(raw_hash)",
            "CREATE INDEX IF NOT EXISTS idx_can_candidates_header ON can_candidates(header)",
            "CREATE INDEX IF NOT EXISTS idx_can_candidates_capture ON can_candidates(capture_id)"
        ]
        for statement in statements {
            try executeLocked(statement, on: connection)
        }

        // EN: The timestamp column was added after the first draft of the SQLite schema.
        // ES: La columna timestamp se añadió después del primer borrador del esquema SQLite.
        // 中文：timestamp 列是在 SQLite 初版 Schema 之后补充的，这里兼容已有研究库。
        let evidenceColumns = try queryLocked("PRAGMA table_info(evidence)", values: [], on: connection)
        let hasTimestamp = evidenceColumns.contains { $0.count > 1 && $0[1] == "timestamp" }
        if !hasTimestamp {
            try executeLocked(
                "ALTER TABLE evidence ADD COLUMN timestamp REAL NOT NULL DEFAULT 0",
                on: connection
            )
            try executeLocked(
                "UPDATE evidence SET timestamp = first_seen_at WHERE timestamp = 0",
                on: connection
            )
        }
    }

    func pragmaUserVersionLocked(on connection: OpaquePointer) throws -> Int {
        let rows = try queryLocked("PRAGMA user_version", values: [], on: connection)
        return Int(rows.first?.first.flatMap { $0 }.flatMap(Int.init) ?? 0)
    }

    func countLocked(on connection: OpaquePointer) throws -> Int {
        let rows = try queryLocked("SELECT COUNT(*) FROM evidence", values: [], on: connection)
        return Int(rows.first?.first.flatMap { $0 }.flatMap(Int.init) ?? 0)
    }

    func executeLocked(_ sql: String, values: [PTSQLiteValue] = [], on connection: OpaquePointer) throws {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw PTProtocolEvidenceDatabaseError.cannotPrepare(String(cString: sqlite3_errmsg(connection)))
        }
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement, on: connection)
        var stepResult = sqlite3_step(statement)
        // EN: Some PRAGMA statements return one row before completing; drain it before finalizing.
        // ES: Algunos PRAGMA devuelven una fila antes de terminar; se consume antes de finalizar.
        // 中文：部分 PRAGMA 会先返回一行结果，必须读完后再结束 Statement。
        while stepResult == SQLITE_ROW {
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else {
            throw PTProtocolEvidenceDatabaseError.cannotExecute(String(cString: sqlite3_errmsg(connection)))
        }
    }

    func queryLocked(_ sql: String, values: [PTSQLiteValue], on connection: OpaquePointer) throws -> [[String?]] {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw PTProtocolEvidenceDatabaseError.cannotPrepare(String(cString: sqlite3_errmsg(connection)))
        }
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement, on: connection)

        var rows: [[String?]] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE { break }
            guard stepResult == SQLITE_ROW else {
                throw PTProtocolEvidenceDatabaseError.cannotExecute(String(cString: sqlite3_errmsg(connection)))
            }
            let columnCount = sqlite3_column_count(statement)
            var row: [String?] = []
            row.reserveCapacity(Int(columnCount))
            for column in 0..<columnCount {
                if sqlite3_column_type(statement, column) == SQLITE_NULL {
                    row.append(nil)
                } else if let value = sqlite3_column_text(statement, column) {
                    row.append(String(cString: value))
                } else {
                    row.append(nil)
                }
            }
            rows.append(row)
        }
        return rows
    }

    func bind(_ values: [PTSQLiteValue], to statement: OpaquePointer, on connection: OpaquePointer) throws {
        // EN: SQLite must copy temporary Swift strings before the closure returns.
        // ES: SQLite debe copiar las cadenas Swift temporales antes de que termine el closure.
        // 中文：SQLite 必须在 Swift 临时字符串闭包结束前复制内容。
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let string):
                if let string {
                    result = string.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
                } else {
                    result = sqlite3_bind_null(statement, index)
                }
            case .integer(let integer):
                result = sqlite3_bind_int64(statement, index, integer)
            case .real(let real):
                result = sqlite3_bind_double(statement, index, real)
            }
            guard result == SQLITE_OK else {
                throw PTProtocolEvidenceDatabaseError.cannotBind(String(cString: sqlite3_errmsg(connection)))
            }
        }
    }

    static func decodeRecord(_ row: [String?]) throws -> PTProtocolEvidenceRecord {
        guard row.count >= 15,
              let id = row[0].flatMap(UUID.init(uuidString:)),
              let domain = row[1].flatMap(PTProtocolEvidenceDomain.init(rawValue:)),
              let kind = row[2].flatMap(PTProtocolEvidenceKind.init(rawValue:)),
              let direction = row[3].flatMap(PTProtocolEvidenceDirection.init(rawValue:)),
              let source = row[4].flatMap(PTProtocolEvidenceSource.init(rawValue:)),
              let timestamp = row[5].flatMap(Double.init),
              let confidence = row[6].flatMap(Double.init),
              let value = row[9] else {
            throw PTProtocolEvidenceDatabaseError.invalidRow("evidence")
        }
        return PTProtocolEvidenceRecord(
            id: id,
            domain: domain,
            kind: kind,
            direction: direction,
            source: source,
            timestamp: Date(timeIntervalSince1970: timestamp),
            confidence: confidence,
            value: value,
            request: row[7],
            response: row[8],
            fingerprint: row[10],
            vehicleID: row[11].flatMap(UUID.init(uuidString:)),
            referenceID: row[12].flatMap(UUID.init(uuidString:)),
            reference: row[13],
            note: row[14]
        )
    }

    static func decodeCandidate(_ row: [String?]) throws -> PTProtocolCANBitCandidate {
        guard row.count >= 17,
              let id = row[0].flatMap(UUID.init(uuidString:)),
              let captureID = row[1].flatMap(UUID.init(uuidString:)),
              let eventID = row[2].flatMap(UUID.init(uuidString:)),
              let header = row[3],
              let bytes = row[4].flatMap(Self.decodeIntArray),
              let bits = row[5].flatMap(Self.decodeIntArray),
              let changedFrameCount = row[8].flatMap(Int.init),
              let score = row[11].flatMap(Int.init),
              let source = row[12].flatMap(PTProtocolEvidenceSource.init(rawValue:)),
              let timestamp = row[13].flatMap(Double.init),
              let confidence = row[14].flatMap(Double.init),
              let note = row[16] else {
            throw PTProtocolEvidenceDatabaseError.invalidRow("can_candidates")
        }
        return PTProtocolCANBitCandidate(
            id: id,
            captureID: captureID,
            eventID: eventID,
            header: header,
            changedByteIndexes: bytes,
            changedBits: bits,
            dominantBeforePayload: row[6],
            dominantAfterPayload: row[7],
            changedFrameCount: changedFrameCount,
            firstChangeRelativeTimestamp: row[9].flatMap(Double.init),
            lastChangeRelativeTimestamp: row[10].flatMap(Double.init),
            score: score,
            source: source,
            timestamp: Date(timeIntervalSince1970: timestamp),
            confidence: confidence,
            vehicleID: row[15].flatMap(UUID.init(uuidString:)),
            note: note
        )
    }

    static func jsonString<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decodeIntArray(_ value: String) -> [Int]? {
        try? JSONDecoder().decode([Int].self, from: Data(value.utf8))
    }

    static func dedupKey(for record: PTProtocolEvidenceRecord) -> String {
        let raw = [
            record.domain.rawValue,
            record.kind.rawValue,
            record.direction.rawValue,
            record.source.rawValue,
            record.vehicleID?.uuidString ?? "",
            record.referenceID?.uuidString ?? "",
            record.request ?? "",
            record.response ?? "",
            record.value,
            record.fingerprint ?? "",
            record.reference ?? ""
        ].joined(separator: "\u{1F}")
        return sha256(raw)
    }

    static func candidateDedupKey(for candidate: PTProtocolCANBitCandidate) -> String {
        let raw = [
            candidate.captureID.uuidString,
            candidate.eventID.uuidString,
            candidate.header,
            candidate.changedByteIndexes.map(String.init).joined(separator: ","),
            candidate.changedBits.map(String.init).joined(separator: ",")
        ].joined(separator: "\u{1F}")
        return sha256(raw)
    }

    static func rawHash(for record: PTProtocolEvidenceRecord) -> String {
        // EN: Hash the protocol payload tuple, not only the display summary, so request/response changes stay observable.
        // ES: Hashea la tupla de carga del protocolo, no solo el resumen mostrado, para conservar cambios de solicitud/respuesta.
        // 中文：对协议载荷元组而不是展示摘要做哈希，确保 request/response 变化可追踪。
        return sha256([
            record.request ?? "",
            record.response ?? "",
            record.value
        ].joined(separator: "\u{1F}"))
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func safetyClassification(for record: PTProtocolEvidenceRecord) -> String {
        switch record.domain {
        case .ymobdFirmwareOTA, .firmwareResearch:
            return "high-risk-research"
        case .can, .xp400BLE, .xp400BLETransport, .xp400BLESemantic, .obd, .obdTransport, .obd2, .uds, .gps, .motion, .correlation:
            return "passive-observation"
        case .ymobdVendorExtension, .adapterVendorExtension:
            return "adapter-read-only"
        }
    }
}
