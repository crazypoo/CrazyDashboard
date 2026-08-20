//
//  PTCANRecorder.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 17/8/2026.
//

import Foundation
import UIKit
import PooTools

//if let url = PTCANCaptureStore.shared
//    .allCaptureFiles()
//    .first {
//    
//    PTCANCaptureShare.present(
//        from: self,
//        fileURL: url
//    )
//}

// MARK: - CAN Capture Model

public enum PTCANCaptureDirection: String, Codable, Sendable {
    /// ATMA / Monitor-All 场景下无法仅凭 ELM327 输出可靠判断方向。
    case bus
    case tx
    case rx
    case unknown
}

public struct PTCANFrame: Codable, Hashable, Sendable {
    
    public let timestamp: TimeInterval
    public let sequence: Int
    public let direction: PTCANCaptureDirection
    public let rawLine: String
    public let header: String?
    public let dataHex: String?
    public let dlc: Int?
    
    public init(timestamp: TimeInterval,
                sequence: Int,
                direction: PTCANCaptureDirection,
                rawLine: String,
                header: String?,
                dataHex: String?,
                dlc: Int?) {
        self.timestamp = timestamp
        self.sequence = sequence
        self.direction = direction
        self.rawLine = rawLine
        self.header = header
        self.dataHex = dataHex
        self.dlc = dlc
    }
}

// MARK: - Capture Session

public struct PTCANCaptureSession: Codable, Sendable {

    public static let currentSchemaVersion = 2
    
    public let id: UUID
    public let name: String
    public let startedAt: Date
    public let endedAt: Date?
    public let filterHeader: String?
    public let frames: [PTCANFrame]
    public let schemaVersion: Int
    public let events: [PTCANCaptureEvent]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case startedAt
        case endedAt
        case filterHeader
        case frames
        case schemaVersion
        case events
    }
    
    public init(
        id: UUID,
        name: String,
        startedAt: Date,
        endedAt: Date?,
        filterHeader: String?,
        frames: [PTCANFrame],
        schemaVersion: Int = PTCANCaptureSession.currentSchemaVersion,
        events: [PTCANCaptureEvent] = []
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.filterHeader = filterHeader
        self.frames = frames
        self.schemaVersion = schemaVersion
        self.events = events
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.startedAt = try container.decode(Date.self, forKey: .startedAt)
        self.endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        self.filterHeader = try container.decodeIfPresent(String.self, forKey: .filterHeader)
        self.frames = try container.decode([PTCANFrame].self, forKey: .frames)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.events = try container.decodeIfPresent([PTCANCaptureEvent].self, forKey: .events) ?? []
    }
    
    public var duration: TimeInterval {
        guard let endedAt else {
            return Date().timeIntervalSince(startedAt)
        }
        
        return endedAt.timeIntervalSince(startedAt)
    }
    
    public var frameCount: Int {
        frames.count
    }
}

// MARK: - Capture Store Error

public enum PTCANCaptureStoreError: Error {
    case directoryCreationFailed
    case fileCreationFailed
    case invalidEncoding
    case emptyCapture
    case invalidCapture
}

// MARK: - Capture Store

/// 负责 Capture 的本地持久化。
///
/// 文件结构：
///
/// Documents/
/// └── PTCANCaptures/
///     ├── Dashboard_Menu_xxx.jsonl
///     ├── Dashboard_Menu_xxx.json
///     └── Dashboard_Menu_xxx.csv
///
/// JSONL：
/// - 录制过程中实时写入
/// - App 异常退出后仍然可以恢复
///
/// JSON：
/// - stop 后生成
/// - 完整 PTCANCaptureSession
///
/// CSV：
/// - 方便 Excel / Python / 其他分析工具处理
///
/// 注意：
/// - 不负责 CAN 通信
/// - 不负责发送任何车辆数据
/// - 不负责启动/停止 Sniffer
public final class PTCANCaptureStore: @unchecked Sendable {
    
    public static let shared = PTCANCaptureStore()
    
    private let stateQueue = DispatchQueue(
        label: "com.pt.cancapture.store.state",
        qos: .utility
    )
    
    private let writeQueue = DispatchQueue(
        label: "com.pt.cancapture.store.write",
        qos: .utility
    )
    
    private var fileHandle: FileHandle?
    private var currentURL: URL?
    
    private init() {}
}

// MARK: - Directory

public extension PTCANCaptureStore {
    
    var directoryURL: URL {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        
        return documents.appendingPathComponent(
            "PTCANCaptures",
            isDirectory: true
        )
    }
}

// MARK: - Live Recording

public extension PTCANCaptureStore {
    
    /// 开始一个新的实时 JSONL 文件。
    @discardableResult
    func begin(
        session: PTCANCaptureSession
    ) throws -> URL {
        
        // 先关闭上一次可能遗留的文件。
        writeQueue.sync {
            closeFileLocked()
        }
        
        let directory = directoryURL
        
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw PTCANCaptureStoreError.directoryCreationFailed
        }
        
        let fileName = makeJSONLFileName(
            session: session
        )
        
        let url = directory.appendingPathComponent(
            fileName
        )
        
        guard FileManager.default.createFile(
            atPath: url.path,
            contents: nil
        ) else {
            throw PTCANCaptureStoreError.fileCreationFailed
        }
        
        let handle: FileHandle
        
        do {
            handle = try FileHandle(
                forWritingTo: url
            )
        } catch {
            throw error
        }
        
        stateQueue.sync {
            currentURL = url
        }
        
        writeQueue.sync {
            fileHandle = handle
        }

        do {
            try writeQueue.sync {
                try writeMetadata(session, for: url)
            }
        } catch {
            writeQueue.sync {
                closeFileLocked()
            }
            stateQueue.sync {
                currentURL = nil
            }
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        
        return url
    }
    
