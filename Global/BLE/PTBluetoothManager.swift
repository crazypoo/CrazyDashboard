//
//  PTBluetoothManager.swift
//  CrazyDashboard
//
//  EN: Compatibility facade that preserves the established PTBluetoothServerManager API and owns only shared state.
//  ES: Fachada de compatibilidad que conserva la API establecida de PTBluetoothServerManager y posee solo el estado compartido.
//  中文：保留既有 PTBluetoothServerManager API 的兼容门面，只负责持有共享状态。
//

import UIKit
import CoreBluetooth
import PooTools
import UserNotifications

// EN: The facade keeps CoreBluetooth ownership while behavior is organized in focused extensions.
// ES: La fachada conserva la propiedad de CoreBluetooth mientras el comportamiento se organiza en extensiones enfocadas.
// 中文：门面继续拥有 CoreBluetooth，具体行为按职责拆分到不同扩展文件中。
class PTBluetoothServerManager: NSObject, CBPeripheralManagerDelegate {
    // EN: The coordinator owns the lifecycle reducer; this notification exposes only observed transport facts.
    // ES: El coordinador posee el reductor del ciclo de vida; esta notificación solo expone hechos observados del transporte.
    // 中文：生命周期归约器仍由协调器持有；此通知只暴露传输层实际观察到的事实。
    static let lifecycleEventDidObserve = Notification.Name("PTBluetoothServerManager.lifecycleEventDidObserve")

    // EN: Persist only explicit user intent and the stable restoration identifier.
    // ES: Persiste solo la intención explícita del usuario y el identificador estable de restauración.
    // 中文：只持久化用户明确的外设意图和稳定的恢复标识。
    static let advertisingIntentKey = "PTBluetoothServerManager.advertisingIntent"
    static let restorationIdentifier = "com.yd.PTSpeed.xp400.dashboard.peripheral"

    // EN: Peripheral infrastructure state is separate from a subscribed dashboard session.
    // ES: El estado de la infraestructura periférica está separado de la sesión suscrita del tablero.
    // 中文：外设基础设施状态与已订阅的仪表盘会话分离。
    enum PeripheralLifecycleState: String {
        case unavailable
        case idle
        case configuring
        case ready
        case advertising
    }

    static let shared = PTBluetoothServerManager()

    class WeakDelegateWrapper {
        weak var delegate: PTBLEDashboardDelegate?
        init(_ delegate: PTBLEDashboardDelegate) {
            self.delegate = delegate
        }
    }
    var delegates: [WeakDelegateWrapper] = []

    // EN: Developer probes retain their existing timers and public entry points.
    // ES: Las sondas de desarrollo conservan sus temporizadores y puntos de entrada públicos existentes.
    // 中文：开发者探针保留原有定时器和 public 入口。
    var diagnosticTimer: Timer?
    var currentProbeIndex: UInt8 = 0x00
    var fuzzTimer: Timer?
    var currentFuzzID: UInt8 = 0x00

    // EN: Keep TCS comparison state available to the frame-decoding extension.
    // ES: Mantiene disponible el estado de comparación TCS para la extensión de decodificación.
    // 中文：为帧解码扩展保留 TCS 比较状态。
    var currentFrontSpeed: Double = 0.0
    var currentRearSpeed: Double = 0.0
    var currentFrontSpeedAvailable = false
    var currentRearSpeedAvailable = false
    let slipThreshold: Double = 5.0

    // EN: Sentinel-aware TCS evaluation stays behaviorally identical to the established implementation.
    // ES: La evaluación TCS consciente de valores centinela conserva el comportamiento establecido.
    // 中文：识别哨兵值的 TCS 判断保持既有行为不变。
    func checkTCSIntervention() {
        guard currentFrontSpeedAvailable, currentRearSpeedAvailable else {
            return
        }
        let speedDelta = currentRearSpeed - currentFrontSpeed
        if speedDelta > slipThreshold {
            let logMsg = "⚠️ [TCS 预警] 检测到打滑物理条件！后轮: \(currentRearSpeed) | 前轮: \(currentFrontSpeed) | 差值: \(String(format: "%.2f", speedDelta)) km/h"
            PTOBDLogger.moto.ptLog(logMsg)
            delegates.forEach { $0.delegate?.dashboardManager(self, dashboardData: "1") }
        } else {
            delegates.forEach { $0.delegate?.dashboardManager(self, dashboardData: "0") }
        }
    }

    public internal(set) var latestData1: PTDashboardData1?
    public internal(set) var latestData2: PTDashboardData2?
    public internal(set) var latestData3: PTDashboardData3?
    public internal(set) var latestControl: PTDashboardControl?
    public internal(set) var latestAbsStatus: PTAbsStatus?

    // EN: Expose only the current dashboard identity; authentication and transport remain internal to the facade.
    // ES: Expone solo la identidad actual del tablero; la autenticación y el transporte permanecen internos a la fachada.
    // 中文：只暴露当前仪表身份，认证和传输继续保持在门面内部。
    public internal(set) var dashboardConnectionIdentity: PTDashboardConnectionIdentity?

    // EN: Keep CoreBluetooth identifiers tied to the tested protocol contract.
    // ES: Mantén los identificadores de CoreBluetooth vinculados al contrato de protocolo probado.
    // 中文：让 CoreBluetooth 标识符统一绑定到已经测试的协议契约。
    let TIO_SERVICE = CBUUID(string: PTXP400BLEProtocol.tioServiceUUID)
    let UART_RX = CBUUID(string: PTXP400BLEProtocol.uartRXUUID)
    let UART_TX = CBUUID(string: PTXP400BLEProtocol.uartTXUUID)
    let UART_RX_CREDITS = CBUUID(string: PTXP400BLEProtocol.uartRXCreditsUUID)
    let UART_TX_CREDITS = CBUUID(string: PTXP400BLEProtocol.uartTXCreditsUUID)

