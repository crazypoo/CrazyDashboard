//
//  PTDashboardThemeBuild83Tests.swift
//  PTSpeedTests
//
//  EN: Pure theme, safety and contrast regression tests for Build 83.
//  ES: Pruebas puras de tema, seguridad y contraste para Build 83.
//  中文：Build83 主题、安全模式和对比度纯逻辑回归测试。
//

import XCTest
import UIKit
@testable import XP400Ride

@MainActor
final class PTDashboardThemeBuild83Tests: XCTestCase {
    func testArtworkThemeProducesNonDefaultDecoration() {
        let palette = PTArtworkColorPalette(
            dominant: PTDashboardThemeColor(red: 0.75, green: 0.08, blue: 0.12),
            accent: PTDashboardThemeColor(red: 1, green: 0.35, blue: 0.08)
        )

        let tokens = PTDashboardThemeResolver.resolve(
            palette: palette,
            enabled: true,
            context: .parked
        )

        XCTAssertEqual(tokens.source, .artwork)
        XCTAssertFalse(tokens.isSafetyFallback)
        XCTAssertGreaterThan(tokens.decorationOpacity, 0)
        XCTAssertNotEqual(tokens.background, PTDashboardThemeTokens.fallback.background)
    }

    func testWarningUsesSafetyFallback() {
        let palette = PTArtworkColorPalette(
            dominant: PTDashboardThemeColor(red: 0.12, green: 0.75, blue: 0.20),
            accent: PTDashboardThemeColor(red: 0.20, green: 0.90, blue: 0.40)
        )

        let tokens = PTDashboardThemeResolver.resolve(
            palette: palette,
            enabled: true,
            context: .warning
        )

        XCTAssertEqual(tokens.source, .safetyFallback)
        XCTAssertTrue(tokens.isSafetyFallback)
        XCTAssertEqual(tokens.background, PTDashboardThemeTokens.fallback.background)
    }

    func testWarningWithoutArtworkStillUsesSafetyFallback() {
        let tokens = PTDashboardThemeResolver.resolve(
            palette: nil,
            enabled: true,
            context: .warning
        )

        XCTAssertEqual(tokens.source, .safetyFallback)
        XCTAssertTrue(tokens.isSafetyFallback)
    }

    func testDisabledThemeFallsBackWithoutArtwork() {
        let tokens = PTDashboardThemeResolver.resolve(
            palette: PTArtworkColorPalette(
                dominant: PTDashboardThemeColor(red: 0.9, green: 0.1, blue: 0.1),
                accent: PTDashboardThemeColor(red: 1, green: 0.8, blue: 0.1)
            ),
            enabled: false,
            context: .parked
        )

        XCTAssertEqual(tokens.source, .default)
        XCTAssertFalse(tokens.isSafetyFallback)
        XCTAssertEqual(tokens, PTDashboardThemeTokens.fallback)
    }

    func testNavigationKeepsThemeSubtle() {
        let palette = PTArtworkColorPalette(
            dominant: PTDashboardThemeColor(red: 0.10, green: 0.20, blue: 0.80),
            accent: PTDashboardThemeColor(red: 0.30, green: 0.60, blue: 1.0)
        )

        let tokens = PTDashboardThemeResolver.resolve(
            palette: palette,
            enabled: true,
            context: .navigating
        )

        XCTAssertEqual(tokens.source, .artwork)
        XCTAssertLessThanOrEqual(tokens.decorationOpacity, 0.30)
        XCTAssertFalse(tokens.isSafetyFallback)
    }

    func testArtworkExtractorReadsNativePNGWithoutUIKitCrossingBoundary() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let data = renderer.pngData { context in
            UIColor(red: 0.86, green: 0.08, blue: 0.10, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }

        let palette = PTDashboardArtworkColorExtractor.extract(from: data)

        XCTAssertNotNil(palette)
        XCTAssertGreaterThan(palette?.dominant.red ?? 0, palette?.dominant.blue ?? 1)
        XCTAssertGreaterThan(palette?.dominant.red ?? 0, palette?.dominant.green ?? 1)
    }
}
