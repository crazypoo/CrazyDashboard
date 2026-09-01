//
//  PTWatchRideAssistant.swift
//  CrazyDashboard
//
//  EN: Shared, read-only navigation state sent from the iPhone to the Watch.
//  ES: Estado de navegación compartido y de solo lectura enviado del iPhone al Watch.
//  中文：从 iPhone 发送到 Watch 的共享只读导航状态。
//

import Foundation

// EN: The source lets the Watch explain whether the prompt comes from a Roadbook or normal navigation.
// ES: La fuente permite que el Watch indique si el aviso viene de un Roadbook o de la navegación normal.
// 中文：来源让 Watch 能说明提示来自 Roadbook 还是普通导航。
nonisolated public enum PTWatchNavigationSource: String, Codable, Equatable, Sendable {
    case none
    case roadbook
    case turnByTurn
}

// EN: These states are intentionally small because the Watch only renders a safe read-only projection.
// ES: Estos estados son deliberadamente pequeños porque el Watch solo muestra una proyección segura de solo lectura.
// 中文：状态保持精简，因为 Watch 只展示安全的只读投影。
nonisolated public enum PTWatchNavigationStatus: String, Codable, Equatable, Sendable {
    case idle
    case active
    case paused
    case offRoute
    case completed
    case rerouting
    case searchingGPS

    public var isVisible: Bool {
        self != .idle
    }

    public var canTriggerHaptic: Bool {
        switch self {
        case .active, .offRoute, .completed, .rerouting, .searchingGPS:
            return true
        case .idle, .paused:
            return false
        }
    }
}

// EN: Dashboard maneuver codes are translated once into semantic Watch haptics and symbols.
// ES: Los códigos de maniobra del tablero se traducen una sola vez a hápticos y símbolos semánticos del Watch.
// 中文：将仪表转向码统一转换为 Watch 可理解的语义触觉和图标。
nonisolated public enum PTWatchNavigationManeuver: String, Codable, Equatable, Sendable {
    case unknown
    case straight
    case keepLeft
    case keepRight
    case left
    case right
    case sharpLeft
    case sharpRight
    case uTurnLeft
    case uTurnRight
    case roundabout
    case depart
    case arrive
    case rerouting
    case noGPS

    nonisolated public init(dashboardCode: UInt8) {
        switch dashboardCode {
        case 1:
            self = .straight
        case 2:
            self = .uTurnRight
        case 3:
            self = .uTurnLeft
        case 4:
            self = .keepRight
        case 5, 6:
            self = .right
        case 7:
            self = .sharpRight
        case 8:
            self = .straight
        case 9:
            self = .keepLeft
        case 10, 11:
            self = .left
        case 12:
            self = .sharpLeft
        case 0x13...0x2A:
            self = .roundabout
        case 43:
            self = .depart
        case 44:
            self = .arrive
        case 48:
            self = .rerouting
        case 49:
            self = .noGPS
        default:
            self = .unknown
        }
    }

    public var symbolName: String {
        switch self {
        case .left, .keepLeft, .sharpLeft, .uTurnLeft:
            return "arrow.turn.up.left"
        case .right, .keepRight, .sharpRight, .uTurnRight:
            return "arrow.turn.up.right"
        case .roundabout:
            return "arrow.triangle.2.circlepath"
        case .arrive:
            return "flag.checkered"
        case .rerouting:
            return "arrow.triangle.2.circlepath"
        case .noGPS:
            return "location.slash"
        case .unknown, .straight, .depart:
            return "arrow.up"
        }
    }
}

// EN: Keep context keys namespaced so new Watch fields cannot collide with legacy Widget keys.
// ES: Mantén las claves del contexto con un espacio de nombres para evitar colisiones con las claves antiguas del Widget.
// 中文：为上下文键增加命名空间，避免与旧 Widget 键冲突。
nonisolated public enum PTWatchRideAssistantContextKeys {
    public static let schemaVersion = "watch_navigation_schemaVersion"
    public static let source = "watch_navigation_source"
    public static let status = "watch_navigation_status"
    public static let routeName = "watch_navigation_routeName"
    public static let instruction = "watch_navigation_instruction"
    public static let maneuver = "watch_navigation_maneuver"
    public static let maneuverIdentifier = "watch_navigation_maneuverIdentifier"
    public static let distanceToManeuverMeters = "watch_navigation_distanceToManeuverMeters"
    public static let distanceToDestinationMeters = "watch_navigation_distanceToDestinationMeters"
    public static let currentStep = "watch_navigation_currentStep"
    public static let totalSteps = "watch_navigation_totalSteps"
    public static let updatedAt = "watch_navigation_updatedAt"
}

