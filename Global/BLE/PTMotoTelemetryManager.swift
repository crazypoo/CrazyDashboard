//
//  PTODBManager.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 5/8/2026.
//

import Foundation
import SwiftOBD2
import Combine
import PooTools

// MARK: - 1. 定义纯 UIKit 风格的代理协议
/// 遵守此协议的 UIViewController 可以实时接收机车遥测数据
public protocol PTMotoTelemetryDelegate: AnyObject {
    /// 连接状态发生改变时调用
    func telemetryManager(_ manager: PTMotoTelemetryManager, didChangeConnectionState isConnected: Bool)
    
    /// 基础动力数据更新时调用 (适合高刷仪表盘指针)
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateBaseData rpm: Double, speed: Double, throttle: Double)
    
    /// 环境与健康数据更新时调用 (适合侧边栏状态监测)
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateHealthData coolantTemp: Int, voltage: Double, intakeAirTemp: Int)
    
    /// 进阶硬核工况数据更新时调用 (适合极客性能面板)
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateAdvancedData map: Int, timingAdvance: Double, maf: Double, runTime: Int)
    
    /// 故障码扫描完成时调用
    func telemetryManager(_ manager: PTMotoTelemetryManager, didFinishScanningTroubleCodes codes: [String])
    
    /// 燃油、气压与行程数据更新时调用
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateTripAndFuelData fuelLevel: Double, fuelRate: Double, barometricPressure: Int, tripDistance: Int)
}

// 为协议提供默认实现，这样 ViewController 可以按需实现，不需要全部重写
public extension PTMotoTelemetryDelegate {
    func telemetryManager(_ manager: PTMotoTelemetryManager, didChangeConnectionState isConnected: Bool) {}
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateBaseData rpm: Double, speed: Double, throttle: Double) {}
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateHealthData coolantTemp: Int, voltage: Double, intakeAirTemp: Int) {}
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateAdvancedData map: Int, timingAdvance: Double, maf: Double, runTime: Int) {}
    func telemetryManager(_ manager: PTMotoTelemetryManager, didFinishScanningTroubleCodes codes: [String]) {}
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateTripAndFuelData fuelLevel: Double, fuelRate: Double, barometricPressure: Int, tripDistance: Int) {}
}

// MARK: - 2. 机车遥测核心管理器
public class PTMotoTelemetryManager {
    
    /// 全局单例
    public static let shared = PTMotoTelemetryManager()
    
    /// 🌟 对外暴露的 Delegate，ViewController 将自身设为代理即可接收数据
    private class WeakDelegateWrapper {
        weak var delegate: PTMotoTelemetryDelegate?
        init(_ delegate: PTMotoTelemetryDelegate) {
            self.delegate = delegate
        }
    }
    private var delegates: [WeakDelegateWrapper] = []
    
    // 内部私有属性
    private var obdService: OBDService
    private var cancellables = Set<AnyCancellable>()
    
    // 当前状态缓存（方便外部随时主动读取当前值，而不是等回调）
    public private(set) var isConnected: Bool = false
    public private(set) var currentRPM: Double = 0.0
    public private(set) var currentSpeed: Double = 0.0
    
    private init() {
        obdService = OBDService(connectionType: .bluetooth)
        setupConnectionListener()
    }
    
    public func addDelegate(_ delegate: PTMotoTelemetryDelegate) {
        cleanupDelegates() // 每次添加前先清理一下已经销毁的旧界面
        
        // 防止同一个 ViewController 重复添加
        let isAlreadyAdded = delegates.contains { $0.delegate === delegate }
        if !isAlreadyAdded {
            delegates.append(WeakDelegateWrapper(delegate))
            PTNSLogConsole("📡 [OBD2] 新增了一个数据监听者。当前监听者数量: \(delegates.count)")
        }
    }
    
    /// 主动移除数据监听者 (通常不需要手动调，因为用了弱引用，页面销毁会自动失效)
    public func removeDelegate(_ delegate: PTMotoTelemetryDelegate) {
        delegates.removeAll { $0.delegate === delegate || $0.delegate == nil }
    }
    
    /// 清理所有已经被系统销毁的空代理
    private func cleanupDelegates() {
        delegates.removeAll { $0.delegate == nil }
    }

    // MARK: - 连接控制
    
