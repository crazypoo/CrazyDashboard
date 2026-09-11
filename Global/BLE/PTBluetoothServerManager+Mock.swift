//
//  PTBluetoothServerManager+Mock.swift
//  CrazyDashboard
//
//  EN: Provides the offline dashboard simulator without changing the real Bluetooth path.
//  ES: Proporciona el simulador de tablero sin cambiar la ruta Bluetooth real.
//  中文：提供离线仪表盘模拟器，不改变真实蓝牙路径。
//
import UIKit
import CoreBluetooth
import PooTools
import UserNotifications

extension PTBluetoothServerManager {
    
    // MARK: - 🎮 离线沙盒：仪表盘数据引擎 (Mock Dashboard Data Pump)
    
    /// 模拟机车的物理状态缓存
    private struct PTMockPhysicsState {
        static var timer: Timer?
        static var mockSpeed: Double = 0.0      // 模拟车速 (km/h)
        static var mockRPM: Double = 1200.0     // 模拟转速 (RPM)，默认怠速
        static var mockFuel: Double = 254.0     // 模拟油量原始值 (约等于 100%)
        static var isAccelerating = true        // 物理状态机：是否正在加速
    }
    
    /// 启动本地模拟数据泵 (完全脱离机车进行 UI 联调)
    func startMockDashboardData() {
        guard !authenticated else {
            PTOBDLogger.moto.ptLog("⚠️ 已连接真实设备，无法开启模拟器")
            return
        }
        
        PTOBDLogger.moto.ptLog("🎮 [模拟器] 正在启动仪表盘沙盒数据泵...")
        
        // 1. 强制击穿安全锁，伪造连接成功状态
        _ = dashboardSession.begin()
        self.authenticated = true
        PTMotoUserDefaultStruct.MotoLinkedAPP = true
        self.delegates.forEach({ $0.delegate?.dashboardManager(self, didChangeConnectionState: true) })
        
        // 2. 启动 10Hz (0.1秒) 的高频数据泵，实现 UI 丝滑刷新
        PTMockPhysicsState.timer?.invalidate()
        PTMockPhysicsState.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // --- 动态物理状态更新 ---
            if PTMockPhysicsState.isAccelerating {
                PTMockPhysicsState.mockSpeed += 1.2
                PTMockPhysicsState.mockRPM += 120.0
                if PTMockPhysicsState.mockSpeed > 135.0 { PTMockPhysicsState.isAccelerating = false } // 极速 135km/h
            } else {
                PTMockPhysicsState.mockSpeed -= 1.8
                PTMockPhysicsState.mockRPM -= 180.0
                if PTMockPhysicsState.mockSpeed <= 0 {
                    PTMockPhysicsState.mockSpeed = 0
                    PTMockPhysicsState.mockRPM = 1200.0 // 恢复怠速
                    PTMockPhysicsState.isAccelerating = true
                }
            }
            // 油量缓慢减少
            PTMockPhysicsState.mockFuel = max(0, PTMockPhysicsState.mockFuel - 0.05)
            
            // --- 组装并投递全套报文 ---
            self.parseDashboardFrame(self.buildMockFrame(id: 2, payload: self.mockData1()))
            self.parseDashboardFrame(self.buildMockFrame(id: 3, payload: self.mockData2()))
            self.parseDashboardFrame(self.buildMockFrame(id: 4, payload: self.mockData3()))
            self.parseDashboardFrame(self.buildMockFrame(id: 5, payload: self.mockControl()))
            self.parseDashboardFrame(self.buildMockFrame(id: 6, payload: self.mockABS()))
        }
    }
    
    /// 停止模拟并恢复未连接状态
    func stopMockDashboardData() {
        PTMockPhysicsState.timer?.invalidate()
        PTMockPhysicsState.timer = nil
        bleState.resetSession()
        dashboardSession.end()
        self.delegates.forEach({ $0.delegate?.dashboardManager(self, didChangeConnectionState: false) })
        PTOBDLogger.moto.ptLog("🛑 [模拟器] 已停止沙盒引擎。")
    }
    
    // MARK: - 逆向组包工具
    
    /// 将十六进制数组封装为仪表盘期望的 [0x16, ID, Payload, 0x00] 格式
    private func buildMockFrame(id: UInt8, payload: [UInt8]) -> Data {
        var frame = Data()
        frame.append(0x16) // Preamble (包头)
        frame.append(id)   // ID
        frame.append(contentsOf: payload) // 载荷
        frame.append(0x00) // EOF (包尾)
        return frame
    }
    
    /// 伪造 DATA1 (油量、平均油耗、小计里程、总里程)
    private func mockData1() -> [UInt8] {
        let fuel = UInt8(PTMockPhysicsState.mockFuel) // 逆向公式: (254 * 0.3937) ≈ 100%
        let avg: UInt8 = 45 // 4.5 L/100km
        let trip: UInt16 = 1250 // 125.0 km
        let odo: UInt32 = 10 // 1.0 km
        
        return [
            fuel, 0x00, avg,
            UInt8((trip >> 8) & 0xFF), UInt8(trip & 0xFF),
            UInt8((odo >> 16) & 0xFF), UInt8((odo >> 8) & 0xFF), UInt8(odo & 0xFF)
        ]
    }
    
    /// 伪造 DATA2 (引擎状态、水温、电瓶电压)
    private func mockData2() -> [UInt8] {
        let engineStatus: UInt8 = 0x02 // 运转中 (0x02)
        let temp: UInt8 = 35 + 50 // 35°C (逆向公式: byte - 50)
        let batt: UInt8 = 142 // 14.2V (逆向公式: byte * 0.1)
        
        // EN: Keep the mock Data2 payload at the confirmed 8-byte size, including two reserved bytes.
        // ES: Mantén la carga simulada Data2 en los 8 bytes confirmados, incluidos dos bytes reservados.
        // 中文：让 Data2 Mock 保持协议确认的 8 字节 Payload，并保留两个预留字节。
        return [0x00, engineStatus, 0x00, 0x00, temp, batt, 0x00, 0x00]
    }
    
    /// 伪造 DATA3 (续航里程、仪表盘颜色/单位、保养距离、语言)
    private func mockData3() -> [UInt8] {
        let auto: UInt16 = 2500 // 250.0 km 剩余续航
        let col: UInt8 = 0x80 // Red (0x80) + 公制
        let dist: UInt16 = 1100 // 1100 km 距离保养
        let lang: UInt8 = 0x02 // 英文
        
        return [
            UInt8((auto >> 8) & 0xFF), UInt8(auto & 0xFF),
            col,
            UInt8((dist >> 8) & 0xFF), UInt8(dist & 0xFF),
            lang, 0x00, 0x00
        ]
    }
    
    /// 伪造 CONTROL (车速、转速、灯光、TCS状态)
    private func mockControl() -> [UInt8] {
        let speedRaw = UInt16(PTMockPhysicsState.mockSpeed / 0.01)
        let rpmRaw = UInt16(PTMockPhysicsState.mockRPM / 0.25)
        let tcsByte: UInt8 = 0x82 // mode1 (0x02) | ready (0x80)
        let lightByte: UInt8 = 0x40 // 近光灯开启 (0x40)
        
        return [
            0x00, 0x00, lightByte, tcsByte,
            UInt8((rpmRaw >> 8) & 0xFF), UInt8(rpmRaw & 0xFF),
            UInt8((speedRaw >> 8) & 0xFF), UInt8(speedRaw & 0xFF)
        ]
    }
    
    /// 伪造 ABS (前轮轮速、ABS灯光)
    private func mockABS() -> [UInt8] {
        let frontSpeedRaw = UInt16(PTMockPhysicsState.mockSpeed / 0.01)
        let absByte: UInt8 = 0x01 // ABS 状态正常
        
        // EN: Pad ABS with five reserved bytes so every vehicle status mock is an 11-byte frame on the wire.
        // ES: Rellena ABS con cinco bytes reservados para que toda trama simulada de estado tenga 11 bytes en el cable.
        // 中文：ABS 补齐五个预留字节，让所有车辆状态 Mock 在线路上都保持 11 字节。
        return [
            UInt8((frontSpeedRaw >> 8) & 0xFF), UInt8(frontSpeedRaw & 0xFF),
            absByte, 0x00, 0x00, 0x00, 0x00, 0x00
        ]
    }
}

