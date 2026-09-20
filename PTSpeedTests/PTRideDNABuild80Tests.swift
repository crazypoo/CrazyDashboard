//
//  PTRideDNABuild80Tests.swift
//  CrazyDashboard
//
//  EN: Deterministic Build80 Ride DNA regression tests.
//  ES: Pruebas de regresión deterministas del ADN de ruta de Build80.
//  中文：Build80 Ride DNA 的确定性回归测试。
//

import XCTest
@testable import XP400Ride

@MainActor
final class PTRideDNABuild80Tests: XCTestCase {
    // EN: The extractor must derive pace, engine and road facts without transport access.
    // ES: El extractor debe obtener ritmo, motor y carretera sin acceder al transporte.
    // 中文：提取器必须在不接触传输层的情况下生成节奏、发动机和道路特征。
    func testExtractsPaceEngineRoadAndMarkers() {
        let report = makeReport(
            start: Date(timeIntervalSince1970: 10_000),
            speedTrace: [0, 10, 42, 58, 4, 0, 70],
            rpmTrace: [0, 2_000, 5_500, 6_200, 1_000, 0, 7_100],
            leanTrace: [0, 8, 32, 14, 0, 0, 22],
            gX: [0, 0.30, 0.10, 0, 0, 0, 0],
            gY: [0, -0.40, 0, 0, 0, 0, 0],
            gZ: [0, 0, 1.10, 0, 0, 0, 0]
        )

        let dna = PTRideDNABuilder.make(report: report, generatedAt: report.endTime)

        XCTAssertEqual(dna.sampleCount, 7)
        XCTAssertGreaterThan(dna.pace.averageMovingSpeedKmh, 0)
        XCTAssertGreaterThan(dna.engine.highRPMDurationSeconds, 0)
        XCTAssertGreaterThanOrEqual(dna.motion.decelerationEventCount, 1)
        XCTAssertGreaterThanOrEqual(dna.road.impactCount, 1)
        XCTAssertTrue(dna.markers.contains { $0.kind == .highRPM })
        XCTAssertTrue(dna.markers.contains { $0.kind == .strongImpact })
        XCTAssertTrue(dna.markers.contains { $0.kind == .largestLean })
        XCTAssertTrue(dna.markers.contains { $0.kind == .longestIdle })
        XCTAssertTrue(dna.markers.contains { $0.kind == .roughRoad })
    }

    // EN: Source coverage must distinguish persisted evidence from an inferred signal source.
    // ES: La cobertura debe distinguir la evidencia persistida de una fuente inferida.
    // 中文：覆盖率必须区分持久化证据和推断出的信号来源。
    func testCoverageDoesNotOverclaimSources() {
        let report = makeReport(
            start: Date(timeIntervalSince1970: 20_000),
            gpxFileName: nil,
            distanceSource: .gps,
            speedTrace: [20, 30],
            rpmTrace: [2_000, 3_000],
            leanTrace: [],
            gX: [],
            gY: [],
            gZ: []
        )

        let coverage = PTRideDNABuilder.make(report: report).coverage

        XCTAssertEqual(coverage.gps, .unavailable)
        XCTAssertEqual(coverage.motion, .unavailable)
        XCTAssertEqual(coverage.obd, .inferred)
        XCTAssertEqual(coverage.xp400, .unavailable)
    }

    // EN: History comparison requires the same vehicle and at least three valid prior rides.
    // ES: La comparación exige el mismo vehículo y al menos tres viajes anteriores válidos.
    // 中文：历史比较必须使用同一辆车，并且至少有三条有效的更早行程。
    func testHistoryComparisonIsVehicleBounded() {
        let vehicleID = UUID()
        let current = makeReport(start: Date(timeIntervalSince1970: 40_000), vehicleID: vehicleID, distanceKm: 20)
        let history = (1...3).map { index in
            makeReport(
                start: Date(timeIntervalSince1970: 40_000 - Double(index * 2_000)),
                vehicleID: vehicleID,
                distanceKm: Double(10 + index)
            )
        }
        let otherVehicle = makeReport(
            start: Date(timeIntervalSince1970: 30_000),
            vehicleID: UUID(),
            distanceKm: 100
        )

        let dna = PTRideDNABuilder.make(
            report: current,
            comparisonPool: history + [otherVehicle]
        )

        XCTAssertFalse(dna.historyComparisons.isEmpty)
        XCTAssertTrue(dna.historyComparisons.allSatisfy { $0.sampleCount == 3 })
    }

