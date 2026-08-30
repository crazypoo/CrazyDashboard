//
//  PTVehicleConnectivityCoordinator.swift
//  CrazyDashboard
//
//  EN: Coordinates vehicle-link state without replacing either stable transport core.
//  ES: Coordina el estado de los enlaces sin reemplazar ninguno de los transportes estables.
//  中文：只协调车辆连接状态，不替换任何已经稳定的底层传输核心。
//

import Foundation

public enum PTVehicleConnectionState: String, Codable, Sendable {
    case idle
    case connecting
    case connected
    case disconnected
    case failed
}

public enum PTVehicleTransport: String, Codable, Sendable {
    case dashboardBluetooth
    case dashboardMock
    case obdBluetooth
    case obdWiFi
    case obdMock
}

public struct PTVehicleLinkSnapshot: Codable, Equatable, Sendable {
    public let state: PTVehicleConnectionState
    public let transport: PTVehicleTransport?
    public let errorMessage: String?
    public let updatedAt: Date

    public init(
        state: PTVehicleConnectionState,
        transport: PTVehicleTransport? = nil,
        errorMessage: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.state = state
        self.transport = transport
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }

    public static let idle = PTVehicleLinkSnapshot(state: .idle, updatedAt: .distantPast)
}

public struct PTVehicleSnapshot: Codable, Equatable, Sendable {
    public let dashboard: PTVehicleLinkSnapshot
    public let obd: PTVehicleLinkSnapshot
    public let updatedAt: Date

    public init(
        dashboard: PTVehicleLinkSnapshot = .idle,
        obd: PTVehicleLinkSnapshot = .idle,
        updatedAt: Date = Date()
    ) {
        self.dashboard = dashboard
        self.obd = obd
        self.updatedAt = updatedAt
    }

    public static let initial = PTVehicleSnapshot(
        dashboard: .idle,
        obd: .idle,
        updatedAt: .distantPast
    )

    public var isDashboardConnected: Bool {
        dashboard.state == .connected
    }

    public var isOBDConnected: Bool {
        obd.state == .connected
    }

    public func replacing(
        dashboard: PTVehicleLinkSnapshot? = nil,
        obd: PTVehicleLinkSnapshot? = nil,
        updatedAt: Date = Date()
    ) -> PTVehicleSnapshot {
        PTVehicleSnapshot(
            dashboard: dashboard ?? self.dashboard,
            obd: obd ?? self.obd,
            updatedAt: updatedAt
        )
    }
}

// EN: This actor-isolated coordinator serializes only orchestration state; all transport work stays in the existing managers.
// ES: Este coordinador aislado al actor serializa solo el estado de orquestación; el transporte sigue en los gestores existentes.
// 中文：该主线程协调器只串行化编排状态，所有传输工作仍由现有管理器负责。
@MainActor
public final class PTVehicleConnectivityCoordinator: NSObject {
    public static let shared = PTVehicleConnectivityCoordinator()
    public static let snapshotDidChange = Notification.Name("PTVehicleConnectivityCoordinator.snapshotDidChange")

    public private(set) var snapshot: PTVehicleSnapshot = .initial

    private let widgetAppGroupID = PTWidgetDataKeys.appGroupID
    private var dashboardAttemptInFlight = false
    private var obdAttemptInFlight = false
    private var obdRetryRequired = false
    private var ignoreNextOBDDisconnect = false
    private var dashboardObserversActivated = false
    private var dashboardAttemptTask: Task<Void, Never>?
    private var obdAttemptTask: Task<Void, Never>?

    private override init() {
        super.init()
        PTBluetoothServerManager.shared.addDelegate(self)
        PTMotoTelemetryManager.shared.addDelegate(self)
        synchronizeInitialState()
    }

    isolated deinit {
        dashboardAttemptTask?.cancel()
        obdAttemptTask?.cancel()
        PTBluetoothServerManager.shared.removeDelegate(self)
        PTMotoTelemetryManager.shared.removeDelegate(self)
    }

    @discardableResult
    public func connectDashboardIfNeeded() -> Bool {
        if PTDashboardConfig.shared.blueConnected {
            updateDashboardState(.connected, transport: .dashboardBluetooth)
            return false
        }

        guard !dashboardAttemptInFlight else { return false }

        dashboardAttemptInFlight = true
        updateDashboardState(.connecting, transport: .dashboardBluetooth)
        startDashboardWatchdog()
        PTBluetoothServerManager.shared.startBaseStationAndScan()
        return true
    }

    @discardableResult
    public func restoreDashboardConnectionIfNeeded() -> Bool {
        guard PTMotoUserDefaultStruct.MotoLinkedAPP else { return false }
        return connectDashboardIfNeeded()
    }

