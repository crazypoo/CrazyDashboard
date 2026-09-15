//
//  PTCrazyTracePlatform.swift
//  CrazyDashboard
//
//  EN: Adds a versioned trace package and deterministic, side-effect-free replay assertions.
//  ES: Añade un paquete de trazas versionado y aserciones de reproducción deterministas y sin efectos secundarios.
//  中文：增加版本化 CrazyTrace 数据包，以及无副作用的确定性回放断言。
//

import CryptoKit
import Foundation

nonisolated public struct PTCrazyTracePackageManifest: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 2

    public let formatVersion: Int
    public let appVersion: String
    public let buildNumber: String
    public let createdAt: Date
    public let device: String
    public let iosVersion: String
    public let vehicleID: String?
    public let domains: [PTTraceDomain]
    public let startTime: Date
    public let endTime: Date?
    public let privacyLevel: String
    public let checksums: [String: String]

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case appVersion
        case buildNumber
        case createdAt
        case device
        case iosVersion = "iOS"
        case vehicleID
        case domains
        case startTime
        case endTime
        case privacyLevel
        case checksums
    }

    public init(
        formatVersion: Int = currentFormatVersion,
        appVersion: String,
        buildNumber: String,
        createdAt: Date = Date(),
        device: String,
        iosVersion: String,
        vehicleID: String?,
        domains: [PTTraceDomain],
        startTime: Date,
        endTime: Date?,
        privacyLevel: String = "redacted",
        checksums: [String: String] = [:]
    ) {
        self.formatVersion = formatVersion
        self.appVersion = String(appVersion.prefix(64))
        self.buildNumber = String(buildNumber.prefix(32))
        self.createdAt = createdAt
        self.device = String(device.prefix(128))
        self.iosVersion = String(iosVersion.prefix(64))
        self.vehicleID = vehicleID.map { String($0.prefix(128)) }
        self.domains = domains.reduce(into: []) { result, domain in
            if !result.contains(domain) { result.append(domain) }
        }.sorted { $0.rawValue < $1.rawValue }
        self.startTime = startTime
        self.endTime = endTime
        self.privacyLevel = String(privacyLevel.prefix(32))
        self.checksums = checksums
    }
}

nonisolated public struct PTCrazyTracePackageMetadata: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let traceID: UUID
    public let name: String
    public let vehicleID: String?
    public let startedAt: Date
    public let endedAt: Date?

    public init(document: PTCrazyTraceDocument) {
        schemaVersion = document.schemaVersion
        traceID = document.traceID
        name = document.name
        vehicleID = document.vehicleID
        startedAt = document.startedAt
        endedAt = document.endedAt
    }
}

nonisolated public enum PTCrazyTracePackageError: Error, LocalizedError, Equatable, Sendable {
    case invalidPackage
    case unsupportedFormat(Int)
    case missingFile(String)
    case checksumMismatch(String)
    case invalidEvent(String)
    case metadataMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidPackage: return "CrazyTrace 数据包无效"
        case .unsupportedFormat(let version): return "不支持的 CrazyTrace 格式：\(version)"
        case .missingFile(let name): return "CrazyTrace 缺少文件：\(name)"
        case .checksumMismatch(let name): return "CrazyTrace 校验失败：\(name)"
        case .invalidEvent(let message): return "CrazyTrace 事件无效：\(message)"
        case .metadataMismatch: return "CrazyTrace manifest 与 metadata 不一致"
        }
    }
}

nonisolated public struct PTCrazyTracePackage: Equatable, Sendable {
    public let directoryURL: URL
    public let manifest: PTCrazyTracePackageManifest
    public let document: PTCrazyTraceDocument

    public init(directoryURL: URL, manifest: PTCrazyTracePackageManifest, document: PTCrazyTraceDocument) {
        self.directoryURL = directoryURL
        self.manifest = manifest
        self.document = document
    }
}

