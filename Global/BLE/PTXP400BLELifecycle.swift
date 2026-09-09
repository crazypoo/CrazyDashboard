//
//  PTXP400BLELifecycle.swift
//  CrazyDashboard
//
//  EN: Models the observable XP400 BLE lifecycle without owning CoreBluetooth transport state.
//  ES: Modela el ciclo de vida observable del BLE del XP400 sin poseer el estado del transporte CoreBluetooth.
//  中文：描述可观察的 XP400 BLE 生命周期，但不接管 CoreBluetooth 传输状态。
//

import Foundation

/// EN: Timeout phases are shared by diagnostics, UI status, and the watchdog.
/// ES: Las fases de tiempo de espera se comparten entre diagnóstico, estado de UI y watchdog.
/// 中文：超时阶段由诊断、界面状态和 watchdog 统一使用。
public enum PTXP400BLETimeoutPhase: String, Codable, CaseIterable, Sendable {
    case serviceConfiguration
    case advertisingStartup
    case centralSubscription
    case authentication
    case connectionFrame
    case sendQueueStall
    case sessionIdle
}

/// EN: Failures stay value-typed so stale callbacks can be compared and ignored safely.
/// ES: Los fallos permanecen como valores para comparar y descartar callbacks obsoletos de forma segura.
/// 中文：失败原因使用值类型，便于安全比较并忽略过期回调。
public enum PTXP400BLEFailure: Equatable, Codable, Sendable {
    case timeout(PTXP400BLETimeoutPhase)
    case serviceConfiguration
    case bluetoothUnavailable
    case transport
    case unknown
}

/// EN: One explicit state replaces the invalid combinations of several lifecycle booleans.
/// ES: Un estado explícito reemplaza las combinaciones inválidas de varios booleanos del ciclo de vida.
/// 中文：使用一个显式状态替代多个生命周期布尔值可能形成的非法组合。
public enum PTXP400BLELifecycleState: Equatable, Codable, Sendable {
    case idle
    case bluetoothUnavailable
    case configuringService
    case advertising
    case centralConnected
    case waitingForSubscriptions
    case authenticating
    case ready
    case disconnecting
    case failed(PTXP400BLEFailure)

    public var isConnected: Bool {
        switch self {
        case .centralConnected, .waitingForSubscriptions, .authenticating, .ready:
            return true
        case .idle, .bluetoothUnavailable, .configuringService, .advertising, .disconnecting, .failed:
            return false
        }
    }

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// EN: Events describe facts observed by the compatibility coordinator, not commands sent to the vehicle.
/// ES: Los eventos describen hechos observados por el coordinador de compatibilidad, no comandos enviados al vehículo.
/// 中文：事件表示兼容协调层观察到的事实，不表示向车辆发送指令。
public enum PTXP400BLELifecycleEvent: Equatable, Sendable {
    case startRequested
    case serviceConfigurationStarted
    case serviceConfigured
    case advertisingStarted
    case centralConnected
    case subscriptionsWaiting
    case subscriptionsReady
    case authenticationStarted
    case authenticationSucceeded
    case disconnectRequested
    case disconnected
    case bluetoothUnavailable
    case bluetoothPoweredOn
    case timeout(PTXP400BLETimeoutPhase)
    case failure(PTXP400BLEFailure)
    case reset
}

/// EN: A deterministic reducer makes lifecycle transitions testable without a vehicle or CoreBluetooth.
/// ES: Un reductor determinista permite probar las transiciones sin vehículo ni CoreBluetooth.
/// 中文：确定性的状态归约器让生命周期转换无需车辆或 CoreBluetooth 即可测试。
public struct PTXP400BLELifecycleMachine: Sendable {
    public private(set) var state: PTXP400BLELifecycleState

    public init(state: PTXP400BLELifecycleState = .idle) {
        self.state = state
    }

    @discardableResult
    public mutating func handle(_ event: PTXP400BLELifecycleEvent) -> PTXP400BLELifecycleState {
        guard let nextState = Self.nextState(from: state, event: event) else {
            return state
        }
        state = nextState
        return nextState
    }

    private static func nextState(
        from state: PTXP400BLELifecycleState,
        event: PTXP400BLELifecycleEvent
    ) -> PTXP400BLELifecycleState? {
        switch event {
        case .startRequested:
            switch state {
            case .idle, .bluetoothUnavailable, .failed:
                return .configuringService
            default:
                return nil
            }

        case .serviceConfigurationStarted:
            switch state {
            case .configuringService, .idle:
                return .configuringService
            default:
                return nil
            }

        case .serviceConfigured:
            guard state == .configuringService else { return nil }
            return .configuringService

        case .advertisingStarted:
            switch state {
            case .configuringService, .advertising:
                return .advertising
            default:
                return nil
            }

        case .centralConnected:
            guard state == .advertising else { return nil }
            return .centralConnected

        case .subscriptionsWaiting:
            guard state == .centralConnected else { return nil }
            return .waitingForSubscriptions

        case .subscriptionsReady:
            guard state == .waitingForSubscriptions else { return nil }
            return .authenticating

        case .authenticationStarted:
            switch state {
            case .centralConnected, .waitingForSubscriptions, .authenticating:
                return .authenticating
            default:
                return nil
            }

        case .authenticationSucceeded:
            guard state == .authenticating else { return nil }
            return .ready

        case .disconnectRequested:
            switch state {
            case .idle, .bluetoothUnavailable:
                return nil
            default:
                return .disconnecting
            }

        case .disconnected:
            switch state {
            case .idle, .bluetoothUnavailable:
                return state
            default:
                return .idle
            }

        case .bluetoothUnavailable:
            return .bluetoothUnavailable

        case .bluetoothPoweredOn:
            guard state == .bluetoothUnavailable else { return nil }
            return .idle

        case .timeout(let phase):
            switch state {
            case .idle, .bluetoothUnavailable:
                return nil
            default:
                return .failed(.timeout(phase))
            }

        case .failure(let failure):
            return .failed(failure)

        case .reset:
            return .idle
        }
    }
}
