//
//  PTAntiTheftManager.swift
//  CrazyDashboard
//
//  EN: Opt-in anti-theft monitoring driven by fresh dashboard data and bounded location verification.
//  ES: Vigilancia antirrobo opcional basada en datos recientes del tablero y verificación de ubicación limitada.
//  中文：基于新鲜仪表数据和有界定位验证的用户主动开启式防盗监控。
//

import CoreLocation
import Foundation
import PooTools

// EN: Explicit states make the UI and notification actions distinguish waiting, armed and unverifiable conditions.
// ES: Los estados explícitos permiten distinguir espera, armado y verificación imposible en la interfaz y las notificaciones.
// 中文：显式状态让 UI 和通知操作能够区分等待、新鲜布防和无法验证。
public enum PTAntiTheftMonitoringState: String, Codable, Equatable, Sendable {
    case disabled
    case waitingForVehicleState
    case gracePeriod
    case armed
    case verifyingDisconnect
    case snoozed
    case alerting
    case unableToVerify
}

// EN: This snapshot is the only state object exposed to screens and automation adapters.
// ES: Esta instantánea es el único objeto de estado expuesto a las pantallas y adaptadores de automatización.
// 中文：该快照是页面和自动化适配器唯一读取的状态对象。
public struct PTAntiTheftMonitoringSnapshot: Codable, Equatable, Sendable {
    public let isEnabled: Bool
    public let state: PTAntiTheftMonitoringState
    public let lastFreshVehicleStateAt: Date?
    public let expectedShutdownUntil: Date?
    public let snoozedUntil: Date?
    public let lastAlarmAt: Date?

    public init(
        isEnabled: Bool,
        state: PTAntiTheftMonitoringState,
        lastFreshVehicleStateAt: Date? = nil,
        expectedShutdownUntil: Date? = nil,
        snoozedUntil: Date? = nil,
        lastAlarmAt: Date? = nil
    ) {
        self.isEnabled = isEnabled
        self.state = state
        self.lastFreshVehicleStateAt = lastFreshVehicleStateAt
        self.expectedShutdownUntil = expectedShutdownUntil
        self.snoozedUntil = snoozedUntil
        self.lastAlarmAt = lastAlarmAt
    }
}

/// EN: The manager never arms from cached launch values; it needs an explicit opt-in and a fresh vehicle frame.
/// ES: El gestor nunca se arma con valores almacenados al iniciar; necesita consentimiento y una trama reciente del vehículo.
/// 中文：管理器不会根据冷启动缓存数据布防，必须同时满足用户授权和新鲜车辆数据。
@MainActor
@objcMembers
public final class PTAntiTheftManager: NSObject {
    public static let shared = PTAntiTheftManager()

    private(set) public var snapshot = PTAntiTheftMonitoringSnapshot(
        isEnabled: PTMotoUserDefaultStruct.PTAntiTheftMonitoringEnabled,
        state: PTMotoUserDefaultStruct.PTAntiTheftMonitoringEnabled
            ? .waitingForVehicleState
            : .disabled
    )

    // EN: A cached link state only prevents an unnecessary wait; a fresh dashboard frame is still required before arming.
    // ES: El estado de enlace almacenado solo evita una espera innecesaria; aún se exige una trama reciente antes de armar.
    // 中文：缓存的连接状态只用于避免无谓等待，真正布防前仍必须收到新鲜仪表数据。
    private var isBluetoothConnected = PTDashboardConfig.shared.blueConnected
    private var hasFreshVehicleState = false
    private var expectedShutdownUntil: Date?
    private var snoozedUntil: Date?
    private var pendingDisconnectWork: DispatchWorkItem?
    private var alarmSuppressedUntil: Date?
    private var lastAlarmAt: Date?

    private let shutdownGracePeriod: TimeInterval = 30
    private let disconnectConfirmationDelay: TimeInterval = 5
    private let nearbyRadius: CLLocationDistance = 15
    private let locationMaximumAge: TimeInterval = 30
    private let locationMaximumAccuracy: CLLocationAccuracy = 50
    private let alarmCooldown: TimeInterval = 5 * 60
    private let snoozeDuration: TimeInterval = 30 * 60

    private override init() {
        super.init()
        setupObservers()
    }

    // EN: Delegate registration observes the already configured Bluetooth server without changing its transport logic.
    // ES: El registro observa el servidor Bluetooth ya configurado sin cambiar su lógica de transporte.
    // 中文：只监听已经配置好的蓝牙服务，不修改底层传输逻辑。
    private func setupObservers() {
        PTBluetoothServerManager.shared.addDelegate(self)
    }