// EN: This is the only navigation payload crossing the WatchConnectivity boundary.
// ES: Esta es la única carga útil de navegación que cruza el límite de WatchConnectivity.
// 中文：这是唯一跨越 WatchConnectivity 边界的导航数据载荷。
nonisolated public struct PTWatchRideAssistantState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let source: PTWatchNavigationSource
    public let status: PTWatchNavigationStatus
    public let routeName: String
    public let instruction: String
    public let maneuver: PTWatchNavigationManeuver
    public let maneuverIdentifier: String
    public let distanceToManeuverMeters: Double
    public let distanceToDestinationMeters: Double
    public let currentStep: Int
    public let totalSteps: Int
    public let updatedAt: Date

    nonisolated public static let placeholder = PTWatchRideAssistantState(
        source: .none,
        status: .idle,
        routeName: "",
        instruction: "",
        maneuver: .unknown,
        maneuverIdentifier: "",
        distanceToManeuverMeters: 0,
        distanceToDestinationMeters: 0,
        currentStep: 0,
        totalSteps: 0,
        updatedAt: .distantPast
    )

    nonisolated public init(
        source: PTWatchNavigationSource,
        status: PTWatchNavigationStatus,
        routeName: String,
        instruction: String,
        maneuver: PTWatchNavigationManeuver,
        maneuverIdentifier: String,
        distanceToManeuverMeters: Double,
        distanceToDestinationMeters: Double,
        currentStep: Int,
        totalSteps: Int,
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.source = source
        self.status = status
        self.routeName = routeName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        self.maneuver = maneuver
        self.maneuverIdentifier = maneuverIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.distanceToManeuverMeters = Self.nonNegativeFinite(distanceToManeuverMeters)
        self.distanceToDestinationMeters = Self.nonNegativeFinite(distanceToDestinationMeters)
        self.currentStep = max(0, currentStep)
        self.totalSteps = max(0, totalSteps)
        self.updatedAt = updatedAt
    }

    nonisolated public init?(applicationContext: [String: Any]) {
        guard let schemaVersion = Self.intValue(applicationContext[PTWatchRideAssistantContextKeys.schemaVersion]),
              schemaVersion <= Self.currentSchemaVersion,
              let sourceRawValue = applicationContext[PTWatchRideAssistantContextKeys.source] as? String,
              let source = PTWatchNavigationSource(rawValue: sourceRawValue),
              let statusRawValue = applicationContext[PTWatchRideAssistantContextKeys.status] as? String,
              let status = PTWatchNavigationStatus(rawValue: statusRawValue),
              let routeName = applicationContext[PTWatchRideAssistantContextKeys.routeName] as? String,
              let instruction = applicationContext[PTWatchRideAssistantContextKeys.instruction] as? String,
              let maneuverRawValue = applicationContext[PTWatchRideAssistantContextKeys.maneuver] as? String,
              let maneuver = PTWatchNavigationManeuver(rawValue: maneuverRawValue),
              let distanceToManeuverMeters = Self.doubleValue(applicationContext[PTWatchRideAssistantContextKeys.distanceToManeuverMeters]),
              let distanceToDestinationMeters = Self.doubleValue(applicationContext[PTWatchRideAssistantContextKeys.distanceToDestinationMeters]),
              let currentStep = Self.intValue(applicationContext[PTWatchRideAssistantContextKeys.currentStep]),
              let totalSteps = Self.intValue(applicationContext[PTWatchRideAssistantContextKeys.totalSteps]),
              let updatedAt = Self.doubleValue(applicationContext[PTWatchRideAssistantContextKeys.updatedAt]) else {
            return nil
        }

        self.init(
            source: source,
            status: status,
            routeName: routeName,
            instruction: instruction,
            maneuver: maneuver,
            maneuverIdentifier: applicationContext[PTWatchRideAssistantContextKeys.maneuverIdentifier] as? String ?? "",
            distanceToManeuverMeters: distanceToManeuverMeters,
            distanceToDestinationMeters: distanceToDestinationMeters,
            currentStep: currentStep,
            totalSteps: totalSteps,
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }

    nonisolated public var applicationContext: [String: Any] {
        [
            PTWatchRideAssistantContextKeys.schemaVersion: schemaVersion,
            PTWatchRideAssistantContextKeys.source: source.rawValue,
            PTWatchRideAssistantContextKeys.status: status.rawValue,
            PTWatchRideAssistantContextKeys.routeName: routeName,
            PTWatchRideAssistantContextKeys.instruction: instruction,
            PTWatchRideAssistantContextKeys.maneuver: maneuver.rawValue,
            PTWatchRideAssistantContextKeys.maneuverIdentifier: maneuverIdentifier,
            PTWatchRideAssistantContextKeys.distanceToManeuverMeters: distanceToManeuverMeters,
            PTWatchRideAssistantContextKeys.distanceToDestinationMeters: distanceToDestinationMeters,
            PTWatchRideAssistantContextKeys.currentStep: currentStep,
            PTWatchRideAssistantContextKeys.totalSteps: totalSteps,
            PTWatchRideAssistantContextKeys.updatedAt: updatedAt.timeIntervalSince1970
        ]
    }

    nonisolated public var isFresh: Bool {
        let age = Date().timeIntervalSince(updatedAt)
        return age >= -5 && age <= 180
    }

    nonisolated public var hapticIdentifier: String? {
        guard source != .none, !maneuverIdentifier.isEmpty else { return nil }

        switch status {
        case .offRoute, .completed, .rerouting, .searchingGPS:
            return "\(maneuverIdentifier)|\(status.rawValue)"
        case .idle, .paused, .active:
            return maneuverIdentifier
        }
    }

    private nonisolated static func nonNegativeFinite(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }

    private nonisolated static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private nonisolated static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}
