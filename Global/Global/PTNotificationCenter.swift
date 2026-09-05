//
//  PTNotificationCenter.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 24/7/2026.
//

import UIKit
import UserNotifications
import PooTools

// EN: Typed notification kinds keep safety, maintenance and diagnostic alerts deduplicated.
// ES: Los tipos de notificación mantienen deduplicadas las alertas de seguridad, mantenimiento y diagnóstico.
// 中文：类型化通知统一处理安全、保养和诊断提醒的去重。
public enum PTAppNotificationKind: String, Codable, Sendable {
    case generic
    case alarm
    case maintenance
    case diagnostic
    case antiTheft
}

public enum PTNotificationDeliveryResult: Equatable, Sendable {
    case scheduled
    case suppressed
    case denied
    case notDetermined
    case failed(String)
}

// EN: This request contains only notification metadata; it never owns vehicle transport state.
// ES: Esta solicitud solo contiene metadatos de notificación; nunca posee el estado del transporte del vehículo.
// 中文：请求只保存通知元数据，不持有任何车辆传输状态。
public struct PTNotificationRequest: @unchecked Sendable {
    public let kind: PTAppNotificationKind
    public let title: String
    public let body: String
    public let identifier: String
    public let deduplicationKey: String?
    public let cooldown: TimeInterval
    public let interruptionLevel: UNNotificationInterruptionLevel
    public let categoryIdentifier: String?
    public let userInfo: [String: String]
    public let trigger: UNNotificationTrigger?

    public init(
        kind: PTAppNotificationKind,
        title: String,
        body: String,
        identifier: String? = nil,
        deduplicationKey: String? = nil,
        cooldown: TimeInterval = 0,
        interruptionLevel: UNNotificationInterruptionLevel = .active,
        categoryIdentifier: String? = nil,
        userInfo: [String: String] = [:],
        trigger: UNNotificationTrigger? = nil
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.identifier = identifier ?? "pt.notification.\(kind.rawValue).\(UUID().uuidString)"
        self.deduplicationKey = deduplicationKey
        self.cooldown = max(cooldown, 0)
        self.interruptionLevel = interruptionLevel
        self.categoryIdentifier = categoryIdentifier
        self.userInfo = userInfo
        self.trigger = trigger
    }
}

public final class PTNotificationCenter: NSObject {
    private static let stateQueue = DispatchQueue(label: "com.pt.notification.state", qos: .utility)
    private static let deliveryKey = "PTNotificationCenter.delivery.v1"

    public static let antiTheftCategoryIdentifier = "PT_NOTIFICATION_ANTI_THEFT"
    public static let alarmCategoryIdentifier = "PT_NOTIFICATION_ALARM"
    public static let maintenanceCategoryIdentifier = "PT_NOTIFICATION_MAINTENANCE"
    public static let diagnosticCategoryIdentifier = "PT_NOTIFICATION_DIAGNOSTIC"
    public static let acknowledgeActionIdentifier = "PT_NOTIFICATION_ACKNOWLEDGE"
    public static let snoozeActionIdentifier = "PT_NOTIFICATION_SNOOZE_30M"
    public static let openActionIdentifier = "PT_NOTIFICATION_OPEN"

