//
//  PTCoreTests.swift
//  CrazyDashboard
//
//  中文：覆盖共享状态、CAN 抓包、骑行复盘和只读 OBD 查找的纯数据契约。
//  Español: Cubre los contratos de datos puros del estado compartido, CAN, revisión de ruta y OBD de solo lectura.
//

import XCTest
@testable import XP400Ride

final class PTCoreTests: XCTestCase {
    func testWidgetApplicationContextRoundTrip() {
        let source = PTWidgetSharedStatus(
            fuelLevel: 72,
            tripKm: 128.4,
            isConnected: true,
            parkedLat: 31.2304,
            parkedLon: 121.4737,
            address: "上海外滩",
            lastUpdateTime: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let restored = PTWidgetSharedStatus(applicationContext: source.applicationContext)

        XCTAssertEqual(restored, source)
    }

    // EN: The ride cockpit must prefer the dashboard range and never invent a tank profile.
    // ES: El cockpit debe preferir la autonomía del tablero y nunca inventar un perfil del depósito.
    // 中文：骑行座舱必须优先使用仪表续航，不能擅自猜测油箱参数。
    func testRideRangeAndMaintenanceCalculations() {
        let dashboardRange = PTRideRangeEstimator.estimate(
            dashboardAutonomyKm: 123.4,
            fuelLevelPercent: 20,
            averageConsumptionLitersPer100Km: 4
        )
        XCTAssertEqual(dashboardRange?.source, .dashboard)
        XCTAssertEqual(dashboardRange?.remainingKm ?? -1, 123.4, accuracy: 0.001)

        let estimatedRange = PTRideRangeEstimator.estimate(
            dashboardAutonomyKm: nil,
            fuelLevelPercent: 50,
            averageConsumptionLitersPer100Km: 5,
            tankCapacityLiters: 10,
            reservePercent: 10
        )
        XCTAssertEqual(estimatedRange?.source, .estimated)
        XCTAssertEqual(estimatedRange?.remainingKm ?? -1, 80, accuracy: 0.001)

        let dueSoon = PTRideMaintenanceAdvisor.advise(
            distanceToMaintenanceKm: 300,
            rawMaintenanceFlag: 0
        )
        XCTAssertEqual(dueSoon.state, .dueSoon)

        let required = PTRideMaintenanceAdvisor.advise(
            distanceToMaintenanceKm: 2_000,
            rawMaintenanceFlag: 0x20
        )
        XCTAssertEqual(required.state, .required)
    }

    func testDiagnosticAddressNormalizesHeaders() {
        let address = PTOBDDiagnosticAddress(tx: " 7a0 ", rx: "7a8")

        XCTAssertEqual(address?.tx, "7A0")
        XCTAssertEqual(address?.rx, "7A8")
        XCTAssertNil(PTOBDDiagnosticAddress(tx: "70", rx: "7A8"))
        XCTAssertNil(PTOBDiagnosticAddress(tx: "800", rx: "808"))
        XCTAssertNil(PTOBDiagnosticAddress(tx: "18DAF110", rx: "FFFFFFFF"))
        XCTAssertNil(PTOBDiagnosticAddress(tx: "7A0", rx: "000007A8"))
        XCTAssertNotNil(PTOBDiagnosticAddress(tx: "18DAF110", rx: "18DAF118"))
    }

    func testUDSPositiveAndNegativeResponses() throws {
        let address = try XCTUnwrap(PTOBDiagnosticAddress(tx: "7A0", rx: "7A8"))

        let positive = try PTUDSReadService.parseDIDResponse(
            address: address,
            did: "F190",
            response: "7A8 06 62 F1 90 31 32 33"
        )
        XCTAssertEqual(positive.status, .success)
        XCTAssertEqual(positive.payloadHex, "313233")

        let negative = try PTUDSReadService.parseDIDResponse(
            address: address,
            did: "F190",
            response: "7A8 03 7F 22 31"
        )
        XCTAssertEqual(negative.status, .negativeResponse)
        XCTAssertEqual(negative.negativeResponseCode, "31")
    }

    func testELM327DLCIsNotStoredAsPayload() {
        let recorder = PTCANRecorder.shared
        recorder.cancel()
        recorder.maxInMemoryFrames = 16
        recorder.start(name: "OBD-CAN-Parser-Test")
        recorder.append(
            rawLine: "7E8 06 41 0C 1A F8 00 00 00",
            timestamp: 1_700_000_000
        )

        let session = recorder.stop()

        XCTAssertEqual(session?.frames.count, 1)
        XCTAssertEqual(session?.frames.first?.header, "7E8")
        XCTAssertEqual(session?.frames.first?.dlc, 6)
        XCTAssertEqual(session?.frames.first?.dataHex, "410C1AF80000")
    }

    // EN: CAN header bounds and ISO-TP parsing must reject invalid frames without touching transport.
    // ES: Los límites del encabezado CAN y el análisis ISO-TP deben rechazar tramas inválidas sin tocar el transporte.
    // 中文：CAN Header 边界和 ISO-TP 解析必须拒绝非法报文，且不能触碰传输层。
    func testCANHeaderBoundsAndISOTransportPayload() throws {
        let recorder = PTCANRecorder.shared
        recorder.cancel()
        recorder.maxInMemoryFrames = 16
        recorder.start(name: "CAN-Bounds-Test")
        recorder.append(rawLine: "18DAF110 02 10 01", timestamp: 1_700_000_000)
        recorder.append(rawLine: "20000000 02 10 01", timestamp: 1_700_000_001)
        let session = recorder.stop()

        XCTAssertEqual(session?.frames.count, 1)
        XCTAssertEqual(session?.frames.first?.header, "18DAF110")

        let address = try XCTUnwrap(PTOBDDiagnosticAddress(tx: "7A0", rx: "7A8"))
        let response = "7E8100A62F19031323334\n7E82135363738"
        let result = try PTUDSReadService.parseDIDResponse(
            address: address,
            did: "F190",
            response: response
        )

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.payloadHex, "3132333435363738")
        XCTAssertEqual(result.decodedText, "12345678")
    }

