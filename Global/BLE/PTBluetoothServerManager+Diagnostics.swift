//
//  PTBluetoothServerManager+Diagnostics.swift
//  CrazyDashboard
//
//  EN: Owns active diagnostic probes and dashboard frame semantic decoding without duplicating the transport.
//  ES: Posee las sondas de diagnóstico activas y la decodificación semántica de tramas sin duplicar el transporte.
//  中文：负责主动诊断探针和仪表盘帧语义解码，不复制传输层。
//
import UIKit
import CoreBluetooth
import PooTools
import UserNotifications

extension PTBluetoothServerManager {
    /// 启动全频段主动查询扫描
    /// 向配置通道 (ID: 7) 发送轮询请求，试图触发车机回传隐藏的物理数据
    public func startActiveDiagnosticScan() {
        // EN: Build 69 downgrades ID 7 probing to passive research until a repeatable vehicle trace proves its meaning.
        // ES: Build 69 degrada la sonda del ID 7 a investigación pasiva hasta que una captura repetible pruebe su significado.
        // 中文：Build 69 将 ID 7 探测降级为被动研究，直到可重复实车抓包证明其语义。
        stopActiveDiagnosticScan()
        PTOBDLogger.moto.ptLog("🧪 [Build 69] ID 7 主动探测已禁用：请使用官方设置 A/B 与被动抓包建立证据。")
    }
    
    /// 停止主动诊断扫描
    public func stopActiveDiagnosticScan() {
        diagnosticTimer?.invalidate()
        diagnosticTimer = nil
        PTOBDLogger.moto.ptLog("🛑 [深度探测] 主动查询扫描已手动结束或完成全频段覆盖。")
    }

    public func requestStaticConfiguration() {
        // EN: Do not treat an accepted ID 7 packet as confirmed configuration semantics.
        // ES: No trates un paquete aceptado por ID 7 como semántica de configuración confirmada.
        // 中文：不能因为 ID 7 接受数据包，就把它当作已确认的配置语义。
        PTOBDLogger.moto.ptLog("🧪 [Build 69] ID 7 配置请求暂不发送，等待被动证据。")
    }