nonisolated public enum PTCrazyTracePackageWriter {
    public static let fileNames = [
        "manifest.json",
        "timeline.jsonl",
        "telemetry.jsonl",
        "obd.jsonl",
        "xp400_ble.jsonl",
        "ymobd.jsonl",
        "ota.jsonl",
        "can.bin",
        "metadata.json"
    ]

    public static func write(
        document: PTCrazyTraceDocument,
        to directoryURL: URL,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
        buildNumber: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
        device: String = "iPhone",
        iosVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        privacyLevel: String = "redacted",
        fileManager: FileManager = .default
    ) throws -> URL {
        let exportedDocument = PTCrazyTracePackagePrivacy.document(
            document,
            privacyLevel: privacyLevel
        )
        let targetURL = directoryURL.standardizedFileURL
        let parentURL = targetURL.deletingLastPathComponent()
        let stagingURL = parentURL.appendingPathComponent(
			".\(targetURL.lastPathComponent).\(UUID().uuidString).staging",
            isDirectory: true
        )

        // EN: Build the complete package beside the destination and publish it only after every file is valid.
        // ES: Construye el paquete completo junto al destino y publícalo solo cuando todos los archivos sean válidos.
        // 中文：先在目标旁边构建完整数据包，所有文件有效后再一次性发布。
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        _ = try recoverIncompletePackages(in: parentURL, fileManager: fileManager)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingURL) }
        try fileManager.createDirectory(at: stagingURL.appendingPathComponent("attachments", isDirectory: true), withIntermediateDirectories: true)

        let encoder = JSONEncoder.crazyTraceEncoder
        let metadataData = try encoder.encode(PTCrazyTracePackageMetadata(document: exportedDocument))
        // EN: Encode one event at a time so a four-hour trace does not create several full-size Data copies.
        // ES: Codifica un evento cada vez para que una traza de cuatro horas no cree varias copias completas de Data.
        // 中文：逐事件编码，避免四小时 Trace 同时创建多份完整 Data 副本。
        let streamWriter = try PTCrazyTraceJSONLStreamWriter(
            directoryURL: stagingURL,
            fileNames: [
                "timeline.jsonl",
                "telemetry.jsonl",
                "obd.jsonl",
                "xp400_ble.jsonl",
                "ymobd.jsonl",
                "ota.jsonl"
            ],
            encoder: encoder
        )
        for event in exportedDocument.events {
            try streamWriter.append(event, to: "timeline.jsonl")
            if let streamName = streamName(for: event.domain) {
                try streamWriter.append(event, to: streamName)
            }
        }
        try streamWriter.finish()
        try Data().write(to: stagingURL.appendingPathComponent("can.bin"), options: .atomic)
        try metadataData.write(to: stagingURL.appendingPathComponent("metadata.json"), options: .atomic)

        var checksums: [String: String] = [:]
        for name in fileNames where name != "manifest.json" {
            let fileURL = stagingURL.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw PTCrazyTracePackageError.missingFile(name)
            }
            checksums[name] = try sha256(fileURL: fileURL)
        }

        let manifest = PTCrazyTracePackageManifest(
            appVersion: appVersion,
            buildNumber: buildNumber,
            device: device,
            iosVersion: iosVersion,
            vehicleID: exportedDocument.vehicleID,
            domains: exportedDocument.events.map(\.domain),
            startTime: exportedDocument.startedAt,
            endTime: exportedDocument.endedAt,
            privacyLevel: privacyLevel,
            checksums: checksums
        )
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: stagingURL.appendingPathComponent("manifest.json"), options: .atomic)

        if fileManager.fileExists(atPath: targetURL.path) {
            _ = try fileManager.replaceItemAt(
                targetURL,
                withItemAt: stagingURL,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
        } else {
            try fileManager.moveItem(at: stagingURL, to: targetURL)
        }
        return targetURL
    }

    /// EN: Removes only hidden trace staging directories in the supplied parent directory.
    /// ES: Elimina solo directorios de staging ocultos de trazas dentro del directorio padre indicado.
    /// 中文：只删除指定父目录内隐藏的 Trace staging 目录。
    @discardableResult
    public static func recoverIncompletePackages(
        in parentURL: URL,
        fileManager: FileManager = .default
    ) throws -> Int {
        guard fileManager.fileExists(atPath: parentURL.path) else { return 0 }
        let entries = try fileManager.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        var removedCount = 0
        for entry in entries {
            let name = entry.lastPathComponent
            guard name.hasPrefix("."), name.hasSuffix(".staging") else { continue }
            guard try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
            try fileManager.removeItem(at: entry)
            removedCount += 1
        }
        return removedCount
    }

    private static func streamName(for domain: PTTraceDomain) -> String? {
        switch domain {
        case .vehicleTelemetry: return "telemetry.jsonl"
        case .obd: return "obd.jsonl"
        case .xp400BLE: return "xp400_ble.jsonl"
        case .ymobdAdapter: return "ymobd.jsonl"
        case .adapterOTA: return "ota.jsonl"
        case .location, .motion, .navigation, .system: return nil
        }
    }

    private static func sha256(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { handle.closeFile() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// EN: Each JSONL stream owns one handle and a bounded buffer; no event crosses an actor boundary here.
// ES: Cada flujo JSONL posee un descriptor y un búfer limitado; ningún evento cruza aquí un límite de actor.
// 中文：每个 JSONL 流独占一个文件句柄和有界缓冲区；这里不让事件跨 actor 边界。
nonisolated private final class PTCrazyTraceJSONLStreamWriter {
    private let encoder: JSONEncoder
    private let bufferLimit = 64 * 1024
    private var handles: [String: FileHandle] = [:]
    private var buffers: [String: Data] = [:]
    private var isFinished = false

    init(
        directoryURL: URL,
        fileNames: [String],
        encoder: JSONEncoder
    ) throws {
        self.encoder = encoder
        for name in fileNames {
            let fileURL = directoryURL.appendingPathComponent(name, isDirectory: false)
            try Data().write(to: fileURL, options: .atomic)
            handles[name] = try FileHandle(forWritingTo: fileURL)
            buffers[name] = Data()
        }
    }

    func append(_ event: PTCrazyTraceEvent, to name: String) throws {
        guard handles[name] != nil else { throw PTCrazyTracePackageError.invalidPackage }
        var line = try encoder.encode(event)
        line.append(0x0A)
        buffers[name, default: Data()].append(line)
        if buffers[name]?.count ?? 0 >= bufferLimit {
            try flush(name)
        }
    }

    func finish() throws {
        guard !isFinished else { return }
        for name in handles.keys.sorted() {
            try flush(name)
            handles[name]?.closeFile()
        }
        isFinished = true
    }

    deinit {
        for handle in handles.values { handle.closeFile() }
    }

    private func flush(_ name: String) throws {
        guard let handle = handles[name], var buffer = buffers[name], !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
        buffers[name] = buffer
    }
}

private nonisolated enum PTCrazyTracePackagePrivacy {
    static func document(_ document: PTCrazyTraceDocument, privacyLevel: String) -> PTCrazyTraceDocument {
        guard privacyLevel.caseInsensitiveCompare("redacted") == .orderedSame else {
            return document
        }

        // EN: Redacted packages remove vehicle identity and precise locations before any checksum is calculated.
        // ES: Los paquetes redactados eliminan la identidad del vehículo y las ubicaciones precisas antes de calcular sumas.
        // 中文：脱敏包会在计算校验和之前移除车辆身份和精确位置。
        let events = document.events.map { event in
            let payload: PTTracePayload
            switch event.payload {
            case .protocolMessage(let message):
                let metadata = message.metadata.reduce(into: [String: String]()) { result, pair in
                    result[pair.key] = isSensitiveKey(pair.key) ? "<redacted>" : pair.value
                }
                payload = .protocolMessage(
                    PTTraceProtocolPayload(
                        raw: redactText(message.raw),
                        command: message.command.map(redactText),
                        metadata: metadata
                    )
                )
            case .location(let location):
                payload = .location(
                    PTTraceLocationPayload(
                        latitude: 0,
                        longitude: 0,
                        altitude: 0,
                        speedKmh: location.speedKmh,
                        courseDegree: location.courseDegree
                    )
                )
            case .marker(let marker):
                let metadata = marker.metadata.reduce(into: [String: String]()) { result, pair in
                    result[pair.key] = isSensitiveKey(pair.key) ? "<redacted>" : pair.value
                }
                payload = .marker(PTTraceMarkerPayload(name: marker.name, metadata: metadata))
            case .text:
                // EN: Free-form trace text is not needed for a redacted replay package and may contain notification or PTT content.
                // ES: El texto libre no es necesario para un paquete de reproducción redactado y puede contener notificaciones o PTT.
                // 中文：脱敏回放包不需要自由文本，因为其中可能包含通知或 PTT 内容。
                payload = .text(PTBuild65PrivacyPolicy.redactFreeText("private trace text"))
            default:
                payload = event.payload
            }
            return PTCrazyTraceEvent(
                id: event.id,
                sequence: event.sequence,
                timestamp: event.timestamp,
                elapsed: event.elapsed,
                domain: event.domain,
                direction: event.direction,
                source: event.source,
                payload: payload
            )
        }
        return PTCrazyTraceDocument(
            schemaVersion: document.schemaVersion,
            traceID: document.traceID,
            name: document.name,
            vehicleID: nil,
            startedAt: document.startedAt,
            endedAt: document.endedAt,
            events: events
        )
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        PTBuild65PrivacyPolicy.isSensitiveKey(key)
    }

    private static func redactText(_ value: String) -> String {
        PTBuild65PrivacyPolicy.redactExportText(value)
    }
}

nonisolated public enum PTCrazyTracePackageReader {
    public static func load(from directoryURL: URL, fileManager: FileManager = .default) throws -> PTCrazyTracePackage {
        let rootURL = directoryURL.standardizedFileURL
        let manifestURL = try packageFileURL(named: "manifest.json", in: rootURL)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw PTCrazyTracePackageError.missingFile("manifest.json")
        }
        let decoder = JSONDecoder.crazyTraceDecoder
        let manifest = try decoder.decode(PTCrazyTracePackageManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.formatVersion == PTCrazyTracePackageManifest.currentFormatVersion else {
            throw PTCrazyTracePackageError.unsupportedFormat(manifest.formatVersion)
        }
        var isAttachmentsDirectory: ObjCBool = false
        let attachmentsURL = rootURL.appendingPathComponent("attachments", isDirectory: true)
        guard fileManager.fileExists(atPath: attachmentsURL.path, isDirectory: &isAttachmentsDirectory),
              isAttachmentsDirectory.boolValue else {
            throw PTCrazyTracePackageError.missingFile("attachments")
        }

        // EN: A valid package must contain every declared v2 stream; this catches interrupted exports.
        // ES: Un paquete válido debe contener cada flujo v2 declarado; así se detectan exportaciones interrumpidas.
        // 中文：有效的 v2 数据包必须包含所有声明的数据流，以识别中断的导出。
        for name in PTCrazyTracePackageWriter.fileNames where name != "manifest.json" {
            guard let expectedChecksum = manifest.checksums[name] else {
                throw PTCrazyTracePackageError.missingFile(name)
            }
            let url = try packageFileURL(named: name, in: rootURL)
            guard fileManager.fileExists(atPath: url.path) else { throw PTCrazyTracePackageError.missingFile(name) }
            let actualChecksum = try sha256(fileURL: url)
            guard actualChecksum == expectedChecksum else { throw PTCrazyTracePackageError.checksumMismatch(name) }
        }

        let metadataURL = try packageFileURL(named: "metadata.json", in: rootURL)
        guard fileManager.fileExists(atPath: metadataURL.path) else { throw PTCrazyTracePackageError.missingFile("metadata.json") }
        let metadata = try decoder.decode(PTCrazyTracePackageMetadata.self, from: Data(contentsOf: metadataURL))
        guard metadata.schemaVersion == PTCrazyTraceDocument.currentSchemaVersion else {
            throw PTCrazyTracePackageError.unsupportedFormat(metadata.schemaVersion)
        }
        guard manifest.vehicleID == metadata.vehicleID,
              manifest.startTime == metadata.startedAt,
              manifest.endTime == metadata.endedAt else {
            throw PTCrazyTracePackageError.metadataMismatch
        }
        let timelineURL = try packageFileURL(named: "timeline.jsonl", in: rootURL)
        guard fileManager.fileExists(atPath: timelineURL.path) else { throw PTCrazyTracePackageError.missingFile("timeline.jsonl") }
        let events = try decodeLines(Data(contentsOf: timelineURL), decoder: decoder)
        let eventDomains = events.map(\.domain).map(\.rawValue).reduce(into: [String]()) { result, domain in
            if !result.contains(domain) { result.append(domain) }
        }.sorted()
        let manifestDomains = manifest.domains.map(\.rawValue).sorted()
        guard eventDomains == manifestDomains else {
            throw PTCrazyTracePackageError.metadataMismatch
        }
        let document = PTCrazyTraceDocument(
            schemaVersion: metadata.schemaVersion,
            traceID: metadata.traceID,
            name: metadata.name,
            vehicleID: metadata.vehicleID,
            startedAt: metadata.startedAt,
            endedAt: metadata.endedAt,
            events: events
        )
        return PTCrazyTracePackage(directoryURL: rootURL, manifest: manifest, document: document)
    }

    /// EN: Streams timeline events in bounded batches for large replay and export jobs.
    /// ES: Transmite los eventos de la línea temporal en lotes limitados para reproducciones y exportaciones grandes.
    /// 中文：以有界批次读取时间线事件，供大型回放和导出使用。
    @discardableResult
    public static func streamEvents(
        from directoryURL: URL,
        batchSize: Int = 256,
        fileManager: FileManager = .default,
        onBatch: ([PTCrazyTraceEvent]) throws -> Void
    ) throws -> Int {
        let rootURL = directoryURL.standardizedFileURL
        let timelineURL = try packageFileURL(named: "timeline.jsonl", in: rootURL)
        guard fileManager.fileExists(atPath: timelineURL.path) else {
            throw PTCrazyTracePackageError.missingFile("timeline.jsonl")
        }

        let safeBatchSize = min(max(batchSize, 1), 2_048)
        let maximumLineLength = 4 * 1024 * 1024
        let handle = try FileHandle(forReadingFrom: timelineURL)
        defer { handle.closeFile() }
        let decoder = JSONDecoder.crazyTraceDecoder
        var pending = Data()
        var batch: [PTCrazyTraceEvent] = []
        batch.reserveCapacity(safeBatchSize)
        var eventCount = 0

        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            pending.append(chunk)
            guard pending.count <= maximumLineLength || pending.contains(0x0A) else {
                throw PTCrazyTracePackageError.invalidEvent("timeline line exceeds 4 MB")
            }
            while let newlineIndex = pending.firstIndex(of: 0x0A) {
                guard newlineIndex <= maximumLineLength else {
                    throw PTCrazyTracePackageError.invalidEvent("timeline line exceeds 4 MB")
                }
                let line = pending.subdata(in: 0..<newlineIndex)
                pending.removeSubrange(0...newlineIndex)
                if let event = try decodeEvent(line, decoder: decoder) {
                    batch.append(event)
                    eventCount += 1
                    if batch.count == safeBatchSize {
                        try onBatch(batch)
                        batch.removeAll(keepingCapacity: true)
                    }
                }
            }
        }

        if !pending.isEmpty, let event = try decodeEvent(pending, decoder: decoder) {
            batch.append(event)
            eventCount += 1
        }
        if !batch.isEmpty {
            try onBatch(batch)
        }
        return eventCount
    }

    private static func packageFileURL(named name: String, in rootURL: URL) throws -> URL {
        let candidate = rootURL.appendingPathComponent(name).standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidate.path.hasPrefix(rootPath) else {
            throw PTCrazyTracePackageError.invalidPackage
        }
        return candidate
    }

    private static func decodeLines(_ data: Data, decoder: JSONDecoder) throws -> [PTCrazyTraceEvent] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw PTCrazyTracePackageError.invalidPackage
        }
        return try text.split(whereSeparator: \.isNewline).map { line in
            do {
                return try decoder.decode(PTCrazyTraceEvent.self, from: Data(line.utf8))
            } catch {
                throw PTCrazyTracePackageError.invalidEvent(error.localizedDescription)
            }
        }
    }

    private static func decodeEvent(_ data: Data, decoder: JSONDecoder) throws -> PTCrazyTraceEvent? {
        guard let text = String(data: data, encoding: .utf8) else {
            throw PTCrazyTracePackageError.invalidPackage
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        do {
            return try decoder.decode(PTCrazyTraceEvent.self, from: Data(normalized.utf8))
        } catch {
            throw PTCrazyTracePackageError.invalidEvent(error.localizedDescription)
        }
    }

    private static func sha256(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { handle.closeFile() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated public enum PTReplayExpectedValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case location(latitude: Double, longitude: Double)
    case missing

    private enum CodingKeys: String, CodingKey { case kind, string, integer, double, boolean, latitude, longitude }
    private enum Kind: String, Codable { case string, integer, double, boolean, location, missing }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .string: self = .string(try container.decode(String.self, forKey: .string))
        case .integer: self = .integer(try container.decode(Int.self, forKey: .integer))
        case .double: self = .double(try container.decode(Double.self, forKey: .double))
        case .boolean: self = .boolean(try container.decode(Bool.self, forKey: .boolean))
        case .location:
            self = .location(
                latitude: try container.decode(Double.self, forKey: .latitude),
                longitude: try container.decode(Double.self, forKey: .longitude)
            )
        case .missing: self = .missing
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value): try container.encode(Kind.string, forKey: .kind); try container.encode(value, forKey: .string)
        case .integer(let value): try container.encode(Kind.integer, forKey: .kind); try container.encode(value, forKey: .integer)
        case .double(let value): try container.encode(Kind.double, forKey: .kind); try container.encode(value, forKey: .double)
        case .boolean(let value): try container.encode(Kind.boolean, forKey: .kind); try container.encode(value, forKey: .boolean)
        case .location(let latitude, let longitude):
            try container.encode(Kind.location, forKey: .kind)
            try container.encode(latitude, forKey: .latitude)
            try container.encode(longitude, forKey: .longitude)
        case .missing: try container.encode(Kind.missing, forKey: .kind)
        }
    }

    public func matches(_ actual: PTReplayExpectedValue?, tolerance: Double) -> Bool {
        if self == .missing {
            return actual == nil || actual == .missing
        }
        guard let actual else { return false }
        switch (self, actual) {
        case (.string(let expected), .string(let actual)): return expected == actual
        case (.integer(let expected), .integer(let actual)): return expected == actual
        case (.double(let expected), .double(let actual)): return abs(expected - actual) <= max(0, tolerance)
        case (.boolean(let expected), .boolean(let actual)): return expected == actual
        case (.location(let expectedLat, let expectedLon), .location(let actualLat, let actualLon)):
            return abs(expectedLat - actualLat) <= max(0, tolerance) && abs(expectedLon - actualLon) <= max(0, tolerance)
        default: return false
        }
    }
}

