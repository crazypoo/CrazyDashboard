//
//  PTProtocolDiscoveryRecorder.swift
//  CrazyDashboard
//
//  English: Passive protocol evidence for real vehicle sessions; it never sends commands.
//  Español: Evidencia pasiva del protocolo para sesiones reales; nunca envía comandos.
//  中文：记录真实车辆会话的被动协议证据，绝不发送指令。
//

import Foundation

// English: Keep the two passive channels separate so BLE frames and OBD transactions cannot be confused.
// Español: Mantén separados los dos canales pasivos para no confundir tramas BLE con transacciones OBD.
// 中文：分开保存两个被动通道，避免把 BLE 帧和 OBD 事务混淆。
nonisolated public enum PTProtocolDiscoveryChannel: String, Codable, Sendable {
    case dashboardBLE
    case obd
}

nonisolated public enum PTProtocolDiscoverySource: String, Codable, Sendable {
    case real
    case mock
    case replay
    case unknown
}

nonisolated public enum PTProtocolDiscoveryDirection: String, Codable, Sendable {
    case tx
    case rx
    case system
}

nonisolated public enum PTProtocolDiscoveryClassification: String, Codable, Sendable {
    case known
    case knownWithUnmappedData
    case knownCommand
    case knownResponse
    case positiveResponse
    case unknownFrameID
    case unknownCommand
    case unexpectedLength
    case malformed
    case unparsedResponse
    case negativeResponse
    case noData
    case timeout
    case transportError
}

nonisolated public struct PTProtocolDiscoveryEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let timestamp: Date
    public let monotonicNanoseconds: UInt64
    public let channel: PTProtocolDiscoveryChannel
    public let source: PTProtocolDiscoverySource
    public let direction: PTProtocolDiscoveryDirection
    public let classification: PTProtocolDiscoveryClassification
    public let value: String
    public let fingerprint: String?
    public let relatedCommand: String?
    public let note: String?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        timestamp: Date,
        monotonicNanoseconds: UInt64,
        channel: PTProtocolDiscoveryChannel,
        source: PTProtocolDiscoverySource,
        direction: PTProtocolDiscoveryDirection,
        classification: PTProtocolDiscoveryClassification,
        value: String,
        fingerprint: String? = nil,
        relatedCommand: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.monotonicNanoseconds = monotonicNanoseconds
        self.channel = channel
        self.source = source
        self.direction = direction
        self.classification = classification
        self.value = String(value.prefix(4_096))
        self.fingerprint = fingerprint
        self.relatedCommand = relatedCommand
        self.note = note
    }
}

nonisolated public struct PTProtocolDiscoverySessionSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let channel: PTProtocolDiscoveryChannel
    public let source: PTProtocolDiscoverySource
    public let transport: String
    public let vehicleID: UUID?
    public let startedAt: Date
    public let endedAt: Date?
    public let eventCount: Int
    public let candidateCount: Int
    public let anomalyCount: Int
    public let droppedEventCount: Int
    public let fileName: String

    public init(
        id: UUID = UUID(),
        channel: PTProtocolDiscoveryChannel,
        source: PTProtocolDiscoverySource,
        transport: String,
        vehicleID: UUID? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        eventCount: Int = 0,
        candidateCount: Int = 0,
        anomalyCount: Int = 0,
        droppedEventCount: Int = 0,
        fileName: String
    ) {
        self.id = id
        self.channel = channel
        self.source = source
        self.transport = transport
        self.vehicleID = vehicleID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.eventCount = eventCount
        self.candidateCount = candidateCount
        self.anomalyCount = anomalyCount
        self.droppedEventCount = droppedEventCount
        self.fileName = fileName
    }
}

nonisolated private enum PTProtocolDiscoveryParsedLog: Sendable {
    case dashboard(direction: PTProtocolDiscoveryDirection, hex: String)
    case obdCommand(String)
    case obdResponse(String)
    case obdBusFrame(String)
    case timeout(String)
    case transportError(String)
}

nonisolated private struct PTProtocolDiscoveryLine: Encodable {
    let type: String
    let session: PTProtocolDiscoverySessionSummary?
    let event: PTProtocolDiscoveryEvent?
    let reason: String?
}

nonisolated private struct PTProtocolDiscoveryMetadata: Codable {
    let schemaVersion: Int
    let summary: PTProtocolDiscoverySessionSummary
    let reason: String?
}

public nonisolated enum PTProtocolExperimentSetting: String, Codable, CaseIterable, Sendable {
    case color
    case unit
    case language
}

public nonisolated enum PTProtocolExperimentPhase: String, Codable, Sendable {
    case baseline
    case firstA
    case b
    case secondA
}

