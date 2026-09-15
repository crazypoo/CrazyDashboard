//
//  PTProtocolResearchStore.swift
//  CrazyDashboard
//
//  EN: Persists Build 63 research artifacts atomically without creating a transport or command store.
//  ES: Persiste atómicamente los artefactos de investigación de Build 63 sin crear un almacén de transporte ni comandos.
//  中文：以原子方式保存 Build 63 研究资料，不建立传输或车辆指令存储。
//

import Foundation

public nonisolated enum PTProtocolResearchStoreError: Error, LocalizedError, Equatable, Sendable {
    case invalidData
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidData:
            return "协议研究资料无法解析 / No se pudieron interpretar los datos de investigación del protocolo."
        case .writeFailed(let message):
            return "协议研究资料保存失败：\(message) / No se pudieron guardar los datos de investigación: \(message)"
        }
    }
}

public nonisolated struct PTProtocolResearchCatalogRecord: Codable, Equatable, Sendable {
    public let vehicleID: UUID
    public let catalog: PTVehicleSignalCatalog

    public init(vehicleID: UUID, catalog: PTVehicleSignalCatalog) {
        self.vehicleID = vehicleID
        self.catalog = catalog
    }
}

public nonisolated struct PTProtocolResearchStoreSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let experiments: [PTCANExperiment]
    public let reports: [PTCANExperimentAnalysisReport]
    public let catalogs: [PTProtocolResearchCatalogRecord]

    public init(
        schemaVersion: Int = PTProtocolResearchStoreSnapshot.currentSchemaVersion,
        experiments: [PTCANExperiment] = [],
        reports: [PTCANExperimentAnalysisReport] = [],
        catalogs: [PTProtocolResearchCatalogRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.experiments = experiments.sorted { $0.id.uuidString < $1.id.uuidString }
        self.reports = reports.sorted { $0.id.uuidString < $1.id.uuidString }
        self.catalogs = catalogs.sorted { $0.vehicleID.uuidString < $1.vehicleID.uuidString }
    }
}

/// EN: Actor isolation serializes research writes and keeps UI/replay callers race-free.
/// ES: La aislación del actor serializa las escrituras y evita carreras entre UI y reproducción.
/// 中文：Actor 隔离串行化研究资料写入，避免 UI 与回放调用产生数据竞争。
public actor PTProtocolResearchStore {
    public static let defaultURL: URL = {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("CrazyDashboard", isDirectory: true)
            .appendingPathComponent("ProtocolResearch", isDirectory: true)
            .appendingPathComponent("PTProtocolResearch.json", isDirectory: false)
    }()

    public let url: URL
    private var snapshot: PTProtocolResearchStoreSnapshot

    public init(url: URL = PTProtocolResearchStore.defaultURL) throws {
        self.url = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: self.url.path) {
            let data: Data
            do {
                data = try Data(contentsOf: self.url)
            } catch {
                throw PTProtocolResearchStoreError.invalidData
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded: PTProtocolResearchStoreSnapshot
            do {
                decoded = try decoder.decode(PTProtocolResearchStoreSnapshot.self, from: data)
            } catch {
                throw PTProtocolResearchStoreError.invalidData
            }
            guard decoded.schemaVersion <= PTProtocolResearchStoreSnapshot.currentSchemaVersion else {
                throw PTProtocolResearchStoreError.invalidData
            }
            self.snapshot = decoded
        } else {
            self.snapshot = PTProtocolResearchStoreSnapshot()
        }
    }

    public func currentSnapshot() -> PTProtocolResearchStoreSnapshot {
        snapshot
    }

    @discardableResult
    public func upsert(_ experiment: PTCANExperiment) throws -> PTCANExperiment {
        var experiments = snapshot.experiments.filter { $0.id != experiment.id }
        experiments.append(experiment)
        let nextSnapshot = PTProtocolResearchStoreSnapshot(
            experiments: experiments,
            reports: snapshot.reports,
            catalogs: snapshot.catalogs
        )
        try commit(nextSnapshot)
        return experiment
    }

    public func experiment(for id: UUID) -> PTCANExperiment? {
        snapshot.experiments.first { $0.id == id }
    }

    public func experiments(for vehicleID: UUID? = nil) -> [PTCANExperiment] {
        snapshot.experiments
            .filter { vehicleID == nil || $0.vehicleID == vehicleID }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func save(_ report: PTCANExperimentAnalysisReport) throws {
        var reports = snapshot.reports.filter { $0.id != report.id }
        reports.append(report)
        let nextSnapshot = PTProtocolResearchStoreSnapshot(
            experiments: snapshot.experiments,
            reports: reports,
            catalogs: snapshot.catalogs
        )
        try commit(nextSnapshot)
    }

    public func report(for experimentID: UUID) -> PTCANExperimentAnalysisReport? {
        snapshot.reports
            .filter { $0.experimentID == experimentID }
            .sorted { lhs, rhs in
                if lhs.generatedAt != rhs.generatedAt { return lhs.generatedAt > rhs.generatedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .first
    }

    public func catalog(for vehicleID: UUID) -> PTVehicleSignalCatalog {
        snapshot.catalogs.first { $0.vehicleID == vehicleID }?.catalog ?? PTVehicleSignalCatalog()
    }

    /// EN: Discovery inserts candidates only; promotion is a separate explicit operation.
    /// ES: El descubrimiento solo inserta candidatos; la promoción es una operación explícita separada.
    /// 中文：Discovery 只能插入候选，晋级必须是单独的显式操作。
    public func insertCandidates(
        _ definitions: [PTVehicleSignalDefinition],
        for vehicleID: UUID
    ) throws {
        var catalog = catalog(for: vehicleID)
        definitions.forEach { catalog.insertCandidate($0) }
        try save(catalog: catalog, for: vehicleID)
    }

    @discardableResult
    public func promote(
        definitionID: String,
        to status: PTSignalDefinitionStatus,
        for vehicleID: UUID
    ) throws -> Bool {
        var catalog = catalog(for: vehicleID)
        guard catalog.setStatus(status, for: definitionID) else { return false }
        try save(catalog: catalog, for: vehicleID)
        return true
    }

    private func save(catalog: PTVehicleSignalCatalog, for vehicleID: UUID) throws {
        var catalogs = snapshot.catalogs.filter { $0.vehicleID != vehicleID }
        catalogs.append(PTProtocolResearchCatalogRecord(vehicleID: vehicleID, catalog: catalog))
        let nextSnapshot = PTProtocolResearchStoreSnapshot(
            experiments: snapshot.experiments,
            reports: snapshot.reports,
            catalogs: catalogs
        )
        try commit(nextSnapshot)
    }

    private func commit(_ nextSnapshot: PTProtocolResearchStoreSnapshot) throws {
        let previousSnapshot = snapshot
        snapshot = nextSnapshot
        do {
            try persist()
        } catch {
            snapshot = previousSnapshot
            throw error
        }
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(snapshot)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            throw PTProtocolResearchStoreError.writeFailed(error.localizedDescription)
        }
    }
}