    /// 实时追加 Frame。
    ///
    /// 使用专用串行写入队列：
    /// - 不阻塞 Recorder lock
    /// - 保证 Frame 写入顺序
    /// - stop 时使用 sync 等待之前所有 append 完成
    func append(
        _ frame: PTCANFrame
    ) {
        
        writeQueue.async { [weak self] in
            guard let self else {
                return
            }
            
            guard let fileHandle = self.fileHandle else {
                return
            }
            
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                
                let data = try encoder.encode(
                    frame
                )
                
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.write(
                    Data([0x0A])
                )
                
            } catch {
                PTNSLogConsole(
                    "[PTCANCaptureStore] Append failed:",
                    error
                )
            }
        }
    }
    
    /// 关闭当前 JSONL。
    ///
    /// 因为是 sync，所以可以保证：
    ///
    /// append 1
    /// append 2
    /// append 3
    /// finish()
    ///
    /// finish 返回时，前三条已经写完。
    @discardableResult
    func finish() -> URL? {
        
        writeQueue.sync {
            closeFileLocked()
        }
        
        let url = stateQueue.sync {
            let value = currentURL
            currentURL = nil
            return value
        }
        
        return url
    }
    
    /// 取消当前 Capture。
    func cancel() {
        
        writeQueue.sync {
            closeFileLocked()
        }
        
        let url = stateQueue.sync {
            let value = currentURL
            currentURL = nil
            return value
        }
        
        if let url {
            try? FileManager.default.removeItem(
                at: url
            )
            try? FileManager.default.removeItem(
                at: metadataURL(for: url)
            )
        }
    }

    /// Updates the sidecar metadata used for crash recovery.
    func updateMetadata(_ session: PTCANCaptureSession) throws {
        guard let url = currentFileURL else {
            return
        }

        try writeQueue.sync {
            try writeMetadata(session, for: url)
        }
    }

    func updateMetadata(_ session: PTCANCaptureSession, for url: URL) throws {
        try writeMetadata(session, for: url)
    }
    
    /// 当前 JSONL 文件。
    var currentFileURL: URL? {
        stateQueue.sync {
            currentURL
        }
    }
}

private extension PTCANCaptureStore {
    
    func closeFileLocked() {
        try? fileHandle?.close()
        fileHandle = nil
    }
}

// MARK: - Final JSON

public extension PTCANCaptureStore {
    
    @discardableResult
    func saveJSON(
        _ session: PTCANCaptureSession
    ) throws -> URL {
        
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        
        let url = directoryURL.appendingPathComponent(
            makeJSONFileName(
                session: session
            )
        )
        
        let data = try PTCANCaptureStorage.encode(
            session
        )
        
        try data.write(
            to: url,
            options: .atomic
        )
        
        return url
    }
}

// MARK: - CSV

public extension PTCANCaptureStore {
    
    @discardableResult
    func saveCSV(
        _ session: PTCANCaptureSession
    ) throws -> URL {
        
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        
        let url = directoryURL.appendingPathComponent(
            makeCSVFileName(
                session: session
            )
        )
        
        let csv = PTCANCaptureStorage.csv(
            session
        )
        
        guard let data = csv.data(
            using: .utf8
        ) else {
            throw PTCANCaptureStoreError.invalidEncoding
        }
        
        try data.write(
            to: url,
            options: .atomic
        )
        
        return url
    }
}

// MARK: - History

public extension PTCANCaptureStore {
    
    /// 获取所有 Capture 文件。
    ///
    /// 默认按照创建时间倒序。
    func allCaptureFiles() -> [URL] {
        
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .creationDateKey,
                .contentModificationDateKey,
                .fileSizeKey
            ],
            options: [
                .skipsHiddenFiles
            ]
        ) else {
            return []
        }
        
        return files
            .filter {
                let ext = $0.pathExtension.lowercased()
                
                return ext == "json" ||
                       ext == "jsonl" ||
                       ext == "csv"
            }
            .sorted {
                
                let lhs =
                    (try? $0.resourceValues(
                        forKeys: [
                            .creationDateKey
                        ]
                    ).creationDate)
                    ?? .distantPast
                
                let rhs =
                    (try? $1.resourceValues(
                        forKeys: [
                            .creationDateKey
                        ]
                    ).creationDate)
                    ?? .distantPast
                
                return lhs > rhs
            }
    }
    
    /// 获取文件大小。
    func fileSize(
        at url: URL
    ) -> Int64 {
        
        guard let values = try? url.resourceValues(
            forKeys: [
                .fileSizeKey
            ]
        ) else {
            return 0
        }
        
        return Int64(
            values.fileSize ?? 0
        )
    }
    
    /// 删除单个文件。
    func delete(
        fileURL: URL
    ) throws {
        try FileManager.default.removeItem(
            at: fileURL
        )

        if fileURL.pathExtension.lowercased() == "jsonl" {
            try? FileManager.default.removeItem(
                at: metadataURL(for: fileURL)
            )
        }
    }
    
    /// 删除所有 Capture 文件。
    func deleteAll() throws {
        
        for url in allCaptureFiles() {
            try? FileManager.default.removeItem(
                at: url
            )
        }
    }
}

// MARK: - Read JSON

public extension PTCANCaptureStore {
    
    func loadJSON(
        from url: URL
    ) throws -> PTCANCaptureSession {
        
        let data = try Data(
            contentsOf: url
        )
        
        return try PTCANCaptureStorage.decode(
            data
        )
    }
}

// MARK: - Read JSONL

public extension PTCANCaptureStore {
    
    /// 从 JSONL 恢复 Capture。
    ///
    func loadJSONL(
        from url: URL
    ) throws -> PTCANCaptureSession {
        
        let data = try Data(
            contentsOf: url
        )
        
        guard let text = String(
            data: data,
            encoding: .utf8
        ) else {
            throw PTCANCaptureStoreError.invalidEncoding
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let metadata = try? Data(contentsOf: metadataURL(for: url)),
           let session = try? PTCANCaptureStorage.decode(metadata) {
            var frames: [PTCANFrame] = []

            for substring in text.split(whereSeparator: \.isNewline) {
                guard let lineData = String(substring).data(using: .utf8),
                      let frame = try? decoder.decode(PTCANFrame.self, from: lineData) else {
                    continue
                }
                frames.append(frame)
            }

            return PTCANCaptureSession(
                id: session.id,
                name: session.name,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                filterHeader: session.filterHeader,
                frames: frames,
                schemaVersion: session.schemaVersion,
                events: session.events
            )
        }
        
        var frames: [PTCANFrame] = []
        
        for substring in text.split(
            whereSeparator: \.isNewline
        ) {
            
            let line = String(
                substring
            )
            
            guard !line.isEmpty else {
                continue
            }
            
            guard let lineData = line.data(
                using: .utf8
            ) else {
                continue
            }
            
            if let frame = try? decoder.decode(
                PTCANFrame.self,
                from: lineData
            ) {
                frames.append(frame)
            }
        }
        
        guard let first = frames.first else {
            throw PTCANCaptureStoreError.emptyCapture
        }
        
        let startedAt = Date(
            timeIntervalSince1970:
                first.timestamp
        )
        
        let endedAt = Date(
            timeIntervalSince1970:
                frames.last?.timestamp
                ?? first.timestamp
        )
        
        return PTCANCaptureSession(
            id: UUID(),
            name: url
                .deletingPathExtension()
                .lastPathComponent,
            startedAt: startedAt,
            endedAt: endedAt,
            filterHeader: nil,
            frames: frames
        )
    }
}

// MARK: - File Names

private extension PTCANCaptureStore {

