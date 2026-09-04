//
//  PTDataPersistenceActor.swift
//  CrazyDashboard
//
//  EN: Serial, off-main persistence for local documents and iCloud files.
//  ES: Persistencia serial fuera del hilo principal para documentos locales y archivos de iCloud.
//  中文：为本地文档和 iCloud 文件提供串行、非主线程持久化。
//

import Foundation

public enum PTDataPersistenceError: Error, Equatable, LocalizedError, Sendable {
    case invalidFileName
    case fileNotFound(String)
    case localReadFailed(String)
    case localWriteFailed(String)
    case localDeleteFailed(String)
    case iCloudUnavailable
    case iCloudDownloadTimedOut(String)
    case iCloudReadFailed(String)
    case iCloudWriteFailed(String)
    case iCloudDeleteFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidFileName:
            return "文件名无效"
        case .fileNotFound(let fileName):
            return "文件不存在：\(fileName)"
        case .localReadFailed(let message):
            return "本地文件读取失败：\(message)"
        case .localWriteFailed(let message):
            return "本地文件写入失败：\(message)"
        case .localDeleteFailed(let message):
            return "本地文件删除失败：\(message)"
        case .iCloudUnavailable:
            return "iCloud 当前不可用"
        case .iCloudDownloadTimedOut(let fileName):
            return "iCloud 文件下载超时：\(fileName)"
        case .iCloudReadFailed(let message):
            return "iCloud 文件读取失败：\(message)"
        case .iCloudWriteFailed(let message):
            return "iCloud 文件写入失败：\(message)"
        case .iCloudDeleteFailed(let message):
            return "iCloud 文件删除失败：\(message)"
        case .cancelled:
            return "文件操作已取消"
        }
    }
}

public struct PTDataPersistenceWriteResult: Equatable, Sendable {
    public let fileName: String
    public let localURL: URL
    public let didWriteLocal: Bool
    public let didWriteCloud: Bool
    public let didSkipStaleWrite: Bool
    public let cloudErrorDescription: String?

    nonisolated public init(fileName: String,
                            localURL: URL,
                            didWriteLocal: Bool,
                            didWriteCloud: Bool,
                            didSkipStaleWrite: Bool = false,
                            cloudErrorDescription: String? = nil) {
        self.fileName = fileName
        self.localURL = localURL
        self.didWriteLocal = didWriteLocal
        self.didWriteCloud = didWriteCloud
        self.didSkipStaleWrite = didSkipStaleWrite
        self.cloudErrorDescription = cloudErrorDescription
    }
}

public struct PTDataPersistenceDeleteResult: Equatable, Sendable {
    public let fileName: String
    public let didDeleteLocal: Bool
    public let didDeleteCloud: Bool
    public let cloudErrorDescription: String?

    nonisolated public init(fileName: String,
                            didDeleteLocal: Bool,
                            didDeleteCloud: Bool,
                            cloudErrorDescription: String? = nil) {
        self.fileName = fileName
        self.didDeleteLocal = didDeleteLocal
        self.didDeleteCloud = didDeleteCloud
        self.cloudErrorDescription = cloudErrorDescription
    }
}