nonisolated public struct PTReplayAssertion: Codable, Equatable, Sendable {
    public let timestamp: TimeInterval
    public let path: String
    public let expected: PTReplayExpectedValue
    public let tolerance: Double

    public init(timestamp: TimeInterval, path: String, expected: PTReplayExpectedValue, tolerance: Double = 0.001) {
        self.timestamp = max(0, timestamp)
        self.path = String(path.prefix(256))
        self.expected = expected
        self.tolerance = max(0, tolerance)
    }
}

nonisolated public struct PTCrazyTraceExpectedResult: Codable, Equatable, Sendable {
    public let fixtureID: String
    public let assertions: [PTReplayAssertion]

    public init(fixtureID: String, assertions: [PTReplayAssertion]) {
        self.fixtureID = String(fixtureID.prefix(128))
        self.assertions = assertions
    }
}

nonisolated public struct PTCrazyTraceReplayState: Equatable, Sendable {
    private var values: [String: PTReplayExpectedValue] = [:]

    public init() {}

    public func value(for path: String) -> PTReplayExpectedValue? {
        values[path]
    }

    public mutating func apply(_ event: PTCrazyTraceEvent) {
        switch event.payload {
        case .telemetry(let snapshot):
            for resolvedValue in snapshot.values {
                values["telemetry.\(resolvedValue.signal.rawValue)"] = Self.replayValue(for: resolvedValue.value)
                values["telemetry.\(resolvedValue.signal.rawValue).source"] = .string(resolvedValue.source.rawValue)
            }
        case .adapter(let payload):
            values["obd.transport"] = .string(payload.transport.rawValue)
            values["obd.elmState"] = .string(payload.mode.rawValue == "disconnected" ? "disconnected" : "ready")
            values["ymobd.vendor"] = payload.vendor.map { .string($0) }
            values["ymobd.firmware"] = payload.firmwareVersion.map { .string($0) }
        case .protocolMessage(let payload):
            apply(protocolPayload: payload, domain: event.domain)
        case .marker(let payload):
            values["marker.name"] = .string(payload.name)
        case .location, .motion, .text:
            break
        }
    }

    private mutating func apply(protocolPayload: PTTraceProtocolPayload, domain: PTTraceDomain) {
        if let connected = boolValue(protocolPayload.metadata["connected"]) {
            values["xp400.connected"] = .boolean(connected)
        }
        if let authenticated = boolValue(protocolPayload.metadata["authenticated"]) {
            switch domain {
            case .xp400BLE: values["xp400.authenticated"] = .boolean(authenticated)
            case .ymobdAdapter, .obd: values["ymobd.authenticated"] = .boolean(authenticated)
            default: break
            }
        }
        if let tcsMode = protocolPayload.metadata["tcsMode"] {
            values["xp400.tcsMode"] = .string(tcsMode)
        }
        if let elmState = protocolPayload.metadata["elmState"] {
            values["obd.elmState"] = .string(elmState)
        }
        if let otaState = protocolPayload.metadata["otaState"] ?? (domain == .adapterOTA ? protocolPayload.metadata["state"] : nil) {
            values["ota.state"] = .string(otaState)
        }
        let normalized = protocolPayload.raw.lowercased()
        if normalized.contains("disconnect") { values["xp400.connected"] = .boolean(false) }
        if normalized.contains("auth success") { values["xp400.authenticated"] = .boolean(true) }
        if normalized.contains("elm ready") { values["obd.elmState"] = .string("ready") }
    }

    private static func replayValue(for value: PTVehicleTelemetryValue) -> PTReplayExpectedValue {
        switch value {
        case .double(let value): return .double(value)
        case .integer(let value): return .integer(value)
        case .boolean(let value): return .boolean(value)
        case .location(let latitude, let longitude, _): return .location(latitude: latitude, longitude: longitude)
        }
    }

    private func boolValue(_ value: String?) -> Bool? {
        guard let value else { return nil }
        switch value.lowercased() {
        case "1", "true", "yes", "connected", "success": return true
        case "0", "false", "no", "disconnected", "failure": return false
        default: return nil
        }
    }
}