    func metadataURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("metadata")
    }

    func writeMetadata(_ session: PTCANCaptureSession, for url: URL) throws {
        let data = try PTCANCaptureStorage.encode(session)
        try data.write(to: metadataURL(for: url), options: .atomic)
    }
    
    func makeJSONLFileName(
        session: PTCANCaptureSession
    ) -> String {
        
        let name = sanitize(
            session.name
        )
        
        let date = fileDateString(session.startedAt)
        
        let uuid = session.id.uuidString
            .prefix(8)
        
        return "\(name)_\(date)_\(uuid).jsonl"
    }
    
    func makeJSONFileName(
        session: PTCANCaptureSession
    ) -> String {
        
        let name = sanitize(
            session.name
        )
        
        let date = fileDateString(session.startedAt)
        
        let uuid = session.id.uuidString
            .prefix(8)
        
        return "\(name)_\(date)_\(uuid).json"
    }
    
    func makeCSVFileName(
        session: PTCANCaptureSession
    ) -> String {
        
        let name = sanitize(
            session.name
        )
        
        let date = fileDateString(session.startedAt)
        
        let uuid = session.id.uuidString
            .prefix(8)
        
        return "\(name)_\(date)_\(uuid).csv"
    }
    
    func sanitize(
        _ value: String
    ) -> String {
        
        let invalid = CharacterSet(
            charactersIn: "/\\?%*|\"<>:"
        )
        
        let result = value
            .components(
                separatedBy: invalid
            )
            .joined(separator: "_")
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        
        return result.isEmpty
            ? "XP400-Capture"
            : result
    }
    
    func fileDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "en_US_POSIX"
        )
        formatter.timeZone = TimeZone.current
        formatter.dateFormat =
            "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }
}

// MARK: - Recorder

/// 只负责记录，不发送任何车辆数据。
///
/// 数据流：
///
/// PTHiddenOBDConnector
///       ↓
/// ATMA
///       ↓
/// PTCANRecorder.append()
///       ├── Memory
///       └── PTCANCaptureStore → JSONL
///
/// Recorder 自身只使用 NSLock 保护状态。
/// 文件 IO 全部由 PTCANCaptureStore 的独立串行队列处理。
public final class PTCANRecorder: @unchecked Sendable {
    
    public static let shared = PTCANRecorder()
    
    private let lock = NSLock()
    
    private var startedAt: Date?
    private var sessionID: UUID?
    private var sessionName: String = "XP400-Capture"
    private var filterHeader: String?
    private var sequence: Int = 0
    private var frames: [PTCANFrame] = []
    private var events: [PTCANCaptureEvent] = []
    private var _maxInMemoryFrames: Int = 100_000
    
    private init() {}
}

// MARK: - Recorder State

public extension PTCANRecorder {
    
    var isRecording: Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        
        return startedAt != nil
    }
    
    var frameCount: Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        
        return frames.count
    }
    
    var currentFileURL: URL? {
        PTCANCaptureStore.shared.currentFileURL
    }

    public var maxInMemoryFrames: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _maxInMemoryFrames
        }
        set {
            lock.lock()
            _maxInMemoryFrames = max(1, newValue)
            if frames.count > _maxInMemoryFrames {
                frames.removeFirst(frames.count - _maxInMemoryFrames)
            }
            lock.unlock()
        }
    }
}

// MARK: - Start

public extension PTCANRecorder {
    
    func start(
        name: String = "XP400-Capture",
        filterHeader: String? = nil,
        clearPrevious: Bool = true
    ) {
        
        /*
         如果之前还有录制：
         先彻底结束之前的状态。
         
         这里不能调用 stop() 后再 lock，
         因为 stop 自己也会获取 lock。
         */
        
        let hadRecording: Bool = {
            lock.lock()
            defer {
                lock.unlock()
            }
            
            return startedAt != nil
        }()
        
        if hadRecording {
            _ = stop()
        }
        
        let startDate = Date()
        let identifier = UUID()
        let normalizedFilter =
            Self.normalizeHeader(
                filterHeader
            )
        
        lock.lock()
        
        startedAt = startDate
        sessionID = identifier
        sessionName =
            name.isEmpty
            ? "XP400-Capture"
            : name
        self.filterHeader =
            normalizedFilter
        sequence = 0
        events.removeAll(keepingCapacity: true)
        
        if clearPrevious {
            frames.removeAll(
                keepingCapacity: true
            )
        }
        
        let session = PTCANCaptureSession(
            id: identifier,
            name: sessionName,
            startedAt: startDate,
            endedAt: nil,
            filterHeader: normalizedFilter,
            frames: [],
            events: []
        )
        
        lock.unlock()
        
        do {
            try PTCANCaptureStore.shared.begin(
                session: session
            )
        } catch {
            
            // Store 创建失败时，不应该继续假装正在录制。
            lock.lock()
            
            startedAt = nil
            sessionID = nil
            self.filterHeader = nil
            sequence = 0
            
            lock.unlock()
            
            PTNSLogConsole(
                "[PTCANRecorder] Begin storage failed:",
                error
            )
        }
    }
}

// MARK: - Append

public extension PTCANRecorder {
    
