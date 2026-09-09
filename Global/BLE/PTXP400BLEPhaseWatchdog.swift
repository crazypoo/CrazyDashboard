//
//  PTXP400BLEPhaseWatchdog.swift
//  CrazyDashboard
//
//  EN: Owns one cancellable watchdog for one XP400 BLE phase at a time.
//  ES: Posee un único watchdog cancelable para una fase BLE del XP400 a la vez.
//  中文：每次只为一个 XP400 BLE 阶段维护一个可取消的 watchdog。
//

import Foundation

/// EN: Timeout values are centralized so protocol timing is not scattered as magic numbers.
/// ES: Los tiempos se centralizan para no dispersar números mágicos por el protocolo.
/// 中文：集中管理超时数值，避免协议代码散落 magic number。
public struct PTXP400BLETimeouts: Equatable, Sendable {
    public let serviceConfiguration: TimeInterval
    public let advertisingStartup: TimeInterval
    public let centralSubscription: TimeInterval
    public let authentication: TimeInterval
    public let connectionFrame: TimeInterval
    public let sendQueueStall: TimeInterval
    public let sessionIdle: TimeInterval

    public init(
        serviceConfiguration: TimeInterval = 10,
        advertisingStartup: TimeInterval = 10,
        centralSubscription: TimeInterval = 30,
        authentication: TimeInterval = 6,
        connectionFrame: TimeInterval = 6,
        sendQueueStall: TimeInterval = 5,
        sessionIdle: TimeInterval = 60
    ) {
        self.serviceConfiguration = Self.validated(serviceConfiguration)
        self.advertisingStartup = Self.validated(advertisingStartup)
        self.centralSubscription = Self.validated(centralSubscription)
        self.authentication = Self.validated(authentication)
        self.connectionFrame = Self.validated(connectionFrame)
        self.sendQueueStall = Self.validated(sendQueueStall)
        self.sessionIdle = Self.validated(sessionIdle)
    }

    public static let standard = PTXP400BLETimeouts()

    public func interval(for phase: PTXP400BLETimeoutPhase) -> TimeInterval {
        switch phase {
        case .serviceConfiguration:
            return serviceConfiguration
        case .advertisingStartup:
            return advertisingStartup
        case .centralSubscription:
            return centralSubscription
        case .authentication:
            return authentication
        case .connectionFrame:
            return connectionFrame
        case .sendQueueStall:
            return sendQueueStall
        case .sessionIdle:
            return sessionIdle
        }
    }

    private static func validated(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite, value > 0 else { return 0.001 }
        return value
    }
}

/// EN: Main-actor isolation prevents timeout callbacks from racing lifecycle state.
/// ES: El aislamiento del actor principal evita que los callbacks compitan con el estado del ciclo de vida.
/// 中文：主 actor 隔离可避免超时回调与生命周期状态发生数据竞争。
@MainActor
public final class PTXP400BLEPhaseWatchdog {
    public typealias TimeoutHandler = @MainActor @Sendable (PTXP400BLETimeoutPhase) -> Void

    public private(set) var activePhase: PTXP400BLETimeoutPhase?

    private let timeouts: PTXP400BLETimeouts
    private var timeoutTask: Task<Void, Never>?
    private var token: UUID?

    public init(timeouts: PTXP400BLETimeouts = .standard) {
        self.timeouts = timeouts
    }

    public var isArmed: Bool {
        activePhase != nil
    }

    public func arm(
        _ phase: PTXP400BLETimeoutPhase,
        timeout: TimeInterval? = nil,
        handler: @escaping TimeoutHandler
    ) {
        cancel()

        let newToken = UUID()
        token = newToken
        activePhase = phase
        let nanoseconds = UInt64(min(max(timeout ?? timeouts.interval(for: phase), 0.001), 86_400) * 1_000_000_000)

        timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled, let self else { return }
            self.fire(phase: phase, token: newToken, handler: handler)
        }
    }

    public func cancel() {
        timeoutTask?.cancel()
        timeoutTask = nil
        token = nil
        activePhase = nil
    }

    private func fire(
        phase: PTXP400BLETimeoutPhase,
        token: UUID,
        handler: TimeoutHandler
    ) {
        guard self.token == token, activePhase == phase else { return }
        timeoutTask = nil
        self.token = nil
        activePhase = nil
        handler(phase)
    }
}
