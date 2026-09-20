//
//  PTVehicleIntelligenceBuild85Tests.swift
//  PTSpeedTests
//
//  EN: Pure Build 85 tests for evidence, guardrails, rules, expiry and notification eligibility.
//  ES: Pruebas puras de Build 85 para evidencia, límites, reglas, caducidad y avisos elegibles.
//  中文：Build 85 的证据、护栏、规则、过期和通知资格纯逻辑测试。
//

import XCTest
@testable import XP400Ride

@MainActor
final class PTVehicleIntelligenceBuild85Tests: XCTestCase {
    private let vehicleID = UUID()
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testSixRealStartupSamplesCreateEvidenceBackedBatteryTrend() {
        let points = [12.6, 12.4, 12.2, 12.1, 11.8, 11.5].enumerated().map { index, value in
            PTVehicleHealthPoint(
                vehicleID: vehicleID,
                capturedAt: referenceDate.addingTimeInterval(TimeInterval(index * 60)),
                source: .batteryHistory,
                crankVoltage: value
            )
        }

        let summary = makeSummary(health: points)
        let insight = try! XCTUnwrap(summary.insights.first { $0.id == "battery.crank.trend" })

        XCTAssertEqual(insight.evidence.first?.source, .healthTimeline)
        XCTAssertEqual(insight.evidence.first?.sampleCount, 6)
        XCTAssertEqual(insight.evidence.first?.quality, .observed)
        XCTAssertEqual(insight.primaryValue, 11.5)
        XCTAssertTrue(PTVehicleIntelligenceNotificationPolicy.eligibleInsights(from: summary).contains(insight))
    }

    func testSyntheticBatteryValuesNeverBecomeActionable() {
        let points = (0..<6).map { index in
            PTVehicleHealthPoint(
                vehicleID: vehicleID,
                capturedAt: referenceDate.addingTimeInterval(TimeInterval(index * 60)),
                source: .batteryHistory,
                isSynthetic: true,
                crankVoltage: 12.0 - Double(index) * 0.2
            )
        }

        let summary = makeSummary(health: points)

        XCTAssertFalse(summary.insights.contains { $0.isActionable })
        XCTAssertTrue(summary.falsePositiveReview.suppressedRuleIDs.contains("battery.low.synthetic-only"))
    }

    func testConfirmedAndPendingDiagnosticsHaveDifferentSeverity() {
        let confirmed = makeHealthPoint(
            source: .diagnostic,
            confirmedDTCCount: 1,
            capturedAt: referenceDate
        )
        let confirmedSummary = makeSummary(health: [confirmed])
        XCTAssertEqual(confirmedSummary.insights.first(where: { $0.kind == .confirmedDTC })?.severity, .critical)

        let pending = makeHealthPoint(
            source: .diagnostic,
            pendingDTCCount: 2,
            permanentDTCCount: 1,
            capturedAt: referenceDate
        )
        let pendingSummary = makeSummary(health: [pending])
        XCTAssertEqual(pendingSummary.insights.first(where: { $0.kind == .pendingDTC })?.severity, .attention)
        XCTAssertEqual(PTVehicleIntelligenceNotificationPolicy.eligibleInsights(from: pendingSummary).count, 1)
    }

    func testMaintenanceUsesSelectedGarageDistanceWithoutCreatingDuplicateNotification() {
        let profile = PTMotorcycleProfile(
            id: vehicleID,
            name: "XP400 GT",
            odometerKm: 9_900,
            dashboardMaintenanceDistanceKm: 100,
            maintenanceWarningDistanceKm: 500
        )

        let summary = makeSummary(profile: profile)
        let insight = try! XCTUnwrap(summary.insights.first { $0.kind == .maintenance })

        XCTAssertEqual(insight.primaryValue, 100)
        XCTAssertFalse(PTVehicleIntelligenceNotificationPolicy.eligibleInsights(from: summary).contains(insight))
    }