public nonisolated enum PTProtocolExperimentCandidateStatus: String, Codable, Sendable {
    case insufficient
    case candidate
}

// EN: A marker contains only a setting value and timing metadata; it never stores VIN or vehicle identity.
// ES: Una marca solo contiene el valor y el tiempo de la opción; nunca guarda VIN ni identidad del vehículo.
// 中文：标记只保存设置值和时间信息，绝不保存 VIN 或车辆身份。
public nonisolated struct PTProtocolExperimentMarker: Codable, Equatable, Sendable {
    public let phase: PTProtocolExperimentPhase
    public let capturedAt: Date
    public let value: Int?
    public let data3Confirmed: Bool
    public let captureFileName: String?

    public init(
        phase: PTProtocolExperimentPhase,
        capturedAt: Date = Date(),
        value: Int?,
        data3Confirmed: Bool,
        captureFileName: String? = nil
    ) {
        self.phase = phase
        self.capturedAt = capturedAt
        self.value = value
        self.data3Confirmed = data3Confirmed
        self.captureFileName = captureFileName
    }
}

// EN: Each marker keeps a small CAN window summary so evidence can be reviewed without exporting raw vehicle identity.
// ES: Cada marca conserva un pequeño resumen de ventana CAN para revisar la evidencia sin exportar la identidad del vehículo.
// 中文：每个标记保存一个小型 CAN 窗口摘要，便于复核证据且不导出车辆身份。
public nonisolated struct PTProtocolExperimentWindowEvidence: Codable, Equatable, Sendable {
    public let phase: PTProtocolExperimentPhase
    public let capturedAt: Date
    public let frameCount: Int
    public let changedHeaderCount: Int
    public let candidateHeaders: [String]

    public init(
        phase: PTProtocolExperimentPhase,
        capturedAt: Date,
        frameCount: Int,
        changedHeaderCount: Int,
        candidateHeaders: [String]
    ) {
        self.phase = phase
        self.capturedAt = capturedAt
        self.frameCount = max(0, frameCount)
        self.changedHeaderCount = max(0, changedHeaderCount)
        self.candidateHeaders = Array(candidateHeaders.prefix(10))
    }
}

public nonisolated struct PTProtocolExperimentReport: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let setting: PTProtocolExperimentSetting
    public let startedAt: Date
    public let endedAt: Date
    public let markers: [PTProtocolExperimentMarker]
    public let operationHitCount: Int
    public let reverseChangeConsistent: Bool
    public let stableBaseline: Bool
    public let data3ConfirmationCount: Int
    public let candidateScore: Int
    public let candidateStatus: PTProtocolExperimentCandidateStatus
    public let windowEvidence: [PTProtocolExperimentWindowEvidence]?
    public let targetLanguageRawValue: Int?

    public init(
        id: UUID = UUID(),
        setting: PTProtocolExperimentSetting,
        startedAt: Date,
        endedAt: Date = Date(),
        markers: [PTProtocolExperimentMarker],
        windowEvidence: [PTProtocolExperimentWindowEvidence]? = nil,
        targetLanguageRawValue: Int? = nil
    ) {
        self.id = id
        self.setting = setting
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.markers = markers

        let operations = markers.filter {
            $0.phase != .baseline && $0.value != nil
        }
        self.operationHitCount = min(3, operations.count)

        let firstA = markers.first(where: { $0.phase == .firstA })?.value
        let b = markers.first(where: { $0.phase == .b })?.value
        let secondA = markers.first(where: { $0.phase == .secondA })?.value
        self.reverseChangeConsistent = firstA != nil && b != nil && secondA != nil
            && firstA == secondA && firstA != b
        self.stableBaseline = markers.first(where: { $0.phase == .baseline })?.value != nil
        self.data3ConfirmationCount = markers.filter(\.data3Confirmed).count
        self.windowEvidence = windowEvidence

        var score = 0
        if operationHitCount == 3 { score += 40 }
        if reverseChangeConsistent { score += 25 }
        if stableBaseline { score += 20 }
        if data3ConfirmationCount > 0 { score += 15 }
        self.candidateScore = score
        self.candidateStatus = score >= 80 ? .candidate : .insufficient
        self.targetLanguageRawValue = targetLanguageRawValue
    }
}

// EN: Experiment reports stay bounded and are safe to share because they contain no personal vehicle identifiers.
// ES: Los informes de experimentos tienen un límite y se pueden compartir porque no contienen identificadores personales.
// 中文：实验报告数量有上限，并且不含车辆个人标识，因此可以安全分享。
@MainActor
public final class PTProtocolExperimentStore {
    public static let shared = PTProtocolExperimentStore()
    public static let storageKey = "PTProtocolExperimentReports.v1"
    public static let maximumReportCount = 30

