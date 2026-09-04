//
//  PTVehicleConnectivityCoordinator.swift
//  CrazyDashboard
//
//  EN: Coordinates vehicle-link state without replacing either stable transport core.
//  ES: Coordina el estado de los enlaces sin reemplazar ninguno de los transportes estables.
//  中文：只协调车辆连接状态，不替换任何已经稳定的底层传输核心。
//

import Foundation
import UIKit

// EN: This value type is the only dashboard identity that leaves the BLE core.
// ES: Este tipo de valor es la única identidad del tablero que sale del núcleo BLE.
// 中文：这个值类型是唯一允许从 BLE 核心向外传递的仪表身份。
public struct PTDashboardConnectionIdentity: Codable, Equatable, Sendable {
    public let centralIdentifier: UUID?
    public let reportedSerialNumber: String?

    public init(centralIdentifier: UUID? = nil, reportedSerialNumber: String? = nil) {
        self.centralIdentifier = centralIdentifier
        self.reportedSerialNumber = Self.normalizeSerial(reportedSerialNumber)
    }

    public var isUsable: Bool {
        centralIdentifier != nil || reportedSerialNumber != nil
    }

    private static func normalizeSerial(_ value: String?) -> String? {
        guard let value else { return nil }
        var printable = ""
        for scalar in value.unicodeScalars where scalar.value >= 0x20 && scalar.value <= 0x7E {
            printable.unicodeScalars.append(scalar)
        }
        let normalized = printable.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? nil : String(normalized.prefix(64))
    }
}

public enum PTVehicleConnectionState: String, Codable, Sendable {
    case idle
    case connecting
    case connected
    case disconnected
    case failed
}

private enum PTVehicleDashboardSample: Sendable {
    case odometer(Double)
    case maintenanceDistance(Int)
    case maintenanceFlag(Int)
}

// EN: The buffer keeps only the newest primitive values, so a 10 Hz mock stream cannot grow memory.
// ES: El búfer conserva solo los valores primitivos más recientes y evita crecer con un flujo simulado de 10 Hz.
// 中文：缓冲区只保留最新的基础值，10Hz 模拟数据也不会造成内存增长。
private struct PTDashboardLiveBuffer: Sendable {
    var odometerKm: Double?
    var maintenanceDistanceKm: Int?
    var maintenanceFlag: Int?

    init() {
        odometerKm = nil
        maintenanceDistanceKm = nil
        maintenanceFlag = nil
    }

    var hasAnyValue: Bool {
        odometerKm != nil || maintenanceDistanceKm != nil || maintenanceFlag != nil
    }

    mutating func merge(_ sample: PTVehicleDashboardSample) {
        switch sample {
        case .odometer(let value):
            odometerKm = value
        case .maintenanceDistance(let value):
            maintenanceDistanceKm = value
        case .maintenanceFlag(let value):
            maintenanceFlag = value
        }
    }

    func snapshot(
        source: PTGarageDashboardSource = .dashboard,
        capturedAt: Date = Date()
    ) -> PTGarageDashboardSnapshot {
        PTGarageDashboardSnapshot(
            odometerKm: odometerKm,
            maintenanceDistanceKm: maintenanceDistanceKm,
            maintenanceFlag: maintenanceFlag,
            source: source,
            capturedAt: capturedAt
        )
    }
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
    public static let dashboardGarageSyncDidChange = Notification.Name("PTVehicleConnectivityCoordinator.dashboardGarageSyncDidChange")

    public private(set) var snapshot: PTVehicleSnapshot = .initial
    public private(set) var dashboardConnectionIdentity: PTDashboardConnectionIdentity?
    public private(set) var dashboardGarageVehicleID: UUID?
    public private(set) var dashboardLiveSnapshot: PTGarageDashboardSnapshot?

