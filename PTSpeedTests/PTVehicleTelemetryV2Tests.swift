//
//  PTVehicleTelemetryV2Tests.swift
//  PTSpeedTests
//
//  EN: Regression tests for the Build 58 unified telemetry and replay boundary.
//  ES: Pruebas de regresión para el límite unificado de telemetría y reproducción de Build 58.
//  中文：覆盖 Build 58 统一遥测与回放边界的回归测试。
//

import XCTest
import CoreLocation
import PooTools
@testable import XP400Ride

@MainActor
final class PTVehicleTelemetryV2Tests: XCTestCase {
    func testCanonicalSourcesKeepAdapterAndVehicleDomainsSeparate() {
        XCTAssertEqual(PTVehicleTelemetrySource.xp400BLE.domain, .xp400BLE)
        XCTAssertEqual(PTVehicleTelemetrySource.obd.domain, .obd)
        XCTAssertEqual(PTVehicleTelemetrySource.replay.domain, .replay)
        XCTAssertFalse(PTVehicleTelemetrySource.obd.isMock)

        let adapter = PTOBDAdapterSnapshot(
            vendor: "YMOBD",
            model: "XP400",
            firmwareVersion: "2.5.0",
            transport: .mock,
            isOfficialYMOBD: true,
            mode: .elm
        )
        XCTAssertEqual(adapter.vendor, "YMOBD")
        XCTAssertEqual(adapter.mode, .elm)
    }

    func testAdaptersNormalizeLegacySourcesWithoutYMOBDTelemetrySource() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let dashboardSpeed = PTTelemetrySample(value: 52.0, source: .dashboardBluetooth, capturedAt: date)
        let dashboardFuel = PTTelemetrySample(value: 74, source: .dashboardMock, capturedAt: date)
        let obdSpeed = PTTelemetrySample(value: 50.0, source: .obdBluetooth, capturedAt: date)
        let snapshot = PTVehicleTelemetrySnapshot(
            dashboardSpeedKmh: dashboardSpeed,
            obdSpeedKmh: obdSpeed,
            fuelPercent: dashboardFuel,
            updatedAt: date
        )

        let dashboardObservations = PTXP400TelemetryAdapter.observations(from: snapshot)
        let obdObservations = PTOBDTelemetryAdapter.observations(from: snapshot)

