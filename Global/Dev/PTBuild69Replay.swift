//
//  PTBuild69Replay.swift
//  CrazyDashboard
//
//  EN: Replays redacted XP400 raw logs without opening a transport or sending a vehicle command.
//  ES: Reproduce registros RAW XP400 redactados sin abrir un transporte ni enviar comandos al vehículo.
//  中文：只读回放脱敏后的 XP400 原始日志，不打开传输，也不发送车辆指令。
//

import Foundation

// EN: One replay frame keeps its source line and semantic projection together for deterministic inspection.
// ES: Cada trama de replay conserva su línea de origen y su proyección semántica para una inspección determinista.
// 中文：每个回放帧同时保留源日志行和语义投影，便于确定性检查。
public nonisolated struct PTBuild69ReplayFrame: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let lineNumber: Int
    public let timestamp: Date
    public let relativeTime: TimeInterval
    public let rawData: Data
    public let semantic: PTXP400SemanticFrame?
    public let malformedReason: String?

    public init(id: UUID = UUID(), lineNumber: Int, timestamp: Date, relativeTime: TimeInterval, rawData: Data, semantic: PTXP400SemanticFrame?, malformedReason: String? = nil) {
        self.id = id
        self.lineNumber = lineNumber
        self.timestamp = timestamp
        self.relativeTime = max(relativeTime, 0)
        self.rawData = rawData
        self.semantic = semantic
        self.malformedReason = malformedReason
    }
}

public nonisolated struct PTBuild69ReplaySummary: Codable, Equatable, Sendable {
    public let sourceName: String
    public let totalLines: Int
    public let frameCount: Int
    public let semanticFrameCount: Int
    public let malformedLineCount: Int
    public let unknownFrameCount: Int
    public let frameCounts: [String: Int]
    public let data2ClockStart: String?
    public let data2ClockEnd: String?
    public let odometerMinimum: Double?
    public let odometerMaximum: Double?
    public let batteryMinimum: Double?
    public let batteryMaximum: Double?
    public let controlTickDeltaMinimum: Int?
    public let controlTickDeltaMaximum: Int?
    public let controlTickSampleCount: Int

    public init(sourceName: String, totalLines: Int, frameCount: Int, semanticFrameCount: Int, malformedLineCount: Int, unknownFrameCount: Int, frameCounts: [String: Int], data2ClockStart: String?, data2ClockEnd: String?, odometerMinimum: Double?, odometerMaximum: Double?, batteryMinimum: Double?, batteryMaximum: Double?, controlTickDeltaMinimum: Int?, controlTickDeltaMaximum: Int?, controlTickSampleCount: Int) {
        self.sourceName = sourceName
        self.totalLines = max(totalLines, 0)
        self.frameCount = max(frameCount, 0)
        self.semanticFrameCount = max(semanticFrameCount, 0)
        self.malformedLineCount = max(malformedLineCount, 0)
        self.unknownFrameCount = max(unknownFrameCount, 0)
        self.frameCounts = frameCounts
        self.data2ClockStart = data2ClockStart
        self.data2ClockEnd = data2ClockEnd
        self.odometerMinimum = odometerMinimum
        self.odometerMaximum = odometerMaximum
        self.batteryMinimum = batteryMinimum
        self.batteryMaximum = batteryMaximum
        self.controlTickDeltaMinimum = controlTickDeltaMinimum
        self.controlTickDeltaMaximum = controlTickDeltaMaximum
        self.controlTickSampleCount = max(controlTickSampleCount, 0)
    }
}

public nonisolated struct PTBuild69ReplayResult: Codable, Equatable, Sendable {
    public let summary: PTBuild69ReplaySummary
    public let frames: [PTBuild69ReplayFrame]

    public init(summary: PTBuild69ReplaySummary, frames: [PTBuild69ReplayFrame]) {
        self.summary = summary
        self.frames = frames
    }
}