    private let widgetAppGroupID = PTWidgetDataKeys.appGroupID
    private let dashboardAutoSyncInterval: TimeInterval = 60
    private var dashboardAttemptInFlight = false
    private var obdAttemptInFlight = false
    private var obdRetryRequired = false
    private var ignoreNextOBDDisconnect = false
    private var dashboardObserversActivated = false
    private var dashboardAttemptTask: Task<Void, Never>?
    private var obdAttemptTask: Task<Void, Never>?
    private var pendingDashboardIdentity: PTDashboardConnectionIdentity?
    private var dashboardLiveBuffer = PTDashboardLiveBuffer()
    private var dashboardFlushTask: Task<Void, Never>?
    private var dashboardIdentityTask: Task<Void, Never>?
    private var dashboardSessionToken = UUID()
    private var dashboardSessionActive = false
    private var dashboardIdentityResolved = false
    private var dashboardIdentityConflict = false
    private var dashboardPendingCandidateVehicleID: UUID?
    private var dashboardDidPersistInitialSample = false
    private var dashboardLastPersistedAt: Date?
    private var backgroundObserver: NSObjectProtocol?

    private var dashboardSnapshotSource: PTGarageDashboardSource {
        snapshot.dashboard.transport == .dashboardMock ? .mock : .dashboard
    }