    // MARK: - 解析摩托车回传状态
    /// 解析摩托车仪表盘的实时状态帧
    func parseDashboardFrame(_ value: Data) {
        let hexString = value.map { String(format: "%02hhx", $0) }.joined()
        PTOBDLogger.moto.ptLog("📦 [原始包] 收到帧数据: \(hexString)")
        
        // EN: Validate the envelope once in the decoder boundary before reading any payload byte.
        // ES: Valida la envoltura una vez en el límite del decodificador antes de leer la carga.
        // 中文：在读取任何 Payload 字节前，先由解码边界统一校验帧包络。
        guard let decodedFrame = PTXP400TelemetryDecoder.decode(value) else {
            PTDashboardProtocolDiagnostics.shared.record(
                frameID: value.count > 1 ? value[1] : 0,
                rawData: value,
                payload: Data(),
                decodedSummary: "INVALID envelope length=\(value.count)",
                protocolDebug: "frame rejected before semantic decoding"
            )
            PTOBDLogger.moto.ptLog("⚠️ [解析拦截] 包头不匹配或长度不足")
            return
        }

        let id = decodedFrame.id

        // EN: Enqueue semantic evidence after envelope validation; the stable BLE parser remains the source of business state.
        // ES: Encola evidencia semántica después de validar la envoltura; el analizador BLE estable sigue siendo la fuente del estado de negocio.
        // 中文：包络校验后异步入队语义证据，稳定 BLE 解析器仍然是业务状态的唯一来源。
        let evidenceTimestamp = Date()
        let evidenceMonotonicNanoseconds = DispatchTime.now().uptimeNanoseconds
        Task {
            guard let result = await PTBuild69ProtocolEvidenceCoordinator.shared.ingestBLEFrame(
                value,
                timestamp: evidenceTimestamp,
                monotonicNanoseconds: evidenceMonotonicNanoseconds
            ) else { return }
            await MainActor.run {
                _ = PTBuild69EvidenceStore.shared.merge(result)
                _ = PTProtocolEvidenceV2Store.shared.merge(
                    PTBuild69EvidenceRecordFactory.records(from: result, source: .live)
                )
            }
        }

        // EN: Enforce the confirmed wire length for known inbound frames without changing unknown-frame diagnostics.
        // ES: Aplica la longitud de cable confirmada para las tramas entrantes conocidas sin cambiar el diagnóstico de tramas desconocidas.
        // 中文：对已知入站帧执行已确认的线协议长度校验，同时保留未知帧的诊断行为。
        switch id {
        case PTXP400BLEProtocol.connectionFrameID:
            guard value.count == PTXP400BLEProtocol.connectionFrameLength else {
                PTOBDLogger.moto.ptLog("⚠️ [解析拦截] Connection Frame 长度无效: \(value.count)，期待 \(PTXP400BLEProtocol.connectionFrameLength)")
                return
            }
        case PTXP400BLEProtocol.data1FrameID...PTXP400BLEProtocol.absFrameID:
            guard value.count == PTXP400BLEProtocol.vehicleStatusFrameLength else {
                PTOBDLogger.moto.ptLog("⚠️ [解析拦截] 车辆状态帧长度无效: ID=0x\(String(format: "%02X", id))，实际 \(value.count)，期待 \(PTXP400BLEProtocol.vehicleStatusFrameLength)")
                return
            }
        default:
            break
        }
        
        // EN: The existing semantic decoder receives exactly the bytes between ID and terminator.
        // ES: El decodificador semántico existente recibe exactamente los bytes entre el ID y el terminador.
        // 中文：现有语义解码器只接收 ID 与结束字节之间的 Payload。
        let payload = decodedFrame.payload
        let bytes = [UInt8](payload)
        
        switch id {
        case PTXP400BLEProtocol.connectionFrameID:
            PTDashboardProtocolDiagnostics.shared.resetSession()
            if let asciiString = String(bytes: bytes, encoding: .ascii) {
                dashboardConnectionIdentity = PTDashboardConnectionIdentity(
                    centralIdentifier: connectedCentral?.identifier,
                    reportedSerialNumber: asciiString
                )
                delegates.forEach {
                    $0.delegate?.dashboardManager(
                        self,
                        didUpdateConnectionIdentity: dashboardConnectionIdentity
                    )
                }
            }
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "[已知] ID:1 (心跳/连接) -> \(hexString)") })
            if let asciiString = String(bytes: bytes, encoding: .ascii) {
                PTOBDLogger.moto.ptLog("🔗 [状态] 车机报告连接正常 (CONNECTION) | 设备序列号: \(asciiString)")
            } else {
                PTOBDLogger.moto.ptLog("🔗 [状态] 车机报告连接正常 (CONNECTION)")
            }
            PTDashboardProtocolDiagnostics.shared.record(
                frameID: id,
                rawData: value,
                payload: payload,
                decodedSummary: "CONNECTION serial=\(String(bytes: bytes, encoding: .ascii) ?? "-")"
            )
        case PTXP400BLEProtocol.data1FrameID: // DATA1
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "[已知] ID:2 (DATA1) -> \(hexString)") })
            guard bytes.count >= 8 else { return }
            
            let hiddenBits = "b[1]:\(bytes[1].binaryString)"
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "🔬 [未知] DATA1 隐藏位: \(hiddenBits)") })
            
            // EN: Keep sentinel bytes unchanged in rawPayload and never expose their converted values as real readings.
            // ES: Conserva los bytes centinela en rawPayload y nunca expone sus conversiones como lecturas reales.
            // 中文：在 rawPayload 中保留哨兵字节，不把哨兵换算结果当成真实读数。
            let fuelRaw = bytes[0]
            let fuelAvailability: PTDashboardValueAvailability = fuelRaw == 0xFF ? .unavailable : .available
            let fuel = fuelAvailability.isAvailable
                ? min(max(Int(round(Double(fuelRaw) * 0.3937)), 0), 100)
                : 0
            let averageRaw = bytes[2]
            let averageAvailability: PTDashboardValueAvailability = averageRaw == 0xFF ? .unavailable : .available
            let avg = averageAvailability.isAvailable ? Double(averageRaw) * 0.1 : 0
            let tripRaw = (UInt16(bytes[3]) << 8) | UInt16(bytes[4])
            let tripAvailability: PTDashboardValueAvailability = tripRaw == UInt16.max ? .unavailable : .available
            let trip = tripAvailability.isAvailable ? Double(tripRaw) * 0.1 : 0
            let odoRaw = (UInt32(bytes[5]) << 16) | (UInt32(bytes[6]) << 8) | UInt32(bytes[7])
            let odometerAvailability: PTDashboardValueAvailability = odoRaw == 0xFF_FFFF ? .unavailable : .available
            let odo = odometerAvailability.isAvailable ? Double(odoRaw) * 0.1 : 0
            let data1 = PTDashboardData1(
                tripKm: trip,
                odoKm: odo,
                fuelLevelPct: fuel,
                avgConsumptionLt: avg,
                rawPayload: payload,
                fuelLevelAvailability: fuelAvailability,
                averageConsumptionAvailability: averageAvailability,
                tripAvailability: tripAvailability,
                odometerAvailability: odometerAvailability
            )
            self.latestData1 = data1
            delegates.forEach( { $0.delegate?.dashboardManager(self, dashboardData: data1) })
            let fuelDescription = fuelAvailability.isAvailable ? "\(fuel)%" : "-"
            let formattedAverage = averageAvailability.isAvailable ? String(format: "%.1f", avg) : "-"
            let formattedOdometer = odometerAvailability.isAvailable ? String(format: "%.1f", odo) : "-"
            let data1Summary = "DATA1 油量: \(fuelDescription), 消耗: \(formattedAverage)L, 总里程: \(formattedOdometer)km"
            PTDashboardProtocolDiagnostics.shared.record(
                frameID: id,
                rawData: value,
                payload: payload,
                decodedSummary: data1Summary,
                protocolDebug: "payload=\(payload.map { String(format: "%02X", $0) }.joined(separator: " "))"
            )
            
        case PTXP400BLEProtocol.data2FrameID: // DATA2
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "[已知] ID:3 (DATA2) -> \(hexString)") })
            guard bytes.count >= 6 else { return }

            // EN: Data2 bytes 0...2 are the confirmed dashboard RTC; their remaining low bits stay raw.
            // ES: Los bytes 0...2 de Data2 forman el RTC confirmado; sus bits bajos restantes quedan en bruto.
            // 中文：Data2 的 bytes 0…2 是已确认的仪表 RTC，其余低位只保留原始值。
            let byte0 = bytes[0]
            let byte1 = bytes[1]
            let byte2 = bytes[2]
            let clockCandidate = PTDashboardClock(
                hour: byte2 >> 3,
                minute: byte1 >> 2,
                second: byte0 >> 2
            )
            let dashboardClock = clockCandidate.isValid ? clockCandidate : nil
            let engineAvailability: PTDashboardValueAvailability = byte1 == 0xFF ? .unavailable : .available
            let engineStatus = engineAvailability.isAvailable ? Int(byte1 & 0x03) : 0
            let rawByte0LowBits = byte0 & 0x03
            let rawByte2LowBits = byte2 & 0x07
            let engineTempC = 0

            let maintenanceRaw = bytes[3]
            let maintenanceAvailability: PTDashboardValueAvailability = maintenanceRaw == 0xFF ? .unavailable : .available
            let maint = maintenanceAvailability.isAvailable ? Int(maintenanceRaw) : 0
            let outsideTemperatureRaw = bytes[4]
            let outsideTemperatureAvailability: PTDashboardValueAvailability = outsideTemperatureRaw == 0xFF ? .unavailable : .available
            let temp = outsideTemperatureAvailability.isAvailable ? Int(outsideTemperatureRaw) - 50 : 0
            let batteryRaw = bytes[5]
            let batteryAvailability: PTDashboardValueAvailability = batteryRaw == 0xFF ? .unavailable : .available
            let batt = batteryAvailability.isAvailable ? Double(batteryRaw) * 0.1 : 0
            let data2 = PTDashboardData2(
                batteryVolt: batt,
                outsideTempC: temp,
                engineStatus: engineStatus,
                maintenance: maint,
                engineTempC: engineTempC,
                clock: dashboardClock,
                rawByte0LowBits: rawByte0LowBits,
                rawByte2LowBits: rawByte2LowBits,
                backlightMode: nil,
                isKickstandDown: nil,
                batteryDisplayState: nil,
                rawPayload: payload,
                engineAvailability: engineAvailability,
                maintenanceAvailability: maintenanceAvailability,
                outsideTemperatureAvailability: outsideTemperatureAvailability,
                batteryAvailability: batteryAvailability
            )
            self.latestData2 = data2
            delegates.forEach( { $0.delegate?.dashboardManager(self, dashboardData: data2) })
            let engineDescription = engineAvailability.isAvailable
                ? PTDashboardLabels.engineStatusLabel(raw: engineStatus)
                : "-"
            let clockDescription = dashboardClock?.displayString ?? "-"
            let batteryDescription = batteryAvailability.isAvailable ? "\(String(format: "%.1f", batt))V" : "-"
            let data2Summary = "DATA2 RTC: \(clockDescription), 引擎: \(engineDescription), 电压: \(batteryDescription)"
            let data2Debug = "B0=0x\(String(format: "%02X", byte0))/\(byte0.binaryString) B1=0x\(String(format: "%02X", byte1))/\(byte1.binaryString) B2=0x\(String(format: "%02X", byte2))/\(byte2.binaryString) | low2(B0)=0b\(rawByte0LowBits.binaryString(paddedTo: 2)) | low3(B2)=0b\(rawByte2LowBits.binaryString(paddedTo: 3)) | Backlight/Kickstand/BatteryDisplay=unresolved"
            delegates.forEach {
                $0.delegate?.dashboardManager(self, unknownData: "🔬 [PROTOCOL DEBUG] \(data2Summary) | \(data2Debug)")
            }
            PTDashboardProtocolDiagnostics.shared.record(
                frameID: id,
                rawData: value,
                payload: payload,
                decodedSummary: data2Summary,
                protocolDebug: data2Debug
            )
            
        case PTXP400BLEProtocol.data3FrameID: // DATA3
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "[已知] ID:4 (DATA3) -> \(hexString)") })
            guard bytes.count >= 6 else { return }
            if bytes.count >= 8 {
                let hiddenBits = "b[6]:\(bytes[6].binaryString) | b[7]:\(bytes[7].binaryString)"
                delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "🔬 [未知] DATA3 隐藏位: \(hiddenBits)") })
            }

            let autoRaw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            let autonomyAvailability: PTDashboardValueAvailability = autoRaw == UInt16.max ? .unavailable : .available
            let col = Int(bytes[2])
            let distRaw = (UInt16(bytes[3]) << 8) | UInt16(bytes[4])
            let maintenanceDistanceAvailability: PTDashboardValueAvailability = distRaw == UInt16.max ? .unavailable : .available
            let dist = maintenanceDistanceAvailability.isAvailable ? Int(distRaw) : 0
            let lang = Int(bytes[5])
            let configurationAvailability: PTDashboardValueAvailability = bytes[2] == 0xFF ? .unavailable : .available
            let languageAvailability: PTDashboardValueAvailability = bytes[5] == 0xFF ? .unavailable : .available
            let data3 = PTDashboardData3(
                autonomyKm: autonomyAvailability.isAvailable ? Double(autoRaw) * 0.1 : 0,
                distToMaintenance: dist,
                colorMeasur: col,
                language: lang,
                rawPayload: payload,
                autonomyAvailability: autonomyAvailability,
                maintenanceDistanceAvailability: maintenanceDistanceAvailability,
                configurationAvailability: configurationAvailability,
                languageAvailability: languageAvailability
            )
            self.latestData3 = data3
            delegates.forEach( { $0.delegate?.dashboardManager(self, dashboardData: data3) })
            let autonomyDescription = autonomyAvailability.isAvailable ? "\(String(format: "%.1f", Double(autoRaw) * 0.1))km" : "-"
            PTDashboardProtocolDiagnostics.shared.record(
                frameID: id,
                rawData: value,
                payload: payload,
                decodedSummary: "DATA3 剩余续航: \(autonomyDescription)",
                protocolDebug: "configuration=0x\(String(format: "%02X", col)) language=0x\(String(format: "%02X", lang))"
            )
            
        case PTXP400BLEProtocol.controlFrameID: // CONTROL
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "[已知] ID:5 (CONTROL) -> \(hexString)") })
            guard bytes.count >= 8 else { return }

            // EN: Read TCS mode from the low nibble and readiness from the complete control byte.
            // ES: Lee el modo TCS del nibble bajo y la disponibilidad desde el byte de control completo.
            // 中文：从低半字节读取 TCS 模式，从完整控制字节读取系统就绪位。
            let rollingCounterRaw = bytes[0]
            let controlFlagsRaw = bytes[3]
            let tcsModeRaw = controlFlagsRaw & 0x0F
            let isTcsSystemReady = (controlFlagsRaw & 0x80) != 0
            let currentTCS: PTTCSMode
            switch tcsModeRaw {
            case 0x02: currentTCS = .mode1
            case 0x04: currentTCS = .mode2
            case 0x00: currentTCS = .off
            default: currentTCS = .unknown
            }

            let byte1 = bytes[1]
            let isLeftTurnOn = (byte1 & 0b00010000) != 0
            let isRightTurnOn = (byte1 & 0b01000000) != 0

            let byte2 = bytes[2]
                        
            // 提取近光灯 (Bit 6)
            let isLowBeamOn = (byte2 & 0b01000000) != 0
            
            // 提取远光灯 (Bit 4)
            let isHighBeamOn = (byte2 & 0b00010000) != 0
            
            let isHazardAuxBitOn = (byte2 & 0b00000001) != 0
            let isHazardOn = isLeftTurnOn && isRightTurnOn && isHazardAuxBitOn

            let vehicleRaw = (UInt16(bytes[6]) << 8) | UInt16(bytes[7])
            let vehicleSpeedAvailability: PTDashboardValueAvailability = vehicleRaw == UInt16.max ? .unavailable : .available
            let rearSpeed = vehicleSpeedAvailability.isAvailable ? Double(vehicleRaw) * 0.01 : 0

            self.currentRearSpeed = rearSpeed
            self.currentRearSpeedAvailable = vehicleSpeedAvailability.isAvailable
            self.checkTCSIntervention()

            let engineRaw = (UInt16(bytes[4]) << 8) | UInt16(bytes[5])
            let engineRpmAvailability: PTDashboardValueAvailability = engineRaw == UInt16.max ? .unavailable : .available
            let control = PTDashboardControl(
                vehicleSpeedKmh: rearSpeed,
                engineRpm: engineRpmAvailability.isAvailable ? Int(Double(engineRaw) * 0.25) : 0,
                tcsMode: currentTCS,
                isLowBeamOn: isLowBeamOn,
                isHighBeamOn: isHighBeamOn,
                isLeftTurnOn: isLeftTurnOn,
                isRightTurnOn: isRightTurnOn,
                isHazardOn: isHazardOn,
                isTcsSystemReady: isTcsSystemReady,
                tcsModeRaw: tcsModeRaw,
                controlFlagsRaw: controlFlagsRaw,
                rollingCounterRaw: rollingCounterRaw,
                rawPayload: payload,
                vehicleSpeedAvailability: vehicleSpeedAvailability,
                engineRpmAvailability: engineRpmAvailability
            )
            self.latestControl = control
            delegates.forEach( { $0.delegate?.dashboardManager(self, dashboardData: control) })
            let speedDescription = vehicleSpeedAvailability.isAvailable ? "\(String(format: "%.1f", rearSpeed)) km/h" : "-"
            let rpmDescription = engineRpmAvailability.isAvailable ? "\(Int(Double(engineRaw) * 0.25)) rpm" : "-"
            let controlSummary = "CONTROL 车速: \(speedDescription), 转速: \(rpmDescription)"
            let controlDebug = "counter=0x\(String(format: "%02X", rollingCounterRaw)) flags=0x\(String(format: "%02X", controlFlagsRaw))/\(controlFlagsRaw.binaryString) tcsModeRaw=0x\(String(format: "%02X", tcsModeRaw)) ready=\(isTcsSystemReady)"
            delegates.forEach {
                $0.delegate?.dashboardManager(self, unknownData: "🔬 [PROTOCOL DEBUG] \(controlSummary) | \(controlDebug)")
            }
            PTDashboardProtocolDiagnostics.shared.record(
                frameID: id,
                rawData: value,
                payload: payload,
                decodedSummary: controlSummary,
                rollingCounter: rollingCounterRaw,
                protocolDebug: controlDebug
            )
            
        case PTXP400BLEProtocol.absFrameID: // ABS
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "[已知] ID:6 (ABS) -> \(hexString)") })
            guard bytes.count >= 3 else { return }
            
            // 🚨 新挖掘：提取前轮独立车速 (Byte 0 和 Byte 1)
            let frontSpeedRaw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            let frontWheelSpeedAvailability: PTDashboardValueAvailability = frontSpeedRaw == UInt16.max ? .unavailable : .available
            let frontSpeed = frontWheelSpeedAvailability.isAvailable ? Double(frontSpeedRaw) * 0.01 : 0

            // 更新本实例的前轮车速，并触发 TCS 打滑检测
            self.currentFrontSpeed = frontSpeed
            self.currentFrontSpeedAvailable = frontWheelSpeedAvailability.isAvailable
            self.checkTCSIntervention()
                        
            let statusAvailability: PTDashboardValueAvailability = bytes[2] == 0xFF ? .unavailable : .available
            let absWarningState: PTABSWarningState = .unknown

            let absStatus = PTAbsStatus(
                absRaw: statusAvailability.isAvailable ? Int(bytes[2]) : 0,
                frontWheelSpeedKmh: frontSpeed,
                rawByte0: bytes[0],
                rawByte1: bytes[1],
                rawByte2: bytes[2],
                absWarningState: absWarningState,
                rawPayload: payload,
                frontWheelSpeedAvailability: frontWheelSpeedAvailability,
                statusAvailability: statusAvailability
            )
            self.latestAbsStatus = absStatus
            delegates.forEach( { $0.delegate?.dashboardManager(self, dashboardData: absStatus) })
            let absStatusDescription = statusAvailability.isAvailable
                ? PTDashboardLabels.absLabel(raw: Int(bytes[2]))
                : "-"
            let absSummary = "ABS 前轮轮速: \(String(format: "%.1f", frontSpeed)) km/h, 状态: \(absStatusDescription)"
            // EN: Compare the two wheel-speed readings for diagnostics only; never gate or replace business telemetry here.
            // ES: Compara las dos velocidades de rueda solo para diagnóstico; nunca bloquea ni sustituye la telemetría de negocio.
            // 中文：这里只为诊断比较前后轮速，绝不在此处限制或替换业务遥测。
            let wheelSpeedConsistency: String
            if currentRearSpeedAvailable && currentFrontSpeedAvailable {
                let speedDelta = currentRearSpeed - currentFrontSpeed
                wheelSpeedConsistency = "wheelDelta=\(String(format: "%.2f", speedDelta)) km/h"
            } else {
                wheelSpeedConsistency = "wheelDelta=unavailable"
            }
            let absDebug = "B0=0x\(String(format: "%02X", bytes[0])) B1=0x\(String(format: "%02X", bytes[1])) B2=0x\(String(format: "%02X", bytes[2])) warning=unknown | \(wheelSpeedConsistency)"
            delegates.forEach {
                $0.delegate?.dashboardManager(self, unknownData: "🔬 [PROTOCOL DEBUG] \(absSummary) | \(absDebug)")
            }
            PTDashboardProtocolDiagnostics.shared.record(
                frameID: id,
                rawData: value,
                payload: payload,
                decodedSummary: absSummary,
                protocolDebug: absDebug
            )
            
        default:
            let binaryMatrix = bytes.map { $0.binaryString }.joined(separator: " | ")
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "⚠️ [深挖] 捕获未知 ID 0x\(String(format: "%02X", id)) -> 二进制: [ \(binaryMatrix) ]") })
            PTDashboardProtocolDiagnostics.shared.record(
                frameID: id,
                rawData: value,
                payload: payload,
                decodedSummary: "UNKNOWN ID=0x\(String(format: "%02X", id))",
                protocolDebug: "binary=\(binaryMatrix)"
            )
        }
    }
}
