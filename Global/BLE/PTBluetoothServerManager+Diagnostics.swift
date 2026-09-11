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
        guard authenticated else {
            PTOBDLogger.moto.ptLog("⚠️ [查询拦截] 尚未完成认证，无法发送诊断探针。")
            return
        }
        
        PTOBDLogger.moto.ptLog("🚀 [深度探测] 开始发送 ISO-TP 增强版主动查询指令 (OBD/UDS 模式)...")
        currentProbeIndex = 0x00
        
        // 每 1.2 秒发送一次探针，给车机留出处理和回传的时间
        diagnosticTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 🚨 升级点：遵守 ISO-TP 传输层单帧格式 (Single Frame)
            // UDS 规范中，PID 通常是两字节的 (例如 0xF1 0x90)
            // 格式：[有效载荷长度, 服务ID, PID高位, PID低位]
            
            let udsLength: UInt8 = 0x03
            let serviceID: UInt8 = 0x22 // 读取数据服务 (Read Data By Identifier)
            let pidHighByte: UInt8 = 0x00 // 大多车辆标准 PID 从 0x0000 到 0xFFFF
            let pidLowByte: UInt8 = self.currentProbeIndex
            
            // 组合成标准 UDS 载荷
            let payload: [UInt8] = [udsLength, serviceID, pidHighByte, pidLowByte]
            let payloadData = Data(payload)
            
            // 复用你已有的常量 ID_CONFIGURATION (0x07) 作为诊断通道
            let targetID = PTFrameBuilder.ID_CONFIGURATION
            let frame = PTFrameBuilder.wrapTxFrame(idFrame: targetID, payload: payloadData)
            
            // 使用现有的分包发送方法将探针压入蓝牙通道
            self.sendChunkedData(data: frame, to: self.txChar) {
                let hexStr = payload.map { String(format: "%02X", $0) }.joined(separator: " ")
                PTOBDLogger.moto.ptLog("📡 [ISO-TP 探针发射] 通道 ID: 0x\(String(format: "%02X", targetID)), 载荷: [ \(hexStr) ]")
            }
            
            // 扫描结束条件
            if self.currentProbeIndex == 0xFF {
                self.stopActiveDiagnosticScan()
            } else {
                // 使用溢出运算符，防止边界崩溃
                self.currentProbeIndex &+= 1
            }
        }
    }
    
    /// 停止主动诊断扫描
    public func stopActiveDiagnosticScan() {
        diagnosticTimer?.invalidate()
        diagnosticTimer = nil
        PTOBDLogger.moto.ptLog("🛑 [深度探测] 主动查询扫描已手动结束或完成全频段覆盖。")
    }

    public func requestStaticConfiguration() {
        guard authenticated else {
            PTOBDLogger.moto.ptLog("⚠️ [查询拦截] 尚未完成认证，无法发送查询请求。")
            return
        }
        
        // 策略 1：针对已知的配置通道 (ID: 7)，发送 0x00 载荷，触发底层 Read 逻辑
        let readPayload = Data([0x00])
        
        // 利用你封装好的通用封包器
        let requestFrame = PTFrameBuilder.wrapTxFrame(idFrame: 7, payload: readPayload)
        
        sendChunkedData(data: requestFrame, to: txChar) {
            PTOBDLogger.moto.ptLog("📡 [主动查询] 已向配置通道发射探针，请紧盯回传日志...")
        }
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
            PTOBDLogger.moto.ptLog("⚠️ [解析拦截] 包头不匹配或长度不足")
            return
        }

        let id = decodedFrame.id

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
            let averageDescription = averageAvailability.isAvailable ? "\(avg)L" : "-"
            let odometerDescription = odometerAvailability.isAvailable ? "\(odo)km" : "-"
            PTOBDLogger.moto.ptLog("📊 [DATA1] 油量: \(fuelDescription), 消耗: \(averageDescription), 总里程: \(odometerDescription)")
            
        case PTXP400BLEProtocol.data2FrameID: // DATA2
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "[已知] ID:3 (DATA2) -> \(hexString)") })
            guard bytes.count >= 6 else { return }
            
            // 🚨 深度嗅探：提取被忽略的 bytes[0], bytes[2]，以及如果存在的更靠后的字节
            var hiddenBits = "b[2]:\(bytes[2].binaryString)"
            if bytes.count >= 9 { // 根据你提供的数据，DATA2 实际有 9 个 payload 字节
                hiddenBits += " | b[6]:\(bytes[6].binaryString) | b[7]:\(bytes[7].binaryString) | b[8]:\(bytes[8].binaryString)"
            }
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "🔬 [未知] DATA2 隐藏位: \(hiddenBits)") })

            let engineRawByte = bytes[1]
            let engineAvailability: PTDashboardValueAvailability = engineRawByte == 0xFF ? .unavailable : .available
            let engineRaw = Int(engineRawByte)
            // 通过 rawValue 安全地转换为枚举对象，如果匹配失败则回退到 .unknown
            let backlightModeRaw = UInt8((engineRaw & 0xC0) >> 6)
            let currentBacklightMode = engineAvailability.isAvailable
                ? (PTBacklightMode(rawValue: backlightModeRaw) ?? .unknown)
                : .unknown

            let batteryDisplayState = engineAvailability.isAvailable ? (engineRaw & 0x0C) >> 2 : 0
            // 提取最低 2 位获取引擎状态 (0:未启动, 1:启动中, 2:运转中, 3:关闭中)
            let engineStatus = engineAvailability.isAvailable ? engineRaw & 0x03 : 0

            let isKickstandDown = engineAvailability.isAvailable && (engineRaw & 0x30) != 0
            
            let engineTempC = 0

            let engine = Int(bytes[1])
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
                backlightMode: currentBacklightMode,
                engineTempC: engineTempC,
                isKickstandDown: isKickstandDown,
                batteryDisplayState: batteryDisplayState,
                rawPayload: payload,
                engineAvailability: engineAvailability,
                maintenanceAvailability: maintenanceAvailability,
                outsideTemperatureAvailability: outsideTemperatureAvailability,
                batteryAvailability: batteryAvailability
            )
            self.latestData2 = data2
            delegates.forEach( { $0.delegate?.dashboardManager(self, dashboardData: data2) })
            let engineDescription = engineAvailability.isAvailable
                ? PTDashboardLabels.engineStatusLabel(raw: engine)
                : "-"
            let batteryDescription = batteryAvailability.isAvailable ? "\(batt)V" : "-"
            PTOBDLogger.moto.ptLog("🔋 [DATA2] 引擎: \(engineDescription), 电压: \(batteryDescription)")
            
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
            let autonomyDescription = autonomyAvailability.isAvailable ? "\(Double(autoRaw) * 0.1)km" : "-"
            PTOBDLogger.moto.ptLog("🛣️ [DATA3] 剩余续航: \(autonomyDescription)")
            
        case PTXP400BLEProtocol.controlFrameID: // CONTROL
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "[已知] ID:5 (CONTROL) -> \(hexString)") })
            guard bytes.count >= 8 else { return }
                        
            let tcsRaw = bytes[3] & 0x0F // 提取低 4 位
            let isTcsSystemReady = (tcsRaw & 0b10000000) != 0 // 提取最高位作为系统就绪标志
            let currentTCS: PTTCSMode
            switch tcsRaw {
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
                rawPayload: payload,
                vehicleSpeedAvailability: vehicleSpeedAvailability,
                engineRpmAvailability: engineRpmAvailability
            )
            self.latestControl = control
            delegates.forEach( { $0.delegate?.dashboardManager(self, dashboardData: control) })
            let speedDescription = vehicleSpeedAvailability.isAvailable ? "\(rearSpeed) km/h" : "-"
            let rpmDescription = engineRpmAvailability.isAvailable ? "\(Int(Double(engineRaw) * 0.25)) rpm" : "-"
            PTOBDLogger.moto.ptLog("🏍️ [CONTROL] 车速: \(speedDescription), 转速: \(rpmDescription)")
            
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
                        
            let byte1 = bytes[1]
            // 如果结果为 0 (即 00000000)，说明灯是亮起的
            let statusAvailability: PTDashboardValueAvailability = bytes[2] == 0xFF ? .unavailable : .available
            let isAbsLightOn = statusAvailability.isAvailable && (byte1 & 0b00010000) == 0

            let absStatus = PTAbsStatus(
                absRaw: statusAvailability.isAvailable ? Int(bytes[2]) : 0,
                isAbsLightOn: isAbsLightOn,
                frontWheelSpeedKmh: frontSpeed,
                rawPayload: payload,
                frontWheelSpeedAvailability: frontWheelSpeedAvailability,
                statusAvailability: statusAvailability
            )
            self.latestAbsStatus = absStatus
            delegates.forEach( { $0.delegate?.dashboardManager(self, dashboardData: absStatus) })
            PTOBDLogger.moto.ptLog("🛑 [ABS] 状态: \(PTDashboardLabels.absLabel(raw: Int(bytes[2])))")
            
        default:
            let binaryMatrix = bytes.map { $0.binaryString }.joined(separator: " | ")
            delegates.forEach( { $0.delegate?.dashboardManager(self, unknownData: "⚠️ [深挖] 捕获未知 ID 0x\(String(format: "%02X", id)) -> 二进制: [ \(binaryMatrix) ]") })
            PTOBDLogger.moto.ptLog("❓ [未知数据] ID: 0x\(String(format: "%02X", id)) -> \(binaryMatrix)")
        }
    }
}