    private override init() {
        super.init()
        PTBluetoothServerManager.shared.addDelegate(self)
        PTMotoTelemetryManager.shared.addDelegate(self)
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.dashboardSessionActive else { return }
                _ = self.flushDashboardData(force: false)
            }
        }
        synchronizeInitialState()
    }

    isolated deinit {
        dashboardAttemptTask?.cancel()
        obdAttemptTask?.cancel()
        dashboardFlushTask?.cancel()
        dashboardIdentityTask?.cancel()
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
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
        guard prepareForMockDashboardConnection() else {
            return false
        }

        dashboardAttemptInFlight = true
        updateDashboardState(.connecting, transport: .dashboardMock)
        startDashboardWatchdog()
        PTBluetoothServerManager.shared.startMockDashboardData()
        return true
    }

    // EN: Reconcile launch-time restore state before starting a mock; a stale flag or pending scan must not block developer testing.
    // ES: Reconcilia el estado de restauración del arranque antes de iniciar el simulador; una marca obsoleta o un escaneo pendiente no debe bloquear las pruebas.
    // 中文：启动模拟器前先校正恢复状态，过期标记或待处理扫描不能阻塞开发者测试。
    private func prepareForMockDashboardConnection() -> Bool {
        if snapshot.dashboard.state == .connected,
           snapshot.dashboard.transport == .dashboardMock {
            return false
        }

        // EN: A live central identity proves that the real dashboard is still active; never replace it implicitly.
        // ES: Una identidad central activa demuestra que el tablero real sigue conectado; nunca lo sustituimos implícitamente.
        // 中文：存在有效的真实中心设备身份就说明真仪表仍在连接，绝不隐式替换。
        guard PTBluetoothServerManager.shared.dashboardConnectionIdentity?.isUsable != true else {
            return false
        }

        if snapshot.dashboard.transport == .dashboardBluetooth {
            switch snapshot.dashboard.state {
            case .connected:
                endDashboardGarageSession()
                dashboardConnectionIdentity = nil
                pendingDashboardIdentity = nil
                updateDashboardState(.idle, transport: nil)
            case .connecting:
                dashboardAttemptInFlight = false
                dashboardAttemptTask?.cancel()
                dashboardAttemptTask = nil
            default:
                break
            }
        } else if dashboardAttemptInFlight {
            return false
        }

        dashboardConnectionIdentity = nil
        pendingDashboardIdentity = nil

        // EN: This flag is only valid after a live dashboard callback; clear it when no hardware identity exists.
        // ES: Esta marca solo es válida después de un callback activo del tablero; se limpia si no existe identidad de hardware.
        // 中文：该标记只有收到真实仪表回调后才有效，没有硬件身份时清除它。
        PTDashboardConfig.shared.blueConnected = false
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

    public var dashboardDataIsBoundToSelectedVehicle: Bool {
        dashboardGarageVehicleID != nil
            && dashboardGarageVehicleID == PTMotorcycleGarageStore.shared.selectedVehicleID
    }

    public var dashboardNeedsGarageVehicleAssociation: Bool {
        snapshot.dashboard.state == .connected
            && snapshot.dashboard.transport == .dashboardBluetooth
            && dashboardGarageVehicleID == nil
    }

    public var dashboardIdentityIsConflicted: Bool {
        dashboardIdentityConflict
    }

    // EN: Mock and real dashboard sessions share the same bounded garage snapshot path.
    // ES: Las sesiones de tablero simulado y real comparten la misma ruta limitada de instantáneas del garaje.
    // 中文：模拟仪表和真实仪表共用同一条有边界的车库快照路径。
    private var dashboardSupportsGarageSync: Bool {
        switch snapshot.dashboard.transport {
        case .dashboardBluetooth?, .dashboardMock?:
            return true
        default:
            return false
        }
    }

    /// EN: Force the same snapshot path used by automatic checkpoints for the visible vehicle.
    /// ES: Fuerza la misma ruta de instantánea usada por los puntos automáticos para el vehículo visible.
    /// 中文：手动操作也复用自动检查点使用的同一份快照路径。
    @discardableResult
    public func syncCurrentGarageVehicleNow() -> PTGarageDashboardSyncResult {
        guard snapshot.dashboard.state == .connected,
              dashboardSupportsGarageSync else {
            return .unavailable
        }
        guard dashboardGarageVehicleID != nil else {
            return dashboardIdentityConflict ? .identityConflict : .unavailable
        }
        guard dashboardDataIsBoundToSelectedVehicle else { return .identityConflict }
        return flushDashboardData(force: true)
    }

    /// EN: A user-confirmed association is the only path allowed to recover from an ambiguous vehicle match.
    /// ES: La asociación confirmada por el usuario es la única vía para resolver una coincidencia ambigua.
    /// 中文：只有用户确认的关联操作可以解决车辆身份不明确的问题。
    @discardableResult
    public func associateCurrentDashboardWithSelectedVehicle() -> Bool {
        guard snapshot.dashboard.state == .connected,
              snapshot.dashboard.transport == .dashboardBluetooth,
              let selectedVehicleID = PTMotorcycleGarageStore.shared.selectedVehicleID,
              let identity = dashboardConnectionIdentity,
              identity.isUsable,
              PTMotorcycleGarageStore.shared.reassignDashboardIdentity(identity, to: selectedVehicleID) else {
            return false
        }

        dashboardGarageVehicleID = selectedVehicleID
        dashboardIdentityResolved = true
        dashboardIdentityConflict = false
        dashboardPendingCandidateVehicleID = nil
        dashboardIdentityTask?.cancel()
        applySuggestedVehicleNameIfNeeded(vehicleID: selectedVehicleID)
        notifyDashboardGarageSyncChanged()
        _ = flushDashboardData(force: true)
        return true
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
        let currentDashboardIdentity = PTBluetoothServerManager.shared.dashboardConnectionIdentity
        let hasLiveDashboard = PTDashboardConfig.shared.blueConnected
            && currentDashboardIdentity?.isUsable == true

        // EN: A volatile connected flag cannot survive without the core's current hardware identity.
        // ES: Una marca volátil de conexión no puede mantenerse sin la identidad de hardware actual del núcleo.
        // 中文：易失的连接标记没有底层当前硬件身份时不能继续被视为已连接。
        if PTDashboardConfig.shared.blueConnected && !hasLiveDashboard {
            PTDashboardConfig.shared.blueConnected = false
        }

        let dashboardState: PTVehicleConnectionState = hasLiveDashboard ? .connected : .idle
        let obdState: PTVehicleConnectionState = PTMotoTelemetryManager.shared.isConnected ? .connected : .idle
        let dashboardTransport: PTVehicleTransport? = hasLiveDashboard ? .dashboardBluetooth : nil
        let initialDashboard = PTVehicleLinkSnapshot(state: dashboardState, transport: dashboardTransport, updatedAt: now)
        let initialOBD = PTVehicleLinkSnapshot(state: obdState, updatedAt: now)
        snapshot = PTVehicleSnapshot(dashboard: initialDashboard, obd: initialOBD, updatedAt: now)
        pendingDashboardIdentity = currentDashboardIdentity
        dashboardConnectionIdentity = pendingDashboardIdentity

        if dashboardState == .connected {
            activateDashboardObserversIfNeeded()
            beginDashboardGarageSession()
        }
    }

    private func activateDashboardObserversIfNeeded() {
        guard !dashboardObserversActivated else { return }

        dashboardObserversActivated = true
        // EN: Install dashboard-dependent observers only when a dashboard connection exists.
        // ES: Instala observadores dependientes del tablero solo cuando existe una conexión activa.
        // 中文：只有仪表连接存在时才安装依赖仪表数据的观察者。
        _ = PTMotorcycleGarageStore.shared
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

    private func beginDashboardGarageSession() {
        guard !dashboardSessionActive,
              dashboardSupportsGarageSync else {
            return
        }

        dashboardSessionActive = true
        dashboardSessionToken = UUID()
        dashboardFlushTask?.cancel()
        dashboardIdentityTask?.cancel()
        dashboardFlushTask = nil
        dashboardIdentityTask = nil
        dashboardGarageVehicleID = nil
        dashboardLiveSnapshot = nil
        dashboardLiveBuffer = PTDashboardLiveBuffer()
        dashboardIdentityResolved = false
        dashboardIdentityConflict = false
        dashboardPendingCandidateVehicleID = nil
        dashboardDidPersistInitialSample = false
        dashboardLastPersistedAt = nil

        if snapshot.dashboard.transport == .dashboardMock {
            // EN: A local mock has no hardware identity, so it is safely scoped to the selected motorcycle.
            // ES: Un simulador local no tiene identidad de hardware y se limita de forma segura a la motocicleta seleccionada.
            // 中文：本地模拟仪表没有硬件身份，因此安全地绑定到当前选中的摩托车。
            dashboardGarageVehicleID = PTMotorcycleGarageStore.shared.selectedVehicleID
            dashboardIdentityResolved = dashboardGarageVehicleID != nil
        } else {
            if let pendingDashboardIdentity {
                resolveDashboardIdentity(pendingDashboardIdentity)
            }
            scheduleDashboardIdentityResolution()
        }
        notifyDashboardGarageSyncChanged()
    }

    private func endDashboardGarageSession() {
        guard dashboardSessionActive else { return }

        _ = flushDashboardData(force: !dashboardDidPersistInitialSample)
        dashboardSessionActive = false
        dashboardSessionToken = UUID()
        dashboardFlushTask?.cancel()
        dashboardIdentityTask?.cancel()
        dashboardFlushTask = nil
        dashboardIdentityTask = nil
        dashboardGarageVehicleID = nil
        dashboardLiveSnapshot = nil
        dashboardLiveBuffer = PTDashboardLiveBuffer()
        dashboardIdentityResolved = false
        dashboardIdentityConflict = false
        dashboardPendingCandidateVehicleID = nil
        dashboardDidPersistInitialSample = false
        dashboardLastPersistedAt = nil
        dashboardConnectionIdentity = nil
        pendingDashboardIdentity = nil
        notifyDashboardGarageSyncChanged()
    }

    private func receiveDashboardIdentity(_ identity: PTDashboardConnectionIdentity?) {
        dashboardConnectionIdentity = identity
        pendingDashboardIdentity = identity
        guard dashboardSessionActive else { return }

        guard let identity, identity.isUsable else {
            dashboardIdentityConflict = false
            notifyDashboardGarageSyncChanged()
            return
        }
        resolveDashboardIdentity(identity)
    }

    private func resolveDashboardIdentity(_ identity: PTDashboardConnectionIdentity) {
        let resolution = PTMotorcycleGarageStore.shared.resolveDashboardIdentity(
            identity,
            preferredVehicleID: PTMotorcycleGarageStore.shared.selectedVehicleID
        )

        switch resolution {
        case .matched(let vehicleID):
            guard PTMotorcycleGarageStore.shared.bindDashboardIdentity(identity, to: vehicleID) else {
                dashboardIdentityConflict = true
                dashboardGarageVehicleID = nil
                notifyDashboardGarageSyncChanged()
                return
            }
            dashboardGarageVehicleID = vehicleID
            dashboardIdentityResolved = true
            dashboardIdentityConflict = false
            dashboardPendingCandidateVehicleID = nil
            dashboardIdentityTask?.cancel()
            applySuggestedVehicleNameIfNeeded(vehicleID: vehicleID)
            notifyDashboardGarageSyncChanged()
            scheduleDashboardFlush()

        case .candidate(let vehicleID):
            dashboardPendingCandidateVehicleID = vehicleID
            dashboardIdentityConflict = false
            // EN: Wait briefly for the reported serial before claiming an unbound profile with only a UUID.
            // ES: Espera brevemente el número de serie antes de reclamar un perfil libre solo con UUID.
            // 中文：仅有 UUID 时短暂等待序列号，避免错误占用未绑定档案。
            if identity.reportedSerialNumber != nil {
                bindPendingDashboardCandidateIfPossible()
            }
            notifyDashboardGarageSyncChanged()

        case .conflict:
            dashboardIdentityConflict = true
            dashboardGarageVehicleID = nil
            dashboardIdentityResolved = false
            dashboardPendingCandidateVehicleID = nil
            dashboardFlushTask?.cancel()
            dashboardFlushTask = nil
            notifyDashboardGarageSyncChanged()

        case .unavailable:
            dashboardIdentityConflict = false
            dashboardGarageVehicleID = nil
            dashboardIdentityResolved = false
            dashboardPendingCandidateVehicleID = nil
            notifyDashboardGarageSyncChanged()
        }
    }

    private func bindPendingDashboardCandidateIfPossible() {
        guard let vehicleID = dashboardPendingCandidateVehicleID else {
            notifyDashboardGarageSyncChanged()
            return
        }
        guard let identity = dashboardConnectionIdentity,
              identity.isUsable else {
            notifyDashboardGarageSyncChanged()
            return
        }
        guard PTMotorcycleGarageStore.shared.bindDashboardIdentity(identity, to: vehicleID) else {
            dashboardIdentityConflict = true
            dashboardGarageVehicleID = nil
            dashboardIdentityResolved = false
            notifyDashboardGarageSyncChanged()
            return
        }

        dashboardGarageVehicleID = vehicleID
        dashboardIdentityResolved = true
        dashboardIdentityConflict = false
        dashboardPendingCandidateVehicleID = nil
        dashboardIdentityTask?.cancel()
        applySuggestedVehicleNameIfNeeded(vehicleID: vehicleID)
        notifyDashboardGarageSyncChanged()
        scheduleDashboardFlush()
    }

    private func scheduleDashboardIdentityResolution() {
        let token = dashboardSessionToken
        dashboardIdentityTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.dashboardSessionActive,
                  self.dashboardSessionToken == token,
                  !self.dashboardIdentityResolved,
                  !self.dashboardIdentityConflict else {
                return
            }
            self.bindPendingDashboardCandidateIfPossible()
        }
    }

    private func receiveDashboardSample(_ sample: PTVehicleDashboardSample) {
        guard dashboardSupportsGarageSync,
              snapshot.dashboard.state == .connecting || snapshot.dashboard.state == .connected else {
            return
        }
        if !dashboardSessionActive {
            beginDashboardGarageSession()
        }
        guard dashboardSessionActive else { return }

        dashboardLiveBuffer.merge(sample)
        dashboardLiveSnapshot = dashboardLiveBuffer.snapshot(source: dashboardSnapshotSource)
        notifyDashboardGarageSyncChanged()
        guard dashboardIdentityResolved, !dashboardIdentityConflict else { return }
        scheduleDashboardFlush()
    }

    private func scheduleDashboardFlush() {
        guard dashboardSessionActive,
              dashboardIdentityResolved,
              dashboardGarageVehicleID != nil,
              dashboardLiveBuffer.hasAnyValue,
              dashboardFlushTask == nil else {
            return
        }

        let delay: TimeInterval
        if dashboardDidPersistInitialSample {
            let earliest = (dashboardLastPersistedAt ?? .distantPast)
                .addingTimeInterval(dashboardAutoSyncInterval)
            delay = max(0.5, earliest.timeIntervalSinceNow)
        } else {
            delay = 1
        }

        let token = dashboardSessionToken
        let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
        dashboardFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self,
                  !Task.isCancelled,
                  self.dashboardSessionActive,
                  self.dashboardSessionToken == token else {
                return
            }
            _ = self.flushDashboardData(force: false)
        }
    }

    @discardableResult
    private func flushDashboardData(force: Bool) -> PTGarageDashboardSyncResult {
        dashboardFlushTask?.cancel()
        dashboardFlushTask = nil
        guard dashboardSessionActive,
              let vehicleID = dashboardGarageVehicleID,
              dashboardLiveBuffer.hasAnyValue else {
            return .unavailable
        }

        let result = PTMotorcycleGarageStore.shared.applyDashboardSnapshot(
            dashboardLiveBuffer.snapshot(source: dashboardSnapshotSource),
            to: vehicleID,
            recordReceiptWhenUnchanged: force || !dashboardDidPersistInitialSample
        )
        switch result {
        case .updated:
            dashboardDidPersistInitialSample = true
            dashboardLastPersistedAt = Date()
        case .unchanged:
            dashboardDidPersistInitialSample = true
        case .unavailable, .identityConflict, .vehicleNotFound:
            break
        }
        notifyDashboardGarageSyncChanged()
        return result
    }

    private func applySuggestedVehicleNameIfNeeded(vehicleID: UUID) {
        let nickname = PTMotoUserDefaultStruct.PTTCustomUserName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty,
              let vehicle = PTMotorcycleGarageStore.shared.vehicle(id: vehicleID),
              vehicle.name == PTMotorcycleProfile.defaultXP400GT.name else {
            return
        }

        let normalizedName: String
        let nameAlreadyUsed = PTMotorcycleGarageStore.shared.vehicles.contains {
            $0.id != vehicleID && $0.name.caseInsensitiveCompare(nickname) == .orderedSame
        }
        if nameAlreadyUsed {
            let suffix = dashboardConnectionIdentity?.reportedSerialNumber.map { String($0.suffix(4)) }
                ?? dashboardConnectionIdentity?.centralIdentifier.map { String($0.uuidString.suffix(4)) }
                ?? "MOTO"
            normalizedName = "\(nickname) · \(suffix)"
        } else {
            normalizedName = nickname
        }
        _ = PTMotorcycleGarageStore.shared.updateVehicleName(normalizedName, vehicleID: vehicleID)
    }

    private func notifyDashboardGarageSyncChanged() {
        NotificationCenter.default.post(
            name: Self.dashboardGarageSyncDidChange,
            object: self
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
        if isConnected {
            updateDashboardState(
                .connected,
                transport: snapshot.dashboard.transport ?? .dashboardBluetooth
            )
            beginDashboardGarageSession()
        } else {
            endDashboardGarageSession()
            updateDashboardState(
                .disconnected,
                transport: snapshot.dashboard.transport ?? .dashboardBluetooth
            )
        }
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

    nonisolated func dashboardManager(_ manager: PTBluetoothServerManager, dashboardData data: Any?) {
        let sample: PTVehicleDashboardSample?
        // EN: Only persist dashboard fields whose source bytes are available.
        // ES: Solo persiste los campos del tablero cuyos bytes de origen están disponibles.
        // 中文：只持久化源字节有效的仪表字段。
        if let data1 = data as? PTDashboardData1,
           data1.odometerAvailability.isAvailable {
            sample = .odometer(data1.odoKm)
        } else if let data2 = data as? PTDashboardData2,
                  data2.maintenanceAvailability.isAvailable {
            sample = .maintenanceFlag(data2.maintenance)
        } else if let data3 = data as? PTDashboardData3,
                  data3.maintenanceDistanceAvailability.isAvailable {
            sample = .maintenanceDistance(data3.distToMaintenance)
        } else {
            sample = nil
        }

        guard let sample else { return }
        Task { @MainActor [weak self] in
            self?.receiveDashboardSample(sample)
        }
    }

    nonisolated func dashboardManager(
        _ manager: PTBluetoothServerManager,
        didUpdateConnectionIdentity identity: PTDashboardConnectionIdentity?
    ) {
        Task { @MainActor [weak self] in
            self?.receiveDashboardIdentity(identity)
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
