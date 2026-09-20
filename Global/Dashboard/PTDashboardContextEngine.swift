//
//  PTDashboardContextEngine.swift
//  CrazyDashboard
//
//  EN: Main-actor coordinator for dashboard presentation only.
//  ES: Coordinador del actor principal únicamente para la presentación del tablero.
//  中文：只负责仪表盘展示的主线程协调器。
//

import Foundation
import MediaPlayer
import PooTools

// EN: The engine consumes existing snapshots and notifications; it never talks to BLE, ELM327 or YMOBD.
// ES: El motor consume instantáneas y notificaciones existentes; nunca habla con BLE, ELM327 ni YMOBD.
// 中文：Engine 只消费现有快照和通知，绝不直接接触 BLE、ELM327 或 YMOBD。
@MainActor
public final class PTDashboardContextEngine: NSObject, PTVehicleTelemetryConsumer {
    public static let shared = PTDashboardContextEngine()
    public static let didChange = Notification.Name("PTDashboardContextEngine.didChange")

    public private(set) var snapshot = PTDashboardContextResolver.resolve(
        PTDashboardContextInput(),
        now: .distantPast
    )
    public var onChange: ((PTDashboardContextSnapshot) -> Void)?

    private var clientCount = 0
    private var notificationTokens: [NSObjectProtocol] = []
    private var input = PTDashboardContextInput()
    private var navigationDistanceMeters: Double?
    private var navigationRoadName: String?
    private var motionWarningActive = false
    private var lastPublishedAt = Date.distantPast
    private var pendingSnapshot: PTDashboardContextSnapshot?
    private var throttleTask: Task<Void, Never>?
    private var mediaResetTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    // EN: Reference counting lets the dashboard and the Twin page share one engine safely.
    // ES: El recuento de referencias permite que el tablero y la página Twin compartan un solo motor.
    // 中文：引用计数让主仪表盘和 Twin 页面安全共享同一个 Engine。
    public func start() {
        clientCount += 1
        guard clientCount == 1 else {
            refresh()
            return
        }

        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: PTVehicleConnectivityCoordinator.snapshotDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleConnectionChange()
            }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: PTNavigationSessionCoordinator.stateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleNavigationChange()
            }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: PTNavigationSessionCoordinator.guidanceDidUpdateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleNavigationChange()
            }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMediaChange()
            }
        })

        PTVehicleTelemetryConsumerHub.shared.register(self)
        refresh()
    }

    public func stop() {
        guard clientCount > 0 else { return }
        clientCount -= 1
        guard clientCount == 0 else { return }

        PTVehicleTelemetryConsumerHub.shared.unregister(self)
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
        throttleTask?.cancel()
        throttleTask = nil
        mediaResetTask?.cancel()
        mediaResetTask = nil
        pendingSnapshot = nil
    }

    public func refresh() {
        updateConnection(PTVehicleConnectivityCoordinator.shared.snapshot)
        handleNavigationChange()
        input.isRiding = PTTripManager.shared.isRecordingRide
        recompute(force: true)
    }

    public func updateMotion(speedKmh: Double?, warningActive: Bool) {
        motionWarningActive = warningActive
        input.speedKmh = sanitizedSpeed(speedKmh)
        input.isRiding = PTTripManager.shared.isRecordingRide
            || (input.speedKmh.map { $0 >= 3 } ?? false)
        input.warningActive = motionWarningActive
        recompute()
    }

    public func vehicleTelemetryDidUpdate(_ snapshot: PTUnifiedVehicleTelemetrySnapshot) {
        let speed = sanitizedSpeed(snapshot.speedKmh ?? PTMotion.shared.currentSpeedKmh)
        input.speedKmh = speed
        input.isRiding = PTTripManager.shared.isRecordingRide || (speed.map { $0 >= 3 } ?? false)
        input.warningActive = motionWarningActive || snapshot.absLightOn == true
        updateConnection(PTVehicleConnectivityCoordinator.shared.snapshot, shouldRecompute: false)
        recompute()
    }

    private func updateConnection(
        _ connection: PTVehicleSnapshot,
        shouldRecompute: Bool = true
    ) {
        let dashboardConnected = connection.dashboard.state == .connected
        let obdConnected = connection.obd.state == .connected
        let hasConnectedTransport = dashboardConnected || obdConnected
        let pending = connection.dashboard.state == .connecting
            || connection.obd.state == .connecting
        let activeVehicleContext = input.isRiding || input.isNavigating
        input.connectionDegraded = activeVehicleContext
            && (pending || !hasConnectedTransport)
        if shouldRecompute {
            recompute()
        }
    }

    private func handleConnectionChange() {
        updateConnection(PTVehicleConnectivityCoordinator.shared.snapshot)
    }

    private func handleNavigationChange() {
        let coordinator = PTNavigationSessionCoordinator.shared
        let guidance = coordinator.snapshot
        let isNavigating = coordinator.isSessionActive
        let distance = guidance.distanceToManeuverMeters
        input.isNavigating = isNavigating
        input.isManeuver = isNavigating
            && distance.isFinite
            && distance > 0
            && distance <= PTDashboardContextResolver.maneuverDistanceMeters
        navigationDistanceMeters = distance.isFinite && distance > 0 ? distance : nil
        navigationRoadName = guidance.nextRoad.isEmpty ? guidance.currentRoad : guidance.nextRoad
        updateConnection(PTVehicleConnectivityCoordinator.shared.snapshot, shouldRecompute: false)
        recompute()
    }

    private func handleMediaChange() {
        input.mediaChanged = true
        recompute()
        mediaResetTask?.cancel()
        mediaResetTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.input.mediaChanged = false
            self?.recompute()
        }
    }

    private func recompute(force: Bool = false) {
        let candidate = PTDashboardContextResolver.resolve(
            input,
            navigationDistanceMeters: navigationDistanceMeters,
            navigationRoadName: navigationRoadName
        )
        guard force || !candidate.isEquivalentState(to: snapshot) else { return }
        enqueue(candidate, force: force)
    }

    // EN: Twenty hertz is the upper dashboard state budget; raw telemetry may arrive faster.
    // ES: Veinte hercios es el presupuesto máximo del estado del tablero; la telemetría puede llegar más rápido.
    // 中文：仪表盘状态预算上限为 20Hz，原始遥测可以更高频到达。
    private func enqueue(_ candidate: PTDashboardContextSnapshot, force: Bool) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastPublishedAt)
        if force || elapsed >= 0.05 {
            publish(candidate)
            return
        }

        pendingSnapshot = candidate
        guard throttleTask == nil else { return }
        let delay = UInt64(max(0.001, 0.05 - elapsed) * 1_000_000_000)
        throttleTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.throttleTask = nil
            self?.publishPending()
        }
    }

    private func publishPending() {
        guard let pendingSnapshot else { return }
        self.pendingSnapshot = nil
        guard !pendingSnapshot.isEquivalentState(to: snapshot) else { return }
        publish(pendingSnapshot)
    }

    private func publish(_ next: PTDashboardContextSnapshot) {
        snapshot = next
        lastPublishedAt = Date()
        onChange?(next)
        NotificationCenter.default.post(
            name: Self.didChange,
            object: self,
            userInfo: ["snapshot": next]
        )
    }

    private func sanitizedSpeed(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return min(value, 400)
    }

    deinit {
        throttleTask?.cancel()
        mediaResetTask?.cancel()
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }
}
