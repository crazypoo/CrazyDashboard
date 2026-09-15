//
//  PTReplayFixtureCatalog.swift
//  PTSpeedTests
//
//  EN: Deterministic, offline fixtures for XP400, ELM327, YMOBD, OTA, CAN, and combined replay paths.
//  ES: Fixtures deterministas y sin conexión para XP400, ELM327, YMOBD, OTA, CAN y rutas combinadas.
//  中文：为 XP400、ELM327、YMOBD、OTA、CAN 和组合回放提供确定性的离线样本。
//

import Foundation
@testable import XP400Ride

enum PTReplayFixtureCatalog {
    static let xp400FixtureIDs = [
        "normal_connect", "disconnect", "reconnect", "auth_success", "auth_failure",
        "credit_refill", "credit_stall", "malformed_frame", "navigation_start", "navigation_stop"
    ]

    static let obdFixtureIDs = [
        "elm_init_success", "elm_no_data", "elm_timeout", "pid_polling", "uds_positive",
        "uds_negative", "can_monitor", "bus_lease_restore"
    ]

    static let ymobdFixtureIDs = ["ymobd_detect", "ymobd_auth_success", "ymobd_auth_failure", "version_read", "firmware_check"]
    static let otaFixtureIDs = ["ota_prepare", "ota_progress", "ota_reconnect", "ota_success", "ota_verify_failure", "ota_restore_elm"]
    static let canFixtureIDs = ["can_event_window", "can_repeated_frame"]
    static let combinedFixtureIDs = ["normal_connect_with_obd", "combined_disconnect", "combined_reconnect"]

    static let allFixtureIDs = xp400FixtureIDs + obdFixtureIDs + ymobdFixtureIDs + otaFixtureIDs + canFixtureIDs + combinedFixtureIDs

    static func document(for fixtureID: String) -> PTCrazyTraceDocument {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let telemetry = PTUnifiedVehicleTelemetrySnapshot(
            values: [
                PTVehicleTelemetryResolvedValue(
                    signal: .speed,
                    value: .double(fixtureID.contains("navigation") ? 61 : 0),
                    source: .replay,
                    capturedAt: date,
                    freshness: .fresh,
                    confidence: 1,
                    isSynthetic: true
                ),
                PTVehicleTelemetryResolvedValue(
                    signal: .tcs,
                    value: .boolean(true),
                    source: .replay,
                    capturedAt: date,
                    freshness: .fresh,
                    confidence: 1,
                    isSynthetic: true
                )
            ],
            updatedAt: date,
            mode: .replay
        )

        var events: [PTCrazyTraceEvent] = [
            PTCrazyTraceEvent(
                sequence: 0,
                timestamp: date,
                elapsed: 0,
                domain: .vehicleTelemetry,
                direction: .state,
                source: .replay,
                payload: .telemetry(telemetry)
            )
        ]

        let isDisconnect = fixtureID.contains("disconnect") || fixtureID == "elm_no_data" || fixtureID == "elm_timeout"
        let isAuthFailure = fixtureID == "auth_failure"
        let isXP400 = isXP400Fixture(fixtureID)
        if isXP400 {
            events.append(protocolEvent(
                sequence: events.count,
                date: date.addingTimeInterval(1),
                elapsed: 1,
                domain: .xp400BLE,
                raw: isDisconnect ? "XP400 disconnect" : "XP400 connected",
                metadata: ["connected": isDisconnect ? "false" : "true"]
            ))
            events.append(protocolEvent(
                sequence: events.count,
                date: date.addingTimeInterval(2),
                elapsed: 2,
                domain: .xp400BLE,
                raw: isDisconnect || isAuthFailure ? "XP400 auth failure" : "XP400 auth success",
                metadata: ["authenticated": isDisconnect || isAuthFailure ? "false" : "true", "tcsMode": "mode1"]
            ))
        }

        if fixtureID.hasPrefix("elm_") || fixtureID == "pid_polling" || fixtureID == "uds_positive" || fixtureID == "uds_negative" || fixtureID == "can_monitor" || fixtureID == "bus_lease_restore" || fixtureID.contains("with_obd") {
            let ready = fixtureID == "elm_init_success" || fixtureID == "pid_polling" || fixtureID == "uds_positive" || fixtureID == "can_monitor" || fixtureID == "bus_lease_restore" || fixtureID.contains("with_obd")
            events.append(protocolEvent(
                sequence: events.count,
                date: date.addingTimeInterval(3),
                elapsed: 3,
                domain: .obd,
                raw: ready ? "ELM ready" : "ELM timeout",
                metadata: ["elmState": ready ? "ready" : "timeout"]
            ))
        }

        if fixtureID.hasPrefix("ymobd_") || fixtureID.hasPrefix("ota_") {
            events.append(protocolEvent(
                sequence: events.count,
                date: date.addingTimeInterval(4),
                elapsed: 4,
                domain: .ymobdAdapter,
                raw: "YMOBD metadata",
                metadata: [
                    "authenticated": fixtureID == "ymobd_auth_success" || fixtureID == "ymobd_detect" ? "true" : "false"
                ]
            ))
        }

        if fixtureID.hasPrefix("ota_") {
            events.append(protocolEvent(
                sequence: events.count,
                date: date.addingTimeInterval(5),
                elapsed: 5,
                domain: .adapterOTA,
                raw: "OTA state",
                metadata: ["otaState": fixtureID == "ota_success" ? "completed" : "prepared"]
            ))
        }

        return PTCrazyTraceDocument(
            traceID: UUID(uuidString: "00000000-0000-0000-0000-000000000062")!,
            name: fixtureID,
            vehicleID: "fixture-xp400",
            startedAt: date,
            endedAt: date.addingTimeInterval(6),
            events: events
        )
    }