/// EN: The actor is the single writer for trip, GPX, snapshot and widget files.
/// ES: El actor es el único escritor de archivos de viajes, GPX, instantáneas y widgets.
/// 中文：该 actor 是 Trip、GPX、快照和 Widget 文件的唯一写入协调者。
public actor PTDataPersistenceActor {
    public static let shared = PTDataPersistenceActor()

    private let fileManager: FileManager
    private let localDirectoryURL: URL
    private let cloudDirectoryOverride: URL?
    private var latestRevisionByFileName: [String: Int64] = [:]

    /// EN: Production uses Documents and the configured ubiquity container; tests may inject directories.
    /// ES: En producción se usan Documents y el contenedor ubiquo configurado; las pruebas pueden inyectar directorios.
    /// 中文：生产环境使用 Documents 和配置的 iCloud 容器；测试可以注入本地目录和云目录。
    public init(localDirectoryURL: URL? = nil,
                cloudDirectoryURL: URL? = nil,
                fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.localDirectoryURL = localDirectoryURL
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.cloudDirectoryOverride = cloudDirectoryURL
    }

    public func writeData(_ data: Data,
                          fileName: String,
                          revision: Int64? = nil,
                          syncToICloud: Bool = true) throws -> PTDataPersistenceWriteResult {
        let validFileName = try validatedFileName(fileName)
        let localURL = localDirectoryURL.appendingPathComponent(validFileName, isDirectory: false)

        if let revision,
           let latestRevision = latestRevisionByFileName[validFileName],
           revision < latestRevision {
            return PTDataPersistenceWriteResult(
                fileName: validFileName,
                localURL: localURL,
                didWriteLocal: false,
                didWriteCloud: false,
                didSkipStaleWrite: true
            )
        }

        do {
            try ensureDirectoryExists(at: localDirectoryURL)
            try replaceAtomically(data: data, at: localURL, directory: localDirectoryURL)
            if let revision {
                latestRevisionByFileName[validFileName] = revision
            }
        } catch is CancellationError {
            throw PTDataPersistenceError.cancelled
        } catch {
            throw PTDataPersistenceError.localWriteFailed(error.localizedDescription)
        }

        guard syncToICloud else {
            return PTDataPersistenceWriteResult(
                fileName: validFileName,
                localURL: localURL,
                didWriteLocal: true,
                didWriteCloud: false
            )
        }

        do {
            guard let cloudDirectoryURL = try cloudDirectoryURL(createIfNeeded: true) else {
                throw PTDataPersistenceError.iCloudUnavailable
            }
            let cloudURL = cloudDirectoryURL.appendingPathComponent(validFileName, isDirectory: false)
            try replaceAtomically(data: data, at: cloudURL, directory: cloudDirectoryURL)
            return PTDataPersistenceWriteResult(
                fileName: validFileName,
                localURL: localURL,
                didWriteLocal: true,
                didWriteCloud: true
            )
        } catch let error as PTDataPersistenceError {
            return PTDataPersistenceWriteResult(
                fileName: validFileName,
                localURL: localURL,
                didWriteLocal: true,
                didWriteCloud: false,
                cloudErrorDescription: error.localizedDescription
            )
        } catch {
            return PTDataPersistenceWriteResult(
                fileName: validFileName,
                localURL: localURL,
                didWriteLocal: true,
                didWriteCloud: false,
                cloudErrorDescription: PTDataPersistenceError.iCloudWriteFailed(error.localizedDescription).localizedDescription
            )
        }
    }

    public func readData(fileName: String,
                         restoreFromICloud: Bool = true,
                         downloadTimeout: TimeInterval = 8) async throws -> Data {
        let validFileName = try validatedFileName(fileName)
        let localURL = localDirectoryURL.appendingPathComponent(validFileName, isDirectory: false)

        if fileManager.fileExists(atPath: localURL.path) {
            do {
                return try Data(contentsOf: localURL)
            } catch {
                throw PTDataPersistenceError.localReadFailed(error.localizedDescription)
            }
        }

        guard restoreFromICloud else {
            throw PTDataPersistenceError.fileNotFound(validFileName)
        }
        guard let cloudDirectoryURL = try cloudDirectoryURL(createIfNeeded: false) else {
            throw PTDataPersistenceError.iCloudUnavailable
        }

        let cloudURL = cloudDirectoryURL.appendingPathComponent(validFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: cloudURL.path) else {
            throw PTDataPersistenceError.fileNotFound(validFileName)
        }

        try await waitUntilCloudFileIsDownloaded(at: cloudURL,
                                                 fileName: validFileName,
                                                 timeout: downloadTimeout)
        do {
            let data = try Data(contentsOf: cloudURL)
            try ensureDirectoryExists(at: localDirectoryURL)
            try replaceAtomically(data: data, at: localURL, directory: localDirectoryURL)
            return data
        } catch let error as PTDataPersistenceError {
            throw error
        } catch {
            throw PTDataPersistenceError.iCloudReadFailed(error.localizedDescription)
        }
    }

    // EN: Read only the cloud copy so conflict-aware clients can compare local and cloud snapshots.
    // ES: Lee solo la copia en la nube para que los clientes puedan comparar instantáneas locales y remotas.
    // 中文：只读取云端副本，供需要处理冲突的模块比较本地与云端快照。
    public func readCloudData(fileName: String,
                             downloadTimeout: TimeInterval = 8) async throws -> Data {
        let validFileName = try validatedFileName(fileName)
        guard let cloudDirectoryURL = try cloudDirectoryURL(createIfNeeded: false) else {
            throw PTDataPersistenceError.iCloudUnavailable
        }
        let cloudURL = cloudDirectoryURL.appendingPathComponent(validFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: cloudURL.path) else {
            throw PTDataPersistenceError.fileNotFound(validFileName)
        }
        try await waitUntilCloudFileIsDownloaded(
            at: cloudURL,
            fileName: validFileName,
            timeout: downloadTimeout
        )
        do {
            return try Data(contentsOf: cloudURL)
        } catch {
            throw PTDataPersistenceError.iCloudReadFailed(error.localizedDescription)
        }
    }

    public func ensureLocalFileURL(fileName: String,
                                   downloadTimeout: TimeInterval = 8) async throws -> URL {
        let validFileName = try validatedFileName(fileName)
        let localURL = localDirectoryURL.appendingPathComponent(validFileName, isDirectory: false)
        if fileManager.fileExists(atPath: localURL.path) {
            return localURL
        }

        _ = try await readData(fileName: validFileName,
                               restoreFromICloud: true,
                               downloadTimeout: downloadTimeout)
        return localURL
    }

    public func preserveCorruptData(_ data: Data,
                                    fileName: String,
                                    date: Date = Date()) throws -> URL {
        let validFileName = try validatedFileName(fileName)
        try ensureDirectoryExists(at: localDirectoryURL)
        let baseName = URL(fileURLWithPath: validFileName).deletingPathExtension().lastPathComponent
        let extensionName = URL(fileURLWithPath: validFileName).pathExtension
        let timestamp = Int(date.timeIntervalSince1970)
        let suffix = extensionName.isEmpty ? "" : ".\(extensionName)"
        let backupName = "\(baseName).corrupt-\(timestamp)-\(UUID().uuidString)\(suffix)"
        let backupURL = localDirectoryURL.appendingPathComponent(backupName, isDirectory: false)
        do {
            try data.write(to: backupURL, options: .withoutOverwriting)
            return backupURL
        } catch {
            throw PTDataPersistenceError.localWriteFailed(error.localizedDescription)
        }
    }

    public func delete(fileName: String,
                       deleteFromICloud: Bool = true) throws -> PTDataPersistenceDeleteResult {
        let validFileName = try validatedFileName(fileName)
        let localURL = localDirectoryURL.appendingPathComponent(validFileName, isDirectory: false)
        var didDeleteLocal = false

        if fileManager.fileExists(atPath: localURL.path) {
            do {
                try fileManager.removeItem(at: localURL)
                didDeleteLocal = true
            } catch {
                throw PTDataPersistenceError.localDeleteFailed(error.localizedDescription)
            }
        }

        guard deleteFromICloud else {
            return PTDataPersistenceDeleteResult(fileName: validFileName,
                                                 didDeleteLocal: didDeleteLocal,
                                                 didDeleteCloud: false)
        }

        do {
            guard let cloudDirectoryURL = try cloudDirectoryURL(createIfNeeded: false) else {
                throw PTDataPersistenceError.iCloudUnavailable
            }
            let cloudURL = cloudDirectoryURL.appendingPathComponent(validFileName, isDirectory: false)
            if fileManager.fileExists(atPath: cloudURL.path) {
                try fileManager.removeItem(at: cloudURL)
                return PTDataPersistenceDeleteResult(fileName: validFileName,
                                                     didDeleteLocal: didDeleteLocal,
                                                     didDeleteCloud: true)
            }
            return PTDataPersistenceDeleteResult(fileName: validFileName,
                                                 didDeleteLocal: didDeleteLocal,
                                                 didDeleteCloud: false)
        } catch let error as PTDataPersistenceError {
            return PTDataPersistenceDeleteResult(fileName: validFileName,
                                                 didDeleteLocal: didDeleteLocal,
                                                 didDeleteCloud: false,
                                                 cloudErrorDescription: error.localizedDescription)
        } catch {
            return PTDataPersistenceDeleteResult(fileName: validFileName,
                                                 didDeleteLocal: didDeleteLocal,
                                                 didDeleteCloud: false,
                                                 cloudErrorDescription: PTDataPersistenceError.iCloudDeleteFailed(error.localizedDescription).localizedDescription)
        }
    }

    public func deleteCloudFileOnly(fileName: String) throws -> PTDataPersistenceDeleteResult {
        let validFileName = try validatedFileName(fileName)
        do {
            guard let cloudDirectoryURL = try cloudDirectoryURL(createIfNeeded: false) else {
                throw PTDataPersistenceError.iCloudUnavailable
            }
            let cloudURL = cloudDirectoryURL.appendingPathComponent(validFileName, isDirectory: false)
            guard fileManager.fileExists(atPath: cloudURL.path) else {
                return PTDataPersistenceDeleteResult(fileName: validFileName,
                                                     didDeleteLocal: false,
                                                     didDeleteCloud: false)
            }
            try fileManager.removeItem(at: cloudURL)
            return PTDataPersistenceDeleteResult(fileName: validFileName,
                                                 didDeleteLocal: false,
                                                 didDeleteCloud: true)
        } catch let error as PTDataPersistenceError {
            return PTDataPersistenceDeleteResult(fileName: validFileName,
                                                 didDeleteLocal: false,
                                                 didDeleteCloud: false,
                                                 cloudErrorDescription: error.localizedDescription)
        } catch {
            return PTDataPersistenceDeleteResult(fileName: validFileName,
                                                 didDeleteLocal: false,
                                                 didDeleteCloud: false,
                                                 cloudErrorDescription: PTDataPersistenceError.iCloudDeleteFailed(error.localizedDescription).localizedDescription)
        }
    }

    private func validatedFileName(_ fileName: String) throws -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains("..") else {
            throw PTDataPersistenceError.invalidFileName
        }
        return trimmed
    }

    private func ensureDirectoryExists(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url,
                                            withIntermediateDirectories: true,
                                            attributes: nil)
        }
    }

    /// EN: Write beside the destination, then replace it, so an interrupted write keeps the previous valid file.
    /// ES: Escribe junto al destino y después lo reemplaza para conservar el archivo válido anterior si se interrumpe.
    /// 中文：先在目标目录写临时文件，再替换目标，写入中断时保留上一份有效文件。
    private func replaceAtomically(data: Data, at destinationURL: URL, directory: URL) throws {
        try Task.checkCancellation()
        let temporaryURL = directory.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        do {
            try data.write(to: temporaryURL, options: .atomic)
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func cloudDirectoryURL(createIfNeeded: Bool) throws -> URL? {
        if let cloudDirectoryOverride {
            if createIfNeeded {
                try ensureDirectoryExists(at: cloudDirectoryOverride)
            }
            return cloudDirectoryOverride
        }

        guard fileManager.ubiquityIdentityToken != nil,
              let containerURL = fileManager.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        if createIfNeeded {
            try ensureDirectoryExists(at: documentsURL)
        }
        return documentsURL
    }

    /// EN: Never read a ubiquitous placeholder; wait until iCloud reports a downloaded item.
    /// ES: Nunca leemos un marcador ubicuo; esperamos a que iCloud informe que el elemento está descargado.
    /// 中文：绝不读取 iCloud 占位文件，必须等待系统报告文件已下载。
    private func waitUntilCloudFileIsDownloaded(at url: URL,
                                                fileName: String,
                                                timeout: TimeInterval) async throws {
        let initialValues = try url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ])

        guard initialValues.isUbiquitousItem == true else { return }
        if initialValues.ubiquitousItemDownloadingStatus == .downloaded
            || initialValues.ubiquitousItemDownloadingStatus == .current {
            return
        }

        do {
            try fileManager.startDownloadingUbiquitousItem(at: url)
        } catch {
            throw PTDataPersistenceError.iCloudReadFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(max(timeout, 0))
        while Date() < deadline {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if values.ubiquitousItemDownloadingStatus == .downloaded
                || values.ubiquitousItemDownloadingStatus == .current {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        throw PTDataPersistenceError.iCloudDownloadTimedOut(fileName)
    }
}