    @discardableResult
    public func connectMockDashboard() -> Bool {
        if PTDashboardConfig.shared.blueConnected || dashboardAttemptInFlight {
            return false
        }

        dashboardAttemptInFlight = true
        updateDashboardState(.connecting, transport: .dashboardMock)
        startDashboardWatchdog()
        PTBluetoothServerManager.shared.startMockDashboardData()
        return true
    }

    public func stopMockDashboard() {
        dashboardAttemptInFlight = false
        dashboardAttemptTask?.cancel()
        dashboardAttemptTask = nil
        PTBluetoothServerManager.shared.stopMockDashboardData()
        updateDashboardState(.disconnected, transport: .dashboardMock)
    }

    // EN: Route dashboard disconnects through the coordinator so every consumer sees one state transition.
    // ES: Enrutamos la desconexión del tablero por el coordinador para que todos vean una sola transición.
    // 中文：仪表断开也经过协调器，确保所有消费者看到同一次状态变化。
    public func disconnectDashboard() {
        let transport = snapshot.dashboard.transport ?? .dashboardBluetooth
        dashboardAttemptInFlight = false
        dashboardAttemptTask?.cancel()
        dashboardAttemptTask = nil

        if transport == .dashboardMock {
            PTBluetoothServerManager.shared.stopMockDashboardData()
        } else {
            PTBluetoothServerManager.shared.sendDisconnect()
        }

        updateDashboardState(.disconnected, transport: transport)
    }

    @discardableResult
    public func connectOBD(
        via connectionType: PTOBDConnectionType,
        engineType: PTEngineType = .ice
    ) -> Bool {
        if PTMotoTelemetryManager.shared.isConnected {
            updateOBDState(.connected, transport: transport(for: connectionType))
            return false
        }

        guard !obdAttemptInFlight else { return false }

        // EN: A timed-out core scan must be reset before a manual retry, preventing overlapping OBD state machines.
        // ES: Una exploración agotada debe reiniciarse antes del reintento manual para evitar máquinas superpuestas.
        // 中文：底层扫描超时后，手动重试前先重置逻辑状态，避免多个 OBD 状态机重叠。
        if obdRetryRequired {
            ignoreNextOBDDisconnect = true
            PTMotoTelemetryManager.shared.disconnect()
            obdRetryRequired = false
        }

        obdAttemptInFlight = true
        let selectedTransport = transport(for: connectionType)
        updateOBDState(.connecting, transport: selectedTransport)
        startOBDWatchdog()
        PTMotoTelemetryManager.shared.connectToMotorcycle(via: connectionType, engineType: engineType)
        return true
    }

    @discardableResult
    public func connectOBDIfAllowed(
        via connectionType: PTOBDConnectionType = .bluetooth,
        engineType: PTEngineType = .ice
    ) -> Bool {
        guard PTMotoUserDefaultStruct.OBDAutoConnectEnabled else {
            return false
        }
        return connectOBD(via: connectionType, engineType: engineType)
    }

    public func disconnectOBD() {
        obdAttemptInFlight = false
        obdRetryRequired = false
        ignoreNextOBDDisconnect = false
        obdAttemptTask?.cancel()
        obdAttemptTask = nil
        PTMotoTelemetryManager.shared.disconnect()
        updateOBDState(.disconnected)
    }

    public func handleOBDConnectionTimeout() {
        guard obdAttemptInFlight, !PTMotoTelemetryManager.shared.isConnected else { return }

        obdAttemptInFlight = false
        obdRetryRequired = true
        obdAttemptTask?.cancel()
        obdAttemptTask = nil
        updateOBDState(.failed, errorMessage: "OBD connection timed out")
    }

    private func synchronizeInitialState() {
        let now = Date()
        let dashboardState: PTVehicleConnectionState = PTDashboardConfig.shared.blueConnected ? .connected : .idle
        let obdState: PTVehicleConnectionState = PTMotoTelemetryManager.shared.isConnected ? .connected : .idle
        let dashboardTransport: PTVehicleTransport? = PTDashboardConfig.shared.blueConnected ? .dashboardBluetooth : nil
        let initialDashboard = PTVehicleLinkSnapshot(state: dashboardState, transport: dashboardTransport, updatedAt: now)
        let initialOBD = PTVehicleLinkSnapshot(state: obdState, updatedAt: now)
        snapshot = PTVehicleSnapshot(dashboard: initialDashboard, obd: initialOBD, updatedAt: now)

        if dashboardState == .connected {
            activateDashboardObserversIfNeeded()
        }
    }

    private func activateDashboardObserversIfNeeded() {
        guard !dashboardObserversActivated else { return }

        dashboardObserversActivated = true
        // EN: Install dashboard-dependent observers only when a dashboard connection exists.
        // ES: Instala observadores dependientes del tablero solo cuando existe una conexión activa.
        // 中文：只有仪表连接存在时才安装依赖仪表数据的观察者。
        _ = PTAntiTheftManager.shared
        _ = PTDiagnosticManager.shared
        _ = PTMaintenanceManager.shared
    }