    /// 由底层 Sniffing 流调用。
    ///
    /// 只解析/保存数据：
    /// 不会发送任何 CAN / OBD 数据。
    func append(
        rawLine: String,
        direction: PTCANCaptureDirection = .bus,
        timestamp: TimeInterval =
            Date().timeIntervalSince1970
    ) {
        
        let trimmed =
            rawLine.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        
        guard !trimmed.isEmpty else {
            return
        }
        
        guard let parsed =
            Self.parseMonitorLine(
                trimmed
            )
        else {
            /*
             SEARCHING...
             NO DATA
             ERROR
             OK
             等非 CAN 文本不进入 Frame。
             */
            return
        }
        
        lock.lock()
        
        guard startedAt != nil else {
            lock.unlock()
            return
        }
        
        if let filterHeader,
           parsed.header != filterHeader {
            lock.unlock()
            return
        }
        
        sequence += 1
        
        let frame = PTCANFrame(
            timestamp: timestamp,
            sequence: sequence,
            direction: direction,
            rawLine: trimmed,
            header: parsed.header,
            dataHex: parsed.dataHex,
            dlc: parsed.dlc
        )
        
        let memoryLimit = max(1, maxInMemoryFrames)
        if frames.count >= memoryLimit, !frames.isEmpty {
            frames.removeFirst()
        }
        frames.append(frame)
        
        lock.unlock()
        
        /*
         非常重要：
         
         不要在上面的 lock 持有期间写文件。
         
         PTCANCaptureStore 内部有自己的串行写入队列。
         */
        PTCANCaptureStore.shared.append(
            frame
        )
    }
}

// MARK: - Stop

public extension PTCANRecorder {
    
    @discardableResult
    func stop()
        -> PTCANCaptureSession? {
        
        lock.lock()
        
        guard
            let startedAt,
            let sessionID
        else {
            lock.unlock()
            return nil
        }
        
        let endedAt = Date()
        
        let result =
            PTCANCaptureSession(
                id: sessionID,
                name: sessionName,
                startedAt: startedAt,
                endedAt: endedAt,
                filterHeader: filterHeader,
                frames: frames,
                events: events
            )

        let captureURL = PTCANCaptureStore.shared.currentFileURL
        
        /*
         先把 Recorder 状态清掉。
         */
        self.startedAt = nil
        self.sessionID = nil
        self.filterHeader = nil
        self.sequence = 0
        self.events.removeAll(keepingCapacity: true)
        self.frames.removeAll(
            keepingCapacity: true
        )
        
        lock.unlock()
        
        /*
         finish() 内部是 writeQueue.sync。
         
         所以所有已经进入：
         
         store.append(frame)
         
         的任务都会先完成，
         然后才关闭文件。
         */
        _ = PTCANCaptureStore.shared.finish()

        if let captureURL {
            try? PTCANCaptureStore.shared.updateMetadata(
                result,
                for: captureURL
            )
        }
        
        /*
         保存最终 JSON。
         */
        do {
            _ = try PTCANCaptureStore.shared.saveJSON(
                result
            )
        } catch {
            PTNSLogConsole(
                "[PTCANRecorder] Save JSON failed:",
                error
            )
        }
        
        /*
         保存 CSV。
         */
        do {
            _ = try PTCANCaptureStore.shared.saveCSV(
                result
            )
        } catch {
            PTNSLogConsole(
                "[PTCANRecorder] Save CSV failed:",
                error
            )
        }
        
        return result
    }
}

// MARK: - Cancel

public extension PTCANRecorder {
    
    func cancel() {
        
        lock.lock()
        
        startedAt = nil
        sessionID = nil
        filterHeader = nil
        sequence = 0
        events.removeAll(keepingCapacity: true)
        
        frames.removeAll(
            keepingCapacity: true
        )
        
        lock.unlock()
        
        PTCANCaptureStore.shared.cancel()
    }
}

// MARK: - Snapshot

public extension PTCANRecorder {
    
    func snapshot()
        -> PTCANCaptureSession? {
        
        lock.lock()
        defer {
            lock.unlock()
        }
        
        guard
            let startedAt,
            let sessionID
        else {
            return nil
        }
        
        return PTCANCaptureSession(
            id: sessionID,
            name: sessionName,
            startedAt: startedAt,
            endedAt: nil,
            filterHeader: filterHeader,
            frames: frames,
            events: events
        )
    }
}

// MARK: - Parser

private extension PTCANRecorder {
    
    struct ParsedLine {
        let header: String
        let dataHex: String
        let dlc: Int
    }
    
    static func parseMonitorLine(
        _ line: String
    ) -> ParsedLine? {
        
        let parts = line
            .split {
                $0 == " " ||
                $0 == "\t"
            }
            .map(String.init)
            .filter {
                !$0.isEmpty
            }
        
        guard parts.count >= 2 else {
            return nil
        }
        
        let header =
            parts[0].uppercased()
        
        guard isValidCANHeader(
            header
        ) else {
            return nil
        }
        
        let candidateBytes = Array(parts.dropFirst())

        guard !candidateBytes.isEmpty,
              candidateBytes.allSatisfy({ isHexByte($0) }) else {
            return nil
        }

        let declaredDLC = Int(candidateBytes[0], radix: 16)
        let hasELMDLC = declaredDLC.map {
            // ELM327 monitor output is header + DLC + exactly DLC bytes.
            // Requiring the exact shape prevents a raw CAN payload beginning
            // with 00...08 from being mistaken for a DLC field.
            (0...8).contains($0) && candidateBytes.count == $0 + 1
        } ?? false

        let dataBytes: [String]
        let dlc: Int

        if hasELMDLC, let declaredDLC {
            let payload = Array(candidateBytes.dropFirst())
            dataBytes = Array(payload.prefix(declaredDLC))
            dlc = declaredDLC
        } else {
            dataBytes = candidateBytes
            dlc = dataBytes.count
        }
        
        guard !dataBytes.isEmpty else {
            return nil
        }
        
        let dataHex =
            dataBytes
                .joined()
                .uppercased()
        
        return ParsedLine(
            header: header,
            dataHex: dataHex,
            dlc: dlc
        )
    }
    
    static func isValidCANHeader(
        _ value: String
    ) -> Bool {
        
        let hex =
            value.uppercased()
        
        guard hex.allSatisfy({
            "0123456789ABCDEF".contains($0)
        }) else {
            return false
        }
        
        /*
         当前沿用你的协议判断：
         3 位 = 11-bit CAN
         8 位 = 29-bit CAN
         */
        return hex.count == 3 ||
               hex.count == 8
    }
    
