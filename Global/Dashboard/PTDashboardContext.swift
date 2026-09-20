//
//  PTDashboardContext.swift
//  CrazyDashboard
//
//  EN: Value-only context and module policy for the dynamic dashboard.
//  ES: Contexto de solo valor y política de módulos para el tablero dinámico.
//  中文：动态仪表盘使用的值类型上下文与模块策略。
//

import Foundation

// EN: These contexts describe presentation intent, not a new vehicle or navigation state machine.
// ES: Estos contextos describen la intención de presentación, no una nueva máquina de estados del vehículo o la navegación.
// 中文：这些上下文只描述展示意图，不创建新的车辆或导航状态机。
public nonisolated enum PTDashboardContext: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case parked
    case riding
    case navigating
    case maneuver
    case mediaChanged
    case warning
    case connectionDegraded

    var priority: Int {
        switch self {
        case .warning: return 700
        case .maneuver: return 600
        case .navigating: return 500
        case .connectionDegraded: return 400
        case .riding: return 300
        case .mediaChanged: return 200
        case .parked: return 100
        }
    }
}

public nonisolated enum PTDashboardModule: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case vehicleTwin
    case health
    case speedRPM
    case navigation
    case warning
    case media
}

// EN: A module receives a small, deterministic policy instead of inspecting every input source itself.
// ES: Cada módulo recibe una política pequeña y determinista en lugar de inspeccionar todas las fuentes por sí mismo.
// 中文：模块只接收小而确定的展示策略，不再各自读取所有输入源。
public nonisolated struct PTDashboardModulePresentation: Equatable, Sendable {
    public let isVisible: Bool
    public let isCompact: Bool
    public let isEmphasized: Bool
    public let priority: Int

    public init(
        isVisible: Bool,
        isCompact: Bool,
        isEmphasized: Bool,
        priority: Int
    ) {
        self.isVisible = isVisible
        self.isCompact = isCompact
        self.isEmphasized = isEmphasized
        self.priority = priority
    }

    public static let hidden = PTDashboardModulePresentation(
        isVisible: false,
        isCompact: true,
        isEmphasized: false,
        priority: 0
    )
}

public nonisolated struct PTDashboardContextInput: Equatable, Sendable {
    public var speedKmh: Double?
    public var isRiding: Bool
    public var isNavigating: Bool
    public var isManeuver: Bool
    public var mediaChanged: Bool
    public var warningActive: Bool
    public var connectionDegraded: Bool

    public init(
        speedKmh: Double? = nil,
        isRiding: Bool = false,
        isNavigating: Bool = false,
        isManeuver: Bool = false,
        mediaChanged: Bool = false,
        warningActive: Bool = false,
        connectionDegraded: Bool = false
    ) {
        self.speedKmh = speedKmh
        self.isRiding = isRiding
        self.isNavigating = isNavigating
        self.isManeuver = isManeuver
        self.mediaChanged = mediaChanged
        self.warningActive = warningActive
        self.connectionDegraded = connectionDegraded
    }
}

public nonisolated struct PTDashboardContextSnapshot: Equatable, Sendable {
    public let primaryContext: PTDashboardContext
    public let activeContexts: [PTDashboardContext]
    public let modulePresentations: [PTDashboardModule: PTDashboardModulePresentation]
    public let navigationDistanceMeters: Double?
    public let navigationRoadName: String?
    public let updatedAt: Date

    public init(
        primaryContext: PTDashboardContext,
        activeContexts: [PTDashboardContext],
        modulePresentations: [PTDashboardModule: PTDashboardModulePresentation],
        navigationDistanceMeters: Double? = nil,
        navigationRoadName: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.primaryContext = primaryContext
        self.activeContexts = activeContexts
        self.modulePresentations = modulePresentations
        self.navigationDistanceMeters = navigationDistanceMeters
        self.navigationRoadName = navigationRoadName
        self.updatedAt = updatedAt
    }

    public func presentation(for module: PTDashboardModule) -> PTDashboardModulePresentation {
        modulePresentations[module] ?? .hidden
    }

    // EN: Time changes alone must not force a UI render at telemetry frequency.
    // ES: Un cambio de hora por sí solo no debe forzar un render a la frecuencia de la telemetría.
    // 中文：仅时间变化不能在遥测频率下强制触发 UI 重绘。
    public func isEquivalentState(to other: PTDashboardContextSnapshot) -> Bool {
        primaryContext == other.primaryContext
            && activeContexts == other.activeContexts
            && modulePresentations == other.modulePresentations
            && navigationDistanceMeters == other.navigationDistanceMeters
            && navigationRoadName == other.navigationRoadName
    }
}