    // EN: The DNA document is Codable and round-trips without losing marker or histogram structure.
    // ES: El documento de ADN es Codable y conserva marcadores e histogramas al ida y vuelta.
    // 中文：DNA 文档支持 Codable 往返，不会丢失标记或直方图结构。
    func testDNAExportRoundTrip() throws {
        let report = makeReport(
            start: Date(timeIntervalSince1970: 60_000),
            speedTrace: [1, 40, 80],
            rpmTrace: [1_000, 4_000, 6_500],
            leanTrace: [0, 20, 35],
            gX: [0, 0.1, 0.2],
            gY: [0, -0.2, -0.4],
            gZ: [0, 0.1, 0.9]
        )
        let dna = PTRideDNABuilder.make(report: report, generatedAt: report.endTime)
        let data = try JSONEncoder().encode(dna)
        let decoded = try JSONDecoder().decode(PTRideDNA.self, from: data)

        XCTAssertEqual(decoded, dna)
        XCTAssertEqual(decoded.markers.map(\.titleKey), dna.markers.map(\.titleKey))
        XCTAssertEqual(decoded.engine.rpmHistogram.count, dna.engine.rpmHistogram.count)
    }

    private func makeReport(
        start: Date,
        vehicleID: UUID? = UUID(),
        distanceKm: Double = 12,
        gpxFileName: String? = "ride.gpx",
        distanceSource: PTTripDistanceSource = .odometer,
        speedTrace: [Double] = [0, 20, 40],
        rpmTrace: [Int] = [0, 2_000, 4_000],
        leanTrace: [Double] = [0, 5, 10],
        gX: [Double] = [0, 0.1, 0.2],
        gY: [Double] = [0, 0.1, -0.1],
        gZ: [Double] = [0, 0.1, 0.2]
    ) -> PTTripReport {
        PTTripReport(
            id: UUID().uuidString,
            vehicleID: vehicleID,
            startTime: start,
            endTime: start.addingTimeInterval(600),
            durationMinutes: 10,
            maxSpeedKmh: speedTrace.max() ?? 0,
            maxRpm: rpmTrace.max() ?? 0,
            startOdoKm: 100,
            endOdoKm: 100 + distanceKm,
            distanceKm: distanceKm,
            avgConsumption: 4.2,
            maxLeanAngleLeft: -(leanTrace.map(abs).max() ?? 0),
            maxLeanAngleRight: leanTrace.map(abs).max() ?? 0,
            leanAngleTrace: leanTrace,
            maxAccelerationG: gY.max() ?? 0,
            maxBrakingG: gY.min() ?? 0,
            maxCorneringG: gX.map(abs).max() ?? 0,
            maxBumpG: gZ.map(abs).max() ?? 0,
            maxPitchUp: 5,
            maxPitchDown: -4,
            gForceYTrace: gY,
            gForceXTrace: gX,
            gForceZTrace: gZ,
            pitchTrace: [0, 1],
            relativeAltitudeTrace: [10, 12],
            pressureTrace: [1_000, 1_001],
            idleTimeSeconds: 60,
            speedTrace: speedTrace,
            rpmTrace: rpmTrace,
            best0To100Time: nil,
            gpsAvgSpeedKmh: gpxFileName == nil
                ? 0
                : speedTrace.filter { $0 > 2 }.reduce(0, +) / Double(max(speedTrace.filter { $0 > 2 }.count, 1)),
            gpsMaxSpeedKmh: gpxFileName == nil ? 0 : speedTrace.max() ?? 0,
            gpsMinSpeedKmh: gpxFileName == nil ? 0 : speedTrace.min() ?? 0,
            gpxFileName: gpxFileName,
            maxSlipRatio: 0,
            heavySlipCount: 0,
            slipRatioTrace: Array(repeating: 0, count: speedTrace.count),
            offRoadEvents: [],
            distanceSource: distanceSource,
            reviewEvents: []
        )
    }
}
