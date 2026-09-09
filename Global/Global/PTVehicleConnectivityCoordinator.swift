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
    public static let dashboardBLEStateDidChange = Notification.Name("PTVehicleConnectivityCoordinator.dashboardBLEStateDidChange")
    public static let dashboardGarageSyncDidChange = Notification.Name("PTVehicleConnectivityCoordinator.dashboardGarageSyncDidChange")
    public static let telemetryDidChange = Notification.Name("PTVehicleConnectivityCoordinator.telemetryDidChange")

    public private(set) var snapshot: PTVehicleSnapshot = .initial
    // EN: This is a compatibility projection of the protected BLE core, not a second transport state machine.
    // ES: Esta es una proyección compatible del núcleo BLE protegido, no una segunda máquina de transporte.
    // 中文：这是受保护 BLE 核心的兼容状态投影，不是第二套传输状态机。
    public private(set) var dashboardBLEState: PTXP400BLELifecycleState = .idle
    public private(set) var telemetrySnapshot: PTVehicleTelemetrySnapshot = .empty
    public private(set) var wheelSpeedConsistency = PTWheelSpeedConsistencyResult(state: .unavailable)
    public private(set) var batteryHealthSummary = PTBatteryHealthSummary()
    public private(set) var dashboardConnectionIdentity: PTDashboardConnectionIdentity?
    public private(set) var dashboardGarageVehicleID: UUID?
    public private(set) var dashboardLiveSnapshot: PTGarageDashboardSnapshot?
    // EN: Reliability telemetry is bounded and contains no vehicle identifiers or raw BLE payloads.
    // ES: La telemetría de fiabilidad está acotada y no contiene identificadores ni cargas BLE sin procesar.
    // 中文：可靠性遥测有界保存，不包含车辆标识或原始 BLE Payload。
    public var dashboardBLEReliabilitySnapshot: PTXP400BLEReliabilitySnapshot {
        PTXP400BLEReliabilityMonitor.shared.snapshot
    }

    /// EN: Expose a bounded, privacy-safe reliability export for the developer tools.
    /// ES: Expone una exportación acotada y segura para la privacidad a las herramientas de desarrollo.
    /// 中文：为开发者工具提供有界且不含隐私数据的可靠性导出。
    public func exportDashboardBLEReliabilityURL() throws -> URL {
        try PTXP400BLETraceExport.exportReliabilityMetricsURL()
    }

    private let widgetAppGroupID = PTWidgetDataKeys.appGroupID
    private let dashboardAutoSyncInterval: TimeInterval = 60
    private var dashboardBLELifecycle = PTXP400BLELifecycleMachine()
    // EN: Preserve the legacy 15-second connection contract through the centralized phase configuration.
    // ES: Conserva el contrato heredado de 15 segundos mediante la configuración de fase centralizada.
    // 中文：通过集中式阶段配置保留原有 15 秒连接失败语义。
    private let dashboardBLEWatchdog = PTXP400BLEPhaseWatchdog(
        timeouts: PTXP400BLETimeouts(centralSubscription: 15)
    )
    private var dashboardAttemptInFlight = false
    private var obdAttemptInFlight = false
    private var obdRetryRequired = false
    private var ignoreNextOBDDisconnect = false
    private var dashboardObserversActivated = false
    private var obdAttemptTask: Task<Void, Never>?
    private var pendingDashboardIdentity: PTDashboardConnectionIdentity?
    private var dashboardLiveBuffer = PTDashboardLiveBuffer()
    private var dashboardFlushTask: Task<Void, Never>?
    private var dashboardIdentityTask: Task<Void, Never>?
    private var protocolCaptureLifecycleTask: Task<Void, Never>?
    private var dashboardSessionToken = UUID()
    private var dashboardSessionActive = false
    private var dashboardIdentityResolved = false
    private var dashboardIdentityConflict = false
    private var dashboardPendingCandidateVehicleID: UUID?
    private var dashboardDidPersistInitialSample = false
    private var dashboardLastPersistedAt: Date?
    private var backgroundObserver: NSObjectProtocol?
    // EN: This intent survives an expected link loss so the stable peripheral can accept a later reconnect.
    // ES: Esta intención sobrevive una pérdida esperada del enlace para que el periférico estable acepte una reconexión posterior.
    // 中文：该意图在预期链路断开后仍保留，让稳定外设稍后可以接受重新连接。
    private var dashboardBLEConnectionIntent = false
    private var dashboardBLESessionToken = PTXP400BLESessionToken()
    private var foregroundObserver: NSObjectProtocol?
    private var telemetryEngine = PTVehicleTelemetryFusionEngine()
    private var wheelSpeedTracker = PTWheelSpeedConsistencyTracker()
    private var batteryObservations: [PTBatteryObservation] = []
    private var batteryHistoryLastRecordedAt: Date?
    private var batteryHistoryVehicleID: UUID?
    private var turnSignalReminderTracker = PTTurnSignalReminderTracker()
    private var absWarningTracker = PTABSWarningTracker()
    private var telemetryNotificationTask: Task<Void, Never>?
    private var pendingTelemetryNotification: PTVehicleTelemetrySnapshot?

    private var dashboardSnapshotSource: PTGarageDashboardSource {
        snapshot.dashboard.transport == .dashboardMock ? .mock : .dashboard
    }

    private override init() {
        super.init()
        PTBluetoothServerManager.shared.addDelegate(self)
        PTMotoTelemetryManager.shared.addDelegate(self)
        // English: Install passive log observers once; they never start a transport operation.
        // Español: Instala una sola vez los observadores pasivos; nunca inician una operación de transporte.
        // 中文：只安装一次被动日志观察者，它们绝不会启动传输操作。
        Task {
            await PTProtocolDiscoveryRecorder.shared.installObservers()
        }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.dashboardSessionActive else { return }
                _ = self.flushDashboardData(force: false)
                PTXP400BLEReliabilityMonitor.shared.record(
                    .backgroundReconciled,
                    token: self.dashboardBLESessionToken,
                    detail: "garage snapshot flushed"
                )
            }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reconcileDashboardBLEAfterForeground()
            }
        }
        synchronizeInitialState()
        // EN: Re-project values only when the stable manager still reports a live dashboard connection.
        // ES: Vuelve a proyectar valores solo cuando el gestor estable aún informa una conexión activa.
        // 中文：只有稳定管理器仍报告仪表真实连接时，才重新投影缓存数值。
        if snapshot.dashboard.state == .connected {
            if let latestData1 = PTBluetoothServerManager.shared.latestData1 {
                receiveDashboardData(latestData1)
            }
            if let latestData2 = PTBluetoothServerManager.shared.latestData2 {
                receiveDashboardData(latestData2)
            }
            if let latestData3 = PTBluetoothServerManager.shared.latestData3 {
                receiveDashboardData(latestData3)
            }
            if let latestControl = PTBluetoothServerManager.shared.latestControl {
                receiveDashboardData(latestControl)
            }
            if let latestAbsStatus = PTBluetoothServerManager.shared.latestAbsStatus {
                receiveDashboardData(latestAbsStatus)
            }
        }
        syncProtocolCaptureLifecycle(for: snapshot)
    }

    isolated deinit {
        dashboardBLEWatchdog.cancel()
        obdAttemptTask?.cancel()
        dashboardFlushTask?.cancel()
        dashboardIdentityTask?.cancel()
        protocolCaptureLifecycleTask?.cancel()
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        telemetryNotificationTask?.cancel()
        PTBluetoothServerManager.shared.removeDelegate(self)
        PTMotoTelemetryManager.shared.removeDelegate(self)
    }

    @discardableResult
    public func connectDashboardIfNeeded() -> Bool {
        if PTDashboardConfig.shared.blueConnected {
            dashboardBLEConnectionIntent = true
            markDashboardBLEReady()
            updateDashboardState(.connected, transport: .dashboardBluetooth)
            return false
        }

        guard !dashboardAttemptInFlight else { return false }

        let token = beginDashboardBLESession()
        dashboardBLEConnectionIntent = true
        dashboardAttemptInFlight = true
        transitionDashboardBLE(.startRequested)
        updateDashboardState(.connecting, transport: .dashboardBluetooth)
        startDashboardWatchdog(for: token)
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

        let token = beginDashboardBLESession()
        dashboardBLEConnectionIntent = true
        dashboardAttemptInFlight = true
        transitionDashboardBLE(.startRequested)
        updateDashboardState(.connecting, transport: .dashboardMock)
        startDashboardWatchdog(for: token)
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
                finishDashboardBLESession(
                    kind: .sessionFailed,
                    detail: "replaced by mock dashboard"
                )
                endDashboardGarageSession()
                dashboardConnectionIdentity = nil
                pendingDashboardIdentity = nil
                updateDashboardState(.idle, transport: nil)
            case .connecting:
                finishDashboardBLESession(
                    kind: .sessionFailed,
                    detail: "replaced by mock dashboard"
                )
                dashboardAttemptInFlight = false
                dashboardBLEWatchdog.cancel()
            default:
                break
            }
            dashboardBLEConnectionIntent = false
            PTBluetoothServerManager.shared.stopAdvertising()
            invalidateDashboardBLESession()
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
        dashboardBLEConnectionIntent = false
        dashboardAttemptInFlight = false
        dashboardBLEWatchdog.cancel()
        finishDashboardBLESession(kind: .sessionDisconnected, detail: "mock dashboard stopped")
        invalidateDashboardBLESession()
        PTBluetoothServerManager.shared.stopMockDashboardData()
        PTBluetoothServerManager.shared.stopAdvertising()
        finalizeDashboardDisconnect(transport: .dashboardMock)
        telemetryEngine.clearDashboard()
        wheelSpeedTracker = PTWheelSpeedConsistencyTracker()
        wheelSpeedConsistency = PTWheelSpeedConsistencyResult(state: .unavailable)
        resetDashboardDerivedState()
        publishTelemetryChange()
    }

    // EN: Route dashboard disconnects through the coordinator so every consumer sees one state transition.
    // ES: Enrutamos la desconexión del tablero por el coordinador para que todos vean una sola transición.
    // 中文：仪表断开也经过协调器，确保所有消费者看到同一次状态变化。
    public func disconnectDashboard() {
        let transport = snapshot.dashboard.transport ?? .dashboardBluetooth
        dashboardBLEConnectionIntent = false
        dashboardAttemptInFlight = false
        transitionDashboardBLE(.disconnectRequested)
        dashboardBLEWatchdog.cancel()
        finishDashboardBLESession(kind: .sessionDisconnected, detail: "user requested disconnect")
        invalidateDashboardBLESession()

        if transport == .dashboardMock {
            PTBluetoothServerManager.shared.stopMockDashboardData()
        } else {
            PTBluetoothServerManager.shared.sendDisconnect()
            PTBluetoothServerManager.shared.stopAdvertising()
        }

        finalizeDashboardDisconnect(transport: transport)
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
        invalidateOBDBusLease()
        PTMotoTelemetryManager.shared.disconnect()
        updateOBDState(.disconnected)
    }

    public func handleOBDConnectionTimeout() {
        guard obdAttemptInFlight, !PTMotoTelemetryManager.shared.isConnected else { return }

        obdAttemptInFlight = false
        obdRetryRequired = true
        obdAttemptTask?.cancel()
        obdAttemptTask = nil
        invalidateOBDBusLease()
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
            dashboardBLEConnectionIntent = true
            markDashboardBLEReady()
            activateDashboardObserversIfNeeded()
            beginDashboardGarageSession()
        } else {
            dashboardBLELifecycle = PTXP400BLELifecycleMachine()
            dashboardBLEState = dashboardBLELifecycle.state
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
        syncProtocolCaptureLifecycle(for: next)
    }

    private var dashboardTelemetrySource: PTVehicleTelemetrySource {
        snapshot.dashboard.transport == .dashboardMock ? .dashboardMock : .dashboardBluetooth
    }

    private var obdTelemetrySource: PTVehicleTelemetrySource {
        switch snapshot.obd.transport {
        case .obdMock:
            return .obdMock
        case .obdWiFi:
            return .obdWiFi
        default:
            return .obdBluetooth
        }
    }

    // EN: Keep the value current immediately, but coalesce notifications so high-rate frames do not redraw every screen.
    // ES: Mantiene el valor actualizado de inmediato, pero agrupa las notificaciones para no redibujar cada pantalla por cada trama.
    // 中文：数值立即更新，同时合并通知，避免高频帧让所有界面逐帧重绘。
    private func publishTelemetryChange() {
        let next = telemetryEngine.snapshot
        telemetrySnapshot = next
        pendingTelemetryNotification = next
        guard telemetryNotificationTask == nil else { return }

        telemetryNotificationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self else { return }
            guard !Task.isCancelled else {
                self.telemetryNotificationTask = nil
                return
            }
            guard let pending = self.pendingTelemetryNotification else {
                self.telemetryNotificationTask = nil
                return
            }
            self.pendingTelemetryNotification = nil
            NotificationCenter.default.post(
                name: Self.telemetryDidChange,
                object: self,
                userInfo: ["telemetry": pending]
            )
            self.telemetryNotificationTask = nil
        }
    }

    private func updateWheelSpeedConsistency(at date: Date) {
        let current = telemetryEngine.snapshot
        wheelSpeedConsistency = wheelSpeedTracker.update(
            rear: current.dashboardSpeedKmh,
            front: current.frontWheelSpeedKmh,
            at: date
        )
    }

    private func recordBatteryObservation(
        voltage: Double,
        engineStatus: Int,
        source: PTVehicleTelemetrySource,
        at date: Date
    ) {
        guard source.isVerifiedReal,
              voltage.isFinite,
              (6...20).contains(voltage) else { return }
        batteryObservations.append(
            PTBatteryObservation(
                voltage: voltage,
                engineStatus: engineStatus,
                source: source,
                capturedAt: date
            )
        )
        if batteryObservations.count > 120 {
            batteryObservations.removeFirst(batteryObservations.count - 120)
        }
        batteryHealthSummary = PTBatteryHealthAnalyzer.summarize(
            observations: batteryObservations,
            capturedAt: date
        )

        // EN: Persist at most once per minute and only after the real dashboard is bound to a vehicle.
        // ES: Guarda como máximo una vez por minuto y solo después de asociar el tablero real a un vehículo.
        // 中文：最多每分钟保存一次，并且只有真实仪表已绑定车辆后才写入每日摘要。
        guard let vehicleID = dashboardGarageVehicleID else { return }
        let changedVehicle = batteryHistoryVehicleID != vehicleID
        let enoughTimePassed = date.timeIntervalSince(batteryHistoryLastRecordedAt ?? .distantPast) >= 60
        guard changedVehicle || enoughTimePassed else { return }
        if PTBatteryHealthHistoryStore.shared.record(
            summary: batteryHealthSummary,
            for: vehicleID,
            at: date
        ) {
            batteryHistoryLastRecordedAt = date
            batteryHistoryVehicleID = vehicleID
        }
    }

    private func evaluateTurnSignalReminder(_ control: PTDashboardControl, at date: Date) {
        guard snapshot.dashboard.state == .connected else { return }
        let speed = control.vehicleSpeedAvailability.isAvailable ? control.vehicleSpeedKmh : nil
        guard turnSignalReminderTracker.update(
            isActive: control.isLeftTurnOn || control.isRightTurnOn,
            isHazard: control.isHazardOn,
            speedKmh: speed,
            source: dashboardTelemetrySource,
            at: date
        ) else {
            return
        }

        let suffix = dashboardGarageVehicleID?.uuidString ?? "dashboard"
        let request = PTNotificationRequest(
            kind: .diagnostic,
            title: PTDashboardConfig.languageFunc(text: "notification_turn_signal_title"),
            body: PTDashboardConfig.languageFunc(text: "notification_turn_signal_body"),
            identifier: "pt.notification.safety.turn-signal",
            deduplicationKey: "turn-signal-\(suffix)",
            cooldown: 30 * 60,
            interruptionLevel: .timeSensitive,
            categoryIdentifier: PTNotificationCenter.diagnosticCategoryIdentifier,
            userInfo: ["pt_notification_kind": PTAppNotificationKind.diagnostic.rawValue]
        )
        PTNotificationCenter.schedule(request)
    }

    private func evaluateABSWarning(_ status: PTAbsStatus, at date: Date) {
        guard snapshot.dashboard.state == .connected,
              status.statusAvailability.isAvailable,
              let speedSample = telemetryEngine.snapshot.dashboardSpeedKmh,
              speedSample.source.isVerifiedReal,
              speedSample.isFresh(at: date, maximumAge: 2) else {
            absWarningTracker.reset()
            return
        }

        guard absWarningTracker.update(
            isAbnormal: status.isAbsLightOn,
            speedKmh: speedSample.value,
            source: speedSample.source,
            at: date
        ) else {
            return
        }

        let suffix = dashboardGarageVehicleID?.uuidString ?? "dashboard"
        let request = PTNotificationRequest(
            kind: .diagnostic,
            title: PTDashboardConfig.languageFunc(text: "notification_abs_title"),
            body: PTDashboardConfig.languageFunc(text: "notification_abs_body"),
            identifier: "pt.notification.safety.abs",
            deduplicationKey: "abs-\(suffix)",
            cooldown: 30 * 60,
            interruptionLevel: .timeSensitive,
            categoryIdentifier: PTNotificationCenter.diagnosticCategoryIdentifier,
            userInfo: ["pt_notification_kind": PTAppNotificationKind.diagnostic.rawValue]
        )
        PTNotificationCenter.schedule(request)
    }

    // EN: Reset derived safety state whenever the dashboard session ends; persisted daily summaries remain intact.
    // ES: Reinicia el estado de seguridad derivado al terminar la sesión; los resúmenes diarios guardados permanecen.
    // 中文：仪表会话结束时重置派生安全状态，但保留已经保存的每日摘要。
    private func resetDashboardDerivedState() {
        batteryObservations.removeAll(keepingCapacity: true)
        batteryHealthSummary = PTBatteryHealthSummary()
        batteryHistoryLastRecordedAt = nil
        batteryHistoryVehicleID = nil
        turnSignalReminderTracker.reset()
        absWarningTracker.reset()
    }

    // EN: Decode only the already-published dashboard value types; no BLE parsing is duplicated here.
    // ES: Decodifica solo los tipos de valores ya publicados por el tablero; aquí no se duplica el análisis BLE.
    // 中文：这里只消费仪表已经发布的值类型，不重复实现 BLE 解析。
    private func ingestDashboardTelemetry(_ data: Any?, at date: Date) -> PTVehicleDashboardSample? {
        let source = dashboardTelemetrySource
        var garageSample: PTVehicleDashboardSample?
        var didUpdate = false

        if let data1 = data as? PTDashboardData1 {
            if data1.fuelLevelAvailability.isAvailable {
                telemetryEngine.updateFuel(data1.fuelLevelPct, source: source, at: date)
                didUpdate = true
            }
            if data1.tripAvailability.isAvailable {
                telemetryEngine.updateTrip(data1.tripKm, source: source, at: date)
                didUpdate = true
            }
            if data1.odometerAvailability.isAvailable {
                telemetryEngine.updateOdometer(data1.odoKm, source: source, at: date)
                garageSample = .odometer(data1.odoKm)
                didUpdate = true
            }
        } else if let data2 = data as? PTDashboardData2 {
            if data2.engineAvailability.isAvailable {
                telemetryEngine.updateEngineStatus(data2.engineStatus, source: source, at: date)
                telemetryEngine.updateKickstand(data2.isKickstandDown, source: source, at: date)
                didUpdate = true
            }
            if data2.batteryAvailability.isAvailable {
                telemetryEngine.updateBatteryVoltage(data2.batteryVolt, source: source, at: date)
                recordBatteryObservation(
                    voltage: data2.batteryVolt,
                    engineStatus: data2.engineStatus,
                    source: source,
                    at: date
                )
                didUpdate = true
            }
            if data2.maintenanceAvailability.isAvailable {
                telemetryEngine.updateMaintenanceFlag(data2.maintenance, source: source, at: date)
                garageSample = .maintenanceFlag(data2.maintenance)
                didUpdate = true
            }
        } else if let data3 = data as? PTDashboardData3 {
            if data3.autonomyAvailability.isAvailable {
                telemetryEngine.updateRange(data3.autonomyKm, source: source, at: date)
                didUpdate = true
            }
            if data3.maintenanceDistanceAvailability.isAvailable {
                telemetryEngine.updateMaintenanceDistance(
                    data3.distToMaintenance,
                    source: source,
                    at: date
                )
                garageSample = .maintenanceDistance(data3.distToMaintenance)
                didUpdate = true
            }
        } else if let control = data as? PTDashboardControl {
            if control.vehicleSpeedAvailability.isAvailable {
                telemetryEngine.updateDashboardSpeed(
                    control.vehicleSpeedKmh,
                    source: source,
                    at: date
                )
                didUpdate = true
            }
            if control.engineRpmAvailability.isAvailable {
                telemetryEngine.updateRPM(control.engineRpm, source: source, at: date)
                didUpdate = true
            }
            telemetryEngine.updateIndicators(
                left: control.isLeftTurnOn,
                right: control.isRightTurnOn,
                hazard: control.isHazardOn,
                source: source,
                at: date
            )
            evaluateTurnSignalReminder(control, at: date)
            updateWheelSpeedConsistency(at: date)
            didUpdate = true
        } else if let absStatus = data as? PTAbsStatus {
            if absStatus.frontWheelSpeedAvailability.isAvailable {
                telemetryEngine.updateFrontWheelSpeed(
                    absStatus.frontWheelSpeedKmh,
                    source: source,
                    at: date
                )
                didUpdate = true
            }
            if absStatus.statusAvailability.isAvailable {
                telemetryEngine.updateABS(lightOn: absStatus.isAbsLightOn, source: source, at: date)
                evaluateABSWarning(absStatus, at: date)
                didUpdate = true
            }
            updateWheelSpeedConsistency(at: date)
        }

        if didUpdate {
            publishTelemetryChange()
        }
        return garageSample
    }

    private func receiveOBDMeasurements(_ measurements: [String: Any]) {
        guard snapshot.obd.state == .connecting || snapshot.obd.state == .connected else {
            return
        }
        let source = obdTelemetrySource
        let now = Date()
        var didUpdate = false

        if let speed = Self.doubleValue(
            measurements[OBDCommand.mode1(.speed).properties.command]
        ) {
            telemetryEngine.updateOBDSpeed(speed, source: source, at: now)
            didUpdate = true
        }
        if let rpm = Self.doubleValue(
            measurements[OBDCommand.mode1(.rpm).properties.command]
        ) {
            telemetryEngine.updateRPM(Int(rpm.rounded()), source: source, at: now)
            didUpdate = true
        }
        if didUpdate {
            publishTelemetryChange()
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    // English: Start and finish passive evidence with the existing link state; ATMA remains a separate developer action.
    // Español: Inicia y finaliza la evidencia pasiva con el estado existente; ATMA sigue siendo una acción de desarrollador separada.
    // 中文：让被动证据跟随现有连接状态启停，ATMA 继续保持独立的开发者操作。
    private func syncProtocolCaptureLifecycle(for next: PTVehicleSnapshot) {
        switch next.dashboard.state {
        case .connecting, .connected:
            let transport = next.dashboard.transport?.rawValue ?? "dashboardBluetooth"
            let source: PTProtocolDiscoverySource = next.dashboard.transport == .dashboardMock ? .mock : .real
            let vehicleID = dashboardGarageVehicleID ?? PTMotorcycleGarageStore.shared.selectedVehicleID
            enqueueProtocolCaptureOperation {
                await PTProtocolDiscoveryRecorder.shared.startDashboardSession(
                    transport: transport,
                    source: source,
                    vehicleID: vehicleID
                )
            }
        case .disconnected, .failed:
            enqueueProtocolCaptureOperation {
                await PTProtocolDiscoveryRecorder.shared.finishDashboardSession(
                    reason: next.dashboard.errorMessage ?? next.dashboard.state.rawValue
                )
            }
        case .idle:
            break
        }

        switch next.obd.state {
        case .connecting, .connected:
            let transport = next.obd.transport?.rawValue ?? "obd"
            let source: PTProtocolDiscoverySource = next.obd.transport == .obdMock ? .mock : .real
            let vehicleID = PTMotorcycleGarageStore.shared.selectedVehicleID
            enqueueProtocolCaptureOperation {
                await PTProtocolDiscoveryRecorder.shared.startOBDSession(
                    transport: transport,
                    source: source,
                    vehicleID: vehicleID
                )
            }
        case .disconnected, .failed:
            enqueueProtocolCaptureOperation {
                await PTProtocolDiscoveryRecorder.shared.finishOBDSession(
                    reason: next.obd.errorMessage ?? next.obd.state.rawValue
                )
            }
        case .idle:
            break
        }
    }

    // EN: Serialize lifecycle commands so a fast connect/disconnect cannot finish a session before it starts.
    // ES: Serializa los comandos de ciclo de vida para que una conexión/desconexión rápida no cierre antes de iniciar.
    // 中文：串行化生命周期命令，避免快速连接/断开时出现先结束后开始的会话竞态。
    private func enqueueProtocolCaptureOperation(
        _ operation: @escaping @Sendable () async -> Void
    ) {
        let previous = protocolCaptureLifecycleTask
        protocolCaptureLifecycleTask = Task { @MainActor in
            _ = await previous?.result
            guard !Task.isCancelled else { return }
            await operation()
        }
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
        batteryHistoryLastRecordedAt = nil
        batteryHistoryVehicleID = nil

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

    // EN: Reconcile the frozen peripheral on foreground without creating a second connection engine.
    // ES: Reconcilia el periférico congelado al volver al foreground sin crear otro motor de conexión.
    // 中文：回到前台时重新校正冻结的外设，但不创建第二套连接引擎。
    private func reconcileDashboardBLEAfterForeground() {
        PTXP400BLEReliabilityMonitor.shared.record(
            .foregroundReconciled,
            token: dashboardBLESessionToken,
            detail: dashboardBLEConnectionIntent ? "connection intent active" : "no connection intent"
        )
        PTBluetoothServerManager.shared.reconcilePeripheralLifecycle()

        guard dashboardBLEConnectionIntent,
              snapshot.dashboard.state == .connecting,
              !dashboardAttemptInFlight else {
            return
        }
        _ = connectDashboardIfNeeded()
    }

    // EN: A new token is created before every real or mock attempt; no delayed task may cross this boundary.
    // ES: Se crea un token nuevo antes de cada intento real o simulado; ninguna tarea retrasada puede cruzar este límite.
    // 中文：每次真实或模拟连接尝试前都创建新 Token，任何延迟任务都不能跨越这个边界。
    private func beginDashboardBLESession() -> PTXP400BLESessionToken {
        _ = PTXP400BLEReliabilityMonitor.shared.endSession(
            dashboardBLESessionToken,
            kind: .sessionFailed,
            detail: "superseded by a new attempt"
        )
        let token = dashboardBLESessionToken.next()
        dashboardBLESessionToken = token
        PTXP400BLEReliabilityMonitor.shared.beginSession(token)
        return token
    }

    private func finishDashboardBLESession(
        kind: PTXP400BLEReliabilityEventKind,
        detail: String
    ) {
        _ = PTXP400BLEReliabilityMonitor.shared.endSession(
            dashboardBLESessionToken,
            kind: kind,
            detail: detail
        )
    }

    private func invalidateDashboardBLESession() {
        dashboardBLESessionToken = dashboardBLESessionToken.next()
    }

    private func startDashboardWatchdog(for token: PTXP400BLESessionToken) {
        dashboardBLEWatchdog.arm(
            .centralSubscription,
            handler: { [weak self] phase in
                guard let self else { return }
                guard self.dashboardAttemptInFlight,
                      self.dashboardBLESessionToken == token else {
                    PTXP400BLEReliabilityMonitor.shared.record(
                        .staleCallbackIgnored,
                        token: token,
                        detail: "phase watchdog callback"
                    )
                    return
                }

                PTXP400BLEReliabilityMonitor.shared.record(
                    .phaseTimeout,
                    token: token,
                    detail: phase.rawValue
                )
                self.dashboardAttemptInFlight = false
                self.dashboardBLEConnectionIntent = false
                self.finishDashboardBLESession(
                    kind: .sessionFailed,
                    detail: "timeout: \(phase.rawValue)"
                )
                self.invalidateDashboardBLESession()
                PTBluetoothServerManager.shared.stopAdvertising()
                self.transitionDashboardBLE(.timeout(phase))
                self.finalizeDashboardDisconnect(transport: self.snapshot.dashboard.transport ?? .dashboardBluetooth)
                self.telemetryEngine.clearDashboard()
                self.wheelSpeedTracker = PTWheelSpeedConsistencyTracker()
                self.wheelSpeedConsistency = PTWheelSpeedConsistencyResult(state: .unavailable)
                self.resetDashboardDerivedState()
                self.updateDashboardState(.failed, errorMessage: "Dashboard connection timed out")
                self.transitionDashboardBLE(.failure(.timeout(phase)))
                self.publishTelemetryChange()
            }
        )
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
        if isConnected {
            if snapshot.dashboard.state == .connected {
                return
            }

            // EN: An expected reconnect may arrive without a new button tap after Bluetooth or ignition recovery.
            // ES: Una reconexión esperada puede llegar sin otro toque después de recuperar Bluetooth o el encendido.
            // 中文：蓝牙或点火恢复后，预期的重连可能在没有再次点击按钮时到达。
            guard dashboardAttemptInFlight || dashboardBLEConnectionIntent else {
                PTXP400BLEReliabilityMonitor.shared.record(
                    .staleCallbackIgnored,
                    token: dashboardBLESessionToken,
                    detail: "positive callback without connection intent"
                )
                PTOBDLogger.moto.ptLog("⚠️ [仪表生命周期] 忽略无连接意图的成功回调")
                return
            }

            if !dashboardAttemptInFlight {
                let token = beginDashboardBLESession()
                PTXP400BLEReliabilityMonitor.shared.record(
                    .automaticReconnect,
                    token: token,
                    detail: "stable peripheral callback"
                )
            }

            dashboardAttemptInFlight = false
            dashboardBLEWatchdog.cancel()
            PTXP400BLEReliabilityMonitor.shared.markReady(dashboardBLESessionToken)
            markDashboardBLEReady()
            updateDashboardState(
                .connected,
                transport: snapshot.dashboard.transport ?? .dashboardBluetooth
            )
            beginDashboardGarageSession()
        } else {
            let wasExpected = dashboardAttemptInFlight
                || snapshot.dashboard.state == .connecting
                || snapshot.dashboard.state == .connected
            guard wasExpected else {
                // EN: A late negative callback must not overwrite a terminal timeout or an explicit disconnect.
                // ES: Un callback negativo tardío no debe sobrescribir un timeout terminal ni una desconexión explícita.
                // 中文：延迟到达的断开回调不能覆盖最终超时状态或用户主动断开状态。
                PTXP400BLEReliabilityMonitor.shared.record(
                    .staleCallbackIgnored,
                    token: dashboardBLESessionToken,
                    detail: "negative callback after terminal state"
                )
                return
            }
            finishDashboardBLESession(
                kind: .sessionDisconnected,
                detail: "dashboard connection callback"
            )
            dashboardAttemptInFlight = false
            dashboardBLEWatchdog.cancel()
            invalidateDashboardBLESession()
            transitionDashboardBLE(.disconnectRequested)
            finalizeDashboardDisconnect(
                transport: snapshot.dashboard.transport ?? .dashboardBluetooth
            )
            telemetryEngine.clearDashboard()
            wheelSpeedTracker = PTWheelSpeedConsistencyTracker()
            wheelSpeedConsistency = PTWheelSpeedConsistencyResult(state: .unavailable)
            resetDashboardDerivedState()
            publishTelemetryChange()
        }
    }

    // EN: One transition owns disconnect side effects, so manual and delegate paths cannot double-save or skip the final snapshot.
    // ES: Una sola transición posee los efectos de desconexión, evitando duplicar o saltar el guardado final entre la acción manual y el delegado.
    // 中文：所有断开路径共用一次状态转换，避免手动操作与代理回调重复保存或漏掉最终快照。
    private func finalizeDashboardDisconnect(transport: PTVehicleTransport) {
        let wasConnected = snapshot.dashboard.state == .connected
        transitionDashboardBLE(.disconnectRequested)
        endDashboardGarageSession()
        resetDashboardDerivedState()
        updateDashboardState(.disconnected, transport: transport)
        transitionDashboardBLE(.disconnected)

        // EN: Only a real connected-to-disconnected transition may save parking and finalize the widget snapshot.
        // ES: Solo una transición real de conectado a desconectado puede guardar el estacionamiento y cerrar el snapshot del widget.
        // 中文：只有真实的“已连接→已断开”转换才能保存停车点并完成 Widget 快照。
        if wasConnected, transport == .dashboardBluetooth {
            PTLocationEngine.shared.forceUpdateWidgetOnDisconnect()
            PTMOTOParkingManager.shared.saveCurrentLocationAsParkingSpot()
        }
    }

    // EN: The stable manager reports one final authenticated callback, so the projection advances through the observed phases atomically.
    // ES: El gestor estable informa un único callback autenticado final, por lo que la proyección avanza por las fases observadas de forma atómica.
    // 中文：稳定管理器只回调最终的认证成功事件，因此状态投影一次性经过已观察到的阶段。
    private func markDashboardBLEReady() {
        let observedEvents: [PTXP400BLELifecycleEvent] = [
            .serviceConfigurationStarted,
            .serviceConfigured,
            .advertisingStarted,
            .centralConnected,
            .subscriptionsWaiting,
            .subscriptionsReady,
            .authenticationStarted,
            .authenticationSucceeded
        ]
        observedEvents.forEach { transitionDashboardBLE($0) }
    }

    // EN: Every transition is value-based and published only when the explicit state changes.
    // ES: Cada transición se basa en valores y solo se publica cuando cambia el estado explícito.
    // 中文：每次转换都基于值比较，仅在显式状态变化时发布通知。
    private func transitionDashboardBLE(_ event: PTXP400BLELifecycleEvent) {
        let previous = dashboardBLELifecycle.state
        let next = dashboardBLELifecycle.handle(event)
        guard previous != next else { return }
        dashboardBLEState = next
        NotificationCenter.default.post(
            name: Self.dashboardBLEStateDidChange,
            object: self,
            userInfo: ["state": next]
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
        if !isConnected {
            invalidateOBDBusLease()
            telemetryEngine.clearOBD()
            publishTelemetryChange()
        }
    }

    // EN: Revoke OBD leases as soon as the link disappears; queued diagnostics must not cross connection generations.
    // ES: Revoca las concesiones OBD al desaparecer el enlace; ningún diagnóstico en cola cruza generaciones.
    // 中文：链路消失时立即撤销 OBD 租约，排队诊断不能跨越连接代次。
    private func invalidateOBDBusLease() {
        Task {
            await PTOBDCompatibilityGateway.shared.invalidateForDisconnect()
        }
    }
}

extension PTVehicleConnectivityCoordinator: PTBLEDashboardDelegate {
    nonisolated func dashboardManager(_ manager: PTBluetoothServerManager, didChangeConnectionState isConnected: Bool) {
        Task { @MainActor [weak self] in
            self?.receiveDashboardConnection(isConnected)
        }
    }

    nonisolated func dashboardManager(_ manager: PTBluetoothServerManager, dashboardData data: Any?) {
        Task { @MainActor [weak self] in
            self?.receiveDashboardData(data)
        }
    }

    // EN: Cast dashboard payloads only on the main actor, where availability metadata is isolated.
    // ES: Convierte los datos del tablero solo en el actor principal, donde está aislada la disponibilidad.
    // 中文：仅在主 actor 中转换仪表数据，因为可用性元数据属于主 actor 隔离状态。
    private func receiveDashboardData(_ data: Any?) {
        guard snapshot.dashboard.state == .connecting || snapshot.dashboard.state == .connected else {
            return
        }
        let sample = ingestDashboardTelemetry(data, at: Date())

        if let sample {
            receiveDashboardSample(sample)
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

    public nonisolated func telemetryManager(
        _ manager: PTMotoTelemetryManager,
        didUpdateMeasurements measurements: [String: Any]
    ) {
        Task { @MainActor [weak self] in
            self?.receiveOBDMeasurements(measurements)
        }
    }
}