        XCTAssertEqual(dashboardObservations.first(where: { $0.signal == .speed })?.source, .xp400BLE)
        XCTAssertTrue(dashboardObservations.first(where: { $0.signal == .fuel })?.isSynthetic == true)
        XCTAssertEqual(obdObservations.first(where: { $0.signal == .speed })?.source, .obd)
        XCTAssertFalse(obdObservations.contains { $0.source.rawValue.lowercased().contains("ymobd") })
    }

    func testResolverPrefersFreshValuesAndFallsBackToLowerPriorityWhenStale() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var resolver = PTVehicleTelemetryResolver()
        resolver.ingest([
            PTVehicleTelemetryObservation(
                signal: .speed,
                value: .double(90),
                source: .xp400BLE,
                capturedAt: date.addingTimeInterval(-10)
            ),
            PTVehicleTelemetryObservation(
                signal: .speed,
                value: .double(48),
                source: .obd,
                capturedAt: date
            )
        ])

        let fallback = resolver.snapshot(at: date)
        XCTAssertEqual(fallback.speedKmh ?? 0, 48, accuracy: 0.001)
        XCTAssertEqual(fallback.value(for: .speed)?.source, .obd)

        resolver.ingest([
            PTVehicleTelemetryObservation(
                signal: .speed,
                value: .double(92),
                source: .xp400BLE,
                capturedAt: date.addingTimeInterval(0.1)
            )
        ])
        let preferred = resolver.snapshot(at: date.addingTimeInterval(0.1))
        XCTAssertEqual(preferred.speedKmh ?? 0, 92, accuracy: 0.001)
        XCTAssertEqual(preferred.value(for: .speed)?.source, .xp400BLE)
    }

    func testSyntheticValueCannotReplaceARealValueFromTheSameCanonicalDomain() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var resolver = PTVehicleTelemetryResolver()
        resolver.ingest([
            PTVehicleTelemetryObservation(
                signal: .speed,
                value: .double(80),
                source: .xp400BLE,
                capturedAt: date.addingTimeInterval(-10),
                isSynthetic: false
            ),
            PTVehicleTelemetryObservation(
                signal: .speed,
                value: .double(1),
                source: .xp400BLE,
                capturedAt: date,
                isSynthetic: true
            )
        ])

        let resolved = resolver.snapshot(at: date)
        XCTAssertEqual(resolved.speedKmh ?? 0, 80, accuracy: 0.001)
        XCTAssertFalse(resolved.value(for: .speed)?.isSynthetic == true)
    }

    func testSnapshotAndTraceRoundTripPreserveAllDomains() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let value = PTVehicleTelemetryResolvedValue(
            signal: .speed,
            value: .double(42),
            source: .obd,
            capturedAt: date,
            freshness: .fresh,
            confidence: 0.9,
            isSynthetic: false
        )
        let snapshot = PTUnifiedVehicleTelemetrySnapshot(values: [value], updatedAt: date)
        let events = [
            PTCrazyTraceEvent(
                sequence: 0,
                timestamp: date,
                elapsed: 0,
                domain: .vehicleTelemetry,
                direction: .state,
                source: .live,
                payload: .telemetry(snapshot)
            ),
            PTCrazyTraceEvent(
                sequence: 1,
                timestamp: date.addingTimeInterval(0.5),
                elapsed: 0.5,
                domain: .xp400BLE,
                direction: .input,
                source: .live,
                payload: .protocolMessage(PTTraceProtocolPayload(raw: "XP400 event"))
            ),
            PTCrazyTraceEvent(
                sequence: 2,
                timestamp: date.addingTimeInterval(0.75),
                elapsed: 0.75,
                domain: .obd,
                direction: .input,
                source: .live,
                payload: .protocolMessage(PTTraceProtocolPayload(raw: "010C"))
            ),
            PTCrazyTraceEvent(
                sequence: 3,
                timestamp: date.addingTimeInterval(1),
                elapsed: 1,
                domain: .ymobdAdapter,
                direction: .state,
                source: .live,
                payload: .adapter(PTTraceAdapterPayload(snapshot: .unavailable))
            ),
            PTCrazyTraceEvent(
                sequence: 4,
                timestamp: date.addingTimeInterval(2),
                elapsed: 2,
                domain: .adapterOTA,
                direction: .output,
                source: .live,
                payload: .protocolMessage(PTTraceProtocolPayload(raw: "OTA evidence"))
            )
        ]
        let document = PTCrazyTraceDocument(
            name: "Build 58 Trace",
            startedAt: date,
            endedAt: date.addingTimeInterval(2),
            events: events
        )

        XCTAssertTrue(document.hasConsistentDomains)
        let data = try JSONEncoder.crazyTraceEncoder.encode(document)
        let decoded = try JSONDecoder.crazyTraceDecoder.decode(PTCrazyTraceDocument.self, from: data)
        XCTAssertEqual(decoded, document)
        XCTAssertEqual(
            decoded.events.map(\.domain),
            [.vehicleTelemetry, .xp400BLE, .obd, .ymobdAdapter, .adapterOTA]
        )
    }

    func testGPSAndMotionAdaptersRejectInvalidCoordinatesAndKeepMotionSeparate() {
        let invalidLocation = CLLocation(latitude: 120, longitude: 300)
        XCTAssertTrue(PTGPSMotionTelemetryAdapter.observations(from: invalidLocation).isEmpty)

        let motion = PTMotion.shared.currentData
        let observations = PTGPSMotionTelemetryAdapter.observations(from: motion)
        XCTAssertEqual(observations.count, 6)
        XCTAssertTrue(observations.allSatisfy { $0.source == .motion })
    }

    func testReplayPlayerEmitsEventsOnlyAndMaintainsOrder() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let document = PTCrazyTraceDocument(
            name: "Replay",
            startedAt: date,
            endedAt: date.addingTimeInterval(1),
            events: [
                PTCrazyTraceEvent(
                    sequence: 0,
                    timestamp: date,
                    elapsed: 0,
                    domain: .vehicleTelemetry,
                    direction: .state,
                    source: .replay,
                    payload: .telemetry(.empty)
                ),
                PTCrazyTraceEvent(
                    sequence: 1,
                    timestamp: date.addingTimeInterval(1),
                    elapsed: 1,
                    domain: .adapterOTA,
                    direction: .output,
                    source: .replay,
                    payload: .text("no device call")
                )
            ]
        )
        let player = PTCrazyTraceReplayPlayer(document: document)
        var domains: [PTTraceDomain] = []
        player.onEvent = { domains.append($0.domain) }
        player.seek(to: document.duration)

        XCTAssertEqual(domains, [.vehicleTelemetry, .adapterOTA])
        XCTAssertFalse(player.isPlaying)
    }

    func testRecorderIsBoundedAndStopsCleanly() {
        let recorder = PTCrazyTraceRecorder.shared
        recorder.stop()
        XCTAssertNotNil(recorder.start(name: "Bounded"))
        for _ in 0...PTCrazyTraceRecorder.maximumEventCount {
            recorder.record(domain: .system, payload: .text("event"))
        }
        XCTAssertEqual(recorder.eventCount, PTCrazyTraceRecorder.maximumEventCount)
        XCTAssertEqual(recorder.droppedEventCount, 1)
        XCTAssertNotNil(recorder.stop())
        XCTAssertFalse(recorder.isRecording)
    }
}
