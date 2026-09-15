//
//  PTProtocolResearchLabBuild63Tests.swift
//  PTSpeedTests
//
//  EN: Verifies Build 63 repeatable protocol research, candidate safety, correlation, graph, and replay.
//  ES: Verifica la investigación repetible, la seguridad de candidatos, la correlación, el grafo y la reproducción de Build 63.
//  中文：验证 Build 63 的重复协议研究、候选安全、跨协议关联、关系图和回放能力。
//

import Foundation
import XCTest
@testable import XP400Ride

final class PTProtocolResearchLabBuild63Tests: XCTestCase {
    func testRepeatedTrialsProduceCandidateStatisticsAndFalsePositiveReport() {
        let fixture = makeFixture()
        let report = PTProtocolResearchAnalyzer.analyze(
            experiment: fixture.experiment,
            captures: fixture.captures,
            configuration: PTProtocolResearchAnalysisConfiguration(beforeWindow: 1, afterWindow: 1),
            generatedAt: fixture.generatedAt
        )

        XCTAssertEqual(report.statistics.count, 1)
        guard let statistic = report.statistics.first else { return }
        XCTAssertEqual(statistic.key, PTCANCandidateKey(header: "0x321", byteIndex: 1, bitIndex: 5))
        XCTAssertEqual(statistic.activationTrials, 2)
        XCTAssertEqual(statistic.activationHits, 2)
        XCTAssertEqual(statistic.deactivationTrials, 2)
        XCTAssertEqual(statistic.deactivationHits, 2)
        XCTAssertEqual(statistic.sessions, 2)
        XCTAssertGreaterThan(statistic.backgroundComparisons, 0)
        XCTAssertEqual(statistic.backgroundChanges, 0)
        XCTAssertNotNil(statistic.medianDelay)
        XCTAssertNotNil(statistic.p95Delay)
        XCTAssertEqual(statistic.status, .candidate)
        XCTAssertEqual(report.groups.count, 1)
        XCTAssertEqual(report.falsePositives.count, 1)
        XCTAssertEqual(report.falsePositives[0].backgroundIsolation, 1, accuracy: 0.0001)
    }

    func testBackgroundMutationReducesCandidateConfidence() {
        let fixture = makeFixture()
        let cleanReport = PTProtocolResearchAnalyzer.analyze(
            experiment: fixture.experiment,
            captures: fixture.captures,
            configuration: PTProtocolResearchAnalysisConfiguration(beforeWindow: 1, afterWindow: 1),
            generatedAt: fixture.generatedAt
        )
        let noisyCaptures = fixture.captures.enumerated().map { index, capture in
            index == 0 ? captureWithBackgroundMutation(capture) : capture
        }
        let noisyReport = PTProtocolResearchAnalyzer.analyze(
            experiment: fixture.experiment,
            captures: noisyCaptures,
            configuration: PTProtocolResearchAnalysisConfiguration(beforeWindow: 1, afterWindow: 1),
            generatedAt: fixture.generatedAt
        )

        XCTAssertLessThan(noisyReport.statistics[0].backgroundIsolation, cleanReport.statistics[0].backgroundIsolation)
        XCTAssertLessThan(noisyReport.statistics[0].confidence, cleanReport.statistics[0].confidence)
        XCTAssertEqual(noisyReport.falsePositives[0].mutationRate, 0.25, accuracy: 0.0001)
    }

    func testCatalogRequiresExplicitPromotion() {
        let definition = PTVehicleSignalDefinition(
            id: "xp400.leftIndicator",
            name: "Left indicator",
            vehicleModel: "XP400 GT",
            transport: .can,
            frameIdentifier: "321",
            byteIndex: 1,
            bitIndex: 5,
            encoding: .boolean,
            confidence: .capturedRepeatable,
            evidenceIDs: [fixtureUUID("evidence")]
        )
        var catalog = PTVehicleSignalCatalog()

        catalog.insertCandidate(definition)
        XCTAssertEqual(catalog.definition(for: definition.id)?.status, .candidate)
        XCTAssertTrue(catalog.setStatus(.confirmed, for: definition.id))
        XCTAssertEqual(catalog.definition(for: definition.id)?.status, .confirmed)

        // EN: Automatic insertion cannot overwrite an explicit human confirmation.
        // ES: La inserción automática no puede sobrescribir una confirmación humana explícita.
        // 中文：自动插入不能覆盖用户已经明确确认的定义。
        catalog.insertCandidate(definition)
        XCTAssertEqual(catalog.definition(for: definition.id)?.status, .confirmed)
    }