    static func isHexByte(
        _ value: String
    ) -> Bool {
        
        guard value.count == 2 else {
            return false
        }
        
        return value.allSatisfy {
            "0123456789ABCDEFabcdef"
                .contains($0)
        }
    }
    
    static func normalizeHeader(
        _ header: String?
    ) -> String? {
        
        guard let header else {
            return nil
        }
        
        let value =
            header
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .uppercased()
        
        guard value.count == 3 ||
              value.count == 8 else {
            return nil
        }
        
        guard value.allSatisfy({
            "0123456789ABCDEF".contains($0)
        }) else {
            return nil
        }
        
        return value
    }
}

// MARK: - Capture Storage

public enum PTCANCaptureStorage {
    
    public static func encode(
        _ session: PTCANCaptureSession
    ) throws -> Data {
        
        let encoder = JSONEncoder()
        
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]
        
        encoder.dateEncodingStrategy = .iso8601
        
        return try encoder.encode(
            session
        )
    }
    
    public static func decode(
        _ data: Data
    ) throws -> PTCANCaptureSession {
        
        let decoder = JSONDecoder()
        
        decoder.dateDecodingStrategy =
            .iso8601
        
        return try decoder.decode(
            PTCANCaptureSession.self,
            from: data
        )
    }
    
    public static func csv(
        _ session: PTCANCaptureSession
    ) -> String {
        
        var lines = [
            "sequence,timestamp,elapsed,direction,header,dlc,dataHex,rawLine"
        ]
        
        lines.reserveCapacity(
            session.frames.count + 1
        )
        
        let startedTimestamp =
            session.startedAt
                .timeIntervalSince1970
        
        for frame in session.frames {
            
            let elapsed =
                frame.timestamp -
                startedTimestamp
            
            let fields = [
                String(frame.sequence),
                String(
                    format: "%.6f",
                    frame.timestamp
                ),
                String(
                    format: "%.6f",
                    elapsed
                ),
                frame.direction.rawValue,
                frame.header ?? "",
                frame.dlc.map(String.init) ?? "",
                frame.dataHex ?? "",
                csvEscape(
                    frame.rawLine
                )
            ]
            
            lines.append(
                fields.joined(
                    separator: ","
                )
            )
        }
        
        return lines.joined(
            separator: "\n"
        )
    }
    
    private static func csvEscape(
        _ value: String
    ) -> String {
        
        if value.contains(",") ||
           value.contains("\"") ||
           value.contains("\n") {
            
            return "\""
                + value.replacingOccurrences(
                    of: "\"",
                    with: "\"\""
                )
                + "\""
        }
        
        return value
    }
}

// MARK: - Offline Diff

public struct PTCANFrameDelta:
    Codable,
    Sendable {
    
    public let header: String
    public let dataHexA: String?
    public let dataHexB: String?
    public let countA: Int
    public let countB: Int
    
    public var kind: Kind {
        
        switch (
            dataHexA,
            dataHexB
        ) {
            
        case (nil, .some):
            return .added
            
        case (.some, nil):
            return .removed
            
        case let (.some(a), .some(b))
            where a != b:
            return .changed
            
        default:
            return .unchanged
        }
    }
    
    public enum Kind:
        String,
        Codable,
        Sendable {
        
        case added
        case removed
        case changed
        case unchanged
    }
}

public struct PTCANCaptureDiff:
    Codable,
    Sendable {
    
    public let leftName: String
    public let rightName: String
    public let deltas: [PTCANFrameDelta]
    
    public var interesting:
        [PTCANFrameDelta] {
        
        deltas.filter {
            $0.kind != .unchanged
        }
    }
}

public enum PTCANCaptureAnalyzer {
    
    /// 比较两个离线抓包中：
    /// 同一个 CAN ID 的 dominant payload。
    ///
    /// 注意：
    /// 这里仅整理证据，
    /// 不推断字段实际含义。
    public static func diff(
        left: PTCANCaptureSession,
        right: PTCANCaptureSession
    ) -> PTCANCaptureDiff {
        
        let leftMap =
            dominantPayloads(
                left.frames
            )
        
        let rightMap =
            dominantPayloads(
                right.frames
            )
        
        let allHeaders =
            Set(leftMap.keys)
                .union(rightMap.keys)
                .sorted()
        
        let deltas =
            allHeaders.map { header in
                
                let a =
                    leftMap[header]
                
                let b =
                    rightMap[header]
                
                return PTCANFrameDelta(
                    header: header,
                    dataHexA: a?.payload,
                    dataHexB: b?.payload,
                    countA: a?.count ?? 0,
                    countB: b?.count ?? 0
                )
            }
        
        return PTCANCaptureDiff(
            leftName: left.name,
            rightName: right.name,
            deltas: deltas
        )
    }
    
    // MARK: Signal Summary
    
    public struct SignalSummary:
        Codable,
        Sendable {
        
        public let header: String
        public let frameCount: Int
        public let dominantPayload: String
        public let averagePeriod: TimeInterval?
        public let payloadVariants: Int
    }
    
    public static func summarize(
        _ session: PTCANCaptureSession
    ) -> [SignalSummary] {
        
        let validFrames =
            session.frames.compactMap {
                frame -> PTCANFrame? in
                
                guard frame.header != nil,
                      frame.dataHex != nil
                else {
                    return nil
                }
                
                return frame
            }
        
        let grouped =
            Dictionary(
                grouping: validFrames,
                by: {
                    $0.header!
                }
            )
        
        return grouped.keys
            .sorted()
            .compactMap { header in
                
                guard
                    let values =
                        grouped[header],
                    !values.isEmpty
                else {
                    return nil
                }
                
                let variants =
                    Set(
                        values.compactMap(
                            \.dataHex
                        )
                    )
                
                let timestamps =
                    values.map(
                        \.timestamp
                    )
                
                let periods =
                    zip(
                        timestamps,
                        timestamps.dropFirst()
                    ).map {
                        $1 - $0
                    }
                
                let averagePeriod:
                    TimeInterval?
                
                if periods.isEmpty {
                    averagePeriod = nil
                } else {
                    averagePeriod =
                        periods.reduce(
                            0,
                            +
                        ) / Double(
                            periods.count
                        )
                }
                
                let groupedPayload =
                    Dictionary(
                        grouping: values,
                        by: {
                            $0.dataHex!
                        }
                    )
                
                guard let dominant =
                    groupedPayload.max(
                        by: {
                            $0.value.count <
                            $1.value.count
                        }
                    )
                else {
                    return nil
                }
                
                return SignalSummary(
                    header: header,
                    frameCount: values.count,
                    dominantPayload:
                        dominant.key,
                    averagePeriod:
                        averagePeriod,
                    payloadVariants:
                        variants.count
                )
            }
    }
    
