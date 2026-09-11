//
//  PTBluetoothServerManager+Transport.swift
//  CrazyDashboard
//
//  EN: Owns CoreBluetooth lifecycle, authentication ingress, credits, backpressure, and ordered transmission.
//  ES: Posee el ciclo de vida de CoreBluetooth, la entrada de autenticación, los créditos, la contrapresión y la transmisión ordenada.
//  中文：负责 CoreBluetooth 生命周期、认证入口、Credits、背压和有序发送。
//
import UIKit
import CoreBluetooth
import PooTools
import UserNotifications

extension PTBluetoothServerManager {
    // MARK: - 启动基站
    func startBaseStationAndScan() {
        // EN: Starting is an idempotent request; didUpdateState or didAdd will perform the next safe step.
        // ES: El inicio es una solicitud idempotente; didUpdateState o didAdd ejecutará el siguiente paso seguro.
        // 中文：启动只是幂等请求，后续安全步骤由 didUpdateState 或 didAdd 执行。
        observeLifecycle(.startRequested)
        shouldAdvertise = true
        UserDefaults.standard.set(true, forKey: Self.advertisingIntentKey)
        reconcilePeripheralLifecycle()
    }

    // EN: Reconcile the requested peripheral state after foreground transitions or external Bluetooth changes.
    // ES: Reconciliamos el estado solicitado del periférico después del foreground o de cambios externos de Bluetooth.
    // 中文：在回到前台或蓝牙状态外部变化后，重新校正用户请求的外设状态。
    func reconcilePeripheralLifecycle() {
        guard shouldAdvertise else {
            if peripheralManager.isAdvertising {
                peripheralManager.stopAdvertising()
            }
            if peripheralLifecycleState == .advertising {
                peripheralLifecycleState = serviceConfigured ? .ready : .idle
            }
            return
        }

        guard peripheralManager.state == .poweredOn else {
            observeLifecycle(.bluetoothUnavailable)
            peripheralLifecycleState = .unavailable
            PTOBDLogger.moto.ptLog("⏸️ [基站生命周期] 等待蓝牙可用，当前状态: \(peripheralManager.state.rawValue)")
            return
        }

        startAdvertisingIfPossible()
    }

    // EN: Stop only advertising; an existing subscribed central is not forcefully disconnected by this lifecycle API.
    // ES: Detén solo la publicidad; esta API no desconecta forzosamente a un central ya suscrito.
    // 中文：该生命周期接口只停止广播，不强制断开已经订阅的中心设备。
    public func stopAdvertising() {
        shouldAdvertise = false
        UserDefaults.standard.set(false, forKey: Self.advertisingIntentKey)
        peripheralManager.stopAdvertising()
        peripheralLifecycleState = serviceConfigured ? .ready : .idle
        PTOBDLogger.moto.ptLog("⏹️ [基站生命周期] 已停止广播，服务保留以便下次幂等启动")
    }