    private let defaults: UserDefaults
    public private(set) var reports: [PTProtocolExperimentReport]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([PTProtocolExperimentReport].self, from: $0) }
            ?? []
        reports = Array(decoded.sorted { $0.endedAt > $1.endedAt }.prefix(Self.maximumReportCount))
    }

    public func save(_ report: PTProtocolExperimentReport) {
        reports.removeAll { $0.id == report.id }
        reports.insert(report, at: 0)
        reports = Array(reports.prefix(Self.maximumReportCount))
        persist()
    }

    public func clear() {
        reports.removeAll(keepingCapacity: true)
        persist()
    }

    public func exportURL() throws -> URL? {
        guard !reports.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xp400-protocol-experiments-\(Int(Date().timeIntervalSince1970)).json"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(reports).write(to: url, options: .atomic)
        return url
    }

    public func exportCSVURL() throws -> URL? {
        guard !reports.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xp400-protocol-experiments-\(Int(Date().timeIntervalSince1970)).csv"
        )
        let formatter = ISO8601DateFormatter()
        var rows = ["id,setting,targetLanguageRawValue,startedAt,endedAt,operationHitCount,reverseChangeConsistent,stableBaseline,data3ConfirmationCount,candidateScore,candidateStatus,windowEvidenceCount,candidateHeaders"]
        rows.append(contentsOf: reports.map { report in
            var candidateHeaders: [String] = []
            for evidence in report.windowEvidence ?? [] {
                for header in evidence.candidateHeaders where !candidateHeaders.contains(header) {
                    candidateHeaders.append(header)
                }
            }
            return [
                report.id.uuidString,
                report.setting.rawValue,
                report.targetLanguageRawValue.map(String.init) ?? "",
                formatter.string(from: report.startedAt),
                formatter.string(from: report.endedAt),
                String(report.operationHitCount),
                String(report.reverseChangeConsistent),
                String(report.stableBaseline),
                String(report.data3ConfirmationCount),
                String(report.candidateScore),
                report.candidateStatus.rawValue,
                String(report.windowEvidence?.count ?? 0),
                candidateHeaders.joined(separator: ";")
            ].map(Self.csvField).joined(separator: ",")
        })
        try Data(rows.joined(separator: "\n").utf8).write(to: url, options: .atomic)
        return url
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(reports) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