    /// 监听底层蓝牙连接状态
    private func setupConnectionListener() {
        obdService.$connectionState
            .receive(on: DispatchQueue.main) // 确保在主线程回调代理
            .sink { [weak self] state in
                guard let self = self else { return }
                
                self.cleanupDelegates()
                switch state {
                case .connectedToVehicle:
                    self.isConnected = true
                    PTNSLogConsole("✅ [OBD2] 成功连接 ECU，开始数据抓取！")
                    self.delegates.forEach { wrapper in
                        guard let delegate = wrapper.delegate else { return }
                        delegate.telemetryManager(self, didChangeConnectionState: true)
                    }
                    self.startFetchingLiveTelemetry()
                    
                case .disconnected:
                    self.isConnected = false
                    PTNSLogConsole("❌ [OBD2] 连接断开。")
                    self.delegates.forEach { wrapper in
                        guard let delegate = wrapper.delegate else { return }
                        delegate.telemetryManager(self, didChangeConnectionState: false)
                    }
                    // 全局广播：适合在 AppDelegate 或其他非 UI 类中监听断开事件
                    NotificationCenter.default.post(name: NSNotification.Name("PTMotoOBDDisconnected"), object: nil)
                    
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    public func connectToMotorcycle() {
        Task {
            do {
                _ = try await obdService.startConnection()
            } catch {
                PTNSLogConsole("❌ [OBD2] 连接报错: \(error.localizedDescription)")
            }
        }
    }
    
    public func disconnect() {
        obdService.stopConnection()
    }
    
    // MARK: - 核心高频轮询引擎
    
    private func startFetchingLiveTelemetry() {
        let commands: [OBDCommand] = [
            .mode1(.rpm), .mode1(.speed), .mode1(.throttlePos), // 基础
            .mode1(.coolantTemp), .mode1(.controlModuleVoltage), .mode1(.intakeTemp), // 健康
            .mode1(.intakePressure), .mode1(.timingAdvance), .mode1(.maf), .mode1(.runTime), // 进阶
            .mode1(.fuelLevel),                     // 燃油百分比
            .mode1(.barometricPressure),                 // 大气压强
            .mode1(.fuelRate),                     // 瞬时油耗
            .mode1(.distanceSinceDTCCleared)   // 清码后行驶距离 (用作小计里程)
        ]
        
        obdService.startContinuousUpdates(commands)
            .receive(on: DispatchQueue.main) // 🌟 极其重要：确保 UIKit 代理回调永远在主线程
            .sink(receiveCompletion: { completion in
                PTNSLogConsole(">>>>>>>>>>>>>>>>>>>>>>>>\(completion)")
            }, receiveValue: { [weak self] measurements in
                guard let self = self else { return }
                
                self.cleanupDelegates()
                // 1. 解析基础动力数据
                let rpm = measurements[.mode1(.rpm)]?.value as? Double ?? 0.0
                let speed = measurements[.mode1(.speed)]?.value as? Double ?? 0.0
                let throttle = measurements[.mode1(.throttlePos)]?.value as? Double ?? 0.0
                
                // 缓存最新值
                self.currentRPM = rpm
                self.currentSpeed = speed
                                
                let coolant = self.toInt(measurements[.mode1(.coolantTemp)]?.value)
                let voltage = measurements[.mode1(.controlModuleVoltage)]?.value as? Double ?? 0.0
                let airTemp = self.toInt(measurements[.mode1(.intakeTemp)]?.value)
                                
                let map = self.toInt(measurements[.mode1(.intakePressure)]?.value)
                let timing = measurements[.mode1(.timingAdvance)]?.value as? Double ?? 0.0
                let maf = measurements[.mode1(.maf)]?.value as? Double ?? 0.0
                let runTime = self.toInt(measurements[.mode1(.runTime)]?.value)
                                
                let fuelLevel = measurements[.mode1(.fuelLevel)]?.value as? Double ?? 0.0
                let fuelRate = measurements[.mode1(.fuelRate)]?.value as? Double ?? 0.0
                let barometric = self.toInt(measurements[.mode1(.barometricPressure)]?.value)
                let tripDistance = self.toInt(measurements[.mode1(.distanceSinceDTCCleared)]?.value)
                
                self.delegates.forEach { wrapper in
                    guard let delegate = wrapper.delegate else { return }
                    
                    // 1. 发送基础数据
                    delegate.telemetryManager(self, didUpdateBaseData: rpm, speed: speed, throttle: throttle)
                    
                    // 2. 发送健康数据
                    delegate.telemetryManager(self, didUpdateHealthData: coolant, voltage: voltage, intakeAirTemp: airTemp)
                    
                    // 3. 发送进阶数据
                    delegate.telemetryManager(self, didUpdateAdvancedData: map, timingAdvance: timing, maf: maf, runTime: runTime)
                    
                    // 4. 发送油耗与行程数据
                    delegate.telemetryManager(self, didUpdateTripAndFuelData: fuelLevel, fuelRate: fuelRate, barometricPressure: barometric, tripDistance: tripDistance)
                }
            })
            .store(in: &cancellables)
    }
    
    // MARK: - 诊断引擎
    public func scanForEngineFaultCodes() {
        Task {
            do {
                let response = try await obdService.sendCommand(.mode3(.GET_DTC))
                switch response {
                case .success(let success):
                    let map:[String] = success.troubleCode?.compactMap { value in
                        return value.description
                    } ?? []
                    self.cleanupDelegates()
                    self.delegates.forEach { wrapper in
                        guard let delegate = wrapper.delegate else { return }
                        delegate.telemetryManager(self, didFinishScanningTroubleCodes: map)
                    }
                case .failure(let failure):
                    PTNSLogConsole("❌ [OBD诊断] 失败: \(failure.localizedDescription)")
                }
            } catch {
                PTNSLogConsole("❌ [OBD诊断] 失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 安全转换工具
    private func toInt(_ value: Any?) -> Int {
        if let v = value as? Int { return v }
        if let v = value as? Double { return Int(v) }
        return 0
    }
}