    // MARK: Private
    
    private struct PayloadStats {
        let payload: String
        let count: Int
    }
    
    private static func dominantPayloads(
        _ frames: [PTCANFrame]
    ) -> [String: PayloadStats] {
        
        let validFrames =
            frames.compactMap {
                frame -> PTCANFrame? in
                
                guard frame.header != nil,
                      frame.dataHex != nil
                else {
                    return nil
                }
                
                return frame
            }
        
        let grouped =
            Dictionary(
                grouping: validFrames,
                by: {
                    $0.header!
                }
            )
        
        return grouped.reduce(
            into: [:]
        ) { result, item in
            
            let payloadGroups =
                Dictionary(
                    grouping: item.value,
                    by: {
                        $0.dataHex!
                    }
                )
            
            guard let dominant =
                payloadGroups.max(
                    by: {
                        $0.value.count <
                        $1.value.count
                    }
                )
            else {
                return
            }
            
            result[item.key] =
                PayloadStats(
                    payload: dominant.key,
                    count: dominant.value.count
                )
        }
    }
}

// MARK: - Capture Share

public enum PTCANCaptureShare {
    
    @MainActor
    public static func present(
        from viewController: UIViewController,
        fileURL: URL
    ) {
        
        let controller =
            UIActivityViewController(
                activityItems: [
                    fileURL
                ],
                applicationActivities: nil
            )
        
        /*
         iPad / Mac Catalyst。
         */
        if let popover =
            controller.popoverPresentationController {
            
            popover.sourceView =
                viewController.view
            
            popover.sourceRect = CGRect(
                x: viewController.view.bounds.midX,
                y: viewController.view.bounds.midY,
                width: 0,
                height: 0
            )
            
            popover.permittedArrowDirections = []
        }
        
        viewController.present(
            controller,
            animated: true
        )
    }
}

// MARK: - Existing PTMotoTelemetryManager Integration

public extension PTMotoTelemetryManager {
    
    /// 开始一次真实仪表操作 Capture。
    ///
    /// 这里只启动你现有的：
    ///
    ///     startCANSniperMode()
    ///
    /// Recorder 不会发送任何额外车辆数据。
    func startPTCANExperiment(
        name: String = "XP400-Capture",
        filterHeader: String? = nil
    ) async {
        
        PTCANRecorder.shared.start(
            name: name,
            filterHeader: filterHeader
        )
        
        await startCANSniperMode(
            filterHeader: filterHeader
        )
    }
    
    /// 停止真实 Sniffer，
    /// 然后结束 Capture 并保存文件。
    @discardableResult
    func stopPTCANExperiment()
        async -> PTCANCaptureSession? {
        
        await stopCANSniperMode()
        
        return PTCANRecorder.shared.stop()
    }
}

// MARK: - Byte Level Diff

public struct PTCANByteChange: Codable, Sendable {
    
    public let index: Int
    public let before: UInt8?
    public let after: UInt8?
    
    public var changed: Bool {
        before != after
    }
    
    public var xor: UInt8? {
        guard let before, let after else {
            return nil
        }
        
        return before ^ after
    }
    
    public var changedBits: [Int] {
        guard let xor else {
            return []
        }
        
        return (0..<8).filter {
            (xor & (1 << $0)) != 0
        }
    }
}

public struct PTCANPayloadDiff: Codable, Sendable {
    
    public let header: String
    
    public let payloadA: String?
    public let payloadB: String?
    
    public let bytes: [PTCANByteChange]
    
    public var changedByteIndexes: [Int] {
        bytes
            .filter(\.changed)
            .map(\.index)
    }
    
    public var changedByteCount: Int {
        changedByteIndexes.count
    }
    
    public var changedBitCount: Int {
        bytes.reduce(0) {
            $0 + $1.changedBits.count
        }
    }
}

public extension PTCANCaptureAnalyzer {
    
    static func byteDiff(
        left: PTCANCaptureSession,
        right: PTCANCaptureSession
    ) -> [PTCANPayloadDiff] {
        
        let leftMap =
            dominantPayloadsForDiff(
                left.frames
            )
        
        let rightMap =
            dominantPayloadsForDiff(
                right.frames
            )
        
        let headers =
            Set(leftMap.keys)
                .union(rightMap.keys)
                .sorted()
        
        return headers.compactMap { header in
            
            let payloadA =
                leftMap[header]
            
            let payloadB =
                rightMap[header]
            
            guard payloadA != nil ||
                  payloadB != nil
            else {
                return nil
            }
            
            let bytesA =
                payloadA.flatMap {
                    hexToBytes($0)
                } ?? []
            
            let bytesB =
                payloadB.flatMap {
                    hexToBytes($0)
                } ?? []
            
            let count =
                max(
                    bytesA.count,
                    bytesB.count
                )
            
            let changes =
                (0..<count).map { index in
                    
                    PTCANByteChange(
                        index: index,
                        before:
                            index < bytesA.count
                            ? bytesA[index]
                            : nil,
                        after:
                            index < bytesB.count
                            ? bytesB[index]
                            : nil
                    )
                }
            
            return PTCANPayloadDiff(
                header: header,
                payloadA: payloadA,
                payloadB: payloadB,
                bytes: changes
            )
        }
        .filter {
            !$0.changedByteIndexes.isEmpty
        }
    }
}

private extension PTCANCaptureAnalyzer {
    
    static func dominantPayloadsForDiff(
        _ frames: [PTCANFrame]
    ) -> [String: String] {
        
        let grouped =
            Dictionary(
                grouping: frames.compactMap {
                    frame -> PTCANFrame? in
                    
                    guard
                        let header = frame.header,
                        let dataHex = frame.dataHex
                    else {
                        return nil
                    }
                    
                    guard !dataHex.isEmpty else {
                        return nil
                    }
                    
                    return frame
                },
                by: {
                    $0.header!
                }
            )
        
        return grouped.reduce(
            into: [:]
        ) { result, item in
            
            let payloadGroups =
                Dictionary(
                    grouping: item.value,
                    by: {
                        $0.dataHex!
                    }
                )
            
            if let dominant =
                payloadGroups.max(
                    by: {
                        $0.value.count <
                        $1.value.count
                    }
                ) {
                
                result[item.key] =
                    dominant.key
            }
        }
    }
    