    func testRoadEvidenceIsDescriptiveAndNotAnActionableFault() {
        let segment = PTRoadSurfaceSegment(
            vehicleID: vehicleID,
            startedAt: referenceDate,
            endedAt: referenceDate.addingTimeInterval(10),
            startLatitude: 31,
            startLongitude: 121,
            endLatitude: 31,
            endLongitude: 121.001,
            sampleCount: 8,
            distanceMeters: 30,
            score: 80,
            quality: .severe,
            eventKind: .strongImpact,
            maxVerticalImpactG: 1.4,
            maxLateralG: 0.2,
            maxLongitudinalG: 0.3,
            averageSpeedKmh: 35,
            confidence: 0.8
        )

        let summary = makeSummary(roadSegments: [segment])
        let insight = try! XCTUnwrap(summary.insights.first { $0.kind == .roadSummary })

        XCTAssertEqual(insight.evidence.first?.quality, .inferred)
        XCTAssertFalse(insight.isActionable)
    }

    func testOnlyFreshConfirmedXP400ABSStateIsIncluded() {
        let confirmed = makeTwin(abs: .warning, source: .xp400BLE, freshness: .fresh)
        let confirmedSummary = makeSummary(twin: confirmed)
        XCTAssertNotNil(confirmedSummary.insights.first { $0.kind == .absWarning })

        let probable = makeTwin(abs: .warning, source: .obd, freshness: .fresh)
        let probableSummary = makeSummary(twin: probable)
        XCTAssertNil(probableSummary.insights.first { $0.kind == .absWarning })
        XCTAssertTrue(probableSummary.falsePositiveReview.suppressedRuleIDs.contains("semantic.abs-warning.unconfirmed"))
    }

    func testExpiredRideAndRoadInsightsAreNotReusedByTheAnalyzer() {
        let segment = PTRoadSurfaceSegment(
            vehicleID: vehicleID,
            startedAt: referenceDate.addingTimeInterval(-90_000),
            endedAt: referenceDate.addingTimeInterval(-86_400 - 1),
            startLatitude: 31,
            startLongitude: 121,
            endLatitude: 31,
            endLongitude: 121.001,
            sampleCount: 8,
            distanceMeters: 30,
            score: 80,
            quality: .severe,
            eventKind: .strongImpact,
            maxVerticalImpactG: 1.4,
            maxLateralG: 0.2,
            maxLongitudinalG: 0.3,
            averageSpeedKmh: 35,
            confidence: 0.8
        )

        let summary = makeSummary(roadSegments: [segment])

        XCTAssertFalse(summary.insights.contains { $0.kind == .roadSummary })
    }

    private func makeSummary(
        health: [PTVehicleHealthPoint] = [],
        roadSegments: [PTRoadSurfaceSegment] = [],
        profile: PTMotorcycleProfile? = nil,
        twin: PTVehicleTwinSnapshot = .empty
    ) -> PTVehicleIntelligenceSummary {
        PTVehicleIntelligenceAnalyzer.make(
            input: PTVehicleIntelligenceInput(
                vehicleID: vehicleID,
                healthPoints: health,
                roadSegments: roadSegments,
                tripReports: [],
                profile: profile,
                twin: twin,
                now: referenceDate
            )
        )
    }

    private func makeHealthPoint(
        source: PTVehicleHealthPointSource,
        confirmedDTCCount: Int? = nil,
        pendingDTCCount: Int? = nil,
        permanentDTCCount: Int? = nil,
        capturedAt: Date
    ) -> PTVehicleHealthPoint {
        PTVehicleHealthPoint(
            vehicleID: vehicleID,
            capturedAt: capturedAt,
            source: source,
            confirmedDTCCount: confirmedDTCCount,
            pendingDTCCount: pendingDTCCount,
            permanentDTCCount: permanentDTCCount
        )
    }

    private func makeTwin(
        abs: PTVehicleTwinABSState,
        source: PTVehicleTelemetrySource,
        freshness: PTVehicleTwinFreshness
    ) -> PTVehicleTwinSnapshot {
        PTVehicleTwinSnapshot(
            updatedAt: referenceDate,
            speedKmh: nil,
            rpm: nil,
            fuelPercent: nil,
            voltage: nil,
            leanDegrees: nil,
            pitchDegrees: nil,
            longitudinalG: nil,
            lateralG: nil,
            kickstandDown: nil,
            engineState: nil,
            leftIndicatorOn: nil,
            rightIndicatorOn: nil,
            hazardOn: nil,
            lowBeamOn: nil,
            highBeamOn: nil,
            tcsState: nil,
            absState: PTVehicleTwinMetric(
                value: abs,
                source: source,
                capturedAt: referenceDate,
                freshness: freshness
            ),
            coordinate: nil,
            dashboardConnected: true,
            obdConnected: false,
            freshness: freshness,
            isSynthetic: false
        )
    }
}