// EN: The analyzer accepts the current log marker and ignores all non-frame application text.
// ES: El analizador acepta el marcador actual del registro e ignora el texto de aplicación que no es trama.
// 中文：分析器识别当前日志标记，并忽略所有非帧应用文本。
public nonisolated enum PTBuild69ReplayAnalyzer {
    public static let maximumInputBytes = 20 * 1_024 * 1_024
    public static let maximumRetainedFrames = 10_000
    private static let frameMarker = "收到帧数据:"

    public static func analyze(text: String, sourceName: String = "inline") -> PTBuild69ReplayResult {
        var retainedFrames: [PTBuild69ReplayFrame] = []
        retainedFrames.reserveCapacity(min(maximumRetainedFrames, 1_024))
        var frameCounts: [String: Int] = [:]
        var malformedLineCount = 0
        var unknownFrameCount = 0
        var semanticFrameCount = 0
        var totalLines = 0
        var firstRelativeTime: TimeInterval?
        var firstClock: PTDashboardClock?
        var lastClock: PTDashboardClock?
        var odometers: [Double] = []
        var batteries: [Double] = []
        var previousTick: UInt8?
        var tickDeltas: [Int] = []

        for (offset, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            totalLines = offset + 1
            let lineString = String(line)
            guard let markerRange = lineString.range(of: frameMarker) else { continue }
            let relativeTime = parseTime(from: lineString) ?? firstRelativeTime ?? 0
            firstRelativeTime = firstRelativeTime ?? relativeTime
            let timestamp = Date(timeIntervalSinceReferenceDate: relativeTime)
            let hex = String(lineString[markerRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix { $0.isHexDigit }
            guard !hex.isEmpty, hex.count.isMultiple(of: 2), let data = Data(hexString: String(hex)) else {
                malformedLineCount += 1
                continue
            }

            let decoded = PTXP400TelemetryDecoder.decode(data)
            let semantic = decoded.flatMap { PTXP400SemanticDecoder.decode(frame: $0) }
            if let decoded {
                let key = String(format: "0x%02X", decoded.id)
                frameCounts[key, default: 0] += 1
                if PTXP400FrameSchema.schema(for: decoded.id) == nil { unknownFrameCount += 1 }
            } else {
                malformedLineCount += 1
            }
            if semantic != nil { semanticFrameCount += 1 }

            if let semantic {
                if let clock = PTXP400SemanticClock.clock(from: semantic) {
                    firstClock = firstClock ?? clock
                    lastClock = clock
                }
                if let odometer = numericValue(in: semantic, key: "data1.odometer") { odometers.append(odometer) }
                if let battery = numericValue(in: semantic, key: "data2.battery") { batteries.append(battery) }
                if let tick = semantic.fields.first(where: { $0.id == "control.rollingTick" })?.raw.first {
                    if let previousTick {
                        tickDeltas.append(PTXP400RollingTick.moduloDelta(from: previousTick, to: tick))
                    }
                    previousTick = tick
                }
            }

            let frame = PTBuild69ReplayFrame(lineNumber: totalLines, timestamp: timestamp, relativeTime: relativeTime, rawData: data, semantic: semantic, malformedReason: decoded == nil ? "invalid XP400 envelope" : nil)
            retainedFrames.append(frame)
            if retainedFrames.count > maximumRetainedFrames {
                retainedFrames.removeFirst(retainedFrames.count - maximumRetainedFrames)
            }
        }

        let summary = PTBuild69ReplaySummary(
            sourceName: String(sourceName.prefix(256)),
            totalLines: totalLines,
            frameCount: frameCounts.values.reduce(0, +),
            semanticFrameCount: semanticFrameCount,
            malformedLineCount: malformedLineCount,
            unknownFrameCount: unknownFrameCount,
            frameCounts: frameCounts,
            data2ClockStart: firstClock?.displayString,
            data2ClockEnd: lastClock?.displayString,
            odometerMinimum: odometers.min(),
            odometerMaximum: odometers.max(),
            batteryMinimum: batteries.min(),
            batteryMaximum: batteries.max(),
            controlTickDeltaMinimum: tickDeltas.min(),
            controlTickDeltaMaximum: tickDeltas.max(),
            controlTickSampleCount: tickDeltas.count
        )
        return PTBuild69ReplayResult(summary: summary, frames: retainedFrames)
    }

    public static func analyze(fileURL: URL) throws -> PTBuild69ReplayResult {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maximumInputBytes else { throw PTBuild69ReplayError.inputTooLarge(size: size, limit: maximumInputBytes) }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard let text = String(data: data, encoding: .utf8) else { throw PTBuild69ReplayError.invalidUTF8 }
        return analyze(text: text, sourceName: fileURL.lastPathComponent)
    }

    // EN: Historical v2 migration is pure and never marks an old unknown value as confirmed.
    // ES: La migración histórica v2 es pura y nunca confirma un valor desconocido antiguo.
    // 中文：历史 v2 迁移是纯函数，不会把旧的未知值标记为已确认。
    public static func migrateV2(data: Data) throws -> PTProtocolEvidenceV3Document {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return PTProtocolEvidenceV3Migration.fromV2(try decoder.decode(PTProtocolEvidenceV2Document.self, from: data))
    }

    private static func parseTime(from line: String) -> TimeInterval? {
        guard let open = line.firstIndex(of: "["), let close = line.firstIndex(of: "]"), open < close else { return nil }
        let value = line[line.index(after: open)..<close]
        let components = value.split(separator: ":")
        guard components.count == 3,
              let hour = Double(components[0]),
              let minute = Double(components[1]),
              let second = Double(components[2]),
              hour >= 0, minute >= 0, second >= 0 else { return nil }
        return hour * 3_600 + minute * 60 + second
    }

    private static func numericValue(in frame: PTXP400SemanticFrame, key: String) -> Double? {
        frame.fields.first(where: { $0.id == key })?.normalizedValue.flatMap(Double.init)
    }
}

// EN: Historical replay reclassifies old discovery lines without rewriting the source files or promoting hypotheses.
// ES: El replay histórico reclasifica líneas antiguas sin reescribir los archivos ni confirmar hipótesis.
// 中文：历史回放只重新分类旧 Discovery 行，不改写源文件，也不会把假设升级为事实。
public nonisolated struct PTBuild69HistoricalReplaySummary: Codable, Equatable, Sendable {
    public let sourceName: String
    public let lineCount: Int
    public let eventCount: Int
    public let oldCandidateCount: Int
    public let oldAnomalyCount: Int
    public let normalizedKnownCount: Int
    public let normalizedCandidateEventCount: Int
    public let normalizedCandidateFieldCount: Int
    public let normalizedAnomalyCount: Int
    public let ignoredPeriodicCount: Int
    public let candidateEventRatio: Double

    public init(sourceName: String, lineCount: Int, eventCount: Int, oldCandidateCount: Int, oldAnomalyCount: Int, normalizedKnownCount: Int, normalizedCandidateEventCount: Int, normalizedCandidateFieldCount: Int, normalizedAnomalyCount: Int, ignoredPeriodicCount: Int) {
        self.sourceName = String(sourceName.prefix(256))
        self.lineCount = max(lineCount, 0)
        self.eventCount = max(eventCount, 0)
        self.oldCandidateCount = max(oldCandidateCount, 0)
        self.oldAnomalyCount = max(oldAnomalyCount, 0)
        self.normalizedKnownCount = max(normalizedKnownCount, 0)
        self.normalizedCandidateEventCount = max(normalizedCandidateEventCount, 0)
        self.normalizedCandidateFieldCount = max(normalizedCandidateFieldCount, 0)
        self.normalizedAnomalyCount = max(normalizedAnomalyCount, 0)
        self.ignoredPeriodicCount = max(ignoredPeriodicCount, 0)
        self.candidateEventRatio = eventCount > 0 ? Double(max(normalizedCandidateEventCount, 0)) / Double(eventCount) : 0
    }
}

public nonisolated struct PTBuild69HistoricalReplayResult: Codable, Equatable, Sendable {
    public let summary: PTBuild69HistoricalReplaySummary

    public init(summary: PTBuild69HistoricalReplaySummary) {
        self.summary = summary
    }
}

public nonisolated struct PTBuild69EvidenceReplayResult: Sendable {
    public let document: PTProtocolEvidenceV3Document
    public let reanalysis: PTBuild69HistoricalReanalysis

    public init(document: PTProtocolEvidenceV3Document, reanalysis: PTBuild69HistoricalReanalysis) {
        self.document = document
        self.reanalysis = reanalysis
    }
}

// EN: The historical analyzer is intentionally synchronous and bounded because it is a developer/replay operation.
// ES: El analizador histórico es síncrono y acotado porque es una operación de desarrollador/replay.
// 中文：历史分析是开发者回放操作，因此采用同步且有界的实现。
public nonisolated enum PTBuild69HistoricalReplayAnalyzer {
    public static let maximumInputBytes = 100 * 1_024 * 1_024
    public static let maximumLineCount = 1_000_000

    public static func analyzeDiscovery(text: String, sourceName: String = "discovery.jsonl") -> PTBuild69HistoricalReplayResult {
        var lineCount = 0
        var eventCount = 0
        var oldCandidateCount = 0
        var oldAnomalyCount = 0
        var normalizedKnownCount = 0
        var normalizedCandidateEventCount = 0
        var normalizedAnomalyCount = 0
        var ignoredPeriodicCount = 0
        var candidateValues: [String: Set<String>] = [:]
        var lastCandidateValues: [String: String] = [:]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for line in text.split(whereSeparator: \.isNewline).prefix(maximumLineCount) {
            lineCount += 1
            guard let data = String(line).data(using: .utf8),
                  let parsed = try? decoder.decode(PTBuild69DiscoveryReplayLine.self, from: data),
                  let event = parsed.event else {
                continue
            }
            eventCount += 1
            if oldCandidateClassifications.contains(event.classification) { oldCandidateCount += 1 }
            if oldAnomalyClassifications.contains(event.classification) { oldAnomalyCount += 1 }

            let normalized = classify(event: event)
            switch normalized.kind {
            case .known:
                normalizedKnownCount += 1
            case .candidate:
                normalizedCandidateEventCount += 1
            case .anomaly:
                normalizedAnomalyCount += 1
            case .periodic:
                ignoredPeriodicCount += 1
            case .ignored:
                break
            }

            if let semantic = normalized.semantic {
                for field in semantic.fields where isCandidateField(field) {
                    guard let value = field.normalizedValue else { continue }
                    candidateValues[field.id, default: []].insert(value)
                    if let previous = lastCandidateValues[field.id], previous != value {
                        normalizedCandidateEventCount += 1
                    }
                    lastCandidateValues[field.id] = value
                }
            }
        }

        let changedCandidateFieldCount = candidateValues.values.filter { $0.count > 1 }.count
        let summary = PTBuild69HistoricalReplaySummary(
            sourceName: sourceName,
            lineCount: lineCount,
            eventCount: eventCount,
            oldCandidateCount: oldCandidateCount,
            oldAnomalyCount: oldAnomalyCount,
            normalizedKnownCount: normalizedKnownCount,
            normalizedCandidateEventCount: normalizedCandidateEventCount,
            normalizedCandidateFieldCount: changedCandidateFieldCount,
            normalizedAnomalyCount: normalizedAnomalyCount,
            ignoredPeriodicCount: ignoredPeriodicCount
        )
        return PTBuild69HistoricalReplayResult(summary: summary)
    }

    public static func analyzeDiscovery(fileURL: URL) throws -> PTBuild69HistoricalReplayResult {
        let size = try inputSize(for: fileURL)
        guard size <= maximumInputBytes else {
            throw PTBuild69ReplayError.inputTooLarge(size: size, limit: maximumInputBytes)
        }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard let text = String(data: data, encoding: .utf8) else { throw PTBuild69ReplayError.invalidUTF8 }
        return analyzeDiscovery(text: text, sourceName: fileURL.lastPathComponent)
    }

    public static func analyzeEvidenceV2(data: Data) throws -> PTBuild69EvidenceReplayResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(PTProtocolEvidenceV2Document.self, from: data)
        return PTBuild69EvidenceReplayResult(
            document: PTProtocolEvidenceV3Migration.fromV2(document),
            reanalysis: PTBuild69HistoricalReanalyzer.analyze(records: document.records)
        )
    }

    private enum NormalizedKind {
        case known
        case candidate
        case anomaly
        case periodic
        case ignored
    }

    private struct NormalizedEvent {
        let kind: NormalizedKind
        let semantic: PTXP400SemanticFrame?
    }

    private struct PTBuild69DiscoveryReplayLine: Decodable {
        let event: PTProtocolDiscoveryEvent?
    }

    private static let oldCandidateClassifications: Set<PTProtocolDiscoveryClassification> = [
        .knownWithUnmappedData, .candidate, .unknownFrameID, .unknownCommand, .unparsedResponse
    ]

    private static let oldAnomalyClassifications: Set<PTProtocolDiscoveryClassification> = [
        .unexpectedLength, .malformed, .anomaly, .timeout, .transportError
    ]

    private static func classify(event: PTProtocolDiscoveryEvent) -> NormalizedEvent {
        if event.channel == .dashboardBLE, let data = Data(hexString: event.value) {
            return classifyDashboard(data, direction: event.direction)
        }
        switch event.classification {
        case .knownCommand, .knownResponse, .positiveResponse, .negativeResponse, .noData:
            return NormalizedEvent(kind: .known, semantic: nil)
        case .unknownCommand:
            return NormalizedEvent(kind: .candidate, semantic: nil)
        case .timeout, .transportError, .unexpectedLength, .malformed, .anomaly:
            return NormalizedEvent(kind: .anomaly, semantic: nil)
        case .unparsedResponse:
            return NormalizedEvent(kind: .periodic, semantic: nil)
        default:
            return NormalizedEvent(kind: .ignored, semantic: nil)
        }
    }

    private static func classifyDashboard(_ data: Data, direction: PTProtocolDiscoveryDirection) -> NormalizedEvent {
        if direction == .tx, data == PTXP400OutboundPacketClassifier.statusPoll {
            return NormalizedEvent(kind: .periodic, semantic: nil)
        }
        if direction == .tx {
            if data.first != PTXP400BLEProtocol.preamble,
               data.last != PTXP400BLEProtocol.terminator,
               data.count <= PTXP400BLEProtocol.maxTIOChunkLength {
                return NormalizedEvent(kind: .known, semantic: nil)
            }
            guard data.count >= 3,
                  data.first == PTXP400BLEProtocol.preamble,
                  data.last == PTXP400BLEProtocol.terminator else {
                return NormalizedEvent(kind: .anomaly, semantic: nil)
            }
            guard PTXP400BLEProtocol.isValidOutboundFrame(data) else {
                return NormalizedEvent(kind: .anomaly, semantic: nil)
            }
            let id = data[1]
            let known = id == PTXP400BLEProtocol.navigationFrameID ||
                id == PTXP400BLEProtocol.configurationFrameID || id == 0x08
            return NormalizedEvent(kind: known ? .known : .candidate, semantic: nil)
        }

        guard data.count >= 3,
              data.first == PTXP400BLEProtocol.preamble,
              data.last == PTXP400BLEProtocol.terminator else {
            return NormalizedEvent(kind: .anomaly, semantic: nil)
        }

        let id = data[1]
        guard id == PTXP400BLEProtocol.connectionFrameID || (PTXP400BLEProtocol.data1FrameID...PTXP400BLEProtocol.absFrameID).contains(id) else {
            return NormalizedEvent(kind: .anomaly, semantic: nil)
        }
        guard data.count == PTXP400BLEProtocol.vehicleStatusFrameLength || id == PTXP400BLEProtocol.connectionFrameID && data.count == PTXP400BLEProtocol.connectionFrameLength else {
            return NormalizedEvent(kind: .anomaly, semantic: nil)
        }
        guard let semantic = PTXP400SemanticDecoder.decode(frameID: id, payload: Data(data.dropFirst(2).dropLast())) else {
            return NormalizedEvent(kind: .anomaly, semantic: nil)
        }
        if id == PTXP400BLEProtocol.data2FrameID || id == PTXP400BLEProtocol.controlFrameID {
            return NormalizedEvent(kind: .periodic, semantic: semantic)
        }
        if id == PTXP400BLEProtocol.absFrameID,
           semantic.fields.first(where: { $0.id == "abs.padding3to7" })?.quality == .sentinel {
            return NormalizedEvent(kind: .periodic, semantic: semantic)
        }
        return NormalizedEvent(kind: .known, semantic: semantic)
    }

    private static func isCandidateField(_ field: PTXP400SemanticField) -> Bool {
        (field.role == .candidate || field.role == .unknown || field.role == .provisional || field.role == .flags)
            && field.availability.isAvailable
            && field.quality != .sentinel
            && field.normalizedValue != nil
    }

    private static func inputSize(for fileURL: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }
}

public nonisolated enum PTBuild69ReplayError: LocalizedError, Equatable, Sendable {
    case inputTooLarge(size: Int, limit: Int)
    case invalidUTF8

    public var errorDescription: String? {
        switch self {
        case let .inputTooLarge(size, limit): return "Replay input is too large: \(size) bytes (limit \(limit))."
        case .invalidUTF8: return "Replay input is not valid UTF-8."
        }
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let end = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<end], radix: 16) else { return nil }
            bytes.append(byte)
            index = end
        }
        self.init(bytes)
    }
}
