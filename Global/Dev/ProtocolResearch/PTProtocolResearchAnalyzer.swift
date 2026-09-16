//
//  PTProtocolResearchAnalyzer.swift
//  CrazyDashboard
//
//  EN: Build 63 analyzes repeated passive captures with explainable statistics and no transport side effects.
//  ES: Build 63 analiza capturas pasivas repetidas con estadísticas explicables y sin efectos de transporte.
//  中文：Build 63 对重复的被动抓包进行可解释统计分析，不产生任何传输副作用。
//

import Foundation

public nonisolated struct PTProtocolResearchAnalysisConfiguration: Codable, Equatable, Sendable {
    public let beforeWindow: TimeInterval
    public let afterWindow: TimeInterval
    public let maximumCandidates: Int

    public init(
        beforeWindow: TimeInterval = 2,
        afterWindow: TimeInterval = 2,
        maximumCandidates: Int = 256
    ) {
        self.beforeWindow = max(0, beforeWindow)
        self.afterWindow = max(0, afterWindow)
        self.maximumCandidates = min(max(1, maximumCandidates), 10_000)
    }
}

/// EN: Repeatable analysis is a pure read of capture files and event markers.
/// ES: El análisis repetible solo lee archivos de captura y marcas de eventos.
/// 中文：可重复分析只读取抓包文件和事件标记。
public nonisolated enum PTProtocolResearchAnalyzer {
    public static func analyze(
        experiment: PTCANExperiment,
        captures: [PTCANCaptureSession],
        configuration: PTProtocolResearchAnalysisConfiguration = PTProtocolResearchAnalysisConfiguration(),
        generatedAt: Date = Date()
    ) -> PTCANExperimentAnalysisReport {
        var capturesByID: [UUID: PTCANCaptureSession] = [:]
        for capture in captures where capturesByID[capture.id] == nil {
            capturesByID[capture.id] = capture
        }

        let trials = experiment.trials.compactMap { trial -> TrialAnalysis? in
            guard let capture = capturesByID[trial.captureID] else { return nil }
            return analyze(
                trial: trial,
                capture: capture,
                configuration: configuration
            )
        }

        var candidateKeys = Set<PTCANCandidateKey>()
        for trial in trials {
            candidateKeys.formUnion(trial.activationHits)
            candidateKeys.formUnion(trial.deactivationHits)
        }

        let statistics = candidateKeys
            .map { key in statistic(for: key, experiment: experiment, trials: trials, configuration: configuration) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.key.stableID < rhs.key.stableID
            }
            .prefix(configuration.maximumCandidates)
            .map { $0 }

        let falsePositives = statistics.map { statistic in
            let mutationRate = statistic.backgroundComparisons > 0
                ? Double(statistic.backgroundChanges) / Double(statistic.backgroundComparisons)
                : 0
            return PTCANFalsePositiveReport(
                id: PTProtocolResearchMath.stableUUID("false-positive:\(experiment.id.uuidString):\(statistic.key.stableID)"),
                key: statistic.key,
                backgroundFrameCount: trials.reduce(0) { $0 + $1.backgroundFrameCount },
                backgroundComparisons: statistic.backgroundComparisons,
                backgroundChanges: statistic.backgroundChanges,
                mutationRate: mutationRate,
                backgroundIsolation: statistic.backgroundIsolation,
                confidenceAdjustment: statistic.backgroundIsolation
            )
        }

        return PTCANExperimentAnalysisReport(
            id: PTProtocolResearchMath.stableUUID("analysis:\(experiment.id.uuidString)"),
            experimentID: experiment.id,
            vehicleID: experiment.vehicleID,
            targetEvent: experiment.targetEvent,
            generatedAt: generatedAt,
            statistics: Array(statistics),
            groups: PTProtocolResearchCandidateGroupBuilder.group(statistics: Array(statistics)),
            falsePositives: falsePositives
        )
    }

    private struct TrialAnalysis {
        let sessionID: UUID
        let source: PTProtocolEvidenceSource
        let activationAvailable: Bool
        let deactivationAvailable: Bool
        let activationHits: Set<PTCANCandidateKey>
        let deactivationHits: Set<PTCANCandidateKey>
        let activationDelays: [PTCANCandidateKey: [TimeInterval]]
        let deactivationDelays: [PTCANCandidateKey: [TimeInterval]]
        let backgroundChanges: [PTCANCandidateKey: Int]
        let backgroundComparisons: [PTCANCandidateKey: Int]
        let backgroundFrameCount: Int
        let evidenceIDs: [PTCANCandidateKey: Set<UUID>]
    }

    private struct PayloadSample {
        let timestamp: TimeInterval
        let bytes: [UInt8]
    }

    private struct TransitionResult {
        var hits: Set<PTCANCandidateKey> = []
        var delays: [PTCANCandidateKey: [TimeInterval]] = [:]
    }

    private struct BackgroundResult {
        var changes: [PTCANCandidateKey: Int] = [:]
        var comparisons: [PTCANCandidateKey: Int] = [:]
        var frameCount = 0
    }

    private static func analyze(
        trial: PTCANExperimentTrial,
        capture: PTCANCaptureSession,
        configuration: PTProtocolResearchAnalysisConfiguration
    ) -> TrialAnalysis {
        let activationTimestamp = markerTimestamp(trial.activationMarkerID, in: capture)
        let deactivationTimestamp = markerTimestamp(trial.deactivationMarkerID, in: capture)
        let activation = activationTimestamp.map {
            transition(
                frames: capture.frames,
                markerTimestamp: $0,
                before: configuration.beforeWindow,
                after: configuration.afterWindow
            )
        } ?? TransitionResult()
        let deactivation = deactivationTimestamp.map {
            transition(
                frames: capture.frames,
                markerTimestamp: $0,
                before: configuration.beforeWindow,
                after: configuration.afterWindow
            )
        } ?? TransitionResult()

        let exclusionWindows = [
            activationTimestamp.map { ($0 - configuration.beforeWindow)...($0 + configuration.afterWindow) },
            deactivationTimestamp.map { ($0 - configuration.beforeWindow)...($0 + configuration.afterWindow) }
        ].compactMap { $0 }
        let resolvedControlWindow = trial.controlWindow.flatMap {
            resolveControlWindow($0, capture: capture)
        }
        let background = background(
            frames: capture.frames,
            exclusionWindows: exclusionWindows,
            controlWindow: resolvedControlWindow
        )

        var evidenceIDs: [PTCANCandidateKey: Set<UUID>] = [:]
        for key in activation.hits {
            if let markerID = trial.activationMarkerID {
                evidenceIDs[key, default: []].insert(markerID)
            }
        }
        for key in deactivation.hits {
            if let markerID = trial.deactivationMarkerID {
                evidenceIDs[key, default: []].insert(markerID)
            }
        }

        return TrialAnalysis(
            sessionID: trial.sessionID ?? capture.id,
            source: trial.source,
            activationAvailable: activationTimestamp != nil,
            deactivationAvailable: deactivationTimestamp != nil,
            activationHits: activation.hits,
            deactivationHits: deactivation.hits,
            activationDelays: activation.delays,
            deactivationDelays: deactivation.delays,
            backgroundChanges: background.changes,
            backgroundComparisons: background.comparisons,
            backgroundFrameCount: background.frameCount,
            evidenceIDs: evidenceIDs
        )
    }

    private static func statistic(
        for key: PTCANCandidateKey,
        experiment: PTCANExperiment,
        trials: [TrialAnalysis],
        configuration: PTProtocolResearchAnalysisConfiguration
    ) -> PTCANCandidateStatistic {
        let activationTrials = trials.filter(\.activationAvailable).count
        let deactivationTrials = trials.filter(\.deactivationAvailable).count
        let activationHits = trials.filter { $0.activationHits.contains(key) }.count
        let deactivationHits = trials.filter { $0.deactivationHits.contains(key) }.count
        let activationDelays = trials.flatMap { $0.activationDelays[key] ?? [] }
        let deactivationDelays = trials.flatMap { $0.deactivationDelays[key] ?? [] }
        let allDelays = activationDelays + deactivationDelays
        let sessionIDs = Set(trials.map(\.sessionID))
        let sessionsWithHit = Set(
            trials
                .filter { $0.activationHits.contains(key) || $0.deactivationHits.contains(key) }
                .map(\.sessionID)
        )
        let sourceValues = Set(trials.map { $0.source.rawValue })
        let backgroundChanges = trials.reduce(0) { $0 + ($1.backgroundChanges[key] ?? 0) }
        let backgroundComparisons = trials.reduce(0) { $0 + ($1.backgroundComparisons[key] ?? 0) }
        let backgroundMutationRate = backgroundComparisons > 0
            ? Double(backgroundChanges) / Double(backgroundComparisons)
            : 0
        let backgroundIsolation = PTProtocolResearchMath.clamp(1 - backgroundMutationRate)
        let medianDelay = PTProtocolResearchMath.percentile(allDelays, percentile: 0.5)
        let p95Delay = PTProtocolResearchMath.percentile(allDelays, percentile: 0.95)
        let temporalProximity: Double
        if let medianDelay {
            temporalProximity = PTProtocolResearchMath.clamp(
                1 - medianDelay / max(configuration.afterWindow, 0.25)
            )
        } else {
            temporalProximity = 0
        }
        let crossSessionRepeatability = PTProtocolResearchMath.ratio(
            sessionsWithHit.count,
            sessionIDs.count
        )
        let sourceCorrelation = sourceValues.count <= 1
            ? 1
            : PTProtocolResearchMath.clamp(1 / Double(sourceValues.count))
        let activationConsistency = PTProtocolResearchMath.ratio(activationHits, activationTrials)
        let deactivationConsistency = PTProtocolResearchMath.ratio(deactivationHits, deactivationTrials)

        // EN: Keep the weights visible so a researcher can explain every score.
        // ES: Los pesos quedan visibles para que el investigador pueda explicar cada puntuación.
        // 中文：保留显式权重，让研究人员可以解释每一个分数。
        let weightedConfidence = PTProtocolResearchMath.clamp(
            0.25 * activationConsistency
                + 0.20 * deactivationConsistency
                + 0.20 * temporalProximity
                + 0.15 * backgroundIsolation
                + 0.10 * crossSessionRepeatability
                + 0.10 * sourceCorrelation
        )
        let evidenceIDs = trials
            .compactMap { $0.evidenceIDs[key] }
            .reduce(into: Set<UUID>()) { $0.formUnion($1) }

        return PTCANCandidateStatistic(
            id: PTProtocolResearchMath.stableUUID("statistic:\(experiment.id.uuidString):\(key.stableID)"),
            experimentID: experiment.id,
            key: key,
            activationTrials: activationTrials,
            activationHits: activationHits,
            deactivationTrials: deactivationTrials,
            deactivationHits: deactivationHits,
            backgroundChanges: backgroundChanges,
            backgroundComparisons: backgroundComparisons,
            medianDelay: medianDelay,
            p95Delay: p95Delay,
            sessions: sessionIDs.count,
            confidence: weightedConfidence,
            score: Int((weightedConfidence * 100).rounded()),
            temporalProximity: temporalProximity,
            backgroundIsolation: backgroundIsolation,
            crossSessionRepeatability: crossSessionRepeatability,
            sourceCorrelation: sourceCorrelation,
            status: .candidate,
            evidenceIDs: Array(evidenceIDs)
        )
    }

    private static func markerTimestamp(_ markerID: UUID?, in capture: PTCANCaptureSession) -> TimeInterval? {
        guard let markerID,
              let marker = capture.events.first(where: { $0.id == markerID }),
              marker.timestamp.isFinite else { return nil }
        return marker.timestamp
    }

    private static func transition(
        frames: [PTCANFrame],
        markerTimestamp: TimeInterval,
        before: TimeInterval,
        after: TimeInterval
    ) -> TransitionResult {
        let beforeFrames = frames.filter { frame in
            frame.timestamp.isFinite && frame.timestamp >= markerTimestamp - before && frame.timestamp < markerTimestamp
        }
        let afterFrames = frames.filter { frame in
            frame.timestamp.isFinite && frame.timestamp >= markerTimestamp && frame.timestamp <= markerTimestamp + after
        }
        guard !beforeFrames.isEmpty, !afterFrames.isEmpty else { return TransitionResult() }

        let beforeModes = dominantPayloads(beforeFrames)
        let afterModes = dominantPayloads(afterFrames)
        var result = TransitionResult()
        for header in Set(beforeModes.keys).intersection(afterModes.keys).sorted() {
            guard let beforePayload = beforeModes[header], let afterPayload = afterModes[header] else { continue }
            let width = min(beforePayload.bytes.count, afterPayload.bytes.count)
            guard width > 0 else { continue }
            for byteIndex in 0..<width {
                let delta = beforePayload.bytes[byteIndex] ^ afterPayload.bytes[byteIndex]
                guard delta != 0 else { continue }
                for bitIndex in 0..<8 where delta & (UInt8(1) << UInt8(bitIndex)) != 0 {
                    let key = PTCANCandidateKey(header: header, byteIndex: byteIndex, bitIndex: bitIndex)
                    result.hits.insert(key)
                    let delays = afterFrames.compactMap { frame -> TimeInterval? in
                        guard frame.header.map(normalizeHeader) == header,
                              let bytes = parseBytes(frame.dataHex),
                              bytes.count > byteIndex,
                              bytes[byteIndex] != beforePayload.bytes[byteIndex] else { return nil }
                        return max(0, frame.timestamp - markerTimestamp)
                    }
                    if let delay = delays.min() {
                        result.delays[key] = [delay]
                    }
                }
            }
        }
        return result
    }

    private static func background(
        frames: [PTCANFrame],
        exclusionWindows: [ClosedRange<TimeInterval>],
        controlWindow: ClosedRange<TimeInterval>?
    ) -> BackgroundResult {
        let eligibleFrames = frames.filter { frame in
            guard frame.timestamp.isFinite else { return false }
            if let controlWindow, controlWindow.contains(frame.timestamp) { return false }
            return !exclusionWindows.contains { $0.contains(frame.timestamp) }
        }
        var result = BackgroundResult()
        result.frameCount = eligibleFrames.count
        var grouped: [String: [PTCANFrame]] = [:]
        for frame in eligibleFrames {
            guard let header = frame.header.map(normalizeHeader), parseBytes(frame.dataHex) != nil else { continue }
            grouped[header, default: []].append(frame)
        }

        for header in grouped.keys.sorted() {
            let sortedFrames = grouped[header, default: []].sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
                return lhs.sequence < rhs.sequence
            }
            guard sortedFrames.count > 1 else { continue }
            for pair in zip(sortedFrames, sortedFrames.dropFirst()) {
                guard let lhs = parseBytes(pair.0.dataHex), let rhs = parseBytes(pair.1.dataHex) else { continue }
                let width = min(lhs.count, rhs.count)
                for byteIndex in 0..<width {
                    for bitIndex in 0..<8 {
                        let key = PTCANCandidateKey(header: header, byteIndex: byteIndex, bitIndex: bitIndex)
                        result.comparisons[key, default: 0] += 1
                        let lhsBit = lhs[byteIndex] & (UInt8(1) << UInt8(bitIndex))
                        let rhsBit = rhs[byteIndex] & (UInt8(1) << UInt8(bitIndex))
                        if lhsBit != rhsBit {
                            result.changes[key, default: 0] += 1
                        }
                    }
                }
            }
        }
        return result
    }

    private static func dominantPayloads(_ frames: [PTCANFrame]) -> [String: PayloadSample] {
        var grouped: [String: [PayloadSample]] = [:]
        for frame in frames {
            guard let header = frame.header.map(normalizeHeader),
                  let bytes = parseBytes(frame.dataHex) else { continue }
            grouped[header, default: []].append(PayloadSample(timestamp: frame.timestamp, bytes: bytes))
        }

        var result: [String: PayloadSample] = [:]
        for header in grouped.keys.sorted() {
            let samples = grouped[header, default: []]
            var counts: [String: (count: Int, sample: PayloadSample)] = [:]
            for sample in samples {
                let key = sample.bytes.map { String(format: "%02X", $0) }.joined()
                let current = counts[key]
                counts[key] = (count: (current?.count ?? 0) + 1, sample: current?.sample ?? sample)
            }
            if let selected = counts.max(by: { lhs, rhs in
                if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
                return lhs.key > rhs.key
            })?.value.sample {
                result[header] = selected
            }
        }
        return result
    }

    private static func parseBytes(_ value: String?) -> [UInt8]? {
        guard let value else { return nil }
        let hex = value.filter { $0.isHexDigit }
        guard !hex.isEmpty, hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    private static func normalizeHeader(_ value: String) -> String {
        value
            .replacingOccurrences(of: "0x", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private static func resolveControlWindow(
        _ window: ClosedRange<TimeInterval>,
        capture: PTCANCaptureSession
    ) -> ClosedRange<TimeInterval> {
        let captureStart = capture.startedAt.timeIntervalSince1970
        if captureStart > 1_000_000 && abs(window.lowerBound) < 1_000_000 && abs(window.upperBound) < 1_000_000 {
            return (captureStart + window.lowerBound)...(captureStart + window.upperBound)
        }
        return window
    }
}

public nonisolated enum PTProtocolResearchCandidateGroupBuilder {
    public static func group(statistics: [PTCANCandidateStatistic]) -> [PTCANCandidateGroup] {
        var grouped: [PTCANCandidateKey: [PTCANCandidateStatistic]] = [:]
        for statistic in statistics {
            grouped[statistic.key, default: []].append(statistic)
        }
        return grouped.keys.sorted { $0.stableID < $1.stableID }.map { key in
            let members = grouped[key, default: []]
            return PTCANCandidateGroup(
                id: PTProtocolResearchMath.stableUUID("group:\(key.stableID):\(members.map(\.experimentID.uuidString).sorted().joined(separator: ","))"),
                key: key,
                experimentIDs: members.map(\.experimentID),
                statisticIDs: members.map(\.id),
                bestScore: members.map(\.score).max() ?? 0,
                status: .candidate
            )
        }
    }
}

/// EN: The correlation builder creates one auditable timeline for markers, CAN, BLE, OBD, and unified telemetry.
/// ES: El constructor crea una línea temporal auditable para marcas, CAN, BLE, OBD y telemetría unificada.
/// 中文：关联构建器为事件标记、CAN、BLE、OBD 和统一遥测生成一条可审计时间线。
public nonisolated enum PTProtocolResearchCorrelationBuilder {
    public static func build(
        experiment: PTCANExperiment,
        captures: [PTCANCaptureSession],
        evidence: [PTProtocolEvidenceRecord] = [],
        telemetrySnapshots: [PTUnifiedVehicleTelemetrySnapshot] = [],
        window: TimeInterval = 30,
        generatedAt: Date = Date()
    ) -> PTProtocolResearchCorrelationReport {
        let safeWindow = max(0.5, window)
        let capturesByID = captures.reduce(into: [UUID: PTCANCaptureSession]()) { result, capture in
            if result[capture.id] == nil { result[capture.id] = capture }
        }
        var entries: [PTProtocolResearchTimelineEntry] = []
        var markers: [(id: UUID, name: String, timestamp: Date)] = []

        for trial in experiment.trials {
            guard let capture = capturesByID[trial.captureID] else { continue }
            let markerIDs = [trial.activationMarkerID, trial.deactivationMarkerID].compactMap { $0 }
            for event in capture.events where markerIDs.contains(event.id) && event.timestamp.isFinite {
                let markerDate = Date(timeIntervalSince1970: event.timestamp)
                markers.append((event.id, event.name, markerDate))
                entries.append(
                    PTProtocolResearchTimelineEntry(
                        id: event.id,
                        source: .userMarker,
                        timestamp: markerDate,
                        summary: event.name,
                        stateKey: event.name.lowercased(),
                        confidence: 1
                    )
                )
            }
            let markerTimes = markerIDs.compactMap { id in capture.events.first(where: { $0.id == id })?.timestamp }
            for frame in capture.frames where frame.timestamp.isFinite {
                guard markerTimes.contains(where: { abs(frame.timestamp - $0) <= safeWindow }) else { continue }
                let entryID = PTProtocolResearchMath.stableUUID(
                    "can:\(trial.id.uuidString):\(frame.sequence):\(frame.timestamp):\(frame.header ?? "unknown")"
                )
                entries.append(
                    PTProtocolResearchTimelineEntry(
                        id: entryID,
                        source: .can,
                        timestamp: Date(timeIntervalSince1970: frame.timestamp),
                        summary: "CAN \(frame.header ?? "?"): \(frame.dataHex ?? frame.rawLine)",
                        stateKey: frame.header.map { "can:\(normalize($0))" },
                        confidence: frame.dataHex == nil ? 0.25 : 0.5
                    )
                )
            }
        }

        guard let lower = markers.map(\.timestamp).min()?.addingTimeInterval(-safeWindow),
              let upper = markers.map(\.timestamp).max()?.addingTimeInterval(safeWindow) else {
            return PTProtocolResearchCorrelationReport(
                id: PTProtocolResearchMath.stableUUID("correlation:\(experiment.id.uuidString)"),
                experimentID: experiment.id,
                vehicleID: experiment.vehicleID,
                generatedAt: generatedAt,
                entries: [],
                clusters: []
            )
        }

        for record in evidence where record.timestamp >= lower && record.timestamp <= upper {
            guard let source = timelineSource(for: record.domain) else { continue }
            entries.append(
                PTProtocolResearchTimelineEntry(
                    id: record.id,
                    source: source,
                    timestamp: record.timestamp,
                    summary: record.value,
                    stateKey: record.reference ?? record.domain.rawValue,
                    confidence: record.confidence,
                    evidenceIDs: [record.id]
                )
            )
        }

        for snapshot in telemetrySnapshots {
            for value in snapshot.values where value.capturedAt >= lower && value.capturedAt <= upper {
                guard let source = timelineSource(for: value.source.domain) else { continue }
                let entryID = PTProtocolResearchMath.stableUUID(
                    "telemetry:\(value.signal.rawValue):\(value.capturedAt.timeIntervalSince1970):\(describe(value.value))"
                )
                entries.append(
                    PTProtocolResearchTimelineEntry(
                        id: entryID,
                        source: source,
                        timestamp: value.capturedAt,
                        summary: "\(value.signal.rawValue)=\(describe(value.value))",
                        stateKey: "telemetry:\(value.signal.rawValue)",
                        confidence: value.confidence
                    )
                )
            }
        }

        var uniqueEntries: [UUID: PTProtocolResearchTimelineEntry] = [:]
        for entry in entries where uniqueEntries[entry.id] == nil {
            uniqueEntries[entry.id] = entry
        }
        let sortedEntries = uniqueEntries.values.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let clusters = markers.map { marker in
            let nearby = sortedEntries.filter {
                $0.source != .userMarker && abs($0.timestamp.timeIntervalSince(marker.timestamp)) <= safeWindow
            }
            let delays = nearby.map { abs($0.timestamp.timeIntervalSince(marker.timestamp)) }
            let stateCounts = nearby.compactMap(\.stateKey).reduce(into: [String: Int]()) { result, key in
                result[key, default: 0] += 1
            }
            let stateAgreement = stateCounts.values.max().map { PTProtocolResearchMath.ratio($0, nearby.count) } ?? 0
            let sources = Set(nearby.map(\.source))
            let sourceCoverage = PTProtocolResearchMath.clamp(Double(sources.count) / 4)
            let temporalScore = delays.min().map { PTProtocolResearchMath.clamp(1 - $0 / safeWindow) } ?? 0
            let confidence = PTProtocolResearchMath.clamp((stateAgreement + sourceCoverage + temporalScore) / 3)
            return PTProtocolResearchCorrelationCluster(
                id: PTProtocolResearchMath.stableUUID("cluster:\(experiment.id.uuidString):\(marker.id.uuidString)"),
                markerID: marker.id,
                markerName: marker.name,
                markerTimestamp: marker.timestamp,
                entryIDs: nearby.map(\.id),
                sources: Array(sources),
                temporalProximity: delays.min(),
                repetitionCount: nearby.count,
                stateAgreement: stateAgreement,
                confidence: confidence
            )
        }

        return PTProtocolResearchCorrelationReport(
            id: PTProtocolResearchMath.stableUUID("correlation:\(experiment.id.uuidString)"),
            experimentID: experiment.id,
            vehicleID: experiment.vehicleID,
            generatedAt: generatedAt,
            entries: sortedEntries,
            clusters: clusters
        )
    }

    private static func timelineSource(for domain: PTProtocolEvidenceDomain) -> PTProtocolResearchTimelineSource? {
        switch domain {
        case .xp400BLE, .xp400BLETransport, .xp400BLESemantic: return .xp400BLE
        case .obd, .obdTransport, .obd2, .uds, .can: return domain == .can ? .can : .obd
        case .gps, .motion: return .unifiedTelemetry
        case .correlation, .ymobdVendorExtension, .adapterVendorExtension, .ymobdFirmwareOTA, .firmwareResearch: return nil
        }
    }

    private static func timelineSource(for domain: PTVehicleTelemetrySourceDomain) -> PTProtocolResearchTimelineSource? {
        switch domain {
        case .xp400BLE: return .xp400BLE
        case .obd: return .obd
        case .gps, .motion, .calculated, .replay, .unknown: return .unifiedTelemetry
        }
    }

    private static func describe(_ value: PTVehicleTelemetryValue) -> String {
        switch value {
        case .double(let value): return String(format: "%.3f", value)
        case .integer(let value): return String(value)
        case .boolean(let value): return value ? "true" : "false"
        case .location(let latitude, let longitude, _): return String(format: "%.5f,%.5f", latitude, longitude)
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "0x", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}

public nonisolated enum PTProtocolResearchGraphBuilder {
    public static func build(
        experiment: PTCANExperiment,
        analysis: PTCANExperimentAnalysisReport,
        correlation: PTProtocolResearchCorrelationReport,
        catalog: PTVehicleSignalCatalog? = nil
    ) -> PTProtocolResearchGraph {
        var nodes: [String: PTProtocolResearchGraphNode] = [:]
        var edges: [String: PTProtocolResearchGraphEdge] = [:]
        let targetEventNodeID = "event:target:\(experiment.targetEvent.rawValue)"

        func addNode(_ node: PTProtocolResearchGraphNode) {
            if let existing = nodes[node.id] {
                nodes[node.id] = PTProtocolResearchGraphNode(
                    id: existing.id,
                    kind: existing.kind,
                    title: existing.title,
                    evidenceIDs: existing.evidenceIDs + node.evidenceIDs
                )
            } else {
                nodes[node.id] = node
            }
        }

        func addEdge(
            from: String,
            to: String,
            relation: PTProtocolResearchGraphRelation,
            confidence: Double,
            temporalProximity: TimeInterval?,
            evidenceIDs: [UUID]
        ) {
            let edgeID = PTProtocolResearchMath.stableUUID(
                "edge:\(from):\(to):\(relation.rawValue)"
            ).uuidString
            edges[edgeID] = PTProtocolResearchGraphEdge(
                id: edgeID,
                fromNodeID: from,
                toNodeID: to,
                relation: relation,
                confidence: confidence,
                temporalProximity: temporalProximity,
                evidenceIDs: evidenceIDs
            )
        }

        addNode(
            PTProtocolResearchGraphNode(
                id: targetEventNodeID,
                kind: .vehicleEvent,
                title: experiment.targetEvent.displayName
            )
        )

        let entriesByID = Dictionary(uniqueKeysWithValues: correlation.entries.map { ($0.id, $0) })
        for cluster in correlation.clusters {
            let markerNodeID = "event:marker:\(cluster.markerID.uuidString)"
            addNode(
                PTProtocolResearchGraphNode(
                    id: markerNodeID,
                    kind: .vehicleEvent,
                    title: cluster.markerName
                )
            )
            addEdge(
                from: targetEventNodeID,
                to: markerNodeID,
                relation: .coObserved,
                confidence: cluster.confidence,
                temporalProximity: 0,
                evidenceIDs: []
            )
            for entryID in cluster.entryIDs {
                guard let entry = entriesByID[entryID] else { continue }
                let nodeID = "entry:\(entry.id.uuidString)"
                addNode(
                    PTProtocolResearchGraphNode(
                        id: nodeID,
                        kind: nodeKind(for: entry.source),
                        title: entry.summary,
                        evidenceIDs: entry.evidenceIDs
                    )
                )
                addEdge(
                    from: markerNodeID,
                    to: nodeID,
                    relation: .coObserved,
                    confidence: cluster.confidence,
                    temporalProximity: cluster.temporalProximity,
                    evidenceIDs: entry.evidenceIDs
                )
            }
        }

        for statistic in analysis.statistics {
            let nodeID = "can:\(statistic.key.stableID)"
            addNode(
                PTProtocolResearchGraphNode(
                    id: nodeID,
                    kind: .canSignal,
                    title: "CAN \(statistic.key.stableID)",
                    evidenceIDs: statistic.evidenceIDs
                )
            )
            addEdge(
                from: targetEventNodeID,
                to: nodeID,
                relation: .candidateAssociation,
                confidence: statistic.confidence,
                temporalProximity: statistic.medianDelay,
                evidenceIDs: statistic.evidenceIDs
            )
        }

        for definition in catalog?.definitions ?? [] {
            let nodeID = "signal:\(definition.id)"
            addNode(
                PTProtocolResearchGraphNode(
                    id: nodeID,
                    kind: graphNodeKind(for: definition.transport),
                    title: definition.name,
                    evidenceIDs: definition.evidenceIDs
                )
            )
            addEdge(
                from: targetEventNodeID,
                to: nodeID,
                relation: .mapsTo,
                confidence: definition.confidence.score,
                temporalProximity: nil,
                evidenceIDs: definition.evidenceIDs
            )
        }

        return PTProtocolResearchGraph(nodes: Array(nodes.values), edges: Array(edges.values))
    }

    private static func nodeKind(for source: PTProtocolResearchTimelineSource) -> PTProtocolResearchGraphNodeKind {
        switch source {
        case .userMarker: return .vehicleEvent
        case .can: return .canSignal
        case .xp400BLE: return .xp400Signal
        case .obd: return .obdSignal
        case .unifiedTelemetry: return .telemetrySignal
        }
    }

    private static func graphNodeKind(for transport: PTSignalTransport) -> PTProtocolResearchGraphNodeKind {
        switch transport {
        case .can: return .canSignal
        case .xp400BLE: return .xp400Signal
        case .obd: return .obdSignal
        case .unifiedTelemetry: return .telemetrySignal
        }
    }
}
