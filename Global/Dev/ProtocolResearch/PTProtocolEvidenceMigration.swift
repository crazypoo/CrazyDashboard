//
//  PTProtocolEvidenceMigration.swift
//  CrazyDashboard
//
//  EN: Migrates the legacy UserDefaults evidence snapshot transactionally and keeps it as a one-release fallback.
//  ES: Migra de forma transaccional la instantánea antigua de UserDefaults y la conserva como respaldo durante una versión.
//  中文：以事务方式迁移旧 UserDefaults 证据快照，并保留一版作为回退来源。
//

import Foundation

/// EN: Shared UserDefaults keys keep migration independent from the MainActor UI store.
/// ES: Las claves compartidas de UserDefaults mantienen la migración independiente del store MainActor.
/// 中文：共享 UserDefaults Key 让迁移逻辑不依赖 MainActor UI Store。
public enum PTProtocolEvidenceStorageKeys {
    public static let legacyState = "PTProtocolEvidenceV2.state"
}

public struct PTProtocolEvidenceMigrationResult: Equatable, Sendable {
    public let didMigrate: Bool
    public let recordCount: Int
    public let candidateCount: Int

    public init(didMigrate: Bool, recordCount: Int, candidateCount: Int) {
        self.didMigrate = didMigrate
        self.recordCount = recordCount
        self.candidateCount = candidateCount
    }
}

public final class PTProtocolEvidenceMigrationCoordinator: @unchecked Sendable {
    public static let completionKey = "PTProtocolEvidenceV2.databaseMigrationCompleted"
    public static let failureKey = "PTProtocolEvidenceV2.databaseMigrationError"

    private let defaults: UserDefaults
    private let repository: PTProtocolEvidenceRepository

    public init(defaults: UserDefaults, repository: PTProtocolEvidenceRepository) {
        self.defaults = defaults
        self.repository = repository
    }

    public func migrateIfNeeded() throws -> PTProtocolEvidenceMigrationResult {
        guard let data = defaults.data(forKey: PTProtocolEvidenceStorageKeys.legacyState) else {
            defaults.set(true, forKey: Self.completionKey)
            defaults.removeObject(forKey: Self.failureKey)
            return PTProtocolEvidenceMigrationResult(didMigrate: false, recordCount: 0, candidateCount: 0)
        }

        do {
            let state = try PTProtocolEvidenceV2StateCodec.decode(data)
            if defaults.bool(forKey: Self.completionKey),
               try repository.verifyMigration(records: state.records, candidates: state.canCandidates) {
                return PTProtocolEvidenceMigrationResult(
                    didMigrate: false,
                    recordCount: state.records.count,
                    candidateCount: state.canCandidates.count
                )
            }
            _ = try repository.migrate(records: state.records, candidates: state.canCandidates)
            guard try repository.verifyMigration(records: state.records, candidates: state.canCandidates) else {
                throw PTProtocolEvidenceDatabaseError.migrationFailed("migration verification failed")
            }
            // EN: Never remove the old blob; it is the rollback source for this release.
            // ES: Nunca se elimina el blob antiguo; es la fuente de rollback de esta versión.
            // 中文：绝不删除旧 Blob，它是本版本的回滚来源。
            defaults.set(true, forKey: Self.completionKey)
            defaults.removeObject(forKey: Self.failureKey)
            return PTProtocolEvidenceMigrationResult(
                didMigrate: true,
                recordCount: state.records.count,
                candidateCount: state.canCandidates.count
            )
        } catch {
            defaults.set(error.localizedDescription, forKey: Self.failureKey)
            // EN: The database transaction rolls back inside the repository; callers can keep reading the legacy blob.
            // ES: La transacción de la base de datos se revierte dentro del repositorio; los clientes pueden seguir leyendo el blob antiguo.
            // 中文：数据库事务会在 Repository 内回滚，调用方仍可继续读取旧 Blob。
            throw error
        }
    }
}
