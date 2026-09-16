//
//  PTBuild69ProtocolSemanticTests.swift
//  PTSpeedTests
//
//  EN: Regression tests for Build 69 semantic decoding, protocol layering, and evidence boundaries.
//  ES: Pruebas de regresión de Build 69 para decodificación semántica, capas de protocolo y límites de evidencia.
//  中文：Build 69 语义解码、协议分层和证据边界回归测试。
//

import Foundation
import XCTest
@testable import XP400Ride

@MainActor
final class PTBuild69ProtocolSemanticTests: XCTestCase {
    // EN: DATA2 RTC uses only the documented high bits and preserves low bits as independent evidence.
    // ES: El RTC DATA2 usa solo los bits altos documentados y conserva los bits bajos como evidencia independiente.
    // 中文：DATA2 RTC 只使用文档确认的高位，并将低位作为独立证据保留。
    func testData2ClockAndLowBits() {
        let payload = Data([15 << 2 | 0x03, 27 << 2 | 0x01, 12 << 3 | 0x05, 120, 70, 144, 0xFF, 0xFF])
        let frame = PTXP400SemanticDecoder.decode(frameID: PTXP400BLEProtocol.data2FrameID, payload: payload)

        XCTAssertEqual(frame?.fields.first { $0.id == "data2.rtc.second" }?.normalizedValue, "15")
        XCTAssertEqual(frame?.fields.first { $0.id == "data2.rtc.minute" }?.normalizedValue, "27")
        XCTAssertEqual(frame?.fields.first { $0.id == "data2.rtc.hour" }?.normalizedValue, "12")
        XCTAssertEqual(frame?.fields.first { $0.id == "data2.flags.byte0Low2" }?.raw, Data([0x03]))
        XCTAssertEqual(frame?.fields.first { $0.id == "data2.flags.byte2Low3" }?.raw, Data([0x05]))
        XCTAssertEqual(frame?.fields.first { $0.id == "data2.battery" }?.normalizedValue, "14.4")
        XCTAssertEqual(frame?.fields.first { $0.id == "data2.engine.statusRaw" }?.role, .provisional)
        XCTAssertEqual(frame?.fields.first { $0.id == "data2.engine.statusRaw" }?.normalizedValue, "1")
    }

    // EN: TCS mode and bit 7 are separate fields; bit 7 is not renamed as confirmed readiness.
    // ES: El modo TCS y el bit 7 son campos separados; el bit 7 no se renombra como disponibilidad confirmada.
    // 中文：TCS 模式与 bit7 分离，bit7 不被错误命名为已确认的就绪状态。
    func testControlTCSUsesFullByteAndKeepsBitSevenCandidate() {
        let payload = Data([5, 0, 0, 0x82, 0x01, 0x90, 0x00, 0x64])
        let frame = PTXP400SemanticDecoder.decode(frameID: PTXP400BLEProtocol.controlFrameID, payload: payload)

        XCTAssertEqual(frame?.fields.first { $0.id == "control.tcsMode" }?.normalizedValue, "2")
        XCTAssertEqual(frame?.fields.first { $0.id == "control.tcsStatusCandidateBit7" }?.raw, Data([0x80]))
        XCTAssertEqual(frame?.fields.first { $0.id == "control.tcsStatusCandidateBit7" }?.role, .candidate)
    }

    // EN: The rolling counter uses modulo-256 arithmetic and therefore survives wrap-around.
    // ES: El contador usa aritmética módulo 256 y sobrevive al desbordamiento.
    // 中文：滚动计数器使用模 256 运算，能够正确处理回绕。
    func testRollingCounterWrap() {
        XCTAssertEqual(PTDashboardRollingCounter.delta(from: 255, to: 3), 4)
        XCTAssertEqual(PTXP400RollingTick.moduloDelta(from: 0xFA, to: 0xFF), 5)
        XCTAssertEqual(PTXP400RollingTick.moduloDelta(from: 0xFF, to: 0x04), 5)
    }

