//
//  PTDashboardTheme.swift
//  CrazyDashboard
//
//  EN: Value-only decoration tokens for the music-aware dashboard theme.
//  ES: Tokens de decoración basados en valores para el tema musical del tablero.
//  中文：音乐主题仪表盘使用的纯值装饰令牌。
//

import Foundation
import UIKit

// EN: RGB values cross async boundaries; UIKit colors are created only on the main actor.
// ES: Los valores RGB cruzan límites asíncronos; los colores UIKit se crean solo en el actor principal.
// 中文：RGB 数值可以跨越异步边界，UIKit 颜色只在主线程创建。
public nonisolated struct PTDashboardThemeColor: Equatable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    public func scaled(by factor: Double) -> Self {
        Self(red: red * factor, green: green * factor, blue: blue * factor, alpha: alpha)
    }

    public func blended(with other: Self, amount: Double) -> Self {
        let weight = Self.clamp(amount)
        return Self(
            red: red + (other.red - red) * weight,
            green: green + (other.green - green) * weight,
            blue: blue + (other.blue - blue) * weight,
            alpha: alpha + (other.alpha - alpha) * weight
        )
    }

    public func withAlpha(_ value: Double) -> Self {
        Self(red: red, green: green, blue: blue, alpha: value)
    }

    public static let white = PTDashboardThemeColor(red: 1, green: 1, blue: 1)

    @MainActor
    public var uiColor: UIColor {
        UIColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, 0), 1)
    }
}

public nonisolated enum PTDashboardThemeSource: String, Equatable, Sendable {
    case `default`
    case artwork
    case safetyFallback
}

public nonisolated struct PTArtworkColorPalette: Equatable, Sendable {
    public let dominant: PTDashboardThemeColor
    public let accent: PTDashboardThemeColor

    public init(dominant: PTDashboardThemeColor, accent: PTDashboardThemeColor) {
        self.dominant = dominant
        self.accent = accent
    }
}

// EN: Tokens are decorative only; semantic vehicle and navigation colors stay outside this type.
// ES: Estos tokens son solo decorativos; los colores semánticos del vehículo y la navegación quedan fuera.
// 中文：这些令牌只负责装饰，车辆和导航的语义颜色不由它控制。
public nonisolated struct PTDashboardThemeTokens: Equatable, Sendable {
    public let background: PTDashboardThemeColor
    public let ambient: PTDashboardThemeColor
    public let glow: PTDashboardThemeColor
    public let cardStart: PTDashboardThemeColor
    public let cardEnd: PTDashboardThemeColor
    public let primaryText: PTDashboardThemeColor
    public let secondaryText: PTDashboardThemeColor
    public let source: PTDashboardThemeSource
    public let decorationOpacity: Double
    public let isSafetyFallback: Bool

    public init(
        background: PTDashboardThemeColor,
        ambient: PTDashboardThemeColor,
        glow: PTDashboardThemeColor,
        cardStart: PTDashboardThemeColor,
        cardEnd: PTDashboardThemeColor,
        primaryText: PTDashboardThemeColor,
        secondaryText: PTDashboardThemeColor,
        source: PTDashboardThemeSource,
        decorationOpacity: Double,
        isSafetyFallback: Bool
    ) {
        self.background = background
        self.ambient = ambient
        self.glow = glow
        self.cardStart = cardStart
        self.cardEnd = cardEnd
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.source = source
        self.decorationOpacity = min(max(decorationOpacity.isFinite ? decorationOpacity : 0, 0), 1)
        self.isSafetyFallback = isSafetyFallback
    }

    public static let fallback = PTDashboardThemeTokens(
        background: PTDashboardThemeColor(red: 0.035, green: 0.055, blue: 0.10),
        ambient: PTDashboardThemeColor(red: 0.15, green: 0.45, blue: 0.95),
        glow: PTDashboardThemeColor(red: 0.18, green: 0.55, blue: 1),
        cardStart: PTDashboardThemeColor(red: 0.06, green: 0.09, blue: 0.16),
        cardEnd: PTDashboardThemeColor(red: 0.08, green: 0.15, blue: 0.25),
        primaryText: PTDashboardThemeColor(red: 1, green: 1, blue: 1),
        secondaryText: PTDashboardThemeColor(red: 0.78, green: 0.84, blue: 0.92),
        source: .default,
        decorationOpacity: 1,
        isSafetyFallback: false
    )

    @MainActor
    public var backgroundColor: UIColor { background.uiColor }

    @MainActor
    public var ambientColor: UIColor { ambient.uiColor }

    @MainActor
    public var glowColor: UIColor { glow.uiColor }

    @MainActor
    public var cardStartColor: UIColor { cardStart.uiColor }

    @MainActor
    public var cardEndColor: UIColor { cardEnd.uiColor }

    @MainActor
    public var primaryTextColor: UIColor { primaryText.uiColor }

    @MainActor
    public var secondaryTextColor: UIColor { secondaryText.uiColor }
}

