//
//  PTRoadSurfaceBuild79Tests.swift
//  CrazyDashboard
//
//  EN: Offline regression tests for the Build 79 road-surface classifier.
//  ES: Pruebas de regresión sin conexión para el clasificador de superficie de Build 79.
//  中文：Build 79 道路体验分类器的离线回归测试。
//

import XCTest
@testable import XP400Ride

final class PTRoadSurfaceBuild79Tests: XCTestCase {
    func testQualityThresholdsRemainDeterministic() {
        XCTAssertEqual(PTRoadSurfaceAnalyzer.quality(for: 0), .smooth)
        XCTAssertEqual(PTRoadSurfaceAnalyzer.quality(for: 20), .moderate)
        XCTAssertEqual(PTRoadSurfaceAnalyzer.quality(for: 40), .rough)
        XCTAssertEqual(PTRoadSurfaceAnalyzer.quality(for: 70), .severe)
    }

    func testSegmentsSplitOnTimeGapAndIgnoreOtherVehicle() {
        let vehicleID = UUID()
        let otherVehicleID = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        let samples = [
            sample(vehicleID: vehicleID, date: start, latitude: 48, longitude: 2, verticalG: 0.1),
            sample(vehicleID: vehicleID, date: start.addingTimeInterval(1), latitude: 48, longitude: 2.0001, verticalG: 0.1),
            sample(vehicleID: vehicleID, date: start.addingTimeInterval(6), latitude: 48, longitude: 2.0002, verticalG: 0.1),
            sample(vehicleID: vehicleID, date: start.addingTimeInterval(7), latitude: 48, longitude: 2.0003, verticalG: 0.1),
            sample(vehicleID: otherVehicleID, date: start, latitude: 48, longitude: 2, verticalG: 1.5)
        ]

        let segments = PTRoadSurfaceAnalyzer.makeSegments(
            from: samples,
            vehicleID: vehicleID,
            maximumSamplesPerSegment: 10
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertTrue(segments.allSatisfy { $0.vehicleID == vehicleID })
        XCTAssertEqual(segments.map(\.sampleCount).sorted(), [2, 2])
    }

    func testClassifierDetectsImpactAndSummaryCountsSyntheticData() {
        let vehicleID = UUID()
        let start = Date(timeIntervalSince1970: 2_000)
        let impactSamples = (0..<3).map { index in
            sample(
                vehicleID: vehicleID,
                date: start.addingTimeInterval(Double(index) * 0.2),
                latitude: 48,
                longitude: 2 + Double(index) * 0.0001,
                verticalG: 1.4,
                synthetic: true
            )
        }
        let impact = try! XCTUnwrap(
            PTRoadSurfaceAnalyzer.makeSegments(from: impactSamples, vehicleID: vehicleID).first
        )
        XCTAssertEqual(impact.eventKind, .strongImpact)

        let rough = PTRoadSurfaceSegment(
            vehicleID: vehicleID,
            startedAt: start,
            endedAt: start.addingTimeInterval(1),
            startLatitude: 48,
            startLongitude: 2,
            endLatitude: 48,
            endLongitude: 2.0001,
            sampleCount: 4,
            distanceMeters: 12,
            score: 40,
            quality: .rough,
            eventKind: .roughRoad,
            maxVerticalImpactG: 0.4,
            maxLateralG: 0.2,
            maxLongitudinalG: 0.2,
            averageSpeedKmh: 40,
            confidence: 0.9,
            isSynthetic: true
        )
        let summary = PTRoadSurfaceAnalyzer.summary(
            for: [impact, rough],
            vehicleID: vehicleID,
            now: start.addingTimeInterval(10)
        )
        XCTAssertEqual(summary.severeSegmentCount, 1)
        XCTAssertEqual(summary.roughSegmentCount, 1)
        XCTAssertTrue(summary.isSyntheticOnly)
    }

    func testClassifierKeepsRoadEventKindsDistinct() {
        let vehicleID = UUID()
        let start = Date(timeIntervalSince1970: 2_500)

        let bumpSamples = [
            sample(vehicleID: vehicleID, date: start, latitude: 48, longitude: 2, verticalG: 0.5),
            sample(vehicleID: vehicleID, date: start.addingTimeInterval(0.4), latitude: 48, longitude: 2.0001, verticalG: 0.5)
        ]
        XCTAssertEqual(
            PTRoadSurfaceAnalyzer.makeSegments(from: bumpSamples, vehicleID: vehicleID).first?.eventKind,
            .speedBump
        )

        let potholeSamples = [
            sample(vehicleID: vehicleID, date: start, latitude: 48, longitude: 2, verticalG: 0.7)
        ]
        XCTAssertEqual(
            PTRoadSurfaceAnalyzer.makeSegments(from: potholeSamples, vehicleID: vehicleID).first?.eventKind,
            .potholeCandidate
        )

        let vibrationSamples = (0..<6).map { index in
            sample(
                vehicleID: vehicleID,
                date: start.addingTimeInterval(Double(index) * 0.2),
                latitude: 48,
                longitude: 2 + Double(index) * 0.0001,
                verticalG: 0.25
            )
        }
        XCTAssertEqual(
            PTRoadSurfaceAnalyzer.makeSegments(from: vibrationSamples, vehicleID: vehicleID).first?.eventKind,
            .repeatedVibration
        )
    }

    func testInvalidCoordinatesAreRejected() {
        let vehicleID = UUID()
        let invalid = sample(
            vehicleID: vehicleID,
            date: Date(timeIntervalSince1970: 3_000),
            latitude: 180,
            longitude: 2,
            verticalG: 0.2
        )
        XCTAssertTrue(
            PTRoadSurfaceAnalyzer.makeSegments(from: [invalid], vehicleID: vehicleID).isEmpty
        )
    }

    private func sample(
        vehicleID: UUID,
        date: Date,
        latitude: Double,
        longitude: Double,
        verticalG: Double,
        synthetic: Bool = false
    ) -> PTRoadSurfaceSample {
        PTRoadSurfaceSample(
            vehicleID: vehicleID,
            capturedAt: date,
            latitude: latitude,
            longitude: longitude,
            speedKmh: 50,
            verticalG: verticalG,
            lateralG: 0,
            longitudinalG: 0,
            horizontalAccuracyMeters: 5,
            isSynthetic: synthetic
        )
    }
}
