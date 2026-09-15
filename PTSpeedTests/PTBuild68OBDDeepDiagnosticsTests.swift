//
//  PTBuild68OBDDeepDiagnosticsTests.swift
//  PTSpeedTests
//
//  EN: Pure Build 68 OBD parser, evidence, and telemetry-quality regression tests.
//  ES: Pruebas de regresión puras del analizador OBD, la evidencia y la calidad de telemetría de Build 68.
//  中文：Build 68 OBD 解析、证据和遥测质量的纯数据回归测试。
//

import Foundation
import XCTest
@testable import XP400Ride

@MainActor
final class PTBuild68OBDDeepDiagnosticsTests: XCTestCase {
    // EN: ATD1 DLC must be removed from the transport frame without losing application payload bytes.
    // ES: El DLC de ATD1 debe quitarse del marco de transporte sin perder bytes de la carga de aplicación.
    // 中文：ATD1 的 DLC 必须从传输帧中移除，同时不能丢失业务 Payload 字节。
    func testELMHeaderAndDLCStayOutsidePayload() {
        let response = "7E8 06 41 0C 1F A0\r\n>"

        XCTAssertEqual(
            PTBuild68ResponseParser.payloadHex(for: "010C", response: response),
            "0C1FA0"
        )
        XCTAssertEqual(
            PTBuild68ResponseParser.responseStatus(for: "010C", response: response),
            .success
        )
    }

    // EN: Capability masks must preserve continuation pages and the documented Mode 09 identifiers.
    // ES: Las máscaras de capacidad deben conservar las páginas de continuación y los identificadores Mode 09 documentados.
    // 中文：能力位图必须保留续页信息，并正确识别文档中的 Mode 09 标识符。
    func testCapabilityContinuationAndMode09Identifiers() {
        let mode01 = PTBuild68ResponseParser.parseCapability(
            command: "0100",
            response: "7E8 06 41 00 BE 3E B0 13"
        )
        XCTAssertEqual(mode01.mask, 0xBE3EB013)
        XCTAssertTrue(mode01.hasContinuation)
        XCTAssertTrue(mode01.supportedIdentifiers.contains("0101"))

        let mode09 = PTBuild68ResponseParser.parseCapability(
            command: "0900",
            response: "7E8 06 49 00 15 40 00 00"
        )
        XCTAssertEqual(mode09.mask, 0x15400000)
        XCTAssertEqual(
            Set(mode09.supportedIdentifiers),
            Set(["0904", "0906", "0908", "090A"])
        )

        var profile = PTBuild68CapabilityProfile()
        profile.merge(mode01)
        profile.merge(mode09)
        XCTAssertTrue(profile.supports("0101"))
        XCTAssertTrue(profile.mode09PIDs.contains("090A"))

    }

    // EN: Confirmed, pending, permanent, and negative responses retain their distinct semantics.
    // ES: Las respuestas confirmadas, pendientes, permanentes y negativas conservan semánticas distintas.
    // 中文：已确认、待定、永久故障和否定响应必须保留各自语义。
    func testDTCNegativeAndFreezeFrameParsing() {
        let sessionID = UUID()
        let confirmed = PTBuild68ResponseParser.parseDTCs(
            response: "7E8 04 43 01 07 60",
            source: .confirmed,
            sessionID: sessionID
        )
        XCTAssertEqual(confirmed.map(\.code), ["P0107"])
        XCTAssertEqual(confirmed.first?.source, .confirmed)

        XCTAssertEqual(
            PTBuild68ResponseParser.responseStatus(for: "03", response: "7E8 03 7F 22 31"),
            .negativeResponse
        )
        XCTAssertEqual(
            PTBuild68ResponseParser.negativeResponseCode(
                in: "7E8 03 7F 22 31",
                command: "22F190"
            ),
            "31"
        )

        let freeze = PTBuild68ResponseParser.parseFreezeFrameValue(
            pid: "0C",
            response: "7E8 06 42 0C 1A F8 00 00"
        )
        XCTAssertEqual(freeze?.numericValue ?? 0, 1726, accuracy: 0.001)
    }

    // EN: DLC-prefixed ISO-TP continuation frames must not leak transport bytes into an identity payload.
    // ES: Las tramas de continuación ISO-TP con DLC no deben filtrar bytes de transporte al payload de identidad.
    // 中文：带 DLC 的 ISO-TP 连续帧不能把传输字节混入身份 Payload。
    func testDLCAndISOTPContinuationFramesStaySeparate() {
        let response = "7E8 08 10 11 49 04 58 50 34 30\n7E8 08 21 45 35 34 30 30 30 33\n7E8 06 22 37 30 30 30 30"
        XCTAssertEqual(
            PTBuild68ResponseParser.parseCalibrationIDs(response: response),
            ["XP40E54000370000"]
        )
    }

    // EN: ECU fingerprinting is deterministic for the same identity evidence and preserves multiple records.
    // ES: La huella de ECU es determinista para la misma evidencia y conserva varios registros.
    // 中文：相同 ECU 身份证据必须生成稳定指纹，并保留多个 CALID/CVN 记录。
    func testECUFingerprintAndMultipleCalibrationRecords() {
        let records = [
            PTBuild68CalibrationRecord(calibrationID: "1179713900001953", cvn: "00001131"),
            PTBuild68CalibrationRecord(calibrationID: "XP40E54000370000", cvn: "0000DDE6")
        ]
        let first = PTBuild68ResponseParser.makeFingerprint(
            rxAddress: 0x7E8,
            ecuName: "Engine ECU",
            calibrationRecords: records,
            protocolName: "ISO 15765-4 (CAN 11/500)"
        )
        let second = PTBuild68ResponseParser.makeFingerprint(
            rxAddress: 0x7E8,
            ecuName: "Engine ECU",
            calibrationRecords: records.reversed(),
            protocolName: "ISO 15765-4 (CAN 11/500)"
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 64)
    }

