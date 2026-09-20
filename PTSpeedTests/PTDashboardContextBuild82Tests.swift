//
//  PTDashboardContextBuild82Tests.swift
//  PTSpeedTests
//
//  EN: Pure priority and module-policy regression tests for Build 82.
//  ES: Pruebas puras de prioridad y política de módulos para Build 82.
//  中文：Build82 优先级与模块策略纯数据回归测试。
//

import XCTest
@testable import XP400Ride

final class PTDashboardContextBuild82Tests: XCTestCase {
    func testWarningAlwaysWinsOverNavigationAndMedia() {
        let snapshot = PTDashboardContextResolver.resolve(
            PTDashboardContextInput(
                isRiding: true,
                isNavigating: true,
                isManeuver: true,
                mediaChanged: true,
                warningActive: true,
                connectionDegraded: true
            )
        )

        XCTAssertEqual(snapshot.primaryContext, .warning)
        XCTAssertTrue(snapshot.presentation(for: .warning).isVisible)
        XCTAssertTrue(snapshot.presentation(for: .warning).isEmphasized)
        XCTAssertFalse(snapshot.presentation(for: .media).isVisible)
    }

    func testManeuverPromotesNavigationAndCompactsTwin() {
        let snapshot = PTDashboardContextResolver.resolve(
            PTDashboardContextInput(isRiding: true, isNavigating: true, isManeuver: true),
            navigationDistanceMeters: 180,
            navigationRoadName: "Avenue XP400"
        )

        XCTAssertEqual(snapshot.primaryContext, .maneuver)
        XCTAssertTrue(snapshot.presentation(for: .navigation).isEmphasized)
        XCTAssertTrue(snapshot.presentation(for: .vehicleTwin).isCompact)
        XCTAssertEqual(snapshot.navigationDistanceMeters, 180)
    }

    func testParkedKeepsTwinAndHealthVisible() {
        let snapshot = PTDashboardContextResolver.resolve(PTDashboardContextInput())

        XCTAssertEqual(snapshot.primaryContext, .parked)
        XCTAssertTrue(snapshot.presentation(for: .vehicleTwin).isVisible)
        XCTAssertFalse(snapshot.presentation(for: .vehicleTwin).isCompact)
        XCTAssertTrue(snapshot.presentation(for: .health).isVisible)
        XCTAssertFalse(snapshot.presentation(for: .navigation).isVisible)
    }

    func testRidingDoesNotLetMediaChangeInterruptVehiclePriority() {
        let snapshot = PTDashboardContextResolver.resolve(
            PTDashboardContextInput(isRiding: true, mediaChanged: true)
        )

        XCTAssertEqual(snapshot.primaryContext, .riding)
        XCTAssertTrue(snapshot.presentation(for: .speedRPM).isEmphasized)
        XCTAssertTrue(snapshot.presentation(for: .media).isVisible)
        XCTAssertFalse(snapshot.presentation(for: .media).isEmphasized)
    }

    func testConnectionDegradedKeepsMediaMounted() {
        let snapshot = PTDashboardContextResolver.resolve(
            PTDashboardContextInput(isRiding: true, connectionDegraded: true)
        )

        XCTAssertEqual(snapshot.primaryContext, .connectionDegraded)
        XCTAssertTrue(snapshot.presentation(for: .media).isVisible)
    }

    func testInvalidSpeedCannotCreateRidingState() {
        let snapshot = PTDashboardContextResolver.resolve(
            PTDashboardContextInput(speedKmh: .infinity)
        )

        XCTAssertEqual(snapshot.primaryContext, .parked)
    }
}