    // EN: The user-facing switch is the only way to enable monitoring.
    // ES: El interruptor visible para el usuario es la única forma de activar la vigilancia.
    // 中文：只有用户界面开关可以开启监控。
    public func setMonitoringEnabled(_ enabled: Bool) {
        PTMotoUserDefaultStruct.PTAntiTheftMonitoringEnabled = enabled
        pendingDisconnectWork?.cancel()
        pendingDisconnectWork = nil
        alarmSuppressedUntil = nil
        snoozedUntil = nil
        expectedShutdownUntil = nil
        hasFreshVehicleState = false

        if enabled {
            updateSnapshot(state: .waitingForVehicleState, clearFreshAt: true)
        } else {
            updateSnapshot(state: .disabled, clearFreshAt: true)
            recordTimeline(
                kind: .monitoringDisarmed,
                severity: .info,
                messageKey: "security_event_monitoring_disarmed"
            )
        }
    }

    public var isMonitoringEnabled: Bool {
        snapshot.isEnabled
    }

    // EN: Snoozing suppresses alarms for a bounded period but keeps the user's opt-in intact.
    // ES: La pausa suprime las alarmas durante un periodo limitado, pero conserva el consentimiento del usuario.
    // 中文：暂停只在有限时间内抑制报警，不会取消用户的监控授权。
    public func snooze(for duration: TimeInterval = 30 * 60) {
        guard snapshot.isEnabled else { return }
        let safeDuration = min(max(duration.isFinite ? duration : snoozeDuration, 60), 24 * 60 * 60)
        snoozedUntil = Date().addingTimeInterval(safeDuration)
        pendingDisconnectWork?.cancel()
        pendingDisconnectWork = nil
        updateSnapshot(state: .snoozed)
        recordTimeline(
            kind: .monitoringSnoozed,
            severity: .info,
            messageKey: "security_event_monitoring_snoozed"
        )
    }

    // EN: Acknowledgement only changes the local audit trail; it never sends a vehicle command.
    // ES: El reconocimiento solo cambia la auditoría local; nunca envía un comando al vehículo.
    // 中文：确认只修改本地安全记录，不会向车辆发送任何命令。
    public func acknowledgeLatestAlarm() {
        guard let event = PTSecurityEventTimelineStore.shared.events.first(where: {
            $0.kind == .alarmTriggered && !$0.isAcknowledged
        }) else { return }
        _ = PTSecurityEventTimelineStore.shared.acknowledge(id: event.id)
        updateSnapshot(
            state: snapshot.isEnabled
                ? (isBluetoothConnected ? .armed : .waitingForVehicleState)
                : .disabled
        )
        recordTimeline(
            kind: .alarmAcknowledged,
            severity: .info,
            messageKey: "security_event_alarm_acknowledged"
        )
    }

    // EN: The state is recomputed from fresh input so a cold launch cannot inherit an armed state.
    // ES: El estado se recalcula con una entrada reciente para que el arranque no herede un estado armado.
    // 中文：每次根据新鲜输入重新计算状态，避免冷启动继承旧布防状态。
    private func updateArmingState(engineStatus: Int) {
        guard snapshot.isEnabled else {
            updateSnapshot(state: .disabled)
            return
        }

        guard isBluetoothConnected else {
            updateSnapshot(state: .waitingForVehicleState)
            return
        }

        let now = Date()
        let safeEngineStatus = engineStatus & 0x03

        if safeEngineStatus == 2 {
            hasFreshVehicleState = false
            disarmForRunningEngine()
            return
        }

        guard safeEngineStatus == 0 else {
            hasFreshVehicleState = false
            updateSnapshot(state: .waitingForVehicleState, freshAt: now)
            return
        }

        hasFreshVehicleState = true

        if let snoozedUntil, now < snoozedUntil {
            updateSnapshot(state: .snoozed, freshAt: now)
            return
        }
        self.snoozedUntil = nil

        if snapshot.state == .gracePeriod {
            if let expectedShutdownUntil, now < expectedShutdownUntil {
                updateSnapshot(state: .gracePeriod, freshAt: now)
                return
            }
            updateSnapshot(state: .armed, freshAt: now)
            return
        }

        if snapshot.state == .armed || snapshot.state == .verifyingDisconnect || snapshot.state == .alerting {
            updateSnapshot(state: snapshot.state, freshAt: now)
            return
        }

        expectedShutdownUntil = now.addingTimeInterval(shutdownGracePeriod)
        updateSnapshot(state: .gracePeriod, freshAt: now)
        PTNSLogConsole("🛡️ [防盗系统] 用户已开启监控，检测到新鲜熄火状态，进入关机宽限期。")
        PTMOTOParkingManager.shared.saveCurrentLocationAsParkingSpot()
        recordTimeline(
            kind: .monitoringArmed,
            severity: .info,
            messageKey: "security_event_monitoring_armed",
            coordinate: currentParkingCoordinate()
        )
        recordTimeline(
            kind: .parkingSaved,
            severity: .info,
            messageKey: "security_event_parking_saved",
            coordinate: currentParkingCoordinate()
        )
    }