    static func hexToBytes(
        _ hex: String
    ) -> [UInt8] {
        
        let clean =
            hex
                .replacingOccurrences(
                    of: " ",
                    with: ""
                )
                .uppercased()
        
        guard clean.count % 2 == 0 else {
            return []
        }
        
        var result: [UInt8] = []
        result.reserveCapacity(
            clean.count / 2
        )
        
        var index =
            clean.startIndex
        
        while index < clean.endIndex {
            
            let next =
                clean.index(
                    index,
                    offsetBy: 2
                )
            
            let value =
                String(
                    clean[index..<next]
                )
            
            if let byte =
                UInt8(
                    value,
                    radix: 16
                ) {
                
                result.append(byte)
            }
            
            index = next
        }
        
        return result
    }
}

// MARK: - CAN Event Analyzer

public struct PTCANEventWindow: Codable, Sendable {
    
    /// 用户定义的事件时间点
    public let eventTimestamp: TimeInterval
    
    /// 事件前窗口，例如 2 秒
    public let beforeInterval: TimeInterval
    
    /// 事件后窗口，例如 2 秒
    public let afterInterval: TimeInterval
    
    public init(
        eventTimestamp: TimeInterval,
        beforeInterval: TimeInterval = 2.0,
        afterInterval: TimeInterval = 2.0
    ) {
        self.eventTimestamp = eventTimestamp
        self.beforeInterval = beforeInterval
        self.afterInterval = afterInterval
    }
    
    public var startTimestamp: TimeInterval {
        eventTimestamp - beforeInterval
    }
    
    public var endTimestamp: TimeInterval {
        eventTimestamp + afterInterval
    }
}


// MARK: - Event Frame

public struct PTCANEventFrame: Codable, Sendable {
    
    public let frame: PTCANFrame
    
    /// 相对于事件时间点的时间。
    ///
    /// 例如：
    /// - -0.523 = 事件前 523ms
    /// -  0.012 = 事件后 12ms
    public let relativeTimestamp: TimeInterval
    
    public init(
        frame: PTCANFrame,
        eventTimestamp: TimeInterval
    ) {
        self.frame = frame
        self.relativeTimestamp =
            frame.timestamp - eventTimestamp
    }
}


// MARK: - CAN ID Event Summary

public struct PTCANEventIDSummary:
    Codable,
    Sendable {
    
    public let header: String
    
    /// 事件窗口内收到多少帧
    public let frameCount: Int
    
    /// 事件前收到多少帧
    public let beforeCount: Int
    
    /// 事件后收到多少帧
    public let afterCount: Int
    
    /// 事件前最常见 Payload
    public let dominantBeforePayload: String?
    
    /// 事件后最常见 Payload
    public let dominantAfterPayload: String?
    
    /// Payload 发生变化的帧数量
    public let changedFrameCount: Int
    
    /// 发生变化的 Byte
    public let changedByteIndexes: [Int]
    
    /// 发生变化的 Bit
    public let changedBits: [Int]
    
    /// 第一次发生变化的时间点。
    ///
    /// 相对于事件时间。
    public let firstChangeRelativeTimestamp: TimeInterval?
    
    /// 最后一次发生变化的时间点。
    public let lastChangeRelativeTimestamp: TimeInterval?
    
    public var score: Int {
        
        var value = 0
        
        if changedFrameCount > 0 {
            value += 10
        }
        
        value += changedByteIndexes.count * 5
        value += changedBits.count * 2
        
        if firstChangeRelativeTimestamp != nil {
            value += 5
        }
        
        return value
    }
}


// MARK: - Event Analysis Result

public struct PTCANEventAnalysis:
    Codable,
    Sendable {
    
    public let captureID: UUID
    public let captureName: String
    
    public let event: PTCANEventWindow
    
    /// 事件窗口内所有 Frame
    public let frames: [PTCANEventFrame]
    
    /// 按 CAN ID 汇总
    public let summaries: [PTCANEventIDSummary]
    
    public var interestingIDs: [PTCANEventIDSummary] {
        summaries
            .filter {
                $0.changedFrameCount > 0
            }
            .sorted {
                $0.score > $1.score
            }
    }
    
    public var interestingHeaders: [String] {
        interestingIDs.map(\.header)
    }
}


// MARK: - Event Analyzer

public enum PTCANEventAnalyzer {
    
    /// 分析一个事件时间点附近的 CAN 数据。
    ///
    /// 这个方法只读取已有 Capture。
    /// 不发送任何 CAN 数据。
    public static func analyze(
        session: PTCANCaptureSession,
        eventTimestamp: TimeInterval,
        before: TimeInterval = 2.0,
        after: TimeInterval = 2.0
    ) -> PTCANEventAnalysis {
        
        let event = PTCANEventWindow(
            eventTimestamp: eventTimestamp,
            beforeInterval: before,
            afterInterval: after
        )
        
        let selectedFrames =
            session.frames.filter {
                $0.timestamp >= event.startTimestamp &&
                $0.timestamp <= event.endTimestamp
            }
        
        let eventFrames =
            selectedFrames.map {
                PTCANEventFrame(
                    frame: $0,
                    eventTimestamp: eventTimestamp
                )
            }
        
        let grouped =
            Dictionary(
                grouping: selectedFrames.compactMap {
                    frame -> PTCANFrame? in
                    
                    guard frame.header != nil,
                          frame.dataHex != nil
                    else {
                        return nil
                    }
                    
                    return frame
                },
                by: {
                    $0.header!
                }
            )
        
        let summaries =
            grouped.keys
                .sorted()
                .compactMap { header -> PTCANEventIDSummary? in
                    
                    guard
                        let frames = grouped[header],
                        !frames.isEmpty
                    else {
                        return nil
                    }
                    
                    return analyzeID(
                        header: header,
                        frames: frames,
                        eventTimestamp: eventTimestamp
                    )
                }
                .sorted {
                    $0.score > $1.score
                }
        
        return PTCANEventAnalysis(
            captureID: session.id,
            captureName: session.name,
            event: event,
            frames: eventFrames,
            summaries: summaries
        )
    }
}