    static func expectedResult(for fixtureID: String) -> PTCrazyTraceExpectedResult {
        let hasConnection = isXP400Fixture(fixtureID)
        let disconnected = fixtureID.contains("disconnect") || fixtureID == "elm_no_data" || fixtureID == "elm_timeout"
        let authFailure = fixtureID == "auth_failure"
        var assertions: [PTReplayAssertion] = [
            PTReplayAssertion(timestamp: 0, path: "telemetry.speed", expected: .double(fixtureID.contains("navigation") ? 61 : 0)),
            PTReplayAssertion(timestamp: 0, path: "telemetry.tcs", expected: .boolean(true))
        ]
        if hasConnection {
            assertions.append(PTReplayAssertion(timestamp: 1, path: "xp400.connected", expected: .boolean(!disconnected)))
            assertions.append(PTReplayAssertion(timestamp: 2, path: "xp400.authenticated", expected: .boolean(!disconnected && !authFailure)))
        }
        if fixtureID.hasPrefix("elm_") || fixtureID == "pid_polling" || fixtureID == "uds_positive" || fixtureID == "uds_negative" || fixtureID == "can_monitor" || fixtureID == "bus_lease_restore" || fixtureID.contains("with_obd") {
            let ready = fixtureID == "elm_init_success" || fixtureID == "pid_polling" || fixtureID == "uds_positive" || fixtureID == "can_monitor" || fixtureID == "bus_lease_restore" || fixtureID.contains("with_obd")
            assertions.append(PTReplayAssertion(timestamp: 3, path: "obd.elmState", expected: .string(ready ? "ready" : "timeout")))
        }
        if fixtureID == "ymobd_auth_success" || fixtureID == "ymobd_auth_failure" {
            assertions.append(PTReplayAssertion(
                timestamp: 4,
                path: "ymobd.authenticated",
                expected: .boolean(fixtureID == "ymobd_auth_success")
            ))
        }
        if fixtureID.hasPrefix("ota_") {
            assertions.append(PTReplayAssertion(timestamp: 5, path: "ota.state", expected: .string(fixtureID == "ota_success" ? "completed" : "prepared")))
        }
        return PTCrazyTraceExpectedResult(fixtureID: fixtureID, assertions: assertions)
    }

    private static func protocolEvent(
        sequence: Int,
        date: Date,
        elapsed: TimeInterval,
        domain: PTTraceDomain,
        raw: String,
        metadata: [String: String]
    ) -> PTCrazyTraceEvent {
        PTCrazyTraceEvent(
            sequence: sequence,
            timestamp: date,
            elapsed: elapsed,
            domain: domain,
            direction: .state,
            source: .replay,
            payload: .protocolMessage(PTTraceProtocolPayload(raw: raw, metadata: metadata))
        )
    }

    private static func isXP400Fixture(_ fixtureID: String) -> Bool {
        xp400FixtureIDs.contains(fixtureID) || combinedFixtureIDs.contains(fixtureID)
    }
}
