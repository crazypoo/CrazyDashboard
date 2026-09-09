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

// EN: The normal vehicle path never installs the app-owned ANCS-shaped GATT provider.
// ES: El flujo normal del vehículo nunca instala el proveedor GATT con forma ANCS de la app.
// 中文：正常车辆连接路径永远不会安装 App 自有的 ANCS 风格 GATT 提供器。
@MainActor
public final class PTXP400ANCSCoordinator {
    public static let shared = PTXP400ANCSCoordinator()

    public private(set) var channel: PTXP400ANCSChannel = .system

    private init() {}

    // EN: This explicit action is reserved for developer protocol experiments and is never automatic.
    // ES: Esta acción explícita queda reservada para experimentos de protocolo y nunca es automática.
    // 中文：这个显式操作只用于开发者协议实验，绝不会自动执行。
    @discardableResult
    public func sendExperimentalTest() -> PTDashboardANCSDeliveryResult {
        channel = .experimentalCompatibility
        PTDashboardANCSProvider.shared.install()
        return PTDashboardANCSProvider.shared.sendTestNotification()
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
