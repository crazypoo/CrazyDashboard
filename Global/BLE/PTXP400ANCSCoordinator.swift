//
//  PTXP400ANCSCoordinator.swift
//  PTSpeed
//
//  ponytail: Keep one explicit compatibility boundary; no second transport or automatic ANCS bridge.
//  EN: Separates Apple's system notification path from the experimental dashboard bridge.
//  ES: Mantiene un único límite explícito; no añade otro transporte ni un puente ANCS automático.
//  中文：保留一个明确的兼容边界，不新增第二套传输层或自动 ANCS 桥接。
//

import Foundation

nonisolated public enum PTXP400ANCSChannel: String, Codable, Sendable {
    case system
    case experimentalCompatibility
}

/// EN: These are the three real notification sources that must be verified on a paired XP400.
/// ES: Estas son las tres fuentes reales que deben verificarse con un XP400 emparejado.
/// 中文：这三类真实通知来源必须在已配对的 XP400 上分别验证。
nonisolated public enum PTXP400ANCSNotificationSource: String, Codable, CaseIterable, Sendable {
    case phoneCall
    case sms
    case thirdPartyApp
}

/// EN: iOS owns the system ANCS action policy; PTSpeed does not pretend to control call or message actions.
/// ES: iOS posee la política de acciones ANCS del sistema; PTSpeed no finge controlar llamadas ni mensajes.
/// 中文：系统 ANCS 的操作策略由 iOS 管理，PTSpeed 不伪装成可以控制电话或短信操作。
nonisolated public enum PTXP400ANCSActionSupport: String, Codable, Sendable {
    case systemManaged
    case noAppActionBridge
}

/// EN: A manual real-device case prevents local notifications from being mistaken for ANCS proof.
/// ES: Un caso manual en dispositivo real evita confundir las notificaciones locales con una prueba ANCS.
/// 中文：手动真机测试项可避免把本地通知误认为 ANCS 证据。
nonisolated public struct PTXP400ANCSVerificationCase: Codable, Equatable, Identifiable, Sendable {
    public let source: PTXP400ANCSNotificationSource
    public let channel: PTXP400ANCSChannel
    public let actionSupport: PTXP400ANCSActionSupport
    public let requiresRealPairedDevice: Bool

    public var id: String { source.rawValue }

    public init(
        source: PTXP400ANCSNotificationSource,
        channel: PTXP400ANCSChannel = .system,
        actionSupport: PTXP400ANCSActionSupport = .systemManaged,
        requiresRealPairedDevice: Bool = true
    ) {
        self.source = source
        self.channel = channel
        self.actionSupport = actionSupport
        self.requiresRealPairedDevice = requiresRealPairedDevice
    }
}

/// EN: The system path is deliberately data-only and never installs the app-owned GATT provider.
/// ES: La ruta del sistema solo describe datos y nunca instala el proveedor GATT propio de la app.
/// 中文：系统路径只描述验证数据，绝不会安装 App 自有的 GATT Provider。
nonisolated public enum PTXP400ANCSSystemPath {
    public static let verificationCases: [PTXP400ANCSVerificationCase] =
        PTXP400ANCSNotificationSource.allCases.map {
            PTXP400ANCSVerificationCase(source: $0)
        }

    public static func verificationCase(
        for source: PTXP400ANCSNotificationSource
    ) -> PTXP400ANCSVerificationCase {
        PTXP400ANCSVerificationCase(source: source)
    }
}

// EN: The normal vehicle path never installs the app-owned ANCS-shaped GATT provider.
// ES: El flujo normal del vehículo nunca instala el proveedor GATT con forma ANCS de la app.
// 中文：正常车辆连接路径永远不会安装 App 自有的 ANCS 风格 GATT 提供器。
@MainActor
public final class PTXP400ANCSCoordinator {
    public static let shared = PTXP400ANCSCoordinator()

    public private(set) var channel: PTXP400ANCSChannel = .system
    public var isExperimentalProviderInstalled: Bool {
        PTDashboardANCSProvider.shared.isInstalled
    }

    private init() {}

    // EN: This explicit action is reserved for developer protocol experiments and is never automatic.
    // ES: Esta acción explícita queda reservada para experimentos de protocolo y nunca es automática.
    // 中文：这个显式操作只用于开发者协议实验，绝不会自动执行。
    @discardableResult
    public func sendExperimentalTest() -> PTDashboardANCSDeliveryResult {
        guard PTDashboardANCSProvider.shared.install() else {
            return .unavailable
        }
        channel = .experimentalCompatibility
        return PTDashboardANCSProvider.shared.sendTestNotification()
    }

    /// EN: Explicitly remove the experimental bridge and restore the stable peripheral delegate.
    /// ES: Elimina explícitamente el puente experimental y restaura el delegado periférico estable.
    /// 中文：显式移除实验桥接，并恢复稳定外设委托。
    public func stopExperimentalProvider() {
        PTDashboardANCSProvider.shared.uninstall()
        channel = .system
    }

    // EN: System notifications are scheduled through the typed notification center and rely on iOS ANCS sharing.
    // ES: Las notificaciones del sistema pasan por el centro tipado y dependen del uso ANCS de iOS.
    // 中文：系统通知统一经由类型化通知中心调度，并依赖 iOS 的 ANCS 共享。
    public func scheduleSystemNotification(
        _ request: PTNotificationRequest
    ) async -> PTNotificationDeliveryResult {
        channel = .system
        return await PTNotificationCenter.scheduleAsync(request)
    }
}