    var activeNotifications = [UInt32: PTAncsNotif]()

    var peripheralManager: CBPeripheralManager!
    let auth = PTXP400Authenticator()

    var txChar: CBMutableCharacteristic!
    var txCreditsChar: CBMutableCharacteristic!

    var authState: PTAuthState = .waitKeyId
    var bleState = PTXP400BLEState()
    var authenticated: Bool {
        get { bleState.isAuthenticated }
        set { bleState.isAuthenticated = newValue }
    }
    var isTioSubscribed: Bool {
        get { bleState.isTIOSubscribed }
        set { bleState.isTIOSubscribed = newValue }
    }
    var isCreditsSubscribed: Bool {
        get { bleState.isCreditsSubscribed }
        set { bleState.isCreditsSubscribed = newValue }
    }
    var localCredits: Int { bleState.localCredits }
    var connectedCentral: CBCentral?
    var creditController = PTXP400TIOCreditController()
    var sendCredits: Int { creditController.sendCredits }
    var dashboardSession = PTXP400BLESession()

    // EN: Keep reassembly at the UART ingress boundary; field decoding remains in its dedicated extension.
    // ES: Mantén el reensamblado en el límite de entrada UART; la decodificación queda en su extensión dedicada.
    // 中文：仅在 UART 入站边界进行重组，字段解码放在专用扩展中。
    var inboundReassembler = PTXP400BLEInboundReassembler()

    // EN: Restore only peripheral infrastructure and the user's explicit advertising intent.
    // ES: Restaura solo la infraestructura periférica y la intención explícita de publicidad del usuario.
    // 中文：只恢复外设基础设施和用户明确的广播意图。
    var peripheralLifecycleState: PeripheralLifecycleState = .idle
    var shouldAdvertise = UserDefaults.standard.bool(forKey: PTBluetoothServerManager.advertisingIntentKey)
    var serviceAddInFlight = false
    var serviceConfigured = false
    var dashboardService: CBMutableService?

    // EN: Coalescing state is shared with navigation commands but does not alter frame encoding.
    // ES: El estado de combinación se comparte con los comandos de navegación, pero no altera la codificación de tramas.
    // 中文：合并状态供导航指令使用，但不改变帧编码。
    typealias PTNavigationFingerprint = PTXP400NavigationFingerprint
    struct PendingNavigation {
        let frame: Data
        let fingerprint: PTNavigationFingerprint
    }
    var navigationScheduler = PTXP400NavigationScheduler(minimumSendInterval: 0.5)
    var pendingNavigation: PendingNavigation?
    var pendingNavigationFlushWorkItem: DispatchWorkItem?

    typealias PTNotifyJob = PTXP400TIOSendQueue.Job
    let sendQueue = PTXP400TIOSendQueue()
    var isSending = false

    override init() {
        super.init()
        PTOBDLogger.moto.ptLog("🛠️ [DEBUG] 初始化基站 (移除所有多余扫描干扰)")
        // EN: Let iOS restore the peripheral service graph after process termination.
        // ES: Permite que iOS restaure el grafo de servicios del periférico después de terminar el proceso.
        // 中文：让 iOS 在进程被终止后恢复外设服务图。
        peripheralManager = CBPeripheralManager(
            delegate: self,
            queue: nil,
            options: [CBPeripheralManagerOptionRestoreIdentifierKey: Self.restorationIdentifier]
        )
    }

    // EN: Rebind restored GATT objects without restoring authentication or sending stale data.
    // ES: Vuelve a enlazar los objetos GATT restaurados sin restaurar autenticación ni enviar datos obsoletos.
    // 中文：重新绑定恢复的 GATT 对象，但不恢复认证，也不发送过期数据。
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        guard let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService],
              let service = services.first(where: { $0.uuid == TIO_SERVICE }) else {
            PTXP400BLEReliabilityMonitor.shared.record(
                .restorationUnavailable,
                detail: "no restored FEFB service"
            )
            PTOBDLogger.moto.ptLog("ℹ️ [基站恢复] 没有可恢复的 FEFB 服务，等待正常初始化")
            return
        }

        guard let restoredTX = service.characteristics?.first(where: { $0.uuid == UART_TX }) as? CBMutableCharacteristic,
              let restoredCredits = service.characteristics?.first(where: { $0.uuid == UART_TX_CREDITS }) as? CBMutableCharacteristic else {
            PTXP400BLEReliabilityMonitor.shared.record(
                .restorationUnavailable,
                detail: "restored FEFB service is missing TX or credits characteristic"
            )
            PTOBDLogger.moto.ptLog("⚠️ [基站恢复] FEFB 服务缺少必要特征，保持未配置状态，避免后续发送崩溃")
            dashboardService = nil
            serviceAddInFlight = false
            serviceConfigured = false
            txChar = nil
            txCreditsChar = nil
            return
        }

        dashboardService = service
        serviceAddInFlight = false
        serviceConfigured = true
        txChar = restoredTX
        txCreditsChar = restoredCredits
        peripheralLifecycleState = .ready
        PTOBDLogger.moto.ptLog("✅ [基站恢复] 已恢复 FEFB GATT 服务；认证状态将重新从初始阶段开始")

        if shouldAdvertise, peripheral.state == .poweredOn {
            startAdvertisingIfPossible()
        }
    }
}
