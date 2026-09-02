//
//  PTDeveloperSafetyGate.swift
//  CrazyDashboard
//
//  EN: Runtime gate for developer-only vehicle operations.
//  ES: Puerta de ejecución para operaciones del vehículo exclusivas del desarrollador.
//  中文：开发者车辆高风险操作的运行时门禁。
//

import Foundation
import UIKit

public enum PTDeveloperSafetyOperation: String, Codable, Sendable {
    // EN: Live CAN capture is developer-only because it temporarily changes the telemetry read mode.
    // ES: La captura CAN en vivo es exclusiva del desarrollador porque cambia temporalmente el modo de lectura.
    // 中文：实时 CAN 抓包只允许开发者使用，因为它会暂时改变遥测读取模式。
    case canCapture
    case didFuzz
    case memoryRead
    case dashboardWrite
    case securityAccess
    case routineControl
    case firmwareFlash
    case bootLogoExperiment
    case rawCommand
    case lifecycle
}

public enum PTDeveloperSafetyRejection: String, Codable, Sendable {
    case highRiskModeDisabled
    case protocolEvidenceMissing
    case lifecycleReset
    case userDisabled
}

public struct PTDeveloperSafetyEvent: Codable, Sendable {
    public let operation: PTDeveloperSafetyOperation
    public let allowed: Bool
    public let rejection: PTDeveloperSafetyRejection?
    public let timestamp: Date

    public init(
        operation: PTDeveloperSafetyOperation,
        allowed: Bool,
        rejection: PTDeveloperSafetyRejection? = nil,
        timestamp: Date = Date()
    ) {
        self.operation = operation
        self.allowed = allowed
        self.rejection = rejection
        self.timestamp = timestamp
    }
}

/// EN: Enables risky calls only for the current foreground developer session.
/// ES: Solo permite llamadas de riesgo durante la sesión de desarrollador en primer plano.
/// 中文：只在当前前台开发者会话中允许高风险调用。
@MainActor
public final class PTDeveloperSafetyGate {
    public static let shared = PTDeveloperSafetyGate()
    public static let stateDidChange = Notification.Name("PTDeveloperSafetyGate.stateDidChange")

    public private(set) var isEnabled = false
    public private(set) var lastEvent: PTDeveloperSafetyEvent?
    public private(set) var events: [PTDeveloperSafetyEvent] = []

    private var observers: [NSObjectProtocol] = []

    private init() {
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.disable(reason: .lifecycleReset)
            }
        }

        let vehicleObserver = NotificationCenter.default.addObserver(
            forName: PTVehicleConnectivityCoordinator.snapshotDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let snapshot = notification.userInfo?["snapshot"] as? PTVehicleSnapshot,
                snapshot.obd.state != .connected
            else {
                return
            }

            Task { @MainActor [weak self] in
                guard let self, self.isEnabled else { return }
                self.disable(reason: .lifecycleReset)
            }
        }

        observers = [backgroundObserver, vehicleObserver]
    }

    /// EN: The switch is intentionally in-memory and defaults to off; its observers refresh their UI from this value.
    /// ES: El interruptor solo vive en memoria y empieza desactivado; sus observadores actualizan la interfaz desde este valor.
    /// 中文：开关只保存在内存中且默认关闭，所有观察者都从该值刷新界面。
    public func setEnabled(_ enabled: Bool) {
        if enabled {
            guard !isEnabled else { return }
            isEnabled = true
            publishStateChange()
        } else {
            disable(reason: .userDisabled)
        }
    }

    /// EN: Explicit exit, backgrounding, and vehicle disconnects revoke authorization; collapsing the surface does not.
    /// ES: La salida explícita, el fondo y la desconexión del vehículo revocan la autorización; minimizar la superficie no.
    /// 中文：显式退出、进入后台和车辆断开会撤销授权；收起界面不会撤销授权。
    public func disable(reason: PTDeveloperSafetyRejection = .lifecycleReset) {
        isEnabled = false
        record(
            PTDeveloperSafetyEvent(
                operation: .lifecycle,
                allowed: false,
                rejection: reason
            )
        )
        publishStateChange()
    }

    /// EN: Records the decision so the UI and exported developer log have structured evidence.
    /// ES: Registra la decisión para que la UI y el registro exportado tengan evidencia estructurada.
    /// 中文：记录结构化决策，供 UI 和开发者导出日志使用。
    @discardableResult
    public func authorize(
        _ operation: PTDeveloperSafetyOperation,
        protocolEvidenceAvailable: Bool = true
    ) -> Bool {
        guard isEnabled else {
            record(
                PTDeveloperSafetyEvent(
                    operation: operation,
                    allowed: false,
                    rejection: .highRiskModeDisabled
                )
            )
            return false
        }

        guard protocolEvidenceAvailable else {
            record(
                PTDeveloperSafetyEvent(
                    operation: operation,
                    allowed: false,
                    rejection: .protocolEvidenceMissing
                )
            )
            return false
        }

        record(
            PTDeveloperSafetyEvent(
                operation: operation,
                allowed: true
            )
        )
        return true
    }

    private func record(_ event: PTDeveloperSafetyEvent) {
        lastEvent = event
        events.append(event)
        if events.count > 64 {
            events.removeFirst(events.count - 64)
        }
    }

    /// EN: A single notification keeps every developer surface synchronized without adding another state store.
    /// ES: Una sola notificación mantiene sincronizadas todas las superficies de desarrollador sin añadir otro almacén de estado.
    /// 中文：使用一个通知同步所有开发者界面，不再新增第二套状态存储。
    private func publishStateChange() {
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