// EN: The resolver is pure so priority, module visibility and safety ordering are regression-testable.
// ES: El resolvedor es puro para poder probar la prioridad, visibilidad y orden de seguridad.
// 中文：Resolver 保持纯函数，便于回归测试优先级、模块可见性和安全顺序。
public nonisolated enum PTDashboardContextResolver {
    public static let maneuverDistanceMeters: Double = 500

    public static func resolve(
        _ input: PTDashboardContextInput,
        navigationDistanceMeters: Double? = nil,
        navigationRoadName: String? = nil,
        now: Date = Date()
    ) -> PTDashboardContextSnapshot {
        let validSpeed = input.speedKmh.flatMap { value in
            value.isFinite && value >= 0 ? value : nil
        }
        let isRiding = input.isRiding || (validSpeed.map { $0 >= 3 } ?? false)

        var activeContexts: [PTDashboardContext] = []
        if input.warningActive {
            activeContexts.append(.warning)
        }
        if input.isManeuver {
            activeContexts.append(.maneuver)
        } else if input.isNavigating {
            activeContexts.append(.navigating)
        }
        if input.connectionDegraded {
            activeContexts.append(.connectionDegraded)
        }
        if isRiding {
            activeContexts.append(.riding)
        }
        if input.mediaChanged {
            activeContexts.append(.mediaChanged)
        }
        if activeContexts.isEmpty {
            activeContexts.append(.parked)
        }

        activeContexts.sort { lhs, rhs in
            if lhs.priority == rhs.priority { return lhs.rawValue < rhs.rawValue }
            return lhs.priority > rhs.priority
        }
        let primaryContext = activeContexts[0]
        let presentations = Dictionary(uniqueKeysWithValues: PTDashboardModule.allCases.map { module in
            (module, presentation(for: module, primary: primaryContext, active: activeContexts))
        })

        return PTDashboardContextSnapshot(
            primaryContext: primaryContext,
            activeContexts: activeContexts,
            modulePresentations: presentations,
            navigationDistanceMeters: navigationDistanceMeters,
            navigationRoadName: navigationRoadName,
            updatedAt: now
        )
    }

    private static func presentation(
        for module: PTDashboardModule,
        primary: PTDashboardContext,
        active: [PTDashboardContext]
    ) -> PTDashboardModulePresentation {
        let hasNavigation = active.contains(.navigating) || active.contains(.maneuver)
        let hasWarning = active.contains(.warning)

        switch module {
        case .vehicleTwin:
            return PTDashboardModulePresentation(
                isVisible: true,
                isCompact: primary != .parked && primary != .mediaChanged,
                isEmphasized: primary == .warning,
                priority: PTDashboardContext.riding.priority
            )
        case .health:
            return PTDashboardModulePresentation(
                isVisible: primary == .parked || primary == .mediaChanged,
                isCompact: false,
                isEmphasized: primary == .parked,
                priority: PTDashboardContext.parked.priority
            )
        case .speedRPM:
            return PTDashboardModulePresentation(
                isVisible: true,
                isCompact: primary == .parked || primary == .mediaChanged,
                isEmphasized: primary == .riding || primary == .warning,
                priority: PTDashboardContext.riding.priority
            )
        case .navigation:
            return PTDashboardModulePresentation(
                isVisible: hasNavigation,
                isCompact: primary != .maneuver,
                isEmphasized: primary == .navigating || primary == .maneuver,
                priority: PTDashboardContext.navigating.priority
            )
        case .warning:
            return PTDashboardModulePresentation(
                isVisible: hasWarning,
                isCompact: false,
                isEmphasized: primary == .warning,
                priority: PTDashboardContext.warning.priority
            )
        case .media:
            return PTDashboardModulePresentation(
                isVisible: !hasWarning && primary != .maneuver && primary != .connectionDegraded,
                isCompact: primary != .parked && primary != .mediaChanged,
                isEmphasized: primary == .mediaChanged,
                priority: PTDashboardContext.mediaChanged.priority
            )
        }
    }
}

// EN: UIKit modules can consume the same policy without knowing where the context came from.
// ES: Los módulos UIKit pueden consumir la misma política sin conocer el origen del contexto.
// 中文：UIKit 模块可以消费同一份策略，而无需知道上下文来源。
@MainActor
protocol PTDashboardModuleView: AnyObject {
    var dashboardModule: PTDashboardModule { get }
    func applyDashboardPresentation(_ presentation: PTDashboardModulePresentation)
}