    // EN: A single NO DATA is temporary; repeated failures without history are the only path to unsupported.
    // ES: Un solo NO DATA es temporal; solo varios fallos sin historial llevan a unsupported.
    // 中文：单次 NO DATA 只能是临时不可用；没有历史成功记录时连续失败才可判定 unsupported。
    func testPIDAvailabilitySeparatesTransientFailureFromUnsupported() {
        var state = PTBuild68PIDRuntimeState()
        state.recordFailure()
        XCTAssertEqual(state.availability(), .temporarilyUnavailable)

        state.recordFailure()
        state.recordFailure()
        XCTAssertEqual(state.availability(), .unsupported)

        state.markCapability(true)
        XCTAssertNotEqual(state.availability(), .unsupported)
        state.recordSuccess(latency: 0.25)
        XCTAssertEqual(state.availability(), .supported)
        XCTAssertEqual(state.successRate, 0.25, accuracy: 0.001)
    }

    // EN: Voltage domains stay separate and relative throttle wins over absolute throttle.
    // ES: Los dominios de voltaje permanecen separados y el acelerador relativo tiene prioridad.
    // 中文：适配器电压与 ECU 电压保持分离，Relative Throttle 优先于 Absolute Throttle。
    func testVoltageAndThrottleSemantics() {
        let voltage = PTBuild68VoltageSnapshot(adapterVoltage: 12.3, controlModuleVoltage: 14.648)
        XCTAssertTrue(voltage.hasDiscrepancy)
        XCTAssertEqual(voltage.delta ?? 0, 2.348, accuracy: 0.001)

        let throttle = PTBuild68ResponseParser.preferredThrottle(relative: 0, absolute: 9.4)
        XCTAssertEqual(throttle.source, .relative)
        XCTAssertEqual(throttle.percent ?? -1, 0, accuracy: 0.001)
    }

    // EN: Engine runtime produces a stable start-time estimate and the scheduler keeps capability reads out of Tier A.
    // ES: El tiempo de motor produce una estimación estable de arranque y el planificador mantiene las capacidades fuera de Tier A.
    // 中文：发动机运行时间可以推导启动时刻，轮询建议不会把能力探测放入 Tier A。
    func testRuntimeAndAdaptivePollingRecommendation() {
        let runtime = PTBuild68ResponseParser.parseEngineRuntime(
            response: "7E8 04 41 1F 00 32"
        )
        XCTAssertEqual(runtime, 50)

        let recommendations = PTBuild68AdaptivePollScheduler.recommendations(
            supportedCommands: ["010C", "010D", "0145", "0111", "0105", "090A"],
            runtimeStates: [:]
        )
        XCTAssertEqual(recommendations.first?.tier, .tierA)
        XCTAssertFalse(recommendations.first?.commands.contains("090A") == true)
        XCTAssertTrue(recommendations.contains { $0.tier == .tierD && $0.commands.contains("090A") })
    }

    // EN: Capability pages stay out of every runtime polling tier.
    // ES: Las páginas de capacidad quedan fuera de todos los niveles de sondeo en tiempo real.
    // 中文：能力页不得进入任何实时轮询层级。
    func testCapabilityPagesNeverEnterRuntimeRecommendations() {
        XCTAssertTrue(PTBuild68CommandCatalog.isCapabilityOnlyCommand("0100"))
        let recommendations = PTBuild68AdaptivePollScheduler.recommendations(
            supportedCommands: ["0100", "0120", "0140", "0900", "010C", "010D"],
            runtimeStates: [:]
        )
        XCTAssertFalse(recommendations.contains { $0.commands.contains("0100") })
        XCTAssertFalse(recommendations.contains { $0.commands.contains("0120") })
        XCTAssertFalse(recommendations.contains { $0.commands.contains("0900") })
        XCTAssertTrue(recommendations.contains { $0.commands.contains("010C") })
    }

    // EN: Default trace redaction masks adapter secrets and MAC middle octets while retaining CALID/CVN research text.
    // ES: La redacción predeterminada oculta secretos y octetos centrales de MAC, pero conserva CALID/CVN para investigación.
    // 中文：默认日志脱敏会隐藏适配器密钥和 MAC 中间段，同时保留 CALID/CVN 研究文本。
    func testTraceRedactionDefault() {
        let redacted = PTBuild68TraceRedactor.redact(
            "MAC=D9:F8:15:9C:B6:7E crypt:E06AE2B2 AT+SETCRYPT802B378D CALID=XP40E54000370000 CVN=0000DDE6"
        )
        XCTAssertFalse(redacted.contains("E06AE2B2"))
        XCTAssertFalse(redacted.contains("802B378D"))
        XCTAssertFalse(redacted.contains("D9:F8:15:9C:B6:7E"))
        XCTAssertTrue(redacted.contains("XP40E54000370000"))
        XCTAssertTrue(redacted.contains("0000DDE6"))
    }
}