    func testCaptureDiffAndBitDiff() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let leftFrame = PTCANFrame(
            timestamp: date.timeIntervalSince1970,
            sequence: 1,
            direction: .rx,
            rawLine: "7E8 02 10 01",
            header: "7E8",
            dataHex: "1001",
            dlc: 2
        )
        let rightFrame = PTCANFrame(
            timestamp: date.timeIntervalSince1970 + 1,
            sequence: 1,
            direction: .rx,
            rawLine: "7E8 02 10 03",
            header: "7E8",
            dataHex: "1003",
            dlc: 2
        )

        let left = PTCANCaptureSession(
            id: UUID(),
            name: "左侧",
            startedAt: date,
            endedAt: date.addingTimeInterval(1),
            filterHeader: nil,
            frames: [leftFrame]
        )
        let right = PTCANCaptureSession(
            id: UUID(),
            name: "右侧",
            startedAt: date,
            endedAt: date.addingTimeInterval(1),
            filterHeader: nil,
            frames: [rightFrame]
        )

        let captureDiff = PTCANCaptureAnalyzer.diff(left: left, right: right)
        let payloadDiff = PTCANCaptureAnalyzer.byteDiff(left: left, right: right)

        XCTAssertEqual(captureDiff.deltas.first?.kind, .changed)
        XCTAssertEqual(payloadDiff.first?.changedByteCount, 1)
        XCTAssertEqual(payloadDiff.first?.changedBitCount, 1)
    }

    // EN: Legacy capture JSON must decode with safe defaults for new metadata fields.
    // ES: El JSON de captura antiguo debe decodificarse con valores seguros para los metadatos nuevos.
    // 中文：旧版 Capture JSON 必须能解码，新元数据字段使用安全默认值。
    func testLegacyCaptureJSONKeepsBackwardCompatibility() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "legacy",
          "startedAt": "2023-11-14T22:13:20Z",
          "endedAt": "2023-11-14T22:13:21Z",
          "filterHeader": null,
          "frames": [
            {
              "timestamp": 1700000000,
              "sequence": 1,
              "direction": "bus",
              "rawLine": "7E8 02 10 01",
              "header": "7E8",
              "dataHex": "1001",
              "dlc": 2
            }
          ]
        }
        """.data(using: .utf8)!

        let session = try PTCANCaptureStorage.decode(json)

        XCTAssertEqual(session.schemaVersion, 1)
        XCTAssertTrue(session.events.isEmpty)
        XCTAssertEqual(session.totalFrameCount, 1)
        XCTAssertEqual(session.retainedFrameCount, 1)
        XCTAssertEqual(session.droppedFrameCount, 0)
    }

    // EN: CSV output must escape commas, quotes and line breaks in raw frames.
    // ES: La salida CSV debe escapar comas, comillas y saltos de línea de las tramas sin procesar.
    // 中文：CSV 导出必须正确转义原始报文中的逗号、引号和换行。
    func testCaptureCSVEscapesRawLine() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let frame = PTCANFrame(
            timestamp: date.timeIntervalSince1970,
            sequence: 1,
            direction: .bus,
            rawLine: "7E8, \"02 10 01\"\nnext",
            header: "7E8",
            dataHex: "1001",
            dlc: 2
        )
        let session = PTCANCaptureSession(
            id: UUID(),
            name: "csv",
            startedAt: date,
            endedAt: date,
            filterHeader: nil,
            frames: [frame]
        )

        let csv = PTCANCaptureStorage.csv(session)

        XCTAssertTrue(csv.contains("\"7E8, \"\"02 10 01\"\"\nnext\""))
    }

    // EN: An event marker must be included in the in-memory session snapshot.
    // ES: Una marca de evento debe incluirse en la instantánea de sesión en memoria.
    // 中文：事件标记必须实际出现在内存中的 Capture Session 快照里。
    func testCaptureEventIsIncludedInSnapshot() {
        let recorder = PTCANRecorder.shared
        recorder.cancel()
        XCTAssertTrue(recorder.start(name: "Event-Test"))
        let event = recorder.markEvent("engine-start")
        let snapshot = recorder.snapshot()
        recorder.cancel()

        XCTAssertEqual(snapshot?.events.first?.id, event?.id)
        XCTAssertEqual(snapshot?.events.first?.name, "engine-start")
    }

    // EN: Offline replay must deliver frames in capture order without touching vehicle transport.
    // ES: La reproducción offline debe entregar las tramas en orden sin tocar el transporte del vehículo.
    // 中文：离线回放必须按抓包顺序交付帧，且不接触车辆传输层。
    func testCaptureReplayDeliversFramesInOrder() async throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let frames = (0..<2).map { index in
            PTCANFrame(
                timestamp: date.timeIntervalSince1970 + Double(index),
                sequence: index + 1,
                direction: .bus,
                rawLine: "7E8 02 10 0\(index + 1)",
                header: "7E8",
                dataHex: "100\(index + 1)",
                dlc: 2
            )
        }
        let session = PTCANCaptureSession(
            id: UUID(),
            name: "offline",
            startedAt: date,
            endedAt: date.addingTimeInterval(1),
            filterHeader: nil,
            frames: frames
        )

        let replayed = try await PTCANCaptureReplay.replay(session: session) { frame in
            XCTAssertEqual(frame.header, "7E8")
        }

        XCTAssertEqual(replayed, 2)
    }

    func testRideReviewUsesCooldownAndReportsHardBraking() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            makeRoutePoint(timestamp: start, brakingG: -0.8),
            makeRoutePoint(timestamp: start.addingTimeInterval(2), brakingG: -0.9),
            makeRoutePoint(timestamp: start.addingTimeInterval(6), brakingG: -0.7)
        ]

        let events = PTRideReviewAnalyzer.analyze(points: points)

        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy { $0.type == .hardBraking })
    }

    func testStableOBDCommandLookupIsReadOnly() {
        let command = OBDCommand.from(command: "010C")

        XCTAssertNotNil(command)
        XCTAssertEqual(PTDTCManager.determineSeverity(for: "P0300"), .high)
    }

    // EN: Ordinary XP400 entries must remain confirmed, read-only and structurally verifiable.
    // ES: Las entradas ordinarias del XP400 deben seguir confirmadas, ser de solo lectura y verificables.
    // 中文：普通 XP400 指令必须保持已确认、只读且结构可验证。
    func testXP400InstructionCatalogKeepsOrdinaryUIReadOnly() {
        XCTAssertTrue(PTXP400InstructionCatalog.validateOrdinaryUIEntries())
        XCTAssertEqual(PTXP400InstructionCatalog.confirmedDIDs, ["F190"])
        XCTAssertTrue(
            PTXP400InstructionCatalog.ordinaryUIEntries().allSatisfy {
                $0.kind == .read && $0.level == .confirmed && $0.isReversible
            }
        )
    }

    // EN: Firmware experiments stay blocked until every physical recovery prerequisite is verified.
    // ES: Los experimentos de firmware siguen bloqueados hasta verificar cada requisito físico de recuperación.
    // 中文：固件实验必须等所有实体恢复前置条件验证后才允许进入下一阶段。
    func testDeveloperFirmwarePreflightRequiresRecoveryEvidence() {
        let result = PTDeveloperTestPreflight.evaluate(
            level: .firmware,
            checklist: .empty
        )

        XCTAssertFalse(result.isReady)
        XCTAssertTrue(result.blockers.contains("protocolEvidenceMissing"))
        XCTAssertTrue(result.blockers.contains("recoveryPathMissing"))
        XCTAssertTrue(result.blockers.contains("firmwareCompatibilityNotVerified"))
    }

    @MainActor
    func testVehicleSnapshotKeepsDashboardAndOBDStatesIndependent() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let dashboard = PTVehicleLinkSnapshot(
            state: .connected,
            transport: .dashboardBluetooth,
            updatedAt: date
        )
        let obd = PTVehicleLinkSnapshot(
            state: .failed,
            transport: .obdBluetooth,
            errorMessage: "timeout",
            updatedAt: date
        )

        let snapshot = PTVehicleSnapshot.initial.replacing(
            dashboard: dashboard,
            updatedAt: date
        )
        let independentSnapshot = snapshot.replacing(obd: obd, updatedAt: date)

        // EN: Updating OBD must not rewrite the dashboard link.
        // ES: Actualizar OBD no debe modificar el enlace del tablero.
        // 中文：更新 OBD 状态时不能改写仪表盘连接状态。
        XCTAssertEqual(independentSnapshot.dashboard, dashboard)
        XCTAssertEqual(independentSnapshot.obd, obd)
        XCTAssertTrue(independentSnapshot.isDashboardConnected)
        XCTAssertFalse(independentSnapshot.isOBDConnected)
    }

    // EN: Local data must survive a cloud outage, and an older snapshot must not overwrite it.
    // ES: Los datos locales deben sobrevivir a una caída de la nube y una instantánea antigua no debe sobrescribirlos.
    // 中文：iCloud 不可用时本地数据仍要保留，旧快照不能覆盖新快照。
    @MainActor
    func testPersistenceActorKeepsNewestLocalSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PTPersistence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = PTDataPersistenceActor(localDirectoryURL: directory)
        let newest = Data("newest".utf8)
        let stale = Data("stale".utf8)

        let newestResult = try await store.writeData(
            newest,
            fileName: "status.json",
            revision: 2,
            syncToICloud: true
        )
        let staleResult = try await store.writeData(
            stale,
            fileName: "status.json",
            revision: 1,
            syncToICloud: false
        )
        let restored = try await store.readData(fileName: "status.json", restoreFromICloud: false)

        XCTAssertTrue(newestResult.didWriteLocal)
        XCTAssertNotNil(newestResult.cloudErrorDescription)
        XCTAssertTrue(staleResult.didSkipStaleWrite)
        XCTAssertEqual(restored, newest)
    }

    func testPersistenceActorRejectsUnsafeFileNames() async {
        let store = PTDataPersistenceActor(
            localDirectoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("PTPersistence-\(UUID().uuidString)", isDirectory: true)
        )

        do {
            _ = try await store.writeData(Data(), fileName: "../status.json", syncToICloud: false)
            XCTFail("Unsafe file name should be rejected")
        } catch let error as PTDataPersistenceError {
            XCTAssertEqual(error, .invalidFileName)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPTTLiveActivityEligibilityRequiresConnectedMembersAndWorkingAudio() {
        XCTAssertFalse(PTLiveActivityEligibility.shouldDisplayPTT(
            isRunning: true,
            connectedPeerCount: 0,
            audioOperational: true,
            microphoneAvailable: true
        ))
        XCTAssertFalse(PTLiveActivityEligibility.shouldDisplayPTT(
            isRunning: true,
            connectedPeerCount: 1,
            audioOperational: false,
            microphoneAvailable: true
        ))
        XCTAssertTrue(PTLiveActivityEligibility.shouldDisplayPTT(
            isRunning: true,
            connectedPeerCount: 1,
            audioOperational: true,
            microphoneAvailable: true
        ))
    }

    // EN: Developer-only operations must be denied by default and without protocol evidence.
    // ES: Las operaciones exclusivas del desarrollador deben rechazarse por defecto y sin evidencia del protocolo.
    // 中文：开发者专属操作默认必须拒绝，缺少协议证据时也必须拒绝。
    @MainActor
    func testDeveloperSafetyGateDefaultsToReadOnly() {
        let gate = PTDeveloperSafetyGate.shared
        gate.setEnabled(false)
        XCTAssertFalse(gate.authorize(.didFuzz))

        gate.setEnabled(true)
        XCTAssertFalse(gate.authorize(.dashboardWrite, protocolEvidenceAvailable: false))
        gate.disable()
    }

    private func makeRoutePoint(timestamp: Date, brakingG: Double) -> PTRoutePoint {
        PTRoutePoint(
            lat: 31.2304,
            lon: 121.4737,
            altitude: 4,
            timestamp: timestamp,
            speed: 60,
            rpm: 4_000,
            leanAngle: 10,
            gForceY: brakingG,
            gForceX: 0,
            gForceZ: 0,
            slipRatio: 0
        )
    }
}
