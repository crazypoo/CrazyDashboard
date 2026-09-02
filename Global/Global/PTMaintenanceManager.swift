//
//  PTMaintenanceManager.swift
//  CrazyDashboard
//
//  EN: Evaluates dashboard maintenance data and sends bounded read-only reminders.
//  ES: Evalúa los datos de mantenimiento del tablero y envía recordatorios limitados de solo lectura.
//  中文：评估仪表保养数据，并发送有界的只读保养提醒。
//

import Foundation
import UserNotifications
import PooTools

private enum PTMaintenanceDashboardSample: Sendable {
    case maintenanceFlag(Int)
    case distanceToMaintenance(Int)
}

@MainActor
@objcMembers
public final class PTMaintenanceManager: NSObject {
    public static let shared = PTMaintenanceManager()

    private static let warningInterval: TimeInterval = 7 * 24 * 60 * 60

    private var latestMaintenanceFlag: Int?
    private var latestDistanceToMaintenanceKm: Int?

    private override init() {
        super.init()
        PTBluetoothServerManager.shared.addDelegate(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGarageChange),
            name: PTMotorcycleGarageStore.didChangeNotification,
            object: nil
        )
    }

    /// EN: Discard cached dashboard values after the active motorcycle changes.
    /// ES: Descarta los datos guardados cuando cambia la motocicleta activa.
    /// 中文：当前摩托车切换后，丢弃已经缓存的仪表数据。
    @objc private func handleGarageChange() {
        latestMaintenanceFlag = nil
        latestDistanceToMaintenanceKm = nil
    }

    private func receive(_ sample: PTMaintenanceDashboardSample) {
        switch sample {
        case .maintenanceFlag(let value):
            latestMaintenanceFlag = value
        case .distanceToMaintenance(let value):
            latestDistanceToMaintenanceKm = value
        }
        evaluateAndNotify()
    }

    private func evaluateAndNotify() {
        let thresholdKm = Int(PTMotorcycleGarageStore.shared.currentMaintenanceWarningDistanceKm.rounded())
        let advice = PTRideMaintenanceAdvisor.advise(
            distanceToMaintenanceKm: latestDistanceToMaintenanceKm,
            rawMaintenanceFlag: latestMaintenanceFlag,
            warningThresholdKm: thresholdKm
        )

        switch advice.state {
        case .required:
            triggerWarningIfNeeded(
                state: .required,
                title: "🛠️" + PTDashboardConfig.languageFunc(text: "maintenance_need_title"),
                body: PTDashboardConfig.languageFunc(text: "maintenance_need_msg")
            )
        case .dueSoon:
            guard let distance = advice.distanceToMaintenanceKm else { return }
            let displayedDistance = PTDashboardConfig.shared.appShowMileageValueString(Double(distance))
                + PTDashboardConfig.shared.appShowUniLabel
            triggerWarningIfNeeded(
                state: .dueSoon,
                title: "⚙️" + PTDashboardConfig.languageFunc(text: "maintenance_warning_title"),
                body: PTDashboardConfig.language(key: "maintenance_warning_msg", displayedDistance)
            )
        case .normal, .unknown:
            break
        }
    }

    private func triggerWarningIfNeeded(
        state: PTRideMaintenanceState,
        title: String,
        body: String
    ) {
        let vehicleID = PTMotorcycleGarageStore.shared.selectedVehicleID?.uuidString ?? "default"

        // EN: Route maintenance reminders through the typed notification center so permission and cooldown rules are shared.
        // ES: Envía los recordatorios de mantenimiento al centro tipado para compartir permisos y reglas de enfriamiento.
        // 中文：保养提醒统一经过类型化通知中心，复用权限和冷却规则。
        PTNotificationCenter.schedule(
            PTNotificationRequest(
                kind: .maintenance,
                title: title,
                body: body,
                identifier: "pt.notification.maintenance.\(state.rawValue)",
                deduplicationKey: "maintenance-\(vehicleID)-\(state.rawValue)",
                cooldown: Self.warningInterval,
                categoryIdentifier: PTNotificationCenter.maintenanceCategoryIdentifier,
                userInfo: ["pt_notification_kind": PTAppNotificationKind.maintenance.rawValue]
            )
        )
        PTNSLogConsole("🚨 [保养管家] 触发 \(state.rawValue) 通知：\(title)")
    }

    /// EN: Clear stale values after the dashboard disconnects so an old reading cannot trigger a new reminder.
    /// ES: Limpia los valores obsoletos al desconectar el tablero para que una lectura antigua no genere otro aviso.
    /// 中文：仪表断开后清除旧数据，避免旧读数再次触发提醒。
    private func receiveConnectionState(_ isConnected: Bool) {
        guard !isConnected else { return }
        latestMaintenanceFlag = nil
        latestDistanceToMaintenanceKm = nil
    }
}

extension PTMaintenanceManager: PTBLEDashboardDelegate {
    nonisolated func dashboardManager(_ manager: PTBluetoothServerManager, dashboardData data: Any?) {
        let sample: PTMaintenanceDashboardSample?
        if let data2 = data as? PTDashboardData2 {
            sample = .maintenanceFlag(data2.maintenance)
        } else if let data3 = data as? PTDashboardData3 {
            sample = .distanceToMaintenance(data3.distToMaintenance)
        } else {
            sample = nil
        }

        guard let sample else { return }
        Task { @MainActor [weak self] in
            self?.receive(sample)
        }
    }

    nonisolated func dashboardManager(_ manager: PTBluetoothServerManager, didChangeConnectionState isConnected: Bool) {
        Task { @MainActor [weak self] in
            self?.receiveConnectionState(isConnected)
        }
    }
}