    private func disarmForRunningEngine() {
        let hadMonitoringState = snapshot.state != .disabled && snapshot.state != .waitingForVehicleState
        expectedShutdownUntil = nil
        snoozedUntil = nil
        pendingDisconnectWork?.cancel()
        pendingDisconnectWork = nil
        updateSnapshot(state: .waitingForVehicleState)
        if hadMonitoringState {
            PTNSLogConsole("🔓 [防盗系统] 检测到引擎运转，解除警戒。")
            recordTimeline(
                kind: .monitoringDisarmed,
                severity: .info,
                messageKey: "security_event_monitoring_disarmed"
            )
        }
    }

    private func handleDisconnect() {
        guard snapshot.isEnabled else {
            return
        }

        guard hasFreshVehicleState,
              let anchorCoordinate = PTMOTOParkingManager.shared.getLastParkedLocation() else {
            expectedShutdownUntil = nil
            updateSnapshot(state: .waitingForVehicleState)
            return
        }

        if snapshot.state == .gracePeriod,
           let expectedShutdownUntil,
           Date() < expectedShutdownUntil {
            PTNSLogConsole("ℹ️ [防盗系统] 宽限期内断连，不触发报警。")
            self.expectedShutdownUntil = nil
            updateSnapshot(state: .waitingForVehicleState)
            recordTimeline(
                kind: .disconnectCleared,
                severity: .info,
                messageKey: "security_event_disconnect_cleared"
            )
            return
        }

        if snapshot.state == .snoozed,
           let snoozedUntil,
           Date() < snoozedUntil {
            recordTimeline(
                kind: .disconnectCleared,
                severity: .info,
                messageKey: "security_event_disconnect_cleared"
            )
            return
        }

        pendingDisconnectWork?.cancel()
        updateSnapshot(state: .verifyingDisconnect)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.evaluateDisconnect(anchorCoordinate: anchorCoordinate)
        }
        pendingDisconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + disconnectConfirmationDelay, execute: work)
    }

    private func evaluateDisconnect(anchorCoordinate: CLLocationCoordinate2D) {
        guard snapshot.isEnabled else {
            updateSnapshot(state: .disabled)
            return
        }
        guard !isBluetoothConnected else {
            updateSnapshot(state: .waitingForVehicleState)
            return
        }

        recordTimeline(
            kind: .connectionLost,
            severity: .warning,
            messageKey: "security_event_connection_lost",
            coordinate: PTRideCoordinate(latitude: anchorCoordinate.latitude, longitude: anchorCoordinate.longitude)
        )

        let anchorLocation = CLLocation(latitude: anchorCoordinate.latitude, longitude: anchorCoordinate.longitude)
        PTMOTOParkingManager.shared.requestSingleLocationForAntiTheft { [weak self] currentLocation in
            guard let self else { return }
            guard self.snapshot.isEnabled, !self.isBluetoothConnected else {
                self.updateSnapshot(state: .waitingForVehicleState)
                return
            }
            guard let currentLocation, self.isValidVerificationLocation(currentLocation) else {
                self.updateSnapshot(state: .unableToVerify)
                self.recordTimeline(
                    kind: .verificationUnavailable,
                    severity: .warning,
                    messageKey: "security_event_verification_unavailable",
                    coordinate: PTRideCoordinate(latitude: anchorCoordinate.latitude, longitude: anchorCoordinate.longitude)
                )
                return
            }

            let distance = currentLocation.distance(from: anchorLocation)
            PTNSLogConsole("📐 [防盗系统] 手机距离停车点 (distance) 米。")
            if distance <= self.nearbyRadius {
                self.triggerTheftAlarm()
            } else {
                PTNSLogConsole("✅ [防盗系统] 骑手已离开停车点，断连视为正常。")
                self.updateSnapshot(state: .waitingForVehicleState)
                self.recordTimeline(
                    kind: .monitoringDisarmed,
                    severity: .info,
                    messageKey: "security_event_monitoring_disarmed"
                )
            }
        }
    }

    private func isValidVerificationLocation(_ location: CLLocation) -> Bool {
        let coordinate = location.coordinate
        let age = abs(Date().timeIntervalSince(location.timestamp))
        return coordinate.latitude.isFinite &&
            coordinate.longitude.isFinite &&
            (-90...90).contains(coordinate.latitude) &&
            (-180...180).contains(coordinate.longitude) &&
            age <= locationMaximumAge &&
            location.horizontalAccuracy > 0 &&
            location.horizontalAccuracy <= locationMaximumAccuracy
    }

    private func triggerTheftAlarm() {
        let now = Date()
        guard alarmSuppressedUntil.map({ now >= $0 }) ?? true else { return }
        alarmSuppressedUntil = now.addingTimeInterval(alarmCooldown)
        lastAlarmAt = now
        updateSnapshot(state: .alerting)

        let request = PTNotificationRequest(
            kind: .antiTheft,
            title: PTDashboardConfig.languageFunc(text: "notification_anti_theft_title"),
            body: PTDashboardConfig.languageFunc(text: "notification_anti_theft_body"),
            identifier: "pt.notification.anti-theft.alarm",
            deduplicationKey: "anti-theft-alarm",
            cooldown: alarmCooldown,
            interruptionLevel: .timeSensitive,
            categoryIdentifier: PTNotificationCenter.antiTheftCategoryIdentifier,
            userInfo: ["pt_notification_kind": PTAppNotificationKind.antiTheft.rawValue]
        )
        PTNotificationCenter.schedule(request) { result in
            PTNSLogConsole("[防盗系统] 通知投递结果: \(String(describing: result))")
        }
        recordTimeline(
            kind: .alarmTriggered,
            severity: .critical,
            messageKey: "security_event_alarm_triggered"
        )
    }

    private func currentParkingCoordinate() -> PTRideCoordinate? {
        PTMOTOParkingManager.shared.getLastParkedLocation().map {
            PTRideCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private func updateSnapshot(
        state: PTAntiTheftMonitoringState,
        freshAt: Date? = nil,
        clearFreshAt: Bool = false
    ) {
        let currentFreshAt = clearFreshAt ? nil : (freshAt ?? snapshot.lastFreshVehicleStateAt)
        snapshot = PTAntiTheftMonitoringSnapshot(
            isEnabled: PTMotoUserDefaultStruct.PTAntiTheftMonitoringEnabled,
            state: state,
            lastFreshVehicleStateAt: currentFreshAt,
            expectedShutdownUntil: expectedShutdownUntil,
            snoozedUntil: snoozedUntil,
            lastAlarmAt: lastAlarmAt
        )
        NotificationCenter.default.post(
            name: .ptAntiTheftStateDidChange,
            object: self,
            userInfo: ["snapshot": snapshot]
        )
    }

    // EN: Timeline writes remain on the existing main-actor store and are not used as the alarm decision source.
    // ES: Las escrituras de la línea temporal siguen en el almacén del actor principal y no deciden la alarma.
    // 中文：时间轴写入继续使用现有主线程存储，不参与报警判断。
    private func recordTimeline(
        kind: PTRideSecurityEventKind,
        severity: PTRideSecuritySeverity,
        messageKey: String,
        coordinate: PTRideCoordinate? = nil
    ) {
        _ = PTSecurityEventTimelineStore.shared.record(
            kind: kind,
            severity: severity,
            message: PTDashboardConfig.languageFunc(text: messageKey),
            coordinate: coordinate
        )
    }
}

public extension Notification.Name {
    // EN: Screens observe this notification instead of reaching into the manager's private timers.
    // ES: Las pantallas observan esta notificación en lugar de acceder a los temporizadores privados.
    // 中文：页面监听该通知，不直接访问管理器的私有定时器。
    static let ptAntiTheftStateDidChange = Notification.Name("PTAntiTheftStateDidChange")
}

extension PTAntiTheftManager: PTBLEDashboardDelegate {
    func dashboardManager(_ manager: PTBluetoothServerManager, didChangeConnectionState isConnected: Bool) {
        isBluetoothConnected = isConnected
        if isConnected {
            hasFreshVehicleState = false
            let hadPendingDisconnect = pendingDisconnectWork != nil
            pendingDisconnectWork?.cancel()
            pendingDisconnectWork = nil
            if snapshot.isEnabled {
                updateSnapshot(state: .waitingForVehicleState)
            }
            if hadPendingDisconnect {
                recordTimeline(
                    kind: .connectionRestored,
                    severity: .info,
                    messageKey: "security_event_connection_restored"
                )
            }
        } else {
            handleDisconnect()
        }
    }

    func dashboardManager(_ manager: PTBluetoothServerManager, dashboardData data: Any?) {
        guard let data2 = data as? PTDashboardData2 else { return }
        updateArmingState(engineStatus: data2.engineStatus)
    }

    func dashboardManager(_ manager: PTBluetoothServerManager, unknownData data: String) {}
}