public nonisolated struct PTProtocolEvidenceCorrelation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let vehicleID: UUID
    public let sessionIDs: [UUID]
    public let channels: [PTProtocolDiscoveryChannel]
    public let startedAt: Date
    public let endedAt: Date

    public init(
        id: UUID = UUID(),
        vehicleID: UUID,
        sessionIDs: [UUID],
        channels: [PTProtocolDiscoveryChannel],
        startedAt: Date,
        endedAt: Date
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.sessionIDs = sessionIDs
        self.channels = channels
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

// English: The actor owns only evidence state and file I/O; all vehicle transport remains in existing managers.
// Español: El actor solo posee el estado de evidencia y el I/O; el transporte sigue en los gestores existentes.
// 中文：Actor 只负责证据状态和文件 I/O，车辆传输继续由现有管理器负责。
public actor PTProtocolDiscoveryRecorder {
    public static let shared = PTProtocolDiscoveryRecorder()
    public static let didChange = Notification.Name("PTProtocolDiscoveryRecorder.didChange")
    public static let currentSchemaVersion = 1
    public static let maximumSessions = 50
    public static let maximumEventsPerSession = 50_000

    private struct ActiveSession {
        var summary: PTProtocolDiscoverySessionSummary
        let fileURL: URL
        var fileHandle: FileHandle?
        var fingerprintCounts: [String: Int] = [:]
        var lastOBDCommand: String?
        var writtenEventCount = 0
        var candidateCount = 0
        var anomalyCount = 0
        var droppedEventCount = 0
    }

    private var dashboardSession: ActiveSession?
    private var obdSession: ActiveSession?
    private var summaries: [PTProtocolDiscoverySessionSummary]
    private var observersInstalled = false
    public private(set) var lastError: String?

    private init() {
        summaries = Self.loadSummaryIndex()
    }

    // English: Install one observer per existing logger and preserve every transport call unchanged.
    // Español: Instala un observador por cada registrador existente y conserva intacta cada llamada de transporte.
    // 中文：分别监听现有两个日志实例，保持所有传输调用原样不变。
    public func installObservers() async {
        guard !observersInstalled else { return }
        observersInstalled = true

        // EN: Logger registration is main-actor work in this app; ingestion immediately hops back to this actor.
        // ES: El registro del logger pertenece al actor principal; la ingestión vuelve inmediatamente a este actor.
        // 中文：本项目的日志注册属于主线程工作，采集回调会立即切回当前 Actor。
        await MainActor.run {
            PTOBDLogger.moto.addObserver { entry in
                Task {
                    await PTProtocolDiscoveryRecorder.shared.ingest(
                        entry,
                        channel: .dashboardBLE
                    )
                }
            }
            PTOBDLogger.obd.addObserver { entry in
                Task {
                    await PTProtocolDiscoveryRecorder.shared.ingest(
                        entry,
                        channel: .obd
                    )
                }
            }
        }
    }

    @discardableResult
    public func startDashboardSession(
        transport: String,
        source: PTProtocolDiscoverySource,
        vehicleID: UUID? = nil
    ) async -> Bool {
        await installObservers()
        guard dashboardSession == nil else { return false }
        guard let session = makeSession(
            channel: .dashboardBLE,
            transport: transport,
            source: source,
            vehicleID: vehicleID
        ) else { return false }
        dashboardSession = session
        return true
    }

    public func finishDashboardSession(reason: String) {
        guard let session = dashboardSession else { return }
        dashboardSession = nil
        finalize(session, reason: reason)
    }

    @discardableResult
    public func startOBDSession(
        transport: String,
        source: PTProtocolDiscoverySource,
        vehicleID: UUID? = nil
    ) async -> Bool {
        await installObservers()
        guard obdSession == nil else { return false }
        guard let session = makeSession(
            channel: .obd,
            transport: transport,
            source: source,
            vehicleID: vehicleID
        ) else { return false }
        obdSession = session
        return true
    }

    public func finishOBDSession(reason: String) {
        guard let session = obdSession else { return }
        obdSession = nil
        finalize(session, reason: reason)
    }

    public func sessionSummaries(limit: Int = 20) -> [PTProtocolDiscoverySessionSummary] {
        Array(summaries.prefix(max(0, limit)))
    }

    // EN: Correlate only completed BLE/OBD sessions for the same garage vehicle and nearby time window.
    // ES: Correlaciona solo sesiones BLE/OBD terminadas del mismo vehículo y con una ventana temporal cercana.
    // 中文：只关联同一车库车辆且时间接近的已完成 BLE/OBD 会话。
    public func correlatedSessions(limit: Int = 20) -> [PTProtocolEvidenceCorrelation] {
        var correlations: [PTProtocolEvidenceCorrelation] = []
        let completed = summaries
            .filter { $0.endedAt != nil && $0.vehicleID != nil }
            .sorted { $0.startedAt < $1.startedAt }

        for summary in completed {
            guard let vehicleID = summary.vehicleID,
                  let endedAt = summary.endedAt else { continue }
            if let index = correlations.firstIndex(where: { correlation in
                guard correlation.vehicleID == vehicleID else { return false }
                return summary.startedAt <= correlation.endedAt.addingTimeInterval(10)
                    && endedAt >= correlation.startedAt.addingTimeInterval(-10)
            }) {
                let current = correlations[index]
                var sessionIDs = current.sessionIDs
                if !sessionIDs.contains(summary.id) {
                    sessionIDs.append(summary.id)
                }
                var channels = current.channels
                if !channels.contains(summary.channel) {
                    channels.append(summary.channel)
                }
                correlations[index] = PTProtocolEvidenceCorrelation(
                    id: current.id,
                    vehicleID: vehicleID,
                    sessionIDs: sessionIDs,
                    channels: channels,
                    startedAt: min(current.startedAt, summary.startedAt),
                    endedAt: max(current.endedAt, endedAt)
                )
            } else {
                correlations.append(
                    PTProtocolEvidenceCorrelation(
                        vehicleID: vehicleID,
                        sessionIDs: [summary.id],
                        channels: [summary.channel],
                        startedAt: summary.startedAt,
                        endedAt: endedAt
                    )
                )
            }
        }

        return Array(correlations.reversed().prefix(max(0, limit)))
    }

    public func latestFileURL() -> URL? {
        guard let summary = summaries.first else { return nil }
        return storageDirectory().appendingPathComponent(summary.fileName)
    }

    // English: Export completed passive sessions as one bounded JSONL file for developer analysis.
    // Español: Exporta las sesiones pasivas terminadas como un archivo JSONL acotado para el análisis del desarrollador.
    // 中文：将已完成的被动会话合并为一个有界 JSONL 文件，供开发者分析。
    public func exportURL() throws -> URL? {
        guard !summaries.isEmpty else { return nil }

        var data = Data()
        for summary in summaries.reversed() {
            let sourceURL = storageDirectory().appendingPathComponent(summary.fileName)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            data.append(try Data(contentsOf: sourceURL))
        }
        guard !data.isEmpty else { return nil }

        let fileName = "xp400-protocol-discovery-\(Int(Date().timeIntervalSince1970)).jsonl"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    public func clearCompletedSessions() {
        guard dashboardSession == nil, obdSession == nil else { return }
        for summary in summaries {
            let directory = storageDirectory()
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(summary.fileName))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(metadataFileName(for: summary)))
        }
        summaries.removeAll(keepingCapacity: true)
        persistSummaryIndex()
        notifyChange()
    }

    // English: Logger callbacks are parsed off the UI path and ignored unless the matching real session is active.
    // Español: Los callbacks se procesan fuera de la UI y se ignoran si la sesión correspondiente no está activa.
    // 中文：日志回调在 UI 路径之外解析，只有对应会话活动时才会记录。
    public func ingest(_ entry: PTOBDLogEntry, channel: PTProtocolDiscoveryChannel) async {
        guard let parsed = Self.parse(entry.message, channel: channel) else { return }

        switch channel {
        case .dashboardBLE:
            guard var session = dashboardSession else { return }
            handleDashboard(parsed, entry: entry, session: &session)
            dashboardSession = session
        case .obd:
            guard var session = obdSession else { return }
            await handleOBD(parsed, entry: entry, session: &session)
            obdSession = session
        }
    }
}

