//
//  PTSpeedUITests.swift
//  CrazyDashboard
//
//  EN: Minimal launch smoke test for the single PTSpeed TestFlight channel.
//  ES: Prueba mínima de arranque para el único canal TestFlight de PTSpeed.
//  中文：为唯一 PTSpeed TestFlight 渠道提供最小启动冒烟测试。
//

import XCTest

final class PTSpeedUITests: XCTestCase {
    func testApplicationLaunchesInReadOnlyMode() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReadOnly"]
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10),
            "PTSpeed should reach the foreground without entering a developer or write flow."
        )
    }
}