    private func updateDashboardState(
        _ state: PTVehicleConnectionState,
        transport: PTVehicleTransport? = nil,
        errorMessage: String? = nil
    ) {
        let current = snapshot.dashboard
        let next = PTVehicleLinkSnapshot(
            state: state,
            transport: transport ?? current.transport,
            errorMessage: errorMessage,
            updatedAt: Date()
        )

        if state == .connected {
            activateDashboardObserversIfNeeded()
        }

        guard current.state != next.state || current.transport != next.transport || current.errorMessage != next.errorMessage else {
            return
        }

        if state == .connected {
            PTDashboardConfig.shared.blueConnected = true
        } else if state == .disconnected || state == .failed {
            PTDashboardConfig.shared.blueConnected = false
        }
        publish(snapshot.replacing(dashboard: next))
    }

    private func updateOBDState(
        _ state: PTVehicleConnectionState,
        transport: PTVehicleTransport? = nil,
        errorMessage: String? = nil
    ) {
        let current = snapshot.obd
        let next = PTVehicleLinkSnapshot(
            state: state,
            transport: transport ?? current.transport,
            errorMessage: errorMessage,
            updatedAt: Date()
        )
        guard current.state != next.state || current.transport != next.transport || current.errorMessage != next.errorMessage else {
            return
        }

        publish(snapshot.replacing(obd: next))
    }

    private func publish(_ next: PTVehicleSnapshot) {
        snapshot = next
        NotificationCenter.default.post(
            name: Self.snapshotDidChange,
            object: self,
            userInfo: ["snapshot": next]
        )
        syncWidgetConnectionProjection()
    }

    private func syncWidgetConnectionProjection() {
        // EN: Widgets and Watch use PTWidgetSharedStatus; only project the dashboard link and preserve the existing values.
        // ES: El Widget y el Watch usan PTWidgetSharedStatus; solo proyectamos el enlace del tablero y conservamos sus valores.
        // 中文：Widget 和 Watch 使用 PTWidgetSharedStatus，这里只投影仪表连接状态并保留原有数据。
        guard
            let defaults = UserDefaults(suiteName: widgetAppGroupID),
            let current = PTWidgetSharedStatus(defaults: defaults)
        else {
            return
        }

        let dashboardConnected = snapshot.dashboard.state == .connected
        guard current.isConnected != dashboardConnected else { return }

        PTWidgetDataManager.shared.updateWidgetData(
            fuelLevel: current.fuelLevel,
            tripKm: current.tripKm,
            isConnected: dashboardConnected,
            parkedLat: current.parkedLat,
            parkedLon: current.parkedLon,
            address: current.address
        )
    }

    private func startDashboardWatchdog() {
        dashboardAttemptTask?.cancel()
        dashboardAttemptTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, !Task.isCancelled, self.dashboardAttemptInFlight else { return }
            self.dashboardAttemptInFlight = false
            self.updateDashboardState(.failed, errorMessage: "Dashboard connection timed out")
        }
    }

    private func startOBDWatchdog() {
        obdAttemptTask?.cancel()
        obdAttemptTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.handleOBDConnectionTimeout()
        }
    }

    private func transport(for connectionType: PTOBDConnectionType) -> PTVehicleTransport {
        switch connectionType {
        case .bluetooth:
            return .obdBluetooth
        case .wifi:
            return .obdWiFi
        case .mock:
            return .obdMock
        }
    }

    private func receiveDashboardConnection(_ isConnected: Bool) {
        dashboardAttemptInFlight = false
        dashboardAttemptTask?.cancel()
        dashboardAttemptTask = nil
        updateDashboardState(
            isConnected ? .connected : .disconnected,
            transport: snapshot.dashboard.transport ?? .dashboardBluetooth
        )
    }

    private func receiveOBDConnection(_ isConnected: Bool) {
        if !isConnected, ignoreNextOBDDisconnect {
            ignoreNextOBDDisconnect = false
            return
        }

        obdAttemptInFlight = false
        obdRetryRequired = false
        obdAttemptTask?.cancel()
        obdAttemptTask = nil
        updateOBDState(isConnected ? .connected : .disconnected)
    }
}

extension PTVehicleConnectivityCoordinator: PTBLEDashboardDelegate {
    nonisolated func dashboardManager(_ manager: PTBluetoothServerManager, didChangeConnectionState isConnected: Bool) {
        Task { @MainActor [weak self] in
            self?.receiveDashboardConnection(isConnected)
        }
    }
}

extension PTVehicleConnectivityCoordinator: PTMotoTelemetryDelegate {
    public nonisolated func telemetryManager(_ manager: PTMotoTelemetryManager, didChangeConnectionState isConnected: Bool) {
        Task { @MainActor [weak self] in
            self?.receiveOBDConnection(isConnected)
        }
    }
}
