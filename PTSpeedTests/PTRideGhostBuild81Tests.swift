//
//  PTRideGhostBuild81Tests.swift
//  CrazyDashboard
//
//  EN: Build 81 route alignment and Ghost Ride safety regression tests.
//  ES: Pruebas de regresión de alineación y seguridad Ghost Ride de Build 81.
//  中文：Build81 路线对齐与 Ghost Ride 安全回归测试。
//

import XCTest
import CoreLocation
@testable import XP400Ride

@MainActor
final class PTRideGhostBuild81Tests: XCTestCase {
    // EN: Equal geometry must align by route distance and expose metric deltas.
    // ES: La geometría igual debe alinearse por distancia y mostrar diferencias métricas.
    // 中文：相同路线必须按距离对齐，并正确给出遥测差值。
    func testSameRouteOverlapAndInterpolation() {
        let current = makeSession(id: "current", longitudeOffset: 0, speedOffset: 10, rpmOffset: 500)
        let historical = makeSession(id: "history", longitudeOffset: 0, speedOffset: 0, rpmOffset: 0)
        let compare = PTRideGhostSession(
            currentRoute: PTRideGhostRouteNormalizer.make(session: current),
            historicalRoute: PTRideGhostRouteNormalizer.make(session: historical)
        )

        XCTAssertEqual(compare.availability, .ready)
        let result = compare.comparison(at: 30)
        XCTAssertEqual(result.availability, .ready)
        XCTAssertEqual(result.speedDeltaKmh ?? 0, 10, accuracy: 0.1)
        XCTAssertEqual(result.rpmDelta, 500)
        XCTAssertNotNil(result.historicalSample)
    }

    // EN: A distant route must never produce a false Ghost match.
    // ES: Una ruta distante nunca debe producir una coincidencia Ghost falsa.
    // 中文：相距很远的路线不能产生错误的 Ghost 匹配。
    func testDifferentRouteIsSafelyRejected() {
        let current = makeSession(id: "current", longitudeOffset: 0)
        let historical = makeSession(id: "history", longitudeOffset: 2)
        let compare = PTRideGhostSession(
            currentRoute: PTRideGhostRouteNormalizer.make(session: current),
            historicalRoute: PTRideGhostRouteNormalizer.make(session: historical)
        )

        XCTAssertEqual(compare.availability, .insufficientOverlap)
        XCTAssertEqual(compare.comparison(at: 30).fallbackAction, .hideUntilRejoin)
    }

    // EN: Live matching leaves the route untouched and hides the Ghost when the rider leaves it.
    // ES: El emparejamiento en vivo no modifica la ruta y oculta Ghost al salir de ella.
    // 中文：实时匹配不会修改路线，骑手离开路线后会隐藏 Ghost。
    func testLiveGhostFallbackDoesNotReroute() {
        let session = makeSession(id: "history", longitudeOffset: 0)
        let route = PTRideGhostRouteNormalizer.make(session: session)
        var resolver = PTRideGhostLiveResolver(route: route)

        let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let ready = resolver.update(
            coordinate: coordinate,
            speedKmh: 30,
            rpm: 2_000,
            timestamp: session.startTime
        )
        XCTAssertEqual(ready.availability, .ready)
        XCTAssertEqual(ready.historicalRPM, 2_000)
        XCTAssertNotNil(ready.historicalRoadQuality)

        let outside = resolver.update(
            coordinate: CLLocationCoordinate2D(latitude: 20, longitude: 20),
            speedKmh: 30,
            rpm: 2_000,
            timestamp: session.startTime.addingTimeInterval(10)
        )
        XCTAssertEqual(outside.availability, .outsideOverlap)
        XCTAssertEqual(outside.fallbackAction, .hideUntilRejoin)
    }

    // EN: Route normalization must preserve time order and cumulative distance.
    // ES: La normalización debe conservar el orden temporal y la distancia acumulada.
    // 中文：路线归一化必须保持时间顺序和累计距离。
    func testRouteNormalizationProducesProgress() {
        let session = makeSession(id: "history", longitudeOffset: 0)
        let route = PTRideGhostRouteNormalizer.make(session: session)

        XCTAssertEqual(route.samples.count, 7)
        XCTAssertGreaterThan(route.totalDistanceKm, 0.5)
        XCTAssertEqual(route.samples.first?.distanceKm ?? -1, 0, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(route.samples[2].elapsed, route.samples[3].elapsed)
        XCTAssertNotNil(route.sample(atDistance: route.totalDistanceKm / 2))
    }

    private func makeSession(id: String,
                             longitudeOffset: Double,
                             speedOffset: Double = 0,
                             rpmOffset: Int = 0) -> PTRideReplaySession {
        let start = Date(timeIntervalSince1970: 100_000)
        let samples = (0..<7).map { index in
            PTRideReplaySample(
                latitude: Double(index) * 0.001,
                longitude: longitudeOffset,
                timestamp: start.addingTimeInterval(Double(index) * 10),
                altitude: 10,
                speedKmh: 30 + speedOffset + Double(index),
                rpm: 2_000 + rpmOffset + index * 100,
                leanAngle: Double(index),
                gForceX: 0.1,
                gForceY: 0.2,
                gForceZ: 0.3,
                slipRatio: 0
            )
        }
        return PTRideReplaySession(
            report: makeReport(id: id, start: start),
            samples: samples,
            events: []
        )
    }

    private func makeReport(id: String, start: Date) -> PTTripReport {
        PTTripReport(
            id: id,
            vehicleID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"),
            startTime: start,
            endTime: start.addingTimeInterval(60),
            durationMinutes: 1,
            maxSpeedKmh: 36,
            maxRpm: 2_600,
            startOdoKm: 100,
            endOdoKm: 100.7,
            distanceKm: 0.7,
            avgConsumption: 4,
            maxLeanAngleLeft: 0,
            maxLeanAngleRight: 6,
            leanAngleTrace: Array(0..<7).map(Double.init),
            maxAccelerationG: 0.2,
            maxBrakingG: 0,
            maxCorneringG: 0.1,
            maxBumpG: 0.3,
            maxPitchUp: 0,
            maxPitchDown: 0,
            gForceYTrace: Array(repeating: 0.2, count: 7),
            gForceXTrace: Array(repeating: 0.1, count: 7),
            gForceZTrace: Array(repeating: 0.3, count: 7),
            pitchTrace: Array(repeating: 0, count: 7),
            relativeAltitudeTrace: Array(repeating: 10, count: 7),
            pressureTrace: Array(repeating: 1_000, count: 7),
            idleTimeSeconds: 0,
            speedTrace: Array(30..<37).map(Double.init),
            rpmTrace: Array(0..<7).map { 2_000 + $0 * 100 },
            best0To100Time: nil,
            gpsAvgSpeedKmh: 33,
            gpsMaxSpeedKmh: 36,
            gpsMinSpeedKmh: 30,
            gpxFileName: "\(id).gpx",
            maxSlipRatio: 0,
            heavySlipCount: 0,
            slipRatioTrace: Array(repeating: 0, count: 7),
            offRoadEvents: [],
            distanceSource: .gps,
            reviewEvents: []
        )
    }
}