    // EN: Register categories once at launch; registration does not ask the user for permission.
    // ES: Registra las categorías una vez al iniciar; el registro no solicita permiso al usuario.
    // 中文：启动时只注册一次通知分类，注册过程不会向用户申请权限。
    public static func registerCategories() {
        let acknowledge = UNNotificationAction(
            identifier: acknowledgeActionIdentifier,
            title: PTDashboardConfig.languageFunc(text: "notification_action_acknowledge"),
            options: [.authenticationRequired]
        )
        let snooze = UNNotificationAction(
            identifier: snoozeActionIdentifier,
            title: PTDashboardConfig.languageFunc(text: "notification_action_snooze"),
            options: [.authenticationRequired]
        )
        let open = UNNotificationAction(
            identifier: openActionIdentifier,
            title: PTDashboardConfig.languageFunc(text: "notification_action_open"),
            options: [.foreground]
        )
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: antiTheftCategoryIdentifier,
                actions: [acknowledge, snooze, open],
                intentIdentifiers: [],
                options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: alarmCategoryIdentifier,
                actions: [open],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: maintenanceCategoryIdentifier,
                actions: [open],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: diagnosticCategoryIdentifier,
                actions: [open],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    // EN: This compatibility API preserves the legacy dashboard notification behavior.
    // ES: Esta API compatible conserva el comportamiento heredado de las notificaciones del tablero.
    // 中文：兼容 API 保留旧仪表通知行为。
    public static func pushCenter(title: String, body: String, trigger: UNNotificationTrigger? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        content.interruptionLevel = .timeSensitive

        // 生成唯一请求 ID
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        // 将请求加入系统通知中心
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                PTNSLogConsole("❌ [消息推送] 发送失败: \(error.localizedDescription)")
            } else {
                PTNSLogConsole("🚀 [消息推送] 消息已提交给 iOS 通知中心；是否由 XP400 通过系统 ANCS 显示取决于配对和系统设置。")
            }
        }
    }

    // EN: Typed alerts do not request permission implicitly; callers can show a clear opt-in UI first.
    // ES: Las alertas tipadas no solicitan permisos implícitamente; la interfaz puede pedir consentimiento antes.
    // 中文：类型化提醒不会隐式申请权限，调用方可先展示明确的授权界面。
    @discardableResult
    public static func schedule(
        _ request: PTNotificationRequest,
        completion: ((PTNotificationDeliveryResult) -> Void)? = nil
    ) -> PTNotificationDeliveryResult {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let result: PTNotificationDeliveryResult
            switch settings.authorizationStatus {
            case .denied:
                result = .denied
            case .notDetermined:
                result = .notDetermined
            case .authorized, .provisional, .ephemeral:
                guard Self.claimDelivery(for: request) else {
                    result = .suppressed
                    completion?(result)
                    return
                }

                let content = UNMutableNotificationContent()
                content.title = request.title
                content.body = request.body
                content.sound = .default
                content.interruptionLevel = request.interruptionLevel
                if let categoryIdentifier = request.categoryIdentifier {
                    content.categoryIdentifier = categoryIdentifier
                }
                if !request.userInfo.isEmpty {
                    content.userInfo = request.userInfo.reduce(into: [AnyHashable: Any]()) { result, item in
                        result[item.key] = item.value
                    }
                }

                let notification = UNNotificationRequest(
                    identifier: request.identifier,
                    content: content,
                    trigger: request.trigger
                )
                let center = UNUserNotificationCenter.current()
                center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                center.add(notification) { error in
                    let deliveryResult: PTNotificationDeliveryResult
                    if let error {
                        Self.releaseDelivery(for: request)
                        deliveryResult = .failed(error.localizedDescription)
                    } else {
                        deliveryResult = .scheduled
                    }
                    completion?(deliveryResult)
                }
                return
            @unknown default:
                result = .failed("Unknown notification authorization status")
            }
            completion?(result)
        }
        return .notDetermined
    }

    // EN: The async bridge lets new scheduling features reuse the existing permission and cooldown rules.
    // ES: El puente asíncrono permite que las nuevas funciones reutilicen los permisos y las reglas de enfriamiento existentes.
    // 中文：异步桥接让新调度功能继续复用现有权限和冷却规则。
    public static func scheduleAsync(_ request: PTNotificationRequest) async -> PTNotificationDeliveryResult {
        await withCheckedContinuation { continuation in
            schedule(request) { result in
                continuation.resume(returning: result)
            }
        }
    }

    // EN: Remove pending and delivered copies so cancelling an alarm is visible immediately.
    // ES: Elimina las copias pendientes y entregadas para que cancelar una alarma sea inmediato.
    // 中文：同时移除待处理和已投递副本，让取消提醒立即生效。
    public static func cancel(identifier: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    // EN: Pending identifiers are used only for reconciliation; this method never schedules new work.
    // ES: Los identificadores pendientes solo se usan para reconciliación; este método nunca programa trabajo nuevo.
    // 中文：待处理标识符仅用于校准，不会通过该方法创建新的通知。
    public static func pendingIdentifiers() async -> Set<String> {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: Set(requests.map(\.identifier)))
            }
        }
    }

    // EN: Async permission access keeps AlarmKit fallback decisions off callback pyramids.
    // ES: El acceso asíncrono a permisos evita pirámides de callbacks al decidir el respaldo de AlarmKit.
    // 中文：异步权限访问避免 AlarmKit 回退判断出现回调嵌套。
    public static func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            authorizationStatus { status in
                continuation.resume(returning: status)
            }
        }
    }

    // EN: Permission prompts remain explicit while callers can await the final result.
    // ES: Las solicitudes de permiso siguen siendo explícitas y los llamadores pueden esperar el resultado final.
    // 中文：权限请求仍然只由用户操作触发，同时调用方可以等待最终结果。
    public static func requestAuthorizationAsync() async -> (granted: Bool, errorDescription: String?) {
        await withCheckedContinuation { continuation in
            requestAuthorization { granted, error in
                continuation.resume(returning: (granted, error?.localizedDescription))
            }
        }
    }

    public static func requestAuthorization(completion: ((Bool, Error?) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            completion?(granted, error)
        }
    }

    public static func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings {
            completion($0.authorizationStatus)
        }
    }

    private static func claimDelivery(for request: PTNotificationRequest) -> Bool {
        guard let key = request.deduplicationKey, request.cooldown > 0 else {
            return true
        }

        return stateQueue.sync {
            var deliveries = loadDeliveries()
            let now = Date()
            if let lastDelivery = deliveries[key], now.timeIntervalSince(lastDelivery) < request.cooldown {
                return false
            }
            deliveries[key] = now
            saveDeliveries(deliveries)
            return true
        }
    }

    // EN: A failed system submission must not consume the cooldown window.
    // ES: Un envío fallido al sistema no debe consumir la ventana de enfriamiento.
    // 中文：系统提交失败时不能消耗去重冷却窗口。
    private static func releaseDelivery(for request: PTNotificationRequest) {
        guard let key = request.deduplicationKey else { return }
        stateQueue.sync {
            var deliveries = loadDeliveries()
            deliveries.removeValue(forKey: key)
            saveDeliveries(deliveries)
        }
    }

    private static func loadDeliveries() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: deliveryKey),
              let values = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return [:]
        }
        return values
    }

    private static func saveDeliveries(_ deliveries: [String: Date]) {
        guard let data = try? JSONEncoder().encode(deliveries) else { return }
        UserDefaults.standard.set(data, forKey: deliveryKey)
    }
}