// MARK: - ID Analysis

private extension PTCANEventAnalyzer {
    
    static func analyzeID(
        header: String,
        frames: [PTCANFrame],
        eventTimestamp: TimeInterval
    ) -> PTCANEventIDSummary {
        
        let sortedFrames =
            frames.sorted {
                $0.timestamp < $1.timestamp
            }
        
        let beforeFrames =
            sortedFrames.filter {
                $0.timestamp < eventTimestamp
            }
        
        let afterFrames =
            sortedFrames.filter {
                $0.timestamp >= eventTimestamp
            }
        
        let beforePayload =
            dominantPayload(
                beforeFrames
            )
        
        let afterPayload =
            dominantPayload(
                afterFrames
            )
        
        let changedPairs =
            findChangedPairs(
                frames: sortedFrames
            )
        
        let changedBytes =
            Set(
                changedPairs.flatMap {
                    byteDiff(
                        before: $0.before,
                        after: $0.after
                    )
                    .filter(\.changed)
                    .map(\.index)
                }
            )
            .sorted()
        
        let changedBits =
            Set(
                changedPairs.flatMap {
                    byteDiff(
                        before: $0.before,
                        after: $0.after
                    )
                    .flatMap(\.changedBits)
                }
            )
            .sorted()
        
        let firstChange =
            changedPairs.first.map {
                $0.timestamp -
                eventTimestamp
            }
        
        let lastChange =
            changedPairs.last.map {
                $0.timestamp -
                eventTimestamp
            }
        
        return PTCANEventIDSummary(
            header: header,
            frameCount: sortedFrames.count,
            beforeCount: beforeFrames.count,
            afterCount: afterFrames.count,
            dominantBeforePayload: beforePayload,
            dominantAfterPayload: afterPayload,
            changedFrameCount:
                changedPairs.count,
            changedByteIndexes:
                changedBytes,
            changedBits:
                changedBits,
            firstChangeRelativeTimestamp:
                firstChange,
            lastChangeRelativeTimestamp:
                lastChange
        )
    }
}


// MARK: - Payload Helpers

private extension PTCANEventAnalyzer {
    
    static func dominantPayload(
        _ frames: [PTCANFrame]
    ) -> String? {
        
        let payloads =
            frames.compactMap(\.dataHex)
        
        guard !payloads.isEmpty else {
            return nil
        }
        
        let groups =
            Dictionary(
                grouping: payloads,
                by: {
                    $0
                }
            )
        
        return groups.max {
            $0.value.count <
            $1.value.count
        }?.key
    }
}


// MARK: - Change Detection

private extension PTCANEventAnalyzer {
    
    struct ChangedPair {
        let timestamp: TimeInterval
        let before: String?
        let after: String?
    }
    
    /// 找到相邻 CAN Frame Payload 的变化。
    static func findChangedPairs(
        frames: [PTCANFrame]
    ) -> [ChangedPair] {
        
        guard frames.count >= 2 else {
            return []
        }
        
        var result: [ChangedPair] = []
        
        for index in 1..<frames.count {
            
            let previous =
                frames[index - 1]
            
            let current =
                frames[index]
            
            let before =
                previous.dataHex
            
            let after =
                current.dataHex
            
            guard before != after else {
                continue
            }
            
            result.append(
                ChangedPair(
                    timestamp:
                        current.timestamp,
                    before: before,
                    after: after
                )
            )
        }
        
        return result
    }
    
    static func byteDiff(
        before: String?,
        after: String?
    ) -> [PTCANByteChange] {
        
        let beforeBytes =
            before.flatMap {
                hexToBytes($0)
            } ?? []
        
        let afterBytes =
            after.flatMap {
                hexToBytes($0)
            } ?? []
        
        let count =
            max(
                beforeBytes.count,
                afterBytes.count
            )
        
        guard count > 0 else {
            return []
        }
        
        return (0..<count).map {
            index in
            
            PTCANByteChange(
                index: index,
                before:
                    index < beforeBytes.count
                    ? beforeBytes[index]
                    : nil,
                after:
                    index < afterBytes.count
                    ? afterBytes[index]
                    : nil
            )
        }
    }
    
    static func hexToBytes(
        _ hex: String
    ) -> [UInt8] {
        
        let clean =
            hex
                .replacingOccurrences(
                    of: " ",
                    with: ""
                )
                .uppercased()
        
        guard clean.count % 2 == 0 else {
            return []
        }
        
        var result: [UInt8] = []
        
        result.reserveCapacity(
            clean.count / 2
        )
        
        var index =
            clean.startIndex
        
        while index < clean.endIndex {
            
            let next =
                clean.index(
                    index,
                    offsetBy: 2
                )
            
            let string =
                String(
                    clean[index..<next]
                )
            
            if let byte =
                UInt8(
                    string,
                    radix: 16
                ) {
                
                result.append(byte)
            }
            
            index = next
        }
        
        return result
    }
}

// MARK: - Capture Event Marker

public struct PTCANCaptureEvent:
    Codable,
    Sendable {
    
    public let id: UUID
    
    public let name: String
    
    /// Unix timestamp
    public let timestamp: TimeInterval
    
    public init(
        id: UUID = UUID(),
        name: String,
        timestamp: TimeInterval =
            Date().timeIntervalSince1970
    ) {
        self.id = id
        self.name = name
        self.timestamp = timestamp
    }
}

// MARK: - Event Marker

public extension PTCANRecorder {
    
    @discardableResult
    func markEvent(
        _ name: String
    ) -> PTCANCaptureEvent? {

        lock.lock()

        guard startedAt != nil else {
            lock.unlock()
            return nil
        }

        let event = PTCANCaptureEvent(
            name: name
        )
        events.append(event)

        let metadataSession = PTCANCaptureSession(
            id: sessionID ?? UUID(),
            name: sessionName,
            startedAt: startedAt ?? Date(),
            endedAt: nil,
            filterHeader: filterHeader,
            frames: [],
            events: events
        )
        lock.unlock()

        try? PTCANCaptureStore.shared.updateMetadata(metadataSession)
        return event
    }
}
