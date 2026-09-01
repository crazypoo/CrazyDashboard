//
//  PTCoreTests.swift
//  CrazyDashboard
//
//  中文：覆盖共享状态、CAN 抓包、骑行复盘和只读 OBD 查找的纯数据契约。
//  Español: Cubre los contratos de datos puros del estado compartido, CAN, revisión de ruta y OBD de solo lectura.
//

import XCTest
import MultipeerConnectivity
import CoreLocation
@testable import XP400Ride

final class PTCoreTests: XCTestCase {
    // EN: GPX imports must support both recorded tracks and standard route points.
    // ES: Las importaciones GPX deben admitir tanto trazas grabadas como puntos de ruta estándar.
    // 中文：GPX 导入必须同时支持录制轨迹点和标准路线点。
    func testGPXParserSupportsTrackAndRoutePoints() throws {
        let data = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk><trkseg>
            <trkpt lat="31.230400" lon="121.473700"><ele>4</ele><time>2026-08-01T10:00:00Z</time></trkpt>
          </trkseg></trk>
          <rte>
            <rtept lat="31.231400" lon="121.474700"><name>Finish</name></rtept>
          </rte>
        </gpx>
        """.utf8)

        let points = try PTGPXParser.parseTrack(data: data)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].altitude ?? -1, 4, accuracy: 0.001)
        XCTAssertNotNil(points[0].timestamp)

        let waypoints = PTGPXParser.makeRoadbookWaypoints(
            from: points,
            minimumSpacingMeters: 1,
            maximumWaypointCount: 10
        )
        XCTAssertEqual(waypoints.count, 2)
        XCTAssertEqual(waypoints.last?.latitude ?? 0, 31.2314, accuracy: 0.000001)
    }

    // EN: Replay must preserve GPX telemetry and interpolate it between recorded points.
    // ES: La reproducción debe conservar la telemetría GPX e interpolarla entre puntos grabados.
    // 中文：回放必须保留 GPX 遥测数据，并在录制点之间进行插值。
    func testReplayBuilderUsesGPXTelemetryAndEvents() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let data = Data("""
        <gpx version="1.1">
          <trk><trkseg>
            <trkpt lat="31.2304" lon="121.4737">
              <time>2023-11-14T22:13:20Z</time>
              <extensions>
                <speed>10</speed><rpm>1000</rpm><lean>2</lean>
                <gforce_x>0.1</gforce_x><gforce_y>-0.2</gforce_y><gforce_z>0.3</gforce_z>
                <slip_ratio>1</slip_ratio>
              </extensions>
            </trkpt>
            <trkpt lat="31.2305" lon="121.4738">
              <time>2023-11-14T22:13:22Z</time>
              <extensions>
                <speed>30</speed><rpm>3000</rpm><lean>8</lean>
                <gforce_x>0.3</gforce_x><gforce_y>-0.4</gforce_y><gforce_z>0.5</gforce_z>
                <slip_ratio>3</slip_ratio>
              </extensions>
            </trkpt>
          </trkseg></trk>
        </gpx>
        """.utf8)

        let points = try PTGPXParser.parseTrack(data: data)
        let session = try PTRideReplayBuilder.makeSession(
            report: makeTripReport(start: start),
            trackPoints: points
        )

        XCTAssertEqual(session.samples.count, 2)
        XCTAssertEqual(session.samples[0].speedKmh, 10, accuracy: 0.001)
        XCTAssertEqual(session.samples[1].rpm, 3_000)
        XCTAssertEqual(session.samples[1].gForceZ, 0.5, accuracy: 0.001)
        XCTAssertEqual(session.events.count, 1)

        let middle = try XCTUnwrap(session.sample(at: 1))
        XCTAssertEqual(middle.speedKmh, 20, accuracy: 0.001)
        XCTAssertEqual(middle.rpm, 2_000)
        XCTAssertEqual(middle.leanAngle, 5, accuracy: 0.001)

        let legacyPoints = [
            PTGPXTrackPoint(latitude: 31.2304, longitude: 121.4737),
            PTGPXTrackPoint(latitude: 31.2305, longitude: 121.4738)
        ]
        let legacySession = try PTRideReplayBuilder.makeSession(
            report: makeTripReport(start: start),
            trackPoints: legacyPoints
        )
        XCTAssertEqual(legacySession.samples[0].speedKmh, 20, accuracy: 0.001)
        XCTAssertEqual(legacySession.samples[1].rpm, 4_000)
    }

    // EN: Waypoint persistence must retain the raw coordinate and maneuver code.
    // ES: La persistencia debe conservar la coordenada original y el código de maniobra.
    // 中文：路点持久化必须保留原始坐标和转向代码。
    func testRoadbookWaypointCodableRoundTrip() throws {
        let source = PTCruiseWaypoint(
            latitude: 31.2304,
            longitude: 121.4737,
            instruction: "Checkpoint",
            maneuverCode: PTManeuverMap.quiteRight
        )
        let data = try JSONEncoder().encode(source)
        let restored = try JSONDecoder().decode(PTCruiseWaypoint.self, from: data)

        XCTAssertEqual(restored, source)
        XCTAssertEqual(restored.coordinate.latitude, source.coordinate.latitude, accuracy: 0.000001)
    }

    // EN: Off-route status is only entered after three consecutive invalid samples.
    // ES: El estado fuera de ruta solo aparece después de tres muestras inválidas consecutivas.
    // 中文：连续三次无效定位样本后才进入偏航状态。
    @MainActor
    func testRoadbookRequiresThreeOffRouteSamples() throws {
        let manager = PTCustomRouteManager.shared
        manager.stopCruise()
        let previousNavigationState = PTDashboardConfig.shared.naving
        PTDashboardConfig.shared.naving = false
        defer {
            manager.stopCruise()
            PTDashboardConfig.shared.naving = previousNavigationState
        }

        let route = PTRoadbook(
            name: "Test Roadbook",
            coordinateSystem: .amapGCJ02,
            waypoints: [
                PTCruiseWaypoint(latitude: 31.2304, longitude: 121.4737, instruction: "Start", maneuverCode: PTManeuverMap.straight),
                PTCruiseWaypoint(latitude: 31.2304, longitude: 121.4837, instruction: "Finish", maneuverCode: PTManeuverMap.arrive)
            ]
        )
        try manager.startRoadbook(route)

        for _ in 0..<2 {
            manager.processCurrentLocation(makeAccurateLocation(latitude: 31.2404, longitude: 121.4787))
        }
        XCTAssertEqual(manager.state, .active)

        manager.processCurrentLocation(makeAccurateLocation(latitude: 31.2404, longitude: 121.4787))
        XCTAssertEqual(manager.state, .offRoute)
        XCTAssertEqual(manager.navigationSnapshot.offRouteSampleCount, 3)

        manager.processCurrentLocation(makeAccurateLocation(latitude: 31.2304, longitude: 121.4740))
        XCTAssertEqual(manager.state, .active)
    }

    @MainActor
    private func makeAccurateLocation(latitude: Double, longitude: Double) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 10,
            timestamp: Date()
        )
    }

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

    // EN: Parameterized dashboard localization must use the integer argument, not the variadic argument array itself.
    // ES: La localización parametrizada debe usar el entero, no el propio array de argumentos variádicos.
    // 中文：带参数的仪表盘本地化必须使用实际整数，不能把可变参数数组本身当成参数。
    func testParameterizedDashboardLocalizationUsesActualArgument() {
        let text = PTDashboardConfig.language(key: "ptt_ready_connect_count", 0)

        XCTAssertTrue(text.contains("0"), "Unexpected localized count text: \(text)")
    }

    // EN: External routes must preserve legacy URLs while rejecting ambiguous parameters.
    // ES: Las rutas externas deben conservar las URL antiguas y rechazar parámetros ambiguos.
    // 中文：外部路由必须兼容旧 URL，同时拒绝含义不明确的参数。
    func testExternalRouteParsing() {
        XCTAssertEqual(
            PTRoutingManager.parse(url: URL(string: "xp400://checkFuel")!),
            .checkFuel
        )
        XCTAssertEqual(
            PTRoutingManager.parse(url: URL(string: "xp400://action/openHUD")!),
            .openHUD
        )
        XCTAssertEqual(
            PTRoutingManager.parse(url: URL(string: "xp400://antiTheft?enable=true")!),
            .toggleAntiTheft(enable: true)
        )
        XCTAssertEqual(
            PTRoutingManager.parse(url: URL(string: "xp400://antiTheft?enable=false")!),
            .toggleAntiTheft(enable: false)
        )
        XCTAssertEqual(
            PTRoutingManager.parse(url: URL(string: "xp400://navigate?destination=%E7%8F%A0%E6%B1%9F%E6%96%B0%E5%9F%8E")!),
            .navigateTo(destination: "珠江新城")
        )

        XCTAssertEqual(
            PTRoutingManager.parse(url: URL(string: "xp400://antiTheft")!),
            .unknown
        )
        XCTAssertEqual(
            PTRoutingManager.parse(url: URL(string: "xp400://antiTheft?enable=maybe")!),
            .unknown
        )
        XCTAssertEqual(
            PTRoutingManager.parse(url: URL(string: "xp400://navigate?destination=%0A")!),
            .unknown
        )
        XCTAssertEqual(
            PTRoutingManager.parse(url: URL(string: "xp400://navigate?destination=%20%20")!),
            .unknown
        )
        XCTAssertNil(PTRoutingManager.parse(url: URL(string: "other://checkFuel")!))
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

    // EN: Black-box windows must stay bounded and preserve the available ride context.
    // ES: Las ventanas de la caja negra deben estar acotadas y conservar el contexto disponible.
    // 中文：黑匣子窗口必须有边界，并保留事件周围实际存在的行程上下文。
    func testRideBlackBoxBuildsBoundedEventWindow() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let event = PTRideBlackBoxEvent(
            rideStartTime: start,
            timestamp: start.addingTimeInterval(60),
            source: .manual,
            title: "manual",
            latitude: 31.2304,
            longitude: 121.4737
        )
        let points = [-60.0, 0.0, 30.0].map { offset in
            makeRoutePoint(timestamp: event.timestamp.addingTimeInterval(offset), brakingG: 0)
        }

        let clip = PTRideBlackBoxBuilder.makeClip(
            event: event,
            points: points,
            beforeSeconds: 60,
            afterSeconds: 30,
            createdAt: start
        )

        XCTAssertEqual(clip.points.count, 3)
        XCTAssertEqual(clip.availableBeforeSeconds, 60, accuracy: 0.001)
        XCTAssertEqual(clip.availableAfterSeconds, 30, accuracy: 0.001)
        XCTAssertTrue(clip.hasCompleteRequestedWindow)
    }

    // EN: The local black-box repository must cap retained clips and keep cloud sync disabled.
    // ES: El repositorio local debe limitar los clips retenidos y mantener desactivada la nube.
    // 中文：本地黑匣子仓库必须限制保留数量，并保持关闭云端同步。
    func testRideBlackBoxStoreCapsLocalClips() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PTRideBlackBox-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = PTDataPersistenceActor(localDirectoryURL: directory)
        let store = PTRideBlackBoxStore(
            fileName: "blackbox.json",
            maximumClipCount: 1,
            persistence: persistence
        )
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let firstEvent = PTRideBlackBoxEvent(
            id: UUID(),
            rideStartTime: start,
            timestamp: start,
            source: .manual,
            title: "first",
            latitude: 31.2304,
            longitude: 121.4737
        )
        let secondEvent = PTRideBlackBoxEvent(
            id: UUID(),
            rideStartTime: start,
            timestamp: start.addingTimeInterval(1),
            source: .manual,
            title: "second",
            latitude: 31.2304,
            longitude: 121.4737
        )

        _ = try await store.append([
            PTRideBlackBoxBuilder.makeClip(event: firstEvent, points: []),
            PTRideBlackBoxBuilder.makeClip(event: secondEvent, points: [])
        ])
        let restored = try await store.load()

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.event.title, "second")
        let localData = try await persistence.readData(
            fileName: "blackbox.json",
            restoreFromICloud: false
        )
        XCTAssertFalse(localData.isEmpty)
        let deletedCount = try await store.deleteClips(forRideStartTime: start)
        let clipsAfterDelete = try await store.load()
        XCTAssertEqual(deletedCount, 1)
        XCTAssertTrue(clipsAfterDelete.isEmpty)
    }

    // EN: A ride story must expose existing cornering, elevation and event data without guessing new vehicle metrics.
    // ES: La historia debe exponer los datos existentes de curvas, elevación y eventos sin inventar métricas.
    // 中文：行程故事必须展示已有的弯道、爬升和事件数据，不能猜测新车型指标。
    func testRideStorySummarizesExistingTelemetry() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let report = makeTripReport(start: start)
        let story = PTRideStoryBuilder.make(from: report)

        XCTAssertEqual(story.distanceKm, 12.5, accuracy: 0.001)
        XCTAssertEqual(story.averageSpeedKmh, 30, accuracy: 0.001)
        XCTAssertEqual(story.maximumLeanAngle, 25, accuracy: 0.001)
        XCTAssertEqual(story.elevationGainMeters, 10, accuracy: 0.001)
        XCTAssertEqual(story.elevationLossMeters, 5, accuracy: 0.001)
        XCTAssertEqual(story.eventCount, 1)
        XCTAssertEqual(story.eventBreakdown[PTRideReviewEventType.highLean.rawValue], 1)
    }

    // EN: Group safety must distinguish a stale position, a distant rider and a connected rider.
    // ES: La seguridad de grupo debe distinguir una posición obsoleta, un piloto lejano y uno conectado.
    // 中文：组队安全分析必须区分位置过期、成员过远和正常连接三种状态。
    func testRideGroupSafetyClassifiesPeerStates() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let local = PTRideCoordinate(latitude: 31.2304, longitude: 121.4737)
        let connected = PTRidePeerLocationSample(
            peerID: "connected",
            displayName: "Connected",
            coordinate: PTRideCoordinate(latitude: 31.2305, longitude: 121.4738),
            speedKmh: 30,
            course: 0,
            updatedAt: now
        )
        let stale = PTRidePeerLocationSample(
            peerID: "stale",
            displayName: "Stale",
            coordinate: local,
            speedKmh: 0,
            course: 0,
            updatedAt: now.addingTimeInterval(-20)
        )
        let snapshot = PTRideGroupSafetyAnalyzer.analyze(
            activePeerIDs: ["connected", "stale", "missing"],
            samples: ["connected": connected, "stale": stale],
            localCoordinate: local,
            now: now,
            policy: PTRideGroupSafetyPolicy(staleAfterSeconds: 15, tooFarDistanceMeters: 20)
        )

        XCTAssertEqual(snapshot.peers.first(where: { $0.peerID == "connected" })?.state, .tooFar)
        XCTAssertEqual(snapshot.peers.first(where: { $0.peerID == "stale" })?.state, .stale)
        XCTAssertEqual(snapshot.peers.first(where: { $0.peerID == "missing" })?.state, .noLocation)
        XCTAssertEqual(snapshot.stalePeerCount, 1)
        XCTAssertEqual(snapshot.noLocationPeerCount, 1)
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

    // EN: Membership normalization must remove repeated peer identities without using display names.
    // ES: La normalización debe eliminar identidades repetidas sin usar los nombres visibles.
    // 中文：成员规范化必须移除重复身份，不能使用显示昵称去重。
    @MainActor
    func testPTTPeerSnapshotNormalizesRepeatedIdentities() {
        let firstPeer = MCPeerID(displayName: "Rider A")
        let secondPeer = MCPeerID(displayName: "Rider B")

        let snapshot = PTLocalIntercomManager.normalizedPeerSnapshot([
            firstPeer,
            firstPeer,
            secondPeer,
            secondPeer
        ])

        XCTAssertEqual(snapshot.map(\.displayName), ["Rider A", "Rider B"])
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

    private func makeTripReport(start: Date) -> PTTripReport {
        let event = PTRideReviewEvent(
            type: .highLean,
            timestamp: start.addingTimeInterval(30),
            latitude: 31.2304,
            longitude: 121.4737,
            peakValue: 45,
            speedKmh: 50,
            severity: 1.2
        )
        return PTTripReport(
            startTime: start,
            endTime: start.addingTimeInterval(1_800),
            durationMinutes: 30,
            maxSpeedKmh: 80,
            maxRpm: 6_000,
            startOdoKm: 100,
            endOdoKm: 112.5,
            distanceKm: 12.5,
            avgConsumption: 4.5,
            maxLeanAngleLeft: -25,
            maxLeanAngleRight: 20,
            leanAngleTrace: [-5, 25, 10],
            maxAccelerationG: 0.4,
            maxBrakingG: -0.5,
            maxCorneringG: 0.3,
            maxBumpG: 0.4,
            maxPitchUp: 8,
            maxPitchDown: -6,
            gForceYTrace: [0, 0, 0],
            gForceXTrace: [0, 0, 0],
            gForceZTrace: [0, 0, 0],
            pitchTrace: [0, 2, 0],
            relativeAltitudeTrace: [100, 110, 105],
            pressureTrace: [1_000, 1_001, 1_000],
            idleTimeSeconds: 30,
            speedTrace: [20, 40, 30],
            rpmTrace: [2_000, 4_000, 3_000],
            best0To100Time: nil,
            gpsAvgSpeedKmh: 30,
            gpsMaxSpeedKmh: 80,
            gpsMinSpeedKmh: 5,
            gpxFileName: "MotoRide_test.gpx",
            maxSlipRatio: 0,
            heavySlipCount: 0,
            slipRatioTrace: [0, 0, 0],
            offRoadEvents: [],
            distanceSource: .odometer,
            reviewEvents: [event]
        )
    }
}
