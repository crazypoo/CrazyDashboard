// EN: Keep initialization policy separate while the legacy connector remains the compatibility facade.
// ES: Separa la política de inicialización mientras el conector heredado sigue siendo la fachada compatible.
// 中文：分离初始化策略，同时保留旧连接器作为兼容门面。

import Foundation

public final class PTYMOBDInitializer {
    public enum State: String, Sendable {
        case idle
        case initializing
        case authenticating
        case checkingECU
        case ready
        case failed
    }

    // EN: This is the shared 19-command ELM327-compatible queue; AUTH is only an optional slot.
    // ES: Esta es la cola compartida compatible con ELM327 de 19 comandos; AUTH es solo un hueco opcional.
    // 中文：这是共享的 19 条 ELM327 兼容初始化队列；AUTH 只是可选槽位。
    public static let defaultCommandQueue: [String] = [
        "ATZ", "ATE0", "ATL0", "ATH1", "ATSP0", "AT+VERSION", "ATI", "ATRV", "<AUTH>",
        "0100", "020000", "0600", "0900", "ATDP", "0120", "0140", "0902", "0904", "0906"
    ]

    public static let maximum0100RetryCount = 20
    public static let initializationTimeout: TimeInterval = 20

    public private(set) var state: State = .idle
    public private(set) var retryCountFor0100 = 0
    public private(set) var hasTriggeredDebugFlagFor0100 = false
    public private(set) var pid0100Mask: UInt32?

    public init() {}

    public func begin() {
        retryCountFor0100 = 0
        hasTriggeredDebugFlagFor0100 = false
        pid0100Mask = nil
        state = .initializing
    }

    public func reset() {
        retryCountFor0100 = 0
        hasTriggeredDebugFlagFor0100 = false
        pid0100Mask = nil
        state = .idle
    }

    public func markAuthenticating() {
        state = .authenticating
    }

    public func markCheckingECU() {
        state = .checkingECU
    }

    public func markReady() {
        state = .ready
    }

    public func markFailed() {
        state = .failed
    }

    public func skipOptionalAuthentication() {
        state = .checkingECU
    }

    public func recordPID0100Mask(_ mask: UInt32) {
        pid0100Mask = (pid0100Mask ?? 0) | mask
        state = .checkingECU
    }

    public func canEnterReadyState() -> Bool {
        guard let pid0100Mask, pid0100Mask != 0 else { return false }
        return true
    }

    public func shouldSendDebugFlag(forYMOBD isYMOBD: Bool) -> Bool {
        guard isYMOBD, !hasTriggeredDebugFlagFor0100 else { return false }
        hasTriggeredDebugFlagFor0100 = true
        state = .checkingECU
        return true
    }

    public func consume0100Retry() -> Bool {
        guard retryCountFor0100 < Self.maximum0100RetryCount else {
            state = .failed
            return false
        }
        retryCountFor0100 += 1
        state = .checkingECU
        return true
    }
}