private extension PTProtocolDiscoveryRecorder {
    static func loadSummaryIndex() -> [PTProtocolDiscoverySessionSummary] {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PTProtocolDiscovery", isDirectory: true)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("index.json")) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([PTProtocolDiscoverySessionSummary].self, from: data) else {
            return []
        }
        return Array(decoded.prefix(maximumSessions))
    }

    func storageDirectory() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PTProtocolDiscovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeSession(
        channel: PTProtocolDiscoveryChannel,
        transport: String,
        source: PTProtocolDiscoverySource,
        vehicleID: UUID?
    ) -> ActiveSession? {
        let id = UUID()
        let fileName = "\(channel.rawValue)-\(Int(Date().timeIntervalSince1970))-\(id.uuidString.prefix(8)).jsonl"
        let url = storageDirectory().appendingPathComponent(fileName)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            lastError = "Unable to create passive evidence file."
            return nil
        }

        let summary = PTProtocolDiscoverySessionSummary(
            id: id,
            channel: channel,
            source: source,
            transport: transport,
            vehicleID: vehicleID,
            fileName: fileName
        )

        do {
            let handle = try FileHandle(forWritingTo: url)
            var session = ActiveSession(summary: summary, fileURL: url, fileHandle: handle)
            guard write(
                PTProtocolDiscoveryLine(
                    type: "session",
                    session: summary,
                    event: nil,
                    reason: nil
                ),
                to: &session
            ) else {
                try? handle.close()
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return session
        } catch {
            lastError = error.localizedDescription
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    private func finalize(_ session: ActiveSession, reason: String) {
        let finished = PTProtocolDiscoverySessionSummary(
            id: session.summary.id,
            channel: session.summary.channel,
            source: session.summary.source,
            transport: session.summary.transport,
            vehicleID: session.summary.vehicleID,
            startedAt: session.summary.startedAt,
            endedAt: Date(),
            eventCount: session.writtenEventCount,
            candidateCount: session.candidateCount,
            anomalyCount: session.anomalyCount,
            droppedEventCount: session.droppedEventCount,
            fileName: session.summary.fileName
        )

        var closedSession = session
        _ = write(
            PTProtocolDiscoveryLine(
                type: "end",
                session: finished,
                event: nil,
                reason: reason
            ),
            to: &closedSession
        )
        try? closedSession.fileHandle?.synchronize()
        try? closedSession.fileHandle?.close()

        let metadata = PTProtocolDiscoveryMetadata(
            schemaVersion: Self.currentSchemaVersion,
            summary: finished,
            reason: reason
        )
        let metadataURL = storageDirectory().appendingPathComponent(metadataFileName(for: finished))
        if let data = try? encoded(metadata) {
            try? data.write(to: metadataURL, options: .atomic)
        }

        summaries.insert(finished, at: 0)
        let evicted = Array(summaries.dropFirst(Self.maximumSessions))
        summaries = Array(summaries.prefix(Self.maximumSessions))
        for oldSummary in evicted {
            let directory = storageDirectory()
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(oldSummary.fileName))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(metadataFileName(for: oldSummary)))
        }
        persistSummaryIndex()
        notifyChange()
    }

    private func handleDashboard(
        _ parsed: PTProtocolDiscoveryParsedLog,
        entry: PTOBDLogEntry,
        session: inout ActiveSession
    ) {
        guard case let .dashboard(direction, hex) = parsed,
              let data = Self.hexData(hex) else {
            return
        }

        let result = Self.classifyDashboard(data, direction: direction)
        guard result.classification != .known else { return }

        let key = result.fingerprint
        let occurrence = (session.fingerprintCounts[key, default: 0] + 1)
        session.fingerprintCounts[key] = occurrence

        // ponytail: keep the first sample and logarithmic repeats; a full packet stream remains in the legacy text log.
        guard occurrence == 1 || occurrence == 10 || occurrence == 100 || occurrence == 1_000 else {
            return
        }

        let event = PTProtocolDiscoveryEvent(
            sessionID: session.summary.id,
            timestamp: entry.timestamp,
            monotonicNanoseconds: entry.monotonicNanoseconds,
            channel: .dashboardBLE,
            source: session.summary.source,
            direction: direction,
            classification: result.classification,
            value: Self.hexString(data),
            fingerprint: key,
            note: "occurrence=\(occurrence); \(result.note)"
        )
        writeEvent(event, to: &session)
    }

    private func handleOBD(
        _ parsed: PTProtocolDiscoveryParsedLog,
        entry: PTOBDLogEntry,
        session: inout ActiveSession
    ) async {
        let event: PTProtocolDiscoveryEvent?
        switch parsed {
        case .obdCommand(let command):
            session.lastOBDCommand = command
            let known = await Self.isKnownOBDCommand(command)
            event = PTProtocolDiscoveryEvent(
                sessionID: session.summary.id,
                timestamp: entry.timestamp,
                monotonicNanoseconds: entry.monotonicNanoseconds,
                channel: .obd,
                source: session.summary.source,
                direction: .tx,
                classification: known ? .knownCommand : .unknownCommand,
                value: command,
                fingerprint: "obd:tx:\(command)",
                note: known ? nil : "command is outside the current OBD catalog"
            )
        case .obdResponse(let response):
            let classification = Self.classifyOBDResponse(response, command: session.lastOBDCommand)
            event = PTProtocolDiscoveryEvent(
                sessionID: session.summary.id,
                timestamp: entry.timestamp,
                monotonicNanoseconds: entry.monotonicNanoseconds,
                channel: .obd,
                source: session.summary.source,
                direction: .rx,
                classification: classification,
                value: Self.redactedOBDValue(response),
                fingerprint: "obd:rx:\(session.lastOBDCommand ?? "?"):\(classification.rawValue)",
                relatedCommand: session.lastOBDCommand
            )
        case .obdBusFrame(let frame):
            let fingerprint = "obd:bus:\(frame.uppercased())"
            let occurrence = session.fingerprintCounts[fingerprint, default: 0] + 1
            session.fingerprintCounts[fingerprint] = occurrence
            if occurrence == 1 || occurrence == 10 || occurrence == 100 || occurrence == 1_000 {
                event = PTProtocolDiscoveryEvent(
                    sessionID: session.summary.id,
                    timestamp: entry.timestamp,
                    monotonicNanoseconds: entry.monotonicNanoseconds,
                    channel: .obd,
                    source: session.summary.source,
                    direction: .rx,
                    classification: .unparsedResponse,
                    value: Self.redactedOBDValue(frame),
                    fingerprint: fingerprint,
                    note: "occurrence=\(occurrence); passive ATMA bus frame"
                )
            } else {
                event = nil
            }
        case .timeout(let command):
            event = PTProtocolDiscoveryEvent(
                sessionID: session.summary.id,
                timestamp: entry.timestamp,
                monotonicNanoseconds: entry.monotonicNanoseconds,
                channel: .obd,
                source: session.summary.source,
                direction: .system,
                classification: .timeout,
                value: command,
                relatedCommand: command
            )
        case .transportError(let message):
            event = PTProtocolDiscoveryEvent(
                sessionID: session.summary.id,
                timestamp: entry.timestamp,
                monotonicNanoseconds: entry.monotonicNanoseconds,
                channel: .obd,
                source: session.summary.source,
                direction: .system,
                classification: .transportError,
                value: String(message.prefix(512)),
                relatedCommand: session.lastOBDCommand
            )
        case .dashboard:
            event = nil
        }

        if let event {
            writeEvent(event, to: &session)
        }
    }

    private func writeEvent(_ event: PTProtocolDiscoveryEvent, to session: inout ActiveSession) {
        guard session.writtenEventCount < Self.maximumEventsPerSession else {
            session.droppedEventCount += 1
            return
        }
        if event.classification == .knownWithUnmappedData ||
            event.classification == .unknownFrameID ||
            event.classification == .unknownCommand ||
            event.classification == .unparsedResponse {
            session.candidateCount += 1
        }
        if event.classification == .unexpectedLength ||
            event.classification == .malformed ||
            event.classification == .timeout ||
            event.classification == .transportError {
            session.anomalyCount += 1
        }
        guard write(
            PTProtocolDiscoveryLine(type: "event", session: nil, event: event, reason: nil),
            to: &session
        ) else {
            return
        }
        session.writtenEventCount += 1
        notifyChange()
    }

    @discardableResult
    private func write(_ line: PTProtocolDiscoveryLine, to session: inout ActiveSession) -> Bool {
        guard let handle = session.fileHandle,
              let data = try? encoded(line) else {
            return false
        }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func persistSummaryIndex() {
        let url = storageDirectory().appendingPathComponent("index.json")
        if let data = try? encoded(summaries) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func notifyChange() {
        Task { @MainActor in
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    static func metadataFileName(for summary: PTProtocolDiscoverySessionSummary) -> String {
        summary.fileName.replacingOccurrences(of: ".jsonl", with: ".json")
    }

    func metadataFileName(for summary: PTProtocolDiscoverySessionSummary) -> String {
        Self.metadataFileName(for: summary)
    }

    func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func parse(_ message: String, channel: PTProtocolDiscoveryChannel) -> PTProtocolDiscoveryParsedLog? {
        switch channel {
        case .dashboardBLE:
            if let value = value(after: "[原始包] 收到帧数据: ", in: message), !value.isEmpty {
                return .dashboard(direction: .rx, hex: value)
            }
            if let value = value(after: "[发送包] 正在发射指令: ", in: message), !value.isEmpty {
                return .dashboard(direction: .tx, hex: value)
            }
            return nil
        case .obd:
            if let value = value(after: "[TX Async] 响应超时: ", in: message) {
                return .timeout(cleanCommand(value))
            }
            if let value = value(after: "[TX Async] ", in: message), !value.isEmpty {
                return .obdCommand(cleanCommand(value))
            }
            if let value = value(after: "[TX Init", in: message),
               let command = valueAfterClosingBracket(value),
               !command.isEmpty {
                return .obdCommand(cleanCommand(command))
            }
            if message.contains("[RX "), message.contains(" Async] 抛出上层: "),
               let value = value(after: "] 抛出上层: ", in: message) {
                return .obdResponse(value)
            }
            if message.contains("[RX "), message.contains(" Init] 消化: "),
               let value = value(after: "] 消化: ", in: message) {
                return .obdResponse(value)
            }
            if let value = value(after: "[嗅探抓包] 截获报文: ", in: message), !value.isEmpty {
                return .obdBusFrame(value)
            }
            if message.contains("[物理连接断开]") || message.contains("发送失败") {
                return .transportError(message)
            }
            return nil
        }
    }

    static func value(after marker: String, in message: String) -> String? {
        guard let range = message.range(of: marker) else { return nil }
        return String(message[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\r", with: "")
    }

    static func valueAfterClosingBracket(_ value: String) -> String? {
        guard let range = value.range(of: "] ") else { return nil }
        return String(value[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanCommand(_ value: String) -> String {
        value.replacingOccurrences(of: "\\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    static func classifyDashboard(
        _ data: Data,
        direction: PTProtocolDiscoveryDirection
    ) -> (classification: PTProtocolDiscoveryClassification, fingerprint: String, note: String) {
        guard data.count >= 3,
              data.first == PTXP400BLEProtocol.preamble,
              data.last == PTXP400BLEProtocol.terminator else {
            return (.malformed, "ble:malformed:\(hexString(data.prefix(8)))", "invalid envelope")
        }

        if direction == .tx {
            guard PTXP400BLEProtocol.isValidOutboundFrame(data) else {
                return (.malformed, "ble:tx:malformed:\(hexString(data.prefix(8)))", "invalid outbound length")
            }
            let id = data[1]
            let known = id == PTXP400BLEProtocol.navigationFrameID ||
                id == PTXP400BLEProtocol.configurationFrameID || id == 0x08
            guard !known else { return (.known, "ble:tx:\(id)", "known outbound frame") }
            return (.unknownFrameID, "ble:tx:id:\(id):\(hexString(data.dropFirst(2).dropLast()) )", "unknown outbound frame ID")
        }

        let id = data[1]
        switch id {
        case PTXP400BLEProtocol.connectionFrameID:
            guard data.count == PTXP400BLEProtocol.connectionFrameLength,
                  PTXP400BLEProtocol.connectionSerial(in: data) != nil else {
                return (.unexpectedLength, "ble:rx:id1:\(data.count)", "connection frame shape is not confirmed")
            }
            return (.known, "ble:rx:id1", "known connection frame")
        case PTXP400BLEProtocol.data1FrameID...PTXP400BLEProtocol.absFrameID:
            guard data.count == PTXP400BLEProtocol.vehicleStatusFrameLength else {
                return (.unexpectedLength, "ble:rx:id\(id):\(data.count)", "vehicle status length is not confirmed")
            }
            let payload = Array(data.dropFirst(2).dropLast())
            let masks = unmappedMasks(for: id)
            let unknownBytes = zip(payload, masks).map { $0.0 & $0.1 }
            guard unknownBytes.contains(where: { $0 != 0 }) else {
                return (.known, "ble:rx:id\(id)", "known vehicle status frame")
            }
            let unknownHex = unknownBytes.map { String(format: "%02X", $0) }.joined()
            return (
                .knownWithUnmappedData,
                "ble:rx:id\(id):unknown:\(unknownHex)",
                "unmapped bytes or bits are non-zero"
            )
        default:
            return (
                .unknownFrameID,
                "ble:rx:id\(id):\(hexString(data.dropFirst(2).dropLast()))",
                "unknown inbound frame ID"
            )
        }
    }

    static func unmappedMasks(for id: UInt8) -> [UInt8] {
        switch id {
        case PTXP400BLEProtocol.data1FrameID:
            return [0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        case PTXP400BLEProtocol.data2FrameID:
            return [0xFF, 0x00, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0xFF]
        case PTXP400BLEProtocol.data3FrameID:
            return [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF]
        case PTXP400BLEProtocol.controlFrameID:
            return [0xFF, 0xAF, 0xAE, 0xF0, 0x00, 0x00, 0x00, 0x00]
        case PTXP400BLEProtocol.absFrameID:
            return [0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
        default:
            return Array(repeating: 0xFF, count: 8)
        }
    }

    static func isKnownOBDCommand(_ command: String) async -> Bool {
        let adapterCommands: Set<String> = [
            "ATZ", "ATE0", "ATL0", "ATH0", "ATH1", "ATS0", "ATS1", "ATSP0",
            "ATDP", "ATDPN", "ATI", "ATRV", "ATD", "ATAL", "ATCAF0", "ATCSM0", "ATCFC0",
            "ATCFC1", "AT+VERSION", "AT+SETCRYPT", "ATCRA"
        ]
        guard !adapterCommands.contains(command),
              !command.hasPrefix("ATCRA"),
              !command.hasPrefix("ATSH") else {
            return true
        }
        return await MainActor.run {
            OBDCommand.from(command: command) != nil
        }
    }

    static func classifyOBDResponse(
        _ response: String,
        command: String?
    ) -> PTProtocolDiscoveryClassification {
        let upper = response.uppercased()
        if upper.contains("NO DATA") || upper.contains("NODATA") {
            return .noData
        }
        if upper.contains("ERROR") || upper.contains("UNABLE") || upper.contains("?") {
            return .transportError
        }

        let bytes = responseBytes(response)
        if let index = bytes.firstIndex(of: 0x7F), index + 2 < bytes.count {
            return .negativeResponse
        }
        if command?.hasPrefix("AT") == true {
            return .knownResponse
        }
        guard let command, command.count >= 2 else { return .unparsedResponse }
        let expectedService: UInt8?
        switch command.prefix(2) {
        case "01": expectedService = 0x41
        case "02": expectedService = 0x42
        case "03": expectedService = 0x43
        case "04": expectedService = 0x44
        case "06": expectedService = 0x46
        case "07": expectedService = 0x47
        case "08": expectedService = 0x48
        case "09": expectedService = 0x49
        case "22": expectedService = 0x62
        default: expectedService = nil
        }
        guard let expectedService, bytes.contains(expectedService) else {
            return .unparsedResponse
        }
        return .positiveResponse
    }

    static func redactedOBDValue(_ value: String) -> String {
        let clean = value.uppercased().filter { $0.isHexDigit }
        if clean.contains("4902") || clean.contains("62F190") {
            return "<VIN response redacted; bytes=\(clean.count / 2)>"
        }
        return String(value.prefix(4_096))
    }

    static func responseBytes(_ value: String) -> [UInt8] {
        let tokens = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let candidates = tokens.flatMap { token -> [UInt8] in
            let clean = token.uppercased()
            guard clean.count == 2, let byte = UInt8(clean, radix: 16) else { return [] }
            return [byte]
        }
        return candidates
    }

    static func hexData(_ value: String) -> Data? {
        let clean = value.filter { !$0.isWhitespace }
        guard !clean.isEmpty, clean.count.isMultiple(of: 2), clean.allSatisfy(\.isHexDigit) else {
            return nil
        }
        var data = Data(capacity: clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    static func hexString<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
}