    // EN: Start advertising only after the FEFB service is registered and the peripheral is powered on.
    // ES: Inicia la publicidad solo después de registrar el servicio FEFB y confirmar que el periférico está encendido.
    // 中文：只有 FEFB 服务注册完成且蓝牙外设处于开启状态后，才开始广播。
    func startAdvertisingIfPossible() {
        guard !peripheralManager.isAdvertising else {
            peripheralLifecycleState = .advertising
            observeLifecycle(.advertisingStarted)
            PTOBDLogger.moto.ptLog("⚠️ [基站生命周期] 广播已经存在，跳过重复启动")
            return
        }

        guard !serviceAddInFlight else {
            peripheralLifecycleState = .configuring
            PTOBDLogger.moto.ptLog("⏳ [基站生命周期] 服务正在添加，等待 didAdd 回调后广播")
            return
        }

        guard serviceConfigured, dashboardService != nil else {
            setupServices()
            return
        }

        // 🚨 核心修复延续：只广播服务，不带名字，保证 FEFB 绝对暴露给摩托车！
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [TIO_SERVICE]
        ])
        peripheralLifecycleState = .advertising
        observeLifecycle(.advertisingStarted)
        PTOBDLogger.moto.ptLog("📡 [基站生命周期] 已请求广播 FEFB 服务")
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        PTOBDLogger.moto.ptLog("🛠️ [DEBUG] 硬件状态: \(peripheral.state.rawValue)")

        guard peripheral.state == .poweredOn else {
            observeLifecycle(.bluetoothUnavailable)
            peripheral.stopAdvertising()
            peripheral.removeAllServices()
            serviceAddInFlight = false
            serviceConfigured = false
            dashboardService = nil
            txChar = nil
            txCreditsChar = nil
            peripheralLifecycleState = .unavailable
            resetDashboardSessionForPeripheralLoss()
            return
        }

        observeLifecycle(.bluetoothPoweredOn)
        peripheralLifecycleState = shouldAdvertise ? .ready : .idle
        if shouldAdvertise {
            startAdvertisingIfPossible()
        }
    }

    private func setupServices() {
        guard peripheralManager.state == .poweredOn else {
            peripheralLifecycleState = .unavailable
            return
        }

        guard !serviceConfigured, !serviceAddInFlight else {
            peripheralLifecycleState = serviceConfigured ? .ready : .configuring
            return
        }

        observeLifecycle(.serviceConfigurationStarted)

        let rxChar = CBMutableCharacteristic(
            type: UART_RX,
            properties: [.writeWithoutResponse],
            value: nil,
            permissions: [.writeEncryptionRequired]
        )
        
        // 🚨 核心修复 2：使用 notifyEncryptionRequired！
        // 强迫车机在订阅这一刻就弹出系统配对框，否则后续的 8758 会被 iOS 丢弃！
        txChar = CBMutableCharacteristic(
            type: UART_TX,
            properties: [.notifyEncryptionRequired], // 👈 最关键的一步
            value: nil,
            permissions: [.readEncryptionRequired]
        )
        
        let rxCreditsChar = CBMutableCharacteristic(
            type: UART_RX_CREDITS,
            properties: [.write],
            value: nil,
            permissions: [.writeEncryptionRequired]
        )
        
        // 🚨 核心修复 2 延续：使用 indicateEncryptionRequired
        txCreditsChar = CBMutableCharacteristic(
            type: UART_TX_CREDITS,
            properties: [.indicateEncryptionRequired], // 👈 最关键的一步
            value: nil,
            permissions: [.readEncryptionRequired]
        )

        let service = CBMutableService(type: TIO_SERVICE, primary: true)
        service.characteristics = [rxChar, txChar, rxCreditsChar, txCreditsChar]
        dashboardService = service
        serviceAddInFlight = true
        peripheralLifecycleState = .configuring
        peripheralManager.add(service)
                
        PTOBDLogger.moto.ptLog("🛠️ [基站生命周期] 服务注册请求已提交，等待 didAdd 回调")
    }

    // EN: Treat service registration completion as the only safe boundary before advertising.
    // ES: Trata la finalización del registro del servicio como el único límite seguro antes de publicitar.
    // 中文：把服务注册完成作为开始广播前唯一安全的边界。
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard service.uuid == TIO_SERVICE else { return }

        serviceAddInFlight = false
        if let error {
            serviceConfigured = false
            dashboardService = nil
            peripheralLifecycleState = .idle
            observeLifecycle(.failure(.serviceConfiguration))
            PTOBDLogger.moto.ptLog("❌ [基站生命周期] FEFB 服务添加失败: \(error.localizedDescription)")
            return
        }

        guard peripheral.state == .poweredOn else {
            serviceConfigured = false
            dashboardService = nil
            peripheralLifecycleState = .unavailable
            PTOBDLogger.moto.ptLog("⚠️ [基站生命周期] 服务添加完成时蓝牙已不可用，忽略本次服务")
            return
        }

        serviceConfigured = true
        peripheralLifecycleState = .ready
        observeLifecycle(.serviceConfigured)
        PTOBDLogger.moto.ptLog("✅ [基站生命周期] FEFB 服务添加完成")

        if shouldAdvertise {
            startAdvertisingIfPossible()
        }
    }

    // EN: Clear every session-owned resource so a later central cannot inherit stale work or credits.
    // ES: Limpia todos los recursos propios de la sesión para que otro central no herede trabajos ni créditos obsoletos.
    // 中文：清理全部会话资源，避免后续 Central 继承旧任务或旧额度。
    private func resetDashboardSession(notifyDelegates: Bool) {
        let hadSession = authenticated
            || isTioSubscribed
            || isCreditsSubscribed
            || connectedCentral != nil
            || dashboardSession.isActive
            || dashboardConnectionIdentity != nil
            || PTDashboardConfig.shared.blueConnected

        sendQueue.removeAll(keepingCapacity: false)
        creditController.reset()
        isSending = false
        activeNotifications.removeAll(keepingCapacity: false)
        pendingNavigationFlushWorkItem?.cancel()
        pendingNavigationFlushWorkItem = nil
        pendingNavigation = nil
        navigationScheduler.reset()
        currentFrontSpeed = 0
        currentRearSpeed = 0
        currentFrontSpeedAvailable = false
        currentRearSpeedAvailable = false
        authenticated = false
        isTioSubscribed = false
        isCreditsSubscribed = false
        authState = .waitKeyId
        inboundReassembler.reset()
        dashboardSession.end()
        connectedCentral = nil
        dashboardConnectionIdentity = nil

        guard notifyDelegates, hadSession else { return }

        PTOBDLogger.moto.stopFileLogging()
        PTDashboardConfig.shared.blueConnected = false
        delegates.forEach {
            $0.delegate?.dashboardManager(self, didChangeConnectionState: false)
            $0.delegate?.dashboardManager(self, didUpdateConnectionIdentity: nil)
        }
    }

    // EN: Bluetooth loss follows the same cleanup path as an explicit unsubscribe.
    // ES: La pérdida de Bluetooth usa la misma limpieza que una cancelación explícita de suscripción.
    // 中文：蓝牙不可用时与显式取消订阅共用同一套清理路径。
    private func resetDashboardSessionForPeripheralLoss() {
        resetDashboardSession(notifyDelegates: true)
    }

    // EN: Forward facts to the single lifecycle reducer without duplicating transport state here.
    // ES: Reenvía hechos al único reductor del ciclo de vida sin duplicar aquí el estado de transporte.
    // 中文：把事实转发给唯一的生命周期归约器，不在管理器内复制一套传输状态机。
    private func observeLifecycle(_ event: PTXP400BLELifecycleEvent) {
        delegates.forEach {
            $0.delegate?.dashboardManager(self, didObserveLifecycleEvent: event)
        }
        NotificationCenter.default.post(
            name: Self.lifecycleEventDidObserve,
            object: self,
            userInfo: ["event": event]
        )
    }
    
    // MARK: - 监听订阅
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        let identityChanged = connectedCentral?.identifier != central.identifier

        if identityChanged {
            // EN: Close the previous observed session before accepting a replacement central.
            // ES: Cierra la sesión observada anterior antes de aceptar un central de reemplazo.
            // 中文：接受新的 Central 之前，先结束上一个已观察到的会话。
            if connectedCentral != nil {
                observeLifecycle(.disconnectRequested)
                observeLifecycle(.disconnected)
            }
            // EN: A new central starts with an empty authenticated session and empty outbound state.
            // ES: Un central nuevo comienza con una sesión autenticada y un estado de salida vacíos.
            // 中文：新的 Central 必须从空认证会话和空发送状态开始。
            resetDashboardSession(notifyDelegates: true)
            _ = dashboardSession.begin(centralIdentifier: central.identifier)
        }

        connectedCentral = central
        dashboardConnectionIdentity = PTDashboardConnectionIdentity(centralIdentifier: central.identifier)
        if identityChanged {
            observeLifecycle(.centralConnected)
        }
        PTOBDLogger.moto.ptLog("⚡️ [雷达] 摩托车订阅成功: \(characteristic.uuid.uuidString)")

        if identityChanged {
            delegates.forEach {
                $0.delegate?.dashboardManager(self, didUpdateConnectionIdentity: dashboardConnectionIdentity)
            }
        }
        
        if characteristic.uuid == UART_TX { isTioSubscribed = true }
        if characteristic.uuid == UART_TX_CREDITS { isCreditsSubscribed = true }

        if isTioSubscribed && isCreditsSubscribed {
            PTOBDLogger.moto.ptLog("🔗 [状态] 通道订阅完毕！等待车机写入 8758...")
            observeLifecycle(.subscriptionsReady)
            authState = .waitKeyId
            authenticated = false
            inboundReassembler.reset()
        } else {
            observeLifecycle(.subscriptionsWaiting)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        PTOBDLogger.moto.ptLog("⚠️ [状态] 摩托车断开了通道")
        observeLifecycle(.disconnectRequested)
        resetDashboardSession(notifyDelegates: true)
        observeLifecycle(.disconnected)
    }
    
    // MARK: - 监听写入
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == UART_RX {
                guard let data = request.value else { continue }
                if authenticated && creditController.consumeLocalCredit() {
                    if localCredits <= PTXP400BLEProtocol.creditRefillThreshold { grantScooterCredits() }
                }
                receiveUARTData(data)
            } else if request.characteristic.uuid == UART_RX_CREDITS {
                // EN: Respond to every write-with-response credit request only after validation.
                // ES: Responde a cada solicitud de créditos con respuesta solo después de validarla.
                // 中文：只有 Credits 写入校验通过后，才响应每个需要回复的写请求。
                let result = acceptRemoteCredits(request.value)
                if request.characteristic.properties.contains(.write) {
                    peripheralManager.respond(to: request, withResult: result)
                }
            }
        }
    }

    // EN: Reject malformed, zero, oversized, and overflowing credit updates without touching session state.
    // ES: Rechaza actualizaciones de créditos malformadas, cero, grandes o desbordadas sin tocar el estado de sesión.
    // 中文：拒绝格式错误、零值、超大或会溢出的 Credits 更新，不改变当前会话状态。
    private func acceptRemoteCredits(_ data: Data?) -> CBATTError.Code {
        let result = creditController.acceptRemoteCredits(data)
        switch result {
        case .accepted(let amount):
            PTOBDLogger.moto.ptLog("🎟️ [流控通道] 收到 Credits: \(amount)，当前余额: \(sendCredits)")
            flushPendingNavigationIfPossible()
            pumpQueue()
            return .success
        case .missingValue:
            PTOBDLogger.moto.ptLog("⚠️ [流控通道] 拒绝空 Credits 写入")
            return .invalidAttributeValueLength
        case .invalidLength(let actual):
            PTOBDLogger.moto.ptLog("⚠️ [流控通道] 拒绝非法 Credits 写入，长度: \(actual)")
            return .invalidAttributeValueLength
        case .invalidAmount(let actual):
            PTOBDLogger.moto.ptLog("⚠️ [流控通道] 拒绝非法 Credits 数值: \(actual)")
            return .unlikelyError
        case .balanceOverflow(let current, let adding):
            PTOBDLogger.moto.ptLog("⚠️ [流控通道] 拒绝超过会话上限的 Credits 更新: \(current) + \(adding)")
            return .unlikelyError
        }
    }

    // EN: Map the established authentication state to the packet shape expected by the ingress assembler.
    // ES: Mapea el estado de autenticación establecido a la forma de paquete esperada por el ensamblador de entrada.
    // 中文：把既有认证状态映射为入站重组器所期待的数据包类型。
    private var currentInboundPhase: PTXP400BLEInboundPhase {
        if authenticated {
            return .vehicleStatus
        }

        switch authState {
        case .waitKeyId:
            return .keyConfiguration
        case .waitAuthMsg:
            return .authenticationResponse
        case .waitRandomNums:
            return .randomChallenge
        case .waitConnectionFrame:
            return .connectionFrame
        case .success:
            return .vehicleStatus
        }
    }

    // EN: Drain all complete logical packets from one or more BLE writes before waiting for more bytes.
    // ES: Vacía todos los paquetes lógicos completos de una o más escrituras BLE antes de esperar más bytes.
    // 中文：在等待更多字节前，排空一次或多次 BLE 写入中所有完整的逻辑数据包。
    private func receiveUARTData(_ data: Data) {
        inboundReassembler.append(data)

        while true {
            switch inboundReassembler.nextFrame(for: currentInboundPhase) {
            case .frame(let frame):
                handleIncoming(data: frame)
            case .dropped:
                PTOBDLogger.moto.ptLog("⚠️ [上行重组] 丢弃当前认证阶段无法匹配的数据，剩余缓存: \(inboundReassembler.bufferedByteCount) 字节")
            case .waiting:
                return
            }
        }
    }
    
    // MARK: - 身份验证状态机
    private func handleIncoming(data: Data) {
        if authenticated {
            PTOBDLogger.moto.ptLog("🔄 [DEBUG] 解析仪表盘数据包...")
            parseDashboardFrame(data)
            return
        }
        
        switch authState {
        case .waitKeyId:
            guard PTXP400BLEProtocol.isValidAuthenticationKeyConfiguration(data) else {
                PTOBDLogger.moto.ptLog("⚠️ [握手干扰] Key/Configuration 帧长度无效: \(data.count)")
                return
            }

            PTOBDLogger.moto.ptLog("✅ [握手 1/4] 收到 8758！下发挑战码...")
            observeLifecycle(.authenticationStarted)
            let challenge = auth.createChallenge()
            var challengeData = Data()
            for num in challenge {
                var beNum = num.bigEndian
                challengeData.append(Data(bytes: &beNum, count: 2))
            }
            sendChunkedData(data: challengeData, to: txChar)
            authState = .waitAuthMsg
            
        case .waitAuthMsg:
            guard PTXP400BLEProtocol.isValidAuthenticationChallenge(data) else {
                PTOBDLogger.moto.ptLog("⚠️ [握手干扰] 认证响应长度无效: \(data.count)")
                return
            }

            if auth.checkAuthMsg(scooterResponse: data) {
                PTOBDLogger.moto.ptLog("✅ [握手 2/4] 车机答题正确！发送 KeyID，等待车机出题...")
                sendChunkedData(data: auth.getScooterKeyId(), to: txChar)
                
                // 🚨 核心修复：握手还没完，进入下半场！
                authState = .waitRandomNums
            } else {
                PTOBDLogger.moto.ptLog("❌ [错误] 密码本校验失败")
            }
            
        case .waitRandomNums:
            // 🚨 核心修复：这就是你抓到的 27b21814... (车机的考题)
            guard PTXP400BLEProtocol.isValidAuthenticationChallenge(data) else {
                PTOBDLogger.moto.ptLog("⚠️ [握手干扰] 期待 20 字节挑战码，实际收到: \(data.count) 字节")
                return
            }

            PTOBDLogger.moto.ptLog("✅ [握手 3/4] 收到车机挑战码！正在计算答案并回复...")
            var r = [UInt16](repeating: 0, count: 10)
            for i in 0..<10 {
                let start = i * 2
                let byte0 = UInt16(data[start])
                let byte1 = UInt16(data[start + 1])
                r[i] = (byte0 << 8) | byte1
            }

            // EN: Calculate the response without changing the established authentication algorithm.
            // ES: Calcula la respuesta sin cambiar el algoritmo de autenticación establecido.
            // 中文：在不改变既有认证算法的前提下计算响应。
            let authMsg = auth.createAuthenticationMessage(r: r)
            sendChunkedData(data: authMsg, to: txChar)

            // 答完题，等待车机的 0x16 确认信
            authState = .waitConnectionFrame
            
        case .waitConnectionFrame:
            // EN: Accept authentication only after the exact 15-byte connection identity frame is validated.
            // ES: Acepta la autenticación solo después de validar la trama de identidad de conexión exacta de 15 bytes.
            // 中文：只有严格校验 15 字节连接身份帧后，才接受认证完成。
            if PTXP400BLEProtocol.connectionSerial(in: data) != nil {
                PTOBDLogger.moto.ptLog("🎉 [握手 4/4] 互信认证全部打通！蓝灯长亮！解锁数据通道！")
                
                authState = .success
                authenticated = true
                observeLifecycle(.authenticationSucceeded)
                PTMotoUserDefaultStruct.MotoLinkedAPP = true
                PTOBDLogger.moto.startFileLogging(prefix: "MotoHexLog", headerTitle: "PEUGEOT XP400GT RAW HEX LOG")
                // 必须在互信彻底完成后，再发钱解锁仪表盘！
                grantScooterCredits()
                
                delegates.forEach( { $0.delegate?.dashboardManager(self, didChangeConnectionState: true) })
                
                // 别浪费这第一包数据，立刻丢给仪表盘解析器
                parseDashboardFrame(data)
            } else {
                PTOBDLogger.moto.ptLog("⚠️ [握手干扰] 期待 0x16 确认帧，收到了其他数据")
            }
        case .success:
            break
        }

    }
    
    // MARK: - 发送逻辑 (队列保持不变)
    private func grantScooterCredits() {
        let refill = creditController.refillLocalCredits()
        if refill <= 0 { return }
        let data = Data([UInt8(refill)])
        sendChunkedData(data: data, to: txCreditsChar)
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        isSending = false
        flushPendingNavigationIfPossible()
        pumpQueue()
    }

    // EN: Flush the newest navigation frame only when credits and the minimum interval allow it.
    // ES: Envía la navegación más reciente solo cuando hay créditos y se cumple el intervalo mínimo.
    // 中文：只有 Credits 足够且满足最小间隔时，才发送最新导航帧。
    func flushPendingNavigationIfPossible() {
        guard authenticated,
              sendCredits > 0,
              let pendingNavigation else {
            return
        }

        if navigationScheduler.isDuplicate(pendingNavigation.fingerprint) {
            self.pendingNavigation = nil
            pendingNavigationFlushWorkItem?.cancel()
            pendingNavigationFlushWorkItem = nil
            return
        }

        let remaining = navigationScheduler.remainingDelay(at: Date())
        if remaining > 0 {
            schedulePendingNavigationFlush(after: remaining)
            return
        }

        self.pendingNavigation = nil
        pendingNavigationFlushWorkItem?.cancel()
        pendingNavigationFlushWorkItem = nil
        enqueueNavigationFrame(pendingNavigation.frame, fingerprint: pendingNavigation.fingerprint)
    }

    // EN: Replace a scheduled flush with one timer so frequent map callbacks cannot build work items.
    // ES: Reemplaza el envío programado con un solo temporizador para que los callbacks frecuentes no acumulen tareas.
    // 中文：始终只保留一个延迟任务，避免高频地图回调堆积任务。
    func schedulePendingNavigationFlush(after delay: TimeInterval) {
        guard pendingNavigation != nil else { return }

        pendingNavigationFlushWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingNavigationFlushWorkItem = nil
            self.flushPendingNavigationIfPossible()
        }
        pendingNavigationFlushWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(delay, 0),
            execute: workItem
        )
    }

    // EN: Remove only superseded navigation chunks and leave every other protocol job untouched.
    // ES: Elimina solo los fragmentos de navegación sustituidos y conserva los demás trabajos del protocolo.
    // 中文：只删除被替换的导航分片，其他协议任务保持不变。
    func removeQueuedNavigationJobs() {
        let wasBlockedNavigation = isSending
            && sendQueue.first.map { job in
                if case .navigation = job.kind { return true }
                return false
            } == true
        sendQueue.removeAll { job in
            if case .navigation = job.kind { return true }
            return false
        }
        if wasBlockedNavigation {
            isSending = false
        }
    }

    // EN: Record a navigation update at queue admission, then split it with the existing transport path.
    // ES: Registra la actualización al admitirla en la cola y después usa el transporte fragmentado existente.
    // 中文：导航进入队列时记录状态，然后继续复用现有分片发送路径。
    func enqueueNavigationFrame(_ frame: Data, fingerprint: PTNavigationFingerprint) {
        pendingNavigation = nil
        pendingNavigationFlushWorkItem?.cancel()
        pendingNavigationFlushWorkItem = nil
        removeQueuedNavigationJobs()
        navigationScheduler.recordSent(fingerprint)
        sendChunkedData(data: frame, to: txChar, kind: .navigation)
    }

    func sendChunkedData(
        data: Data,
        to characteristic: CBMutableCharacteristic,
        kind: PTNotifyJob.Kind = .regular,
        completion: (() -> Void)? = nil
    ) {
        var offset = 0
        let hexString = data.map { String(format: "%02hhx", $0) }.joined()
        PTOBDLogger.moto.ptLog("⬆️ [发送包] 正在发射指令: \(hexString)")
        // 🚨 优化：向订阅了该特征的中心设备查询它所支持的最大长度，如果没有则安全降级回默认值 20
        // 对于 WriteWithoutResponse 或 Notify，使用 .withoutResponse 类型的 MTU
        let maxChunkSize = PTXP400BLEProtocol.maxTIOChunkLength
                
        let totalChunks = Int(ceil(Double(data.count) / Double(maxChunkSize)))
        var currentChunk = 0

        while offset < data.count {
            let end = min(offset + maxChunkSize, data.count)
            currentChunk += 1
            let isLastChunk = (currentChunk == totalChunks)
            
            sendQueue.append(PTNotifyJob(
                data: data.subdata(in: offset..<end),
                characteristic: characteristic,
                kind: kind,
                completion: isLastChunk ? completion : nil
            ))
            offset = end
        }
        pumpQueue()
    }
    
    func pumpQueue() {
        guard !isSending, !sendQueue.isEmpty else { return }
        guard let job = sendQueue.first else { return }
        
        // 🚨 终极死锁破除器：如果当前没有车机订阅此通道，强制丢弃以防永久卡死
        if job.characteristic.uuid == UART_TX {
            // 如果余额不足，绝对不能发！挂起队列，等待车机通过 RX_CREDITS 补充令牌
            guard self.sendCredits > 0 else {
                return
            }
        }

        if !self.isTioSubscribed {
            let completedJob = sendQueue.removeFirst()
            if let callback = completedJob.completion {
                DispatchQueue.main.async { callback() }
            }
            DispatchQueue.main.async { self.pumpQueue() }
            return
        }
        
        // 下方代码保持你原来的逻辑不变
        let success = peripheralManager.updateValue(job.data, for: job.characteristic, onSubscribedCentrals: nil)
        
        if success {
            let completedJob = sendQueue.removeFirst()
            if completedJob.characteristic.uuid == UART_TX {
                _ = creditController.consumeRemoteCredit()
            }

            if let callback = completedJob.completion {
                DispatchQueue.main.async { callback() }
            }
            DispatchQueue.main.async { self.pumpQueue() }
        } else {
            isSending = true
        }
    }
}

