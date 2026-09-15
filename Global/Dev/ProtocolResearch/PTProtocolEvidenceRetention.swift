//
//  PTProtocolEvidenceRetention.swift
//  CrazyDashboard
//
//  EN: Exposes safe, explicit retention and storage reporting for research artifacts.
//  ES: Expone una retención explícita y segura y un informe de almacenamiento para artefactos de investigación.
//  中文：提供安全、显式的研究数据保留策略和存储空间报告。
//

import Foundation

public nonisolated struct PTProtocolEvidenceRetentionPolicy: Equatable, Sendable {
    public let lowValueRecordAge: TimeInterval
    public let maximumLowValueRecordsToDelete: Int
    public let rawCaptureMaximumAge: TimeInterval
    public let rawCaptureMaximumBytes: Int64

    public init(
        lowValueRecordAge: TimeInterval = 90 * 24 * 60 * 60,
        maximumLowValueRecordsToDelete: Int = 500,
        rawCaptureMaximumAge: TimeInterval = 90 * 24 * 60 * 60,
        rawCaptureMaximumBytes: Int64 = 256 * 1024 * 1024
    ) {
        self.lowValueRecordAge = max(0, lowValueRecordAge)
        self.maximumLowValueRecordsToDelete = max(0, maximumLowValueRecordsToDelete)
        self.rawCaptureMaximumAge = max(0, rawCaptureMaximumAge)
        self.rawCaptureMaximumBytes = max(0, rawCaptureMaximumBytes)
    }
}

public nonisolated struct PTProtocolEvidenceStorageUsage: Equatable, Sendable {
    public let evidenceDatabaseBytes: Int64
    public let traceBytes: Int64
    public let canCaptureBytes: Int64
    public let instrumentExportBytes: Int64

    public init(
        evidenceDatabaseBytes: Int64,
        traceBytes: Int64,
        canCaptureBytes: Int64,
        instrumentExportBytes: Int64
    ) {
        self.evidenceDatabaseBytes = max(0, evidenceDatabaseBytes)
        self.traceBytes = max(0, traceBytes)
        self.canCaptureBytes = max(0, canCaptureBytes)
        self.instrumentExportBytes = max(0, instrumentExportBytes)
    }

    public var totalBytes: Int64 {
        evidenceDatabaseBytes + traceBytes + canCaptureBytes + instrumentExportBytes
    }
}

public nonisolated struct PTProtocolEvidenceRetentionResult: Equatable, Sendable {
    public let deletedLowValueRecords: Int
    public let deletedRawCaptureFileCount: Int
    public let usageBefore: PTProtocolEvidenceStorageUsage?
    public let usageAfter: PTProtocolEvidenceStorageUsage?

    public init(
        deletedLowValueRecords: Int,
        deletedRawCaptureFileCount: Int = 0,
        usageBefore: PTProtocolEvidenceStorageUsage? = nil,
        usageAfter: PTProtocolEvidenceStorageUsage? = nil
    ) {
        self.deletedLowValueRecords = deletedLowValueRecords
        self.deletedRawCaptureFileCount = max(0, deletedRawCaptureFileCount)
        self.usageBefore = usageBefore
        self.usageAfter = usageAfter
    }
}

