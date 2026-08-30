//
//  PTRoutingManager.swift
//  CrazyDashboard
//
//  EN: External URL routes and App Intent actions share this main-actor executor.
//  ES: Las rutas URL externas y las acciones de App Intents comparten este ejecutor del actor principal.
//  中文：外部 URL 路由和 App Intent 动作共用这个主线程执行器。
//

import Foundation
import UIKit
import PooTools

public let MotorcycleSearchAndNavigate = NSNotification.Name("MotorcycleSearchAndNavigate")

// EN: This is the compatibility action model for URL Schemes and App Intents.
// ES: Este es el modelo de acciones compatible para URL Schemes y App Intents.
// 中文：这是 URL Scheme 与 App Intents 共用的兼容动作模型。
public enum PTExternalAction: Equatable, Sendable {
    case checkFuel
    case toggleAntiTheft(enable: Bool)
    case openHUD
    case confirmGasStationRoute
    case navigateTo(destination: String)
    case unknown
}

// EN: Keep the old public symbol source-compatible for callers outside this repository.
// ES: Conservamos el símbolo público antiguo para mantener compatibles los llamadores externos.
// 中文：保留旧的公共符号，避免仓库外调用方失去源码兼容性。
public typealias PTAppIntent = PTExternalAction

public enum PTRouteExecutionResult: String, Equatable, Sendable {
    case completed
    case started
    case unavailable
    case rejected

    public var succeeded: Bool {
        switch self {
        case .completed, .started:
            return true
        case .unavailable, .rejected:
            return false
        }
    }
}

@MainActor
public final class PTRoutingManager: NSObject {

    public static let shared = PTRoutingManager()

    private nonisolated static let appScheme = "xp400"
    private nonisolated static let maximumDestinationLength = 256

    private override init() {
        super.init()
    }

    // MARK: - Parsing

    /// EN: Parse without side effects so URL handling can be tested independently.
    /// ES: Analiza sin efectos secundarios para poder probar las URL de forma independiente.
    /// 中文：纯解析且不产生副作用，便于独立测试 URL 行为。
    public nonisolated static func parse(url: URL) -> PTExternalAction? {
        guard let scheme = url.scheme,
              scheme.caseInsensitiveCompare(appScheme) == .orderedSame,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let routeName = routeName(from: components) else {
            return nil
        }

        switch routeName.lowercased() {
        case "checkfuel":
            return .checkFuel

        case "antitheft":
            guard let rawValue = queryValue(named: "enable", in: components),
                  let enable = strictBool(from: rawValue) else {
                return .unknown
            }
            return .toggleAntiTheft(enable: enable)

        case "openhud":
            return .openHUD

        case "confirmgasstationroute":
            return .confirmGasStationRoute

        case "navigate":
            guard let destination = queryValue(named: "destination", in: components),
                  let normalizedDestination = normalizedDestination(destination) else {
                return .unknown
            }
            return .navigateTo(destination: normalizedDestination)

        default:
            return .unknown
        }
    }

    private nonisolated static func routeName(from components: URLComponents) -> String? {
        guard let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }

        // EN: Accept the documented xp400://host form and the older action/path form.
        // ES: Acepta la forma documentada xp400://host y la forma antigua action/path.
        // 中文：同时兼容文档中的 xp400://host 格式和旧的 action/path 格式。
        if host.caseInsensitiveCompare("action") == .orderedSame {
            let pathComponents = components.path.split(separator: "/").map(String.init)
            return pathComponents.count == 1 ? pathComponents[0] : nil
        }