    func testCorrelationGraphAndCrazyTraceReplayAreAuditableAndDeterministic() {
        let fixture = makeFixture()
        let first = PTProtocolResearchReplay.run(
            experiment: fixture.experiment,
            captures: fixture.captures,
            generatedAt: fixture.generatedAt
        )
        let second = PTProtocolResearchReplay.run(
            experiment: fixture.experiment,
            captures: fixture.captures,
            generatedAt: fixture.generatedAt
        )

        XCTAssertEqual(first.traceDocument, second.traceDocument)
        XCTAssertEqual(first.analysis, second.analysis)
        XCTAssertEqual(first.correlation, second.correlation)
        XCTAssertEqual(first.graph, second.graph)
        XCTAssertTrue(first.traceDocument.events.contains { event in
            if case .marker = event.payload { return true }
            return false
        })
        XCTAssertFalse(first.correlation.clusters.isEmpty)
        XCTAssertFalse(first.graph.nodes.isEmpty)
        XCTAssertFalse(first.graph.edges.isEmpty)
        XCTAssertTrue(first.graph.edges.allSatisfy { $0.confidence >= 0 && $0.confidence <= 1 })

        let replayed = PTProtocolResearchReplay.run(
            traceDocument: first.traceDocument,
            experiment: fixture.experiment,
            generatedAt: fixture.generatedAt
        )
        XCTAssertEqual(replayed.analysis, first.analysis)
    }

    func testResearchStorePersistsTrialsReportsAndExplicitPromotion() async throws {
        let fixture = makeFixture()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("build63-research-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try PTProtocolResearchStore(url: url)
        _ = try await store.upsert(fixture.experiment)
        let report = PTProtocolResearchAnalyzer.analyze(
            experiment: fixture.experiment,
            captures: fixture.captures,
            configuration: PTProtocolResearchAnalysisConfiguration(beforeWindow: 1, afterWindow: 1),
            generatedAt: fixture.generatedAt
        )
        try await store.save(report)

        let definition = PTVehicleSignalDefinition(
            id: "xp400.leftIndicator",
            name: "Left indicator",
            vehicleModel: "XP400 GT",
            transport: .can,
            frameIdentifier: "321",
            byteIndex: 1,
            bitIndex: 5,
            encoding: .boolean,
            confidence: .capturedRepeatable,
            evidenceIDs: statisticEvidenceIDs(from: report)
        )
        try await store.insertCandidates([definition], for: fixture.experiment.vehicleID)
        let candidateStatus = await store.catalog(for: fixture.experiment.vehicleID).definition(for: definition.id)?.status
        XCTAssertEqual(candidateStatus, .candidate)
        let promoted = try await store.promote(
            definitionID: definition.id,
            to: .confirmed,
            for: fixture.experiment.vehicleID
        )
        XCTAssertTrue(promoted)

        let reopened = try PTProtocolResearchStore(url: url)
        let storedExperiment = await reopened.experiment(for: fixture.experiment.id)
        let storedReport = await reopened.report(for: fixture.experiment.id)
        let storedStatus = await reopened.catalog(for: fixture.experiment.vehicleID).definition(for: definition.id)?.status
        XCTAssertEqual(storedExperiment?.trials.count, 2)
        XCTAssertEqual(storedReport?.statistics, report.statistics)
        XCTAssertEqual(storedStatus, .confirmed)
    }

    func testResearchStoreRejectsCorruptExistingFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("build63-corrupt-\(UUID().uuidString).json")
        try Data("not-json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try PTProtocolResearchStore(url: url)) { error in
            XCTAssertEqual(error as? PTProtocolResearchStoreError, .invalidData)
        }
    }
}

private struct PTProtocolResearchFixture {
    let experiment: PTCANExperiment
    let captures: [PTCANCaptureSession]
    let generatedAt: Date
}