public nonisolated enum PTDashboardThemeResolver {

    public static func resolve(
        palette: PTArtworkColorPalette?,
        enabled: Bool,
        context: PTDashboardContext
    ) -> PTDashboardThemeTokens {
        let safetyContext = context == .warning || context == .maneuver
        guard !safetyContext else {
            return safetyFallbackIfNeeded(true)
        }
        guard enabled, let palette else {
            return safetyFallbackIfNeeded(false)
        }

        let dominant = darkBackground(palette.dominant)
        let accent = darkBackground(palette.accent)
        let cardStart = readableBackground(dominant.blended(with: accent, amount: 0.18))
        let cardEnd = readableBackground(dominant.blended(with: accent, amount: 0.38))
        let primaryText = contrastText(on: cardStart)
        let secondaryText = primaryText.withAlpha(0.76)

        let opacity: Double
        switch context {
        case .parked, .mediaChanged:
            opacity = 0.92
        case .riding:
            opacity = 0.58
        case .navigating:
            opacity = 0.28
        case .connectionDegraded:
            opacity = 0.22
        case .warning, .maneuver:
            opacity = 0
        }

        return PTDashboardThemeTokens(
            background: dominant,
            ambient: palette.accent.withAlpha(0.58),
            glow: palette.accent.withAlpha(0.76),
            cardStart: cardStart,
            cardEnd: cardEnd,
            primaryText: primaryText,
            secondaryText: secondaryText,
            source: .artwork,
            decorationOpacity: opacity,
            isSafetyFallback: false
        )
    }

    private static func safetyFallbackIfNeeded(_ safety: Bool) -> PTDashboardThemeTokens {
        guard safety else { return .fallback }
        return PTDashboardThemeTokens(
            background: PTDashboardThemeTokens.fallback.background,
            ambient: PTDashboardThemeTokens.fallback.ambient,
            glow: PTDashboardThemeTokens.fallback.glow,
            cardStart: PTDashboardThemeTokens.fallback.cardStart,
            cardEnd: PTDashboardThemeTokens.fallback.cardEnd,
            primaryText: PTDashboardThemeTokens.fallback.primaryText,
            secondaryText: PTDashboardThemeTokens.fallback.secondaryText,
            source: .safetyFallback,
            decorationOpacity: 1,
            isSafetyFallback: true
        )
    }

    private static func darkBackground(_ color: PTDashboardThemeColor) -> PTDashboardThemeColor {
        color.scaled(by: 0.18).withAlpha(1)
    }

    private static func readableBackground(_ color: PTDashboardThemeColor) -> PTDashboardThemeColor {
        var candidate = color
        for _ in 0..<12 where contrastRatio(candidate, .white) < 4.5 {
            candidate = candidate.scaled(by: 0.84)
        }
        return candidate.withAlpha(0.96)
    }

    private static func contrastText(on background: PTDashboardThemeColor) -> PTDashboardThemeColor {
        let white = PTDashboardThemeColor(red: 1, green: 1, blue: 1)
        let black = PTDashboardThemeColor(red: 0.02, green: 0.02, blue: 0.02)
        return contrastRatio(background, white) >= contrastRatio(background, black) ? white : black
    }

    private static func contrastRatio(
        _ lhs: PTDashboardThemeColor,
        _ rhs: PTDashboardThemeColor
    ) -> Double {
        let first = relativeLuminance(lhs)
        let second = relativeLuminance(rhs)
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(_ color: PTDashboardThemeColor) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red)
            + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
    }
}