/// EN: Only caller-provided research directories are eligible for file trimming; production paths are never guessed for deletion.
/// ES: Solo los directorios de investigación proporcionados por el llamador pueden recortarse; nunca se adivinan rutas de producción para borrar.
/// 中文：只有调用方明确提供的研究目录才允许清理，绝不猜测生产路径执行删除。
public nonisolated final class PTProtocolEvidenceRetentionCoordinator: @unchecked Sendable {
    private let repository: PTProtocolEvidenceRepository

    public init(repository: PTProtocolEvidenceRepository) {
        self.repository = repository
    }

    public func maintain(
        policy: PTProtocolEvidenceRetentionPolicy = PTProtocolEvidenceRetentionPolicy(),
        now: Date = Date()
    ) throws -> Int {
        let cutoff = now.addingTimeInterval(-policy.lowValueRecordAge)
        let deleted = try repository.database.pruneLowValueRecords(
            before: cutoff,
            maximumCount: policy.maximumLowValueRecordsToDelete
        )
        if deleted > 0 {
            try repository.database.vacuum()
        }
        return deleted
    }

    /// EN: Deletes only complete, old capture bundles inside an explicitly supplied research directory.
    /// ES: Elimina solo paquetes completos y antiguos dentro de un directorio de investigación proporcionado explícitamente.
    /// 中文：只在调用方明确提供的研究目录内删除完整的旧抓包文件组。
    public func maintain(
        policy: PTProtocolEvidenceRetentionPolicy = PTProtocolEvidenceRetentionPolicy(),
        now: Date = Date(),
        captureDirectoryURL: URL
    ) throws -> PTProtocolEvidenceRetentionResult {
        let usageBefore = PTProtocolEvidenceStorageReporter.usage(
            databaseURL: repository.database.url,
            canCaptureDirectoryURL: captureDirectoryURL
        )
        let deletedEvidence = try maintain(policy: policy, now: now)
        let deletedCaptureFiles = try pruneCaptureBundles(
            in: captureDirectoryURL,
            maximumBytes: policy.rawCaptureMaximumBytes,
            olderThan: now.addingTimeInterval(-policy.rawCaptureMaximumAge)
        )
        let usageAfter = PTProtocolEvidenceStorageReporter.usage(
            databaseURL: repository.database.url,
            canCaptureDirectoryURL: captureDirectoryURL
        )
        return PTProtocolEvidenceRetentionResult(
            deletedLowValueRecords: deletedEvidence,
            deletedRawCaptureFileCount: deletedCaptureFiles,
            usageBefore: usageBefore,
            usageAfter: usageAfter
        )
    }

    private func pruneCaptureBundles(
        in directoryURL: URL,
        maximumBytes: Int64,
        olderThan cutoff: Date,
        fileManager: FileManager = .default
    ) throws -> Int {
        let root = directoryURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return 0
        }
        let files = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter {
            ["jsonl", "json", "csv", "metadata"].contains($0.pathExtension.lowercased())
        }

        var bundles: [String: [URL]] = [:]
        for fileURL in files {
            let key = fileURL.deletingPathExtension().lastPathComponent
            bundles[key, default: []].append(fileURL)
        }

        struct Bundle {
            let files: [URL]
            let bytes: Int64
            let newestDate: Date
        }
        var bundleList = bundles.values.map { files -> Bundle in
            let dates = files.compactMap {
                try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            }
            let bytes = files.reduce(Int64(0)) { partialResult, fileURL in
                partialResult + captureFileSize(at: fileURL, fileManager: fileManager)
            }
            return Bundle(files: files, bytes: bytes, newestDate: dates.max() ?? .distantPast)
        }.sorted { $0.newestDate < $1.newestDate }

        var totalBytes = bundleList.reduce(Int64(0)) { $0 + $1.bytes }
        var deletedFileCount = 0
        while let bundle = bundleList.first,
              (bundle.newestDate < cutoff || totalBytes > maximumBytes) {
            // EN: The caller explicitly supplied the directory; never infer a production path here.
            // ES: El llamador proporcionó explícitamente el directorio; nunca se infiere una ruta de producción.
            // 中文：目录必须由调用方明确传入，绝不在这里猜测生产路径。
            for fileURL in bundle.files {
                try fileManager.removeItem(at: fileURL)
                deletedFileCount += 1
            }
            totalBytes -= bundle.bytes
            bundleList.removeFirst()
        }
        return deletedFileCount
    }

    private func captureFileSize(at url: URL, fileManager: FileManager) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}

public nonisolated enum PTProtocolEvidenceStorageReporter {
    public static func usage(
        databaseURL: URL,
        traceDirectoryURL: URL? = nil,
        canCaptureDirectoryURL: URL? = nil,
        instrumentExportDirectoryURL: URL? = nil,
        excludedDirectoryURLs: [URL] = [],
        fileManager: FileManager = .default
    ) -> PTProtocolEvidenceStorageUsage {
        PTProtocolEvidenceStorageUsage(
            evidenceDatabaseBytes: databaseFamilySize(at: databaseURL, fileManager: fileManager),
            traceBytes: directorySize(
                at: traceDirectoryURL,
                excluding: excludedDirectoryURLs,
                fileManager: fileManager
            ),
            canCaptureBytes: directorySize(at: canCaptureDirectoryURL, fileManager: fileManager),
            instrumentExportBytes: directorySize(at: instrumentExportDirectoryURL, fileManager: fileManager)
        )
    }

    public static func currentUsage(fileManager: FileManager = .default) -> PTProtocolEvidenceStorageUsage {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let canCaptureDirectory = PTCANCaptureStore.shared.directoryURL
        return usage(
            databaseURL: PTProtocolEvidenceDatabase.defaultURL,
            traceDirectoryURL: documents,
            canCaptureDirectoryURL: canCaptureDirectory,
            instrumentExportDirectoryURL: nil,
            excludedDirectoryURLs: [canCaptureDirectory],
            fileManager: fileManager
        )
    }

    private static func databaseFamilySize(at url: URL, fileManager: FileManager) -> Int64 {
        [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")]
            .reduce(0) { $0 + fileSize(at: $1, fileManager: fileManager) }
    }

    private static func directorySize(
        at url: URL?,
        excluding excludedDirectoryURLs: [URL] = [],
        fileManager: FileManager
    ) -> Int64 {
        guard let url,
              fileManager.fileExists(atPath: url.path),
              let enumerator = fileManager.enumerator(
                  at: url,
                  includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                  options: [.skipsHiddenFiles]
              ) else { return 0 }
        let excludedPaths = excludedDirectoryURLs.map { $0.standardizedFileURL.path }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let standardizedPath = fileURL.standardizedFileURL.path
            if excludedPaths.contains(where: { standardizedPath == $0 || standardizedPath.hasPrefix($0 + "/") }) {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            total += fileSize(at: fileURL, fileManager: fileManager)
        }
        return total
    }

    private static func fileSize(at url: URL, fileManager: FileManager) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