private func makeFixture() -> PTProtocolResearchFixture {
    let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let vehicleID = fixtureUUID("vehicle")
    let captureIDs = [fixtureUUID("capture-1"), fixtureUUID("capture-2")]
    let trialIDs = [fixtureUUID("trial-1"), fixtureUUID("trial-2")]
    let activationIDs = [fixtureUUID("activation-1"), fixtureUUID("activation-2")]
    let deactivationIDs = [fixtureUUID("deactivation-1"), fixtureUUID("deactivation-2")]
    let captures = captureIDs.enumerated().map { index, captureID in
        makeCapture(
            id: captureID,
            sequenceOffset: index * 100,
            baseDate: generatedAt.addingTimeInterval(Double(index * 100)),
            activationID: activationIDs[index],
            deactivationID: deactivationIDs[index]
        )
    }
    let trials = captureIDs.enumerated().map { index, captureID in
        PTCANExperimentTrial(
            id: trialIDs[index],
            captureID: captureID,
            sessionID: fixtureUUID("session-\(index + 1)"),
            activationMarkerID: activationIDs[index],
            deactivationMarkerID: deactivationIDs[index],
            source: .live,
            createdAt: generatedAt
        )
    }
    let experiment = PTCANExperiment(
        id: fixtureUUID("experiment"),
        vehicleID: vehicleID,
        name: "Left indicator repeatability",
        targetEvent: .leftIndicator,
        trials: trials,
        createdAt: generatedAt,
        updatedAt: generatedAt,
        status: .analyzed
    )
    return PTProtocolResearchFixture(experiment: experiment, captures: captures, generatedAt: generatedAt)
}

private func makeCapture(
    id: UUID,
    sequenceOffset: Int,
    baseDate: Date,
    activationID: UUID,
    deactivationID: UUID
) -> PTCANCaptureSession {
    let base = baseDate.timeIntervalSince1970
    let frames: [(Double, String)] = [
        (0, "00 00 00 00"),
        (1, "00 00 00 00"),
        (2.25, "00 20 00 00"),
        (5, "00 20 00 00"),
        (6.25, "00 00 00 00"),
        (8, "00 00 00 00"),
        (9, "00 00 00 00")
    ]
    return PTCANCaptureSession(
        id: id,
        name: "Build 63 fixture",
        startedAt: baseDate,
        endedAt: baseDate.addingTimeInterval(10),
        filterHeader: nil,
        monitorProfile: .rawDLC,
        frames: frames.enumerated().map { index, item in
            PTCANFrame(
                timestamp: base + item.0,
                sequence: sequenceOffset + index,
                direction: .bus,
                rawLine: "321 \(item.1)",
                header: "321",
                dataHex: item.1,
                dlc: 4
            )
        },
        events: [
            PTCANCaptureEvent(id: activationID, name: "activation", timestamp: base + 2),
            PTCANCaptureEvent(id: deactivationID, name: "deactivation", timestamp: base + 6)
        ]
    )
}

private func fixtureUUID(_ seed: String) -> UUID {
    PTProtocolResearchMath.stableUUID("test:\(seed)")
}

private func captureWithBackgroundMutation(_ capture: PTCANCaptureSession) -> PTCANCaptureSession {
    let mutatedFrames = capture.frames.map { frame in
        guard frame.timestamp == capture.frames.map(\.timestamp).max() else { return frame }
        return PTCANFrame(
            timestamp: frame.timestamp,
            sequence: frame.sequence,
            direction: frame.direction,
            rawLine: "321 00 20 00 00",
            header: frame.header,
            dataHex: "00 20 00 00",
            dlc: frame.dlc
        )
    }
    return PTCANCaptureSession(
        id: capture.id,
        name: capture.name,
        startedAt: capture.startedAt,
        endedAt: capture.endedAt,
        filterHeader: capture.filterHeader,
        monitorProfile: capture.monitorProfile,
        frames: mutatedFrames,
        schemaVersion: capture.schemaVersion,
        events: capture.events,
        totalFrameCount: capture.totalFrameCount,
        retainedFrameCount: capture.retainedFrameCount,
        droppedFrameCount: capture.droppedFrameCount
    )
}

private func statisticEvidenceIDs(from report: PTCANExperimentAnalysisReport) -> [UUID] {
    report.statistics.flatMap(\.evidenceIDs)
}
