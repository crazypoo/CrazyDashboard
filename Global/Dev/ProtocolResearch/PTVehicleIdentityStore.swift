//
//  PTVehicleIdentityStore.swift
//  CrazyDashboard
//
//  EN: Stores Build 64 identity snapshots and diffs atomically in local Application Support.
//  ES: Guarda atómicamente instantáneas y diferencias de identidad de Build 64 en Application Support local.
//  中文：在本地 Application Support 中以原子方式保存 Build 64 身份快照和差异。
//

import Foundation

public nonisolated enum PTVehicleIdentityStoreError: Error, LocalizedError, Equatable, Sendable {
    case invalidData
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidData:
            return "车辆电子身份资料无法解析 / No se pudieron interpretar los datos de identidad electrónica."
        case .writeFailed(let message):
            return "车辆电子身份保存失败：\(message) / No se pudo guardar la identidad electrónica: \(message)"
        }
    }
}

public nonisolated struct PTVehicleIdentityStoreSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let identities: [PTVehicleElectronicIdentity]
    public let diffs: [PTVehicleIdentityDiff]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        identities: [PTVehicleElectronicIdentity] = [],
        diffs: [PTVehicleIdentityDiff] = []
    ) {
        self.schemaVersion = schemaVersion
        self.identities = identities.sorted {
            if $0.vehicleID != $1.vehicleID {
                return ($0.vehicleID?.uuidString ?? "") < ($1.vehicleID?.uuidString ?? "")
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        self.diffs = diffs.sorted {
            if $0.generatedAt != $1.generatedAt { return $0.generatedAt < $1.generatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

// EN: Actor isolation serializes snapshots and prevents simultaneous UI/background writes from losing topology.
// ES: La aislación del actor serializa las instantáneas y evita perder topología entre UI y segundo plano.
// 中文：Actor 隔离串行化快照，避免 UI 与后台同时写入导致拓扑丢失。
public actor PTVehicleIdentityStore {
    public static let defaultURL: URL = {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("CrazyDashboard", isDirectory: true)
            .appendingPathComponent("ProtocolResearch", isDirectory: true)
            .appendingPathComponent("PTVehicleIdentity.json", isDirectory: false)
    }()

    public let url: URL
    private var snapshot: PTVehicleIdentityStoreSnapshot

    public init(url: URL = PTVehicleIdentityStore.defaultURL) throws {
        self.url = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: self.url.path) {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let data = try Data(contentsOf: self.url)
                let decoded = try decoder.decode(PTVehicleIdentityStoreSnapshot.self, from: data)
                guard decoded.schemaVersion <= PTVehicleIdentityStoreSnapshot.currentSchemaVersion else {
                    throw PTVehicleIdentityStoreError.invalidData
                }
                self.snapshot = decoded
            } catch let error as PTVehicleIdentityStoreError {
                throw error
            } catch {
                throw PTVehicleIdentityStoreError.invalidData
            }
        } else {
            self.snapshot = PTVehicleIdentityStoreSnapshot()
        }
    }

    public func currentSnapshot() -> PTVehicleIdentityStoreSnapshot {
        snapshot
    }

    public func latestIdentity(for vehicleID: UUID?) -> PTVehicleElectronicIdentity? {
        snapshot.identities
            .filter { $0.vehicleID == vehicleID }
            .sorted {
                if $0.generatedAt != $1.generatedAt { return $0.generatedAt > $1.generatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            .first
    }

    public func allIdentities() -> [PTVehicleElectronicIdentity] {
        snapshot.identities
    }

    public func diffs(for vehicleID: UUID? = nil) -> [PTVehicleIdentityDiff] {
        snapshot.diffs
            .filter { vehicleID == nil || $0.vehicleID == vehicleID }
            .sorted {
                if $0.generatedAt != $1.generatedAt { return $0.generatedAt > $1.generatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    // EN: Each save keeps the previous identity long enough to produce an auditable diff, then replaces that vehicle's snapshot.
    // ES: Cada guardado conserva la identidad anterior para producir una diferencia auditable y luego reemplaza su instantánea.
    // 中文：每次保存都会保留旧身份用于生成可审计差异，然后替换该车辆的快照。
    @discardableResult
    public func upsert(
        _ identity: PTVehicleElectronicIdentity
    ) throws -> PTVehicleIdentityDiff {
        let previous = latestIdentity(for: identity.vehicleID)
        let diff = PTVehicleIdentityResolver.diff(old: previous, new: identity, at: identity.generatedAt)
        let nextIdentities = snapshot.identities.filter { existing in
            if let vehicleID = identity.vehicleID {
                return existing.vehicleID != vehicleID
            }
            return existing.id != identity.id
        } + [identity]
        let nextDiffs = Array((snapshot.diffs + [diff]).suffix(500))
        let nextSnapshot = PTVehicleIdentityStoreSnapshot(
            identities: nextIdentities,
            diffs: nextDiffs
        )
        try commit(nextSnapshot)
        return diff
    }

    private func commit(_ nextSnapshot: PTVehicleIdentityStoreSnapshot) throws {
        let previous = snapshot
        snapshot = nextSnapshot
        do {
            try persist()
        } catch {
            snapshot = previous
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
            throw PTVehicleIdentityStoreError.writeFailed(error.localizedDescription)
        }
    }
}