        let pathComponents = components.path.split(separator: "/")
        return pathComponents.isEmpty ? host : nil
    }

    private nonisolated static func queryValue(named name: String, in components: URLComponents) -> String? {
        let matches = components.queryItems?.filter {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        } ?? []
        guard matches.count == 1 else { return nil }
        return matches[0].value
    }

    private nonisolated static func strictBool(from value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private nonisolated static func normalizedDestination(_ destination: String) -> String? {
        let normalized = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.count <= maximumDestinationLength,
              normalized.rangeOfCharacter(from: .controlCharacters) == nil else {
            return nil
        }
        return normalized
    }

    // MARK: - Public execution entry points

    /// EN: Handle a URL in the scene that delivered it; unknown routes never execute side effects.
    /// ES: Maneja la URL en la escena que la entregó; las rutas desconocidas nunca producen efectos.
    /// 中文：在传入 URL 的场景中处理它；未知路由绝不执行副作用。
    @discardableResult
    public func handle(url: URL, in scene: UIScene? = nil) -> Bool {
        guard let action = Self.parse(url: url), action != .unknown else {
            PTNSLogConsole("⚠️ [路由引擎] 拒绝未知或格式错误的 URL: \(url.absoluteString)")
            return false
        }

        let result = execute(action: action, in: scene as? UIWindowScene)
        if !result.succeeded {
            PTNSLogConsole("⚠️ [路由引擎] URL 动作未执行: \(result.rawValue)")
        }
        return result.succeeded
    }

    /// EN: Execute the same typed action used by App Intents without creating a second transport path.
    /// ES: Ejecuta la misma acción tipada que usan los App Intents sin crear otro canal de transporte.
    /// 中文：执行 App Intents 共用的类型化动作，不建立第二套传输链路。
    @discardableResult
    public func execute(action: PTExternalAction, in scene: UIWindowScene? = nil) -> PTRouteExecutionResult {
        switch action {
        case .checkFuel:
            guard let latestData = PTBluetoothServerManager.shared.latestData1 else {
                PTMessagePusher.pushToDashboard(
                    title: PTDashboardConfig.languageFunc(text: "ride_not_available"),
                    body: PTDashboardConfig.languageFunc(text: "ride_not_available")
                )
                return .unavailable
            }

            if latestData.fuelLevelPct <= 15 {
                let promptText = PTDashboardConfig.language(key: "short_cut_fuel", latestData.fuelLevelPct)
                SpeechSynthesizer.Shared.speak(promptText)
                PTFuelRoutingManager.shared.confirmAndSendGasStationRoute()
                return .started
            }

            PTMessagePusher.pushToDashboard(
                title: PTDashboardConfig.languageFunc(text: "short_cut_fuel_title"),
                body: PTDashboardConfig.language(key: "short_cut_fuel_msg", latestData.fuelLevelPct)
            )
            return .completed

        case .toggleAntiTheft(let enable):
            PTNSLogConsole("🗣️ [路由引擎] 收到外部指令：防盗系统设置 -> \(enable ? "开启" : "关闭")")
            if enable {
                PTMOTOParkingManager.shared.saveCurrentLocationAsParkingSpot()
                PTMessagePusher.pushToDashboard(
                    title: PTDashboardConfig.languageFunc(text: "parking_lock_title"),
                    body: PTDashboardConfig.languageFunc(text: "parking_lock_msg")
                )
                return .started
            }

            PTMOTOParkingManager.shared.clearParkingSpot()
            PTMessagePusher.pushToDashboard(
                title: PTDashboardConfig.languageFunc(text: "parking_unlock_title"),
                body: PTDashboardConfig.languageFunc(text: "parking_unlock_msg")
            )
            return .completed

        case .openHUD:
            guard let navigationController = navigationController(in: scene) else {
                return .unavailable
            }

            if navigationController.topViewController is PTDashBoardBaseBoardViewController {
                return .completed
            }

            navigationController.pushViewController(PTDashBoardBaseBoardViewController(), animated: true)
            return .completed

        case .confirmGasStationRoute:
            PTFuelRoutingManager.shared.confirmAndSendGasStationRoute()
            return .started

        case .navigateTo(let destination):
            guard let tabbar = tabbarController(in: scene) else {
                return .unavailable
            }

            tabbar.ptCustomBar.select(1)
            NotificationCenter.default.post(name: MotorcycleSearchAndNavigate, object: destination)
            return .started

        case .unknown:
            return .rejected
        }
    }

    // MARK: - Scene-aware UIKit lookup

    private func applicationWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication }

        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }

    private func rootViewController(in scene: UIWindowScene?) -> UIViewController? {
        let targetScene = scene ?? applicationWindowScene()
        guard let targetScene else { return nil }
        return PTSceneContext.rootViewController(in: targetScene)
    }

    private func tabbarController(in scene: UIWindowScene?) -> PTMotoBaseTabbarController? {
        guard let root = rootViewController(in: scene) else { return nil }
        return findTabbarController(from: root)
    }

    private func findTabbarController(from viewController: UIViewController) -> PTMotoBaseTabbarController? {
        if let tabbar = viewController as? PTMotoBaseTabbarController {
            return tabbar
        }

        if let presented = viewController.presentedViewController,
           let tabbar = findTabbarController(from: presented) {
            return tabbar
        }

        if let navigationController = viewController as? UINavigationController,
           let tabbar = findTabbarController(from: navigationController) {
            return tabbar
        }

        for child in viewController.children.reversed() {
            if let tabbar = findTabbarController(from: child) {
                return tabbar
            }
        }
        return nil
    }

    private func navigationController(in scene: UIWindowScene?) -> UINavigationController? {
        guard let root = rootViewController(in: scene) else { return nil }
        let current = PTUtils.getCurrentVC(from: root)
        if let navigationController = current.navigationController {
            return navigationController
        }

        if let navigationController = root as? UINavigationController {
            return navigationController
        }

        if let tabbar = findTabbarController(from: root),
           let selectedNavigationController = tabbar.selectedViewController as? UINavigationController {
            return selectedNavigationController
        }

        return nil
    }
}