    // EN: ABS wheel speed is confirmed independently from its unresolved status byte and FF padding.
    // ES: La velocidad de rueda ABS se confirma independientemente del estado no resuelto y del relleno FF.
    // 中文：ABS 轮速与未解析状态字节、FF 填充区分别处理。
    func testABSStatusIsUnknownAndPaddingIsSentinel() {
        let payload = Data([0x01, 0xF4, 0x02, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        let frame = PTXP400SemanticDecoder.decode(frameID: PTXP400BLEProtocol.absFrameID, payload: payload)

        XCTAssertEqual(frame?.fields.first { $0.id == "abs.frontSpeed" }?.normalizedValue, "5.00")
        XCTAssertEqual(frame?.fields.first { $0.id == "abs.statusCandidate" }?.quality, .experimental)
        XCTAssertEqual(frame?.fields.first { $0.id == "abs.padding3to7" }?.quality, .sentinel)

        let changedPadding = PTXP400SemanticDecoder.decode(frameID: PTXP400BLEProtocol.absFrameID, payload: Data([0x01, 0xF4, 0x02, 0x00, 0xFF, 0xFF, 0xFF, 0xFF]))
        XCTAssertEqual(changedPadding?.fields.first { $0.id == "abs.padding3to7" }?.quality, .experimental)
    }

    // EN: A byte inspector separates known masks from unresolved candidate bits.
    // ES: El inspector separa las máscaras conocidas de los bits candidatos no resueltos.
    // 中文：字节 Inspector 将已知掩码与未解析候选位分开。
    func testFrameInspectorMasksAndBuild69Roles() {
        let data3 = PTXP400SemanticDecoder.decode(
            frameID: PTXP400BLEProtocol.data3FrameID,
            payload: Data([0x01, 0x2C, 0x10, 0x00, 0x64, 0x04, 0x20, 0x30])
        )!
        XCTAssertEqual(data3.fields.first { $0.id == "data3.configurationFlagsA" }?.role, .candidate)
        XCTAssertEqual(data3.fields.first { $0.id == "data3.maintenance" }?.role, .provisional)
        XCTAssertEqual(data3.fields.first { $0.id == "data3.language" }?.role, .provisional)

        let inspection = PTXP400FrameInspector.inspect(frame: data3)
        XCTAssertEqual(inspection.bytes.count, 8)
        XCTAssertEqual(inspection.bytes[2].unknownMask, 0x10)
        XCTAssertEqual(inspection.bytes[3].knownMask, 0xFF)
        XCTAssertTrue(inspection.unknownMaskHex.contains("10"))
    }

    // EN: The one-byte 0x01 status poll is known and must not be reported as a malformed framed packet.
    // ES: El sondeo de estado 0x01 de un byte es conocido y no debe marcarse como trama mal formada.
    // 中文：单字节 0x01 状态轮询是已知命令，不能再标记为非法包络。
    func testStatusPollIsKnown() {
        XCTAssertEqual(PTXP400OutboundPacketClassifier.classify(Data([0x01])), .statusPoll)
    }

    // EN: A two-character token 06 is ISO-TP data when the ELM output does not expose a separate DLC token.
    // ES: El token de dos caracteres 06 es un dato ISO-TP cuando ELM no expone un DLC separado.
    // 中文：当 ELM 没有单独输出 DLC 时，双字符 Token 06 必须作为 ISO-TP 数据保留。
    func testELMNormalizerSeparatesOptionalDLCFromISOTransportData() {
        let implicitDLC = PTBuild69ELMNormalizer.normalize(
            raw: "7E8 06 41 0C 00 64 00 00 00",
            command: "010C"
        )
        XCTAssertEqual(implicitDLC.status, .positive)
        XCTAssertNil(implicitDLC.frames.first?.declaredDLC)
        XCTAssertEqual(implicitDLC.frames.first?.data, Data([0x06, 0x41, 0x0C, 0x00, 0x64, 0x00, 0x00, 0x00]))
        XCTAssertEqual(implicitDLC.combinedData, Data([0x41, 0x0C, 0x00, 0x64, 0x00, 0x00]))

        let explicitDLC = PTBuild69ELMNormalizer.normalize(
            raw: "7E8 8 06 41 0C 00 64 00 00 00",
            command: "010C"
        )
        XCTAssertEqual(explicitDLC.frames.first?.declaredDLC, 8)
        XCTAssertEqual(explicitDLC.combinedData, implicitDLC.combinedData)

        let noData = PTBuild69ELMNormalizer.normalize(raw: "NO DATA\n>", command: "010C")
        XCTAssertEqual(noData.status, .noData)
        XCTAssertTrue(noData.frames.isEmpty)
    }

    // EN: OBD modes 03, 07, and 02 produce distinct DTC observations instead of a generic parser success.
    // ES: Los modos OBD 03, 07 y 02 producen observaciones DTC distintas, no un éxito genérico.
    // 中文：OBD Mode03、07、02 产生明确的 DTC 状态，而不是笼统的解析成功。
    func testOBD2DTCStatus() {
        let confirmed = PTBuild69ProtocolRouter.route(command: "03", rawResponse: "7E8 4 43 01 07 60")
        guard case .obd2(let response) = confirmed else {
            return XCTFail("Expected OBD-II response")
        }
        XCTAssertEqual(response.positiveService, 0x43)
        XCTAssertEqual(response.dtcStatus, .values(["P0107"]))

        let none = PTBuild69ProtocolRouter.route(command: "07", rawResponse: "7E8 3 47 00 00")
        guard case .obd2(let noneResponse) = none else {
            return XCTFail("Expected pending DTC response")
        }
        XCTAssertEqual(noneResponse.dtcStatus, .confirmedNone)
    }

    // EN: UDS 0x62 and 0x7F retain positive DID and negative NRC semantics.
    // ES: UDS 0x62 y 0x7F conservan la semántica DID positiva y NRC negativa.
    // 中文：UDS 0x62 和 0x7F 分别保留 DID 正响应与 NRC 否定响应语义。
    func testUDSPositiveAndNegativeResponses() {
        let positive = PTBuild69ProtocolRouter.route(command: "22F190", rawResponse: "7E8 4 62 F1 90 41")
        guard case .uds(let positiveResponse) = positive else {
            return XCTFail("Expected UDS response")
        }
        XCTAssertEqual(positiveResponse.did, "F190")
        XCTAssertEqual(positiveResponse.payload, Data([0x41]))
        XCTAssertTrue(positiveResponse.isPositive)

        let negative = PTBuild69ProtocolRouter.route(command: "22F190", rawResponse: "7E8 3 7F 22 31")
        guard case .uds(let negativeResponse) = negative else {
            return XCTFail("Expected UDS negative response")
        }
        XCTAssertEqual(negativeResponse.negativeResponse?.requestedService, 0x22)
        XCTAssertEqual(negativeResponse.negativeResponse?.negativeResponseCode, 0x31)
    }

    // EN: Multi-frame DID data is reassembled after PCI and DLC removal, never exposing transport bytes as VIN data.
    // ES: Los datos DID de varias tramas se reensamblan después de quitar PCI y DLC, sin exponer bytes de transporte como VIN.
    // 中文：多帧 DID 数据在移除 PCI 和 DLC 后拼接，不能把传输字节当成 VIN。
    func testUDSMultiFrameReassembly() {
        let response = "7E8 8 10 0E 62 F1 90 31 32 33 34\n7E8 8 21 35 36 37 38 39 30 31\n7E8 3 22 32 33"
        let routed = PTBuild69ProtocolRouter.route(command: "22F190", rawResponse: response)
        guard case .uds(let value) = routed else {
            return XCTFail("Expected UDS multi-frame response")
        }
        XCTAssertEqual(value.did, "F190")
        XCTAssertEqual(value.payload, Data("12345678901".utf8))
    }

    // EN: A sentinel battery byte yields no numeric observation, while zero remains a valid numeric value.
    // ES: Un byte de batería centinela no produce observación numérica, mientras cero sigue siendo válido.
    // 中文：电池哨兵字节不会产生数值观测，而 0 仍然是合法数值。
    func testUnavailableDoesNotBecomeZero() {
        let unavailable = PTXP400SemanticDecoder.decode(frameID: PTXP400BLEProtocol.data2FrameID, payload: Data([0, 0, 0, 0, 50, 0xFF, 0, 0]))!
        XCTAssertEqual(unavailable.fields.first { $0.id == "data2.battery" }?.availability, .unavailable)
        XCTAssertNil(unavailable.fields.first { $0.id == "data2.battery" }?.normalizedValue)

        let zero = PTXP400SemanticDecoder.decode(frameID: PTXP400BLEProtocol.data2FrameID, payload: Data([0, 0, 0, 0, 50, 0, 0, 0]))!
        XCTAssertEqual(zero.fields.first { $0.id == "data2.battery" }?.normalizedValue, "0.0")
    }

    // EN: OBD mode 0A is a permanent-DTC response and remains in the OBD-II layer.
    // ES: El modo OBD 0A es una respuesta DTC permanente y permanece en la capa OBD-II.
    // 中文：OBD Mode 0A 是永久故障码响应，必须留在 OBD-II 层。
    func testOBD2PermanentDTCStatus() {
        let routed = PTBuild69ProtocolRouter.route(command: "0A", rawResponse: "7E8 4A 01 05 24")
        guard case .obd2(let response) = routed else {
            return XCTFail("Expected permanent OBD-II response")
        }
        XCTAssertEqual(response.positiveService, 0x4A)
        XCTAssertEqual(response.dtcStatus, .values(["P0105"]))
    }

    // EN: A repeated sentinel frame produces no candidate but a sentinel break becomes a warning.
    // ES: Una trama centinela repetida no produce candidato, pero romper el centinela produce una advertencia.
    // 中文：重复的哨兵帧不会产生候选，哨兵被破坏时才记录警告。
    func testSentinelBreakIsAnomaly() async {
        let actor = PTBuild69SemanticIntelligenceActor()
        let normal = PTXP400SemanticDecoder.decode(
            frameID: PTXP400BLEProtocol.absFrameID,
            payload: Data([0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        )!
        let changed = PTXP400SemanticDecoder.decode(
            frameID: PTXP400BLEProtocol.absFrameID,
            payload: Data([0x00, 0x00, 0xFF, 0xFF, 0x00, 0xFF, 0xFF, 0xFF])
        )!
        let normalResult = await actor.ingest(frame: normal)
        XCTAssertFalse(normalResult.anomalies.contains { $0.fieldKey == "abs.padding3to7" })
        let changedResult = await actor.ingest(frame: changed)
        XCTAssertTrue(changedResult.anomalies.contains { $0.fieldKey == "abs.padding3to7" })
    }

    // EN: The replay analyzer accepts the recorded Chinese marker and returns deterministic semantic summaries.
    // ES: El analizador de replay acepta el marcador chino registrado y devuelve resúmenes semánticos deterministas.
    // 中文：回放分析器识别现有中文日志标记，并返回确定性的语义摘要。
    func testReplayAnalyzer() {
        let text = """
        === RAW ===
        [00:00:00.000] 📦 [原始包] 收到帧数据: 1603052a80005290000000
        [00:00:00.500] 📦 [原始包] 收到帧数据: 1605a40000800064000000
        [00:00:01.000] 📦 [原始包] 收到帧数据: 1602a00000000000f424000
        """
        let result = PTBuild69ReplayAnalyzer.analyze(text: text, sourceName: "fixture")
        XCTAssertEqual(result.summary.frameCount, 3)
        XCTAssertEqual(result.summary.semanticFrameCount, 3)
        XCTAssertEqual(result.summary.data2ClockStart, "16:10:01")
        XCTAssertEqual(result.summary.data2ClockEnd, "16:10:01")
        XCTAssertEqual(result.summary.batteryMinimum, 14.4)
        XCTAssertEqual(result.summary.batteryMaximum, 14.4)
    }

    // EN: V2 migration remains additive and leaves the new semantic collections empty until re-analysis.
    // ES: La migración v2 es aditiva y deja vacías las colecciones semánticas nuevas hasta el nuevo análisis.
    // 中文：v2 迁移只做增量兼容，在重新分析前保持新的语义集合为空。
    func testEvidenceV2MigrationDoesNotPromoteHistory() {
        let v2 = PTProtocolEvidenceV2Document(
            generatedAt: Date(timeIntervalSince1970: 1),
            records: [PTProtocolEvidenceRecord(domain: .xp400BLE, kind: .candidate, source: .imported, confidence: 0.8, value: "old unknown")],
            canCandidates: [],
            correlations: [],
            passport: PTVehiclePassport(vehicleID: nil, vehicleFields: [], adapterFields: [])
        )
        let v3 = PTProtocolEvidenceV3Migration.fromV2(v2)
        XCTAssertEqual(v3.migratedFromSchemaVersion, PTProtocolEvidenceV2Document.currentSchemaVersion)
        XCTAssertTrue(v3.fieldObservations.isEmpty)
        XCTAssertTrue(v3.candidates.isEmpty)
        XCTAssertTrue(v3.migrationNotes.contains { $0.contains("never") || $0.contains("not") || $0.contains("不会") })
    }

    // EN: Identical semantic frames are coalesced while a state change remains observable.
    // ES: Las tramas semánticas idénticas se agrupan y un cambio de estado sigue siendo observable.
    // 中文：相同语义帧会合并，而状态变化仍然可观测。
    func testEvidenceCoordinatorDeduplicatesPeriodicState() async {
        let coordinator = PTBuild69ProtocolEvidenceCoordinator()
        await coordinator.reset()
        let raw = Data([0x16, 0x02, 0xA0, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF4, 0x24, 0x00])
        let first = await coordinator.ingestBLEFrame(raw, monotonicNanoseconds: 1)
        XCTAssertNotNil(first)
        let duplicate = await coordinator.ingestBLEFrame(raw, monotonicNanoseconds: 2)
        XCTAssertNil(duplicate)
        let changed = Data([0x16, 0x02, 0xA1, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF4, 0x24, 0x00])
        let changedResult = await coordinator.ingestBLEFrame(changed, monotonicNanoseconds: 3)
        XCTAssertNotNil(changedResult)
    }

    // EN: Passport reduction requires an explicit passport reference and never promotes an unclassified AF1C116A value.
    // ES: La reducción Passport requiere una referencia explícita y nunca promociona AF1C116A sin clasificar.
    // 中文：Passport 归约必须有显式引用，不会把未分类的 AF1C116A 自动放进仪表字段。
    func testPassportNeedsExplicitEvidenceReference() {
        let record = PTProtocolEvidenceRecord(domain: .obd2, kind: .identity, source: .live, timestamp: Date(), confidence: 1, value: "AF1C116A")
        let base = PTVehiclePassport(schemaVersion: 2, vehicleID: nil, vehicleFields: [], adapterFields: [])
        let reduced = PTBuild69PassportReducer.reduce(base: base, records: [record])
        XCTAssertNil(reduced.field(for: "dashboard.reference"))
    }

    // EN: The adapter maps live unified sources to stable evidence field names for cross-source comparison.
    // ES: El adaptador asigna fuentes unificadas en vivo a nombres de campo estables para la comparación cruzada.
    // 中文：适配器将统一实时来源映射到稳定证据字段名，用于跨源比较。
    func testUnifiedObservationAdapterAndCorrelation() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = PTUnifiedVehicleTelemetrySnapshot(
            values: [
                PTVehicleTelemetryResolvedValue(
                    signal: .speed,
                    value: .double(42),
                    source: .dashboardBluetooth,
                    capturedAt: now,
                    freshness: .fresh,
                    confidence: 1,
                    isSynthetic: false
                ),
                PTVehicleTelemetryResolvedValue(
                    signal: .speed,
                    value: .double(41.5),
                    source: .gps,
                    capturedAt: now.addingTimeInterval(0.1),
                    freshness: .fresh,
                    confidence: 0.9,
                    isSynthetic: false
                ),
                PTVehicleTelemetryResolvedValue(
                    signal: .rpm,
                    value: .integer(2_000),
                    source: .obdBluetooth,
                    capturedAt: now,
                    freshness: .fresh,
                    confidence: 1,
                    isSynthetic: false
                )
            ],
            updatedAt: now
        )

        let observations = PTBuild69UnifiedObservationAdapter.observations(from: snapshot, at: now)
        XCTAssertTrue(observations.contains { $0.fieldKey == "control.rearSpeed" && $0.source == .xp400BLE })
        XCTAssertTrue(observations.contains { $0.fieldKey == "gps.speed" && $0.source == .gps })
        XCTAssertTrue(observations.contains { $0.fieldKey == "obd.rpm" && $0.source == .obd2 })
        let metric = PTBuild69TelemetryCorrelationEngine.correlate(
            leftField: "control.rearSpeed",
            rightField: "gps.speed",
            observations: observations
        )
        XCTAssertEqual(metric?.pairCount, 1)
    }

    // EN: Historical discovery replay removes the known 0x01 poll and periodic traffic from anomaly/candidate noise.
    // ES: El replay histórico elimina el sondeo 0x01 y el tráfico periódico del ruido de anomalías/candidatos.
    // 中文：历史 Discovery 回放会把已知 0x01 轮询和周期流量从异常/候选噪声中移除。
    func testHistoricalDiscoveryReplayReclassification() throws {
        struct Line: Encodable {
            let type: String
            let event: PTProtocolDiscoveryEvent
        }
        let sessionID = UUID()
        let poll = PTProtocolDiscoveryEvent(
            sessionID: sessionID,
            timestamp: Date(timeIntervalSince1970: 1),
            monotonicNanoseconds: 1,
            channel: .dashboardBLE,
            source: .real,
            direction: .tx,
            classification: .malformed,
            value: "01"
        )
        let data2 = PTProtocolDiscoveryEvent(
            sessionID: sessionID,
            timestamp: Date(timeIntervalSince1970: 2),
            monotonicNanoseconds: 2,
            channel: .dashboardBLE,
            source: .real,
            direction: .rx,
            classification: .knownWithUnmappedData,
            value: "160300020000558E000000"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let text = [poll, data2].compactMap { event -> String? in
            guard let data = try? encoder.encode(Line(type: "event", event: event)) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")

        let result = PTBuild69HistoricalReplayAnalyzer.analyzeDiscovery(text: text)
        XCTAssertEqual(result.summary.eventCount, 2)
        XCTAssertEqual(result.summary.normalizedAnomalyCount, 0)
        XCTAssertGreaterThanOrEqual(result.summary.ignoredPeriodicCount, 1)
        XCTAssertLessThan(result.summary.candidateEventRatio, 0.1)
    }

    // EN: Real capture replay remains opt-in in CI and records evidence from the supplied log without requiring a vehicle.
    // ES: El replay de una captura real es opcional en CI y registra evidencia del archivo suministrado sin requerir una moto.
    // 中文：真实抓包回放在 CI 中按环境变量选择性执行，只分析给定日志，不需要连接车辆。
    func testExternalMotoHexReplayIfProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["PT_BUILD69_REPLAY_LOG"] else {
            throw XCTSkip("Set PT_BUILD69_REPLAY_LOG to run the external MotoHex acceptance sample.")
        }
        let result = try PTBuild69ReplayAnalyzer.analyze(fileURL: URL(fileURLWithPath: path))
        XCTAssertGreaterThan(result.summary.semanticFrameCount, 0)
        XCTAssertEqual(result.summary.data2ClockStart, "16:10:01")
        XCTAssertEqual(result.summary.batteryMinimum ?? -1, 14.4, accuracy: 0.01)
        XCTAssertEqual(result.summary.odometerMinimum ?? -1, 10_166.4, accuracy: 0.1)
    }

    // EN: The supplied discovery and Evidence v2 files can be replayed independently; migration never promotes old candidates.
    // ES: Los archivos Discovery y Evidence v2 suministrados se pueden reproducir por separado; la migración nunca confirma candidatos antiguos.
    // 中文：提供的 Discovery 与 Evidence v2 文件可独立回放；迁移不会把历史候选升级为确认事实。
    func testExternalHistoricalEvidenceReplayIfProvided() throws {
        guard let discoveryPath = ProcessInfo.processInfo.environment["PT_BUILD69_DISCOVERY_JSONL"],
              let evidencePath = ProcessInfo.processInfo.environment["PT_BUILD69_EVIDENCE_V2_JSON"] else {
            throw XCTSkip("Set PT_BUILD69_DISCOVERY_JSONL and PT_BUILD69_EVIDENCE_V2_JSON for historical acceptance samples.")
        }
        let discovery = try PTBuild69HistoricalReplayAnalyzer.analyzeDiscovery(fileURL: URL(fileURLWithPath: discoveryPath))
        XCTAssertGreaterThan(discovery.summary.eventCount, 0)
        XCTAssertLessThan(discovery.summary.candidateEventRatio, 0.1)

        let evidenceData = try Data(contentsOf: URL(fileURLWithPath: evidencePath))
        let replay = try PTBuild69HistoricalReplayAnalyzer.analyzeEvidenceV2(data: evidenceData)
        XCTAssertEqual(replay.document.schemaVersion, PTProtocolEvidenceV3Document.currentSchemaVersion)
        XCTAssertTrue(replay.document.candidates.isEmpty)
        XCTAssertTrue(replay.reanalysis.notes.contains { $0.contains("never") || $0.contains("not") || $0.contains("不会") })
    }
}
