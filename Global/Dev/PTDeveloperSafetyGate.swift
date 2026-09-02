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

    /// EN: The switch is intentionally in-memory and defaults to off.
    /// ES: El interruptor solo vive en memoria y empieza desactivado.
    /// 中文：开关只保存在内存中，默认关闭。
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    /// EN: Closing the developer surface immediately revokes authorization.
    /// ES: Cerrar la superficie de desarrollador revoca la autorización de inmediato.
    /// 中文：关闭开发者界面后立即撤销授权。
    public func disable(reason: PTDeveloperSafetyRejection = .lifecycleReset) {
        isEnabled = false
        record(
            PTDeveloperSafetyEvent(
                operation: .lifecycle,
                allowed: false,
                rejection: reason
            )
        )
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

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