nonisolated public struct PTReplayAssertionFailure: Equatable, Sendable {
    public let timestamp: TimeInterval
    public let path: String
    public let expected: PTReplayExpectedValue
    public let actual: PTReplayExpectedValue?

    public init(timestamp: TimeInterval, path: String, expected: PTReplayExpectedValue, actual: PTReplayExpectedValue?) {
        self.timestamp = timestamp
        self.path = path
        self.expected = expected
        self.actual = actual
    }
}

nonisolated public struct PTReplayEvaluationResult: Equatable, Sendable {
    public let passed: Bool
    public let finalState: PTCrazyTraceReplayState
    public let failures: [PTReplayAssertionFailure]

    public init(passed: Bool, finalState: PTCrazyTraceReplayState, failures: [PTReplayAssertionFailure]) {
        self.passed = passed
        self.finalState = finalState
        self.failures = failures
    }
}

nonisolated public enum PTCrazyTraceReplayRegression {
    public static func evaluate(
        document: PTCrazyTraceDocument,
        expected: PTCrazyTraceExpectedResult
    ) -> PTReplayEvaluationResult {
        let sortedAssertions = expected.assertions.enumerated().sorted { lhs, rhs in
            lhs.element.timestamp < rhs.element.timestamp
        }
        let sortedEvents = document.events.sorted {
            if $0.elapsed != $1.elapsed { return $0.elapsed < $1.elapsed }
            return $0.sequence < $1.sequence
        }
        var state = PTCrazyTraceReplayState()
        var eventIndex = 0
        var failures: [PTReplayAssertionFailure] = []
        for (_, assertion) in sortedAssertions {
            while eventIndex < sortedEvents.count, sortedEvents[eventIndex].elapsed <= assertion.timestamp {
                state.apply(sortedEvents[eventIndex])
                eventIndex += 1
            }
            let actual = state.value(for: assertion.path)
            if !assertion.expected.matches(actual, tolerance: assertion.tolerance) {
                failures.append(
                    PTReplayAssertionFailure(
                        timestamp: assertion.timestamp,
                        path: assertion.path,
                        expected: assertion.expected,
                        actual: actual
                    )
                )
            }
        }
        while eventIndex < sortedEvents.count {
            state.apply(sortedEvents[eventIndex])
            eventIndex += 1
        }
        return PTReplayEvaluationResult(passed: failures.isEmpty, finalState: state, failures: failures)
    }
}

public extension PTCrazyTraceRecorder {
    func exportPackage(
        _ document: PTCrazyTraceDocument,
        to directoryURL: URL? = nil,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
        buildNumber: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
        privacyLevel: String = "redacted"
    ) async throws -> URL {
        let destination: URL
        if let directoryURL {
            destination = directoryURL
        } else {
            let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            destination = root.appendingPathComponent(
                "\(PTCrazyTracePlatform.fileStem(document.name))-\(document.traceID.uuidString).crazytrace",
                isDirectory: true
            )
        }
        return try await Task.detached(priority: .utility) {
            try PTCrazyTracePackageWriter.write(
                document: document,
                to: destination,
                appVersion: appVersion,
                buildNumber: buildNumber,
                privacyLevel: privacyLevel
            )
        }.value
    }
}

private enum PTCrazyTracePlatform {
    static func fileStem(_ value: String) -> String {
        let allowed = value.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                return Character(String(scalar))
            }
            return "-"
        }
        let stem = String(allowed).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String((stem.isEmpty ? "vehicle-trace" : stem).prefix(64))
    }
}
