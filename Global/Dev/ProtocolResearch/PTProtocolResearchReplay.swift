//
//  PTProtocolResearchReplay.swift
//  CrazyDashboard
//
//  EN: Build 63 turns a passive experiment into a deterministic CrazyTrace replay without invoking a transport SDK.
//  ES: Build 63 convierte un experimento pasivo en una reproducción CrazyTrace determinista sin invocar un SDK de transporte.
//  中文：Build 63 将被动实验转换为确定性的 CrazyTrace 回放，绝不调用任何传输 SDK。
//

import Foundation

public nonisolated struct PTProtocolResearchReplayResult: Codable, Equatable, Sendable {
    public let traceDocument: PTCrazyTraceDocument
    public let analysis: PTCANExperimentAnalysisReport
    public let correlation: PTProtocolResearchCorrelationReport
    public let graph: PTProtocolResearchGraph

    public init(
        traceDocument: PTCrazyTraceDocument,
        analysis: PTCANExperimentAnalysisReport,
        correlation: PTProtocolResearchCorrelationReport,
        graph: PTProtocolResearchGraph
    ) {
        self.traceDocument = traceDocument
        self.analysis = analysis
        self.correlation = correlation
        self.graph = graph
    }
}

/// EN: Replay only reconstructs value models and analysis inputs; it never sends BLE, OBD, CAN, or OTA traffic.
/// ES: La reproducción solo reconstruye modelos de valor y entradas de análisis; nunca envía tráfico BLE, OBD, CAN ni OTA.
/// 中文：Replay 只重建值模型和分析输入，不会发送 BLE、OBD、CAN 或 OTA 流量。
public nonisolated enum PTProtocolResearchReplay {
    public static func run(
        experiment: PTCANExperiment,
        captures: [PTCANCaptureSession],
        evidence: [PTProtocolEvidenceRecord] = [],
        telemetrySnapshots: [PTUnifiedVehicleTelemetrySnapshot] = [],
        configuration: PTProtocolResearchAnalysisConfiguration = PTProtocolResearchAnalysisConfiguration(),
        generatedAt: Date = Date()
    ) -> PTProtocolResearchReplayResult {
        let traceDocument = makeTraceDocument(experiment: experiment, captures: captures)
        let analysis = PTProtocolResearchAnalyzer.analyze(
            experiment: experiment,
            captures: captures,
            configuration: configuration,
            generatedAt: generatedAt
        )
        let correlation = PTProtocolResearchCorrelationBuilder.build(
            experiment: experiment,
            captures: captures,
            evidence: evidence,
            telemetrySnapshots: telemetrySnapshots,
            generatedAt: generatedAt
        )
        let graph = PTProtocolResearchGraphBuilder.build(
            experiment: experiment,
            analysis: analysis,
            correlation: correlation
        )
        return PTProtocolResearchReplayResult(
            traceDocument: traceDocument,
            analysis: analysis,
            correlation: correlation,
            graph: graph
        )
    }

    public static func run(
        traceDocument: PTCrazyTraceDocument,
        experiment: PTCANExperiment,
        evidence: [PTProtocolEvidenceRecord] = [],
        telemetrySnapshots: [PTUnifiedVehicleTelemetrySnapshot] = [],
        configuration: PTProtocolResearchAnalysisConfiguration = PTProtocolResearchAnalysisConfiguration(),
        generatedAt: Date = Date()
    ) -> PTProtocolResearchReplayResult {
        run(
            experiment: experiment,
            captures: captures(from: traceDocument),
            evidence: evidence,
            telemetrySnapshots: telemetrySnapshots,
            configuration: configuration,
            generatedAt: generatedAt
        )
    }

    @MainActor
    public static func exportPackage(
        experiment: PTCANExperiment,
        captures: [PTCANCaptureSession],
        to directoryURL: URL,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
        buildNumber: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
        privacyLevel: String = "redacted",
        fileManager: FileManager = .default
    ) throws -> URL {
        try PTCrazyTracePackageWriter.write(
            document: makeTraceDocument(experiment: experiment, captures: captures),
            to: directoryURL,
            appVersion: appVersion,
            buildNumber: buildNumber,
            privacyLevel: privacyLevel,
            fileManager: fileManager
        )
    }

    public static func makeTraceDocument(
        experiment: PTCANExperiment,
        captures: [PTCANCaptureSession]
    ) -> PTCrazyTraceDocument {
        let captureByID = captures.reduce(into: [UUID: PTCANCaptureSession]()) { result, capture in
            if result[capture.id] == nil { result[capture.id] = capture }
        }
        let startDate = captures
            .map(\.startedAt)
            .min() ?? experiment.createdAt
        var events: [PTCrazyTraceEvent] = []
        var sequence = 0

        for trial in experiment.trials {
            guard let capture = captureByID[trial.captureID] else { continue }
            var markerRoles: [(UUID, String)] = []
            if let markerID = trial.activationMarkerID {
                markerRoles.append((markerID, "activation"))
            }
            if let markerID = trial.deactivationMarkerID {
                markerRoles.append((markerID, "deactivation"))
            }
            for (markerID, role) in markerRoles {
                guard let marker = capture.events.first(where: { $0.id == markerID }) else { continue }
                let timestamp = resolvedDate(for: marker.timestamp, relativeTo: capture.startedAt)
                events.append(
                    PTCrazyTraceEvent(
                        id: PTProtocolResearchMath.stableUUID("replay-marker:\(experiment.id.uuidString):\(trial.id.uuidString):\(markerID.uuidString)"),
                        sequence: sequence,
                        timestamp: timestamp,
                        elapsed: max(0, timestamp.timeIntervalSince(startDate)),
                        domain: .system,
                        direction: .marker,
                        source: .replay,
                        payload: .marker(
                            PTTraceMarkerPayload(
                                name: marker.name,
                                metadata: [
                                    "trialID": trial.id.uuidString,
                                    "captureID": trial.captureID.uuidString,
                                    "markerID": markerID.uuidString,
                                    "markerRole": role
                                ]
                            )
                        )
                    )
                )
                sequence += 1
            }

            let sortedFrames = capture.frames.sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
                return lhs.sequence < rhs.sequence
            }
            for frame in sortedFrames {
                let timestamp = resolvedDate(for: frame.timestamp, relativeTo: capture.startedAt)
                events.append(
                    PTCrazyTraceEvent(
                        id: PTProtocolResearchMath.stableUUID(
                            "replay-can:\(experiment.id.uuidString):\(trial.id.uuidString):\(frame.sequence):\(frame.timestamp):\(frame.rawLine)"
                        ),
                        sequence: sequence,
                        timestamp: timestamp,
                        elapsed: max(0, timestamp.timeIntervalSince(startDate)),
                        domain: .obd,
                        direction: .state,
                        source: .replay,
                        payload: .protocolMessage(
                            PTTraceProtocolPayload(
                                raw: frame.rawLine,
                                metadata: [
                                    "trialID": trial.id.uuidString,
                                    "captureID": trial.captureID.uuidString,
                                    "canHeader": frame.header ?? "",
                                    "dataHex": frame.dataHex ?? "",
                                    "dlc": frame.dlc.map(String.init) ?? "",
                                    "sequence": String(frame.sequence)
                                ]
                            )
                        )
                    )
                )
                sequence += 1
            }
        }

        return PTCrazyTraceDocument(
            traceID: PTProtocolResearchMath.stableUUID("trace:\(experiment.id.uuidString)"),
            name: "Protocol Research - \(experiment.targetEvent.displayName)",
            vehicleID: experiment.vehicleID.uuidString,
            startedAt: startDate,
            endedAt: events.map(\.timestamp).max(),
            events: events
        )
    }

    private static func captures(from document: PTCrazyTraceDocument) -> [PTCANCaptureSession] {
        struct MutableCapture {
            var startedAt: Date
            var frames: [PTCANFrame] = []
            var events: [PTCANCaptureEvent] = []
        }

        var captures: [UUID: MutableCapture] = [:]
        for event in document.events {
            switch event.payload {
            case .protocolMessage(let payload):
                guard let captureID = UUID(uuidString: payload.metadata["captureID"] ?? ""),
                      event.timestamp.timeIntervalSince1970.isFinite else { continue }
                let trialTimestamp = event.timestamp.timeIntervalSince1970
                var capture = captures[captureID] ?? MutableCapture(startedAt: event.timestamp)
                let frame = PTCANFrame(
                    timestamp: trialTimestamp,
                    sequence: Int(payload.metadata["sequence"] ?? "") ?? event.sequence,
                    direction: .bus,
                    rawLine: payload.raw,
                    header: payload.metadata["canHeader"].flatMap { $0.isEmpty ? nil : $0 },
                    dataHex: payload.metadata["dataHex"].flatMap { $0.isEmpty ? nil : $0 },
                    dlc: Int(payload.metadata["dlc"] ?? "")
                )
                capture.frames.append(frame)
                capture.startedAt = min(capture.startedAt, event.timestamp)
                captures[captureID] = capture
            case .marker(let marker):
                guard let captureID = UUID(uuidString: marker.metadata["captureID"] ?? ""),
                      let markerID = UUID(uuidString: marker.metadata["markerID"] ?? "") else { continue }
                var capture = captures[captureID] ?? MutableCapture(startedAt: event.timestamp)
                capture.events.append(
                    PTCANCaptureEvent(
                        id: markerID,
                        name: marker.name,
                        timestamp: event.timestamp.timeIntervalSince1970
                    )
                )
                capture.startedAt = min(capture.startedAt, event.timestamp)
                captures[captureID] = capture
            default:
                continue
            }
        }

        return captures.keys.sorted { $0.uuidString < $1.uuidString }.map { captureID in
            let capture = captures[captureID] ?? MutableCapture(startedAt: document.startedAt)
            let endedAt = (capture.frames.map { Date(timeIntervalSince1970: $0.timestamp) } + capture.events.map { Date(timeIntervalSince1970: $0.timestamp) }).max()
            return PTCANCaptureSession(
                id: captureID,
                name: "Replay \(captureID.uuidString.prefix(8))",
                startedAt: capture.startedAt,
                endedAt: endedAt,
                filterHeader: nil,
                monitorProfile: .rawDLC,
                frames: capture.frames.sorted { lhs, rhs in
                    if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
                    return lhs.sequence < rhs.sequence
                },
                events: capture.events.sorted { lhs, rhs in
                    if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
            )
        }
    }

    private static func resolvedDate(for timestamp: TimeInterval, relativeTo start: Date) -> Date {
        let startTimestamp = start.timeIntervalSince1970
        if timestamp.isFinite, startTimestamp > 1_000_000, abs(timestamp) < 1_000_000 {
            return start.addingTimeInterval(timestamp)
        }
        return timestamp.isFinite ? Date(timeIntervalSince1970: timestamp) : start
    }
}
