//
//  PTRoutingManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 23/7/2026.
//

import UIKit
import Foundation
import PooTools

/// 1. 定义类型安全的指令枚举 (App Intents)
/// 这里的每一个 case 都代表一个允许外部唤醒的功能
public enum PTAppIntent {
    /// 检查油量并可能触发救援
    case checkFuel
    /// 开启或关闭防盗系统
    case toggleAntiTheft(enable: Bool)
    /// 开启沉浸式 HUD 模式
    case openHUD
    /// 去找加油站
    case confirmGasStationRoute
    /// 未知或不支持的指令
    case unknown
}

/// 2. 全局路由分发引擎
@objcMembers
public class PTRoutingManager: NSObject {
    
    public static let shared = PTRoutingManager()
    
    // 你 App 专属的 URL Scheme 头
    private let appScheme = "xp400"
    
    private override init() { super.init() }
    
    /// 解析外部传入的 URL
    /// 预期的 URL 格式例如: ptools://action/checkFuel
    /// 或是带参数的格式: ptools://action/antiTheft?enable=true
    public func handle(url: URL) -> Bool {
        // 确保是我们自己的 Scheme
        guard url.scheme?.lowercased() == appScheme else { return false }
        
        // 解析 URL 为安全的枚举类型
        let intent = parseIntent(from: url)
        
        // 执行对应的意图
        execute(intent: intent)
        return true
    }
    
    /// 将 URL 转化为类型安全的 Enum
    private func parseIntent(from url: URL) -> PTAppIntent {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host else {
            return .unknown
        }
        
        // 根据 Host 和 Query Parameters 路由
        switch host {
        case "checkFuel":
            return .checkFuel
            
        case "antiTheft":
            // 解析 URL 参数 (如 ?enable=true)
            let enableStr = components.queryItems?.first(where: { $0.name == "enable" })?.value
            let enable = (enableStr?.lowercased() == "true")
            return .toggleAntiTheft(enable: enable)
            
        case "openHUD":
            return .openHUD
        case "confirmGasStationRoute":
            return .confirmGasStationRoute
        default:
            return .unknown
        }
    }
    
    /// 集中处理所有的动作分发
    private func execute(intent: PTAppIntent) {
        switch intent {
        case .checkFuel:
            PTNSLogConsole("🗣️ [路由引擎] 收到 Siri 指令：检查油量")
            // 获取当前最新的油量数据 (这里需要你的数据管家提供最新数据的读取接口)
            // 如果处于低油量，直接触发你之前写好的高德搜索
            if let latestData1 = PTBluetoothServerManager.shared.latestData1 {
                if latestData1.fuelLevelPct <= 15 {
                    // 模拟触发低油量广播，唤醒 HUD 弹窗
                    let promptText = PTDashboardConfig.language(key: "short_cut_fuel", latestData1.fuelLevelPct)
                    SpeechSynthesizer.Shared.speak(promptText)
                    NotificationCenter.default.post(name: MotorcycleLowFuelActionRequired, object: promptText)
                } else {
                    PTMessagePusher.pushToDashboard(title: PTDashboardConfig.languageFunc(text: "short_cut_fuel_title"), body: PTDashboardConfig.language(key: "short_cut_fuel_msg", latestData1.fuelLevelPct))
                }
            } else {
                PTNSLogConsole("⚠️ [路由引擎] 蓝牙未连接，无法查询实时油量。")
            }
            
        case .toggleAntiTheft(let enable):
            PTNSLogConsole("🗣️ [路由引擎] 收到 Siri 指令：防盗系统设置 -> \(enable ? "开启" : "关闭")")
            if enable {
                // 调用之前写的防盗管理器打卡
                PTMOTOParkingManager.shared.saveCurrentLocationAsParkingSpot()
                PTMessagePusher.pushToDashboard(title: PTDashboardConfig.languageFunc(text: "parking_lock_title"), body: PTDashboardConfig.languageFunc(text: "parking_lock_msg"))
            } else {
                PTMOTOParkingManager.shared.clearParkingSpot()
                PTMessagePusher.pushToDashboard(title: PTDashboardConfig.languageFunc(text: "parking_unlock_title"), body: PTDashboardConfig.languageFunc(text: "parking_unlock_msg"))
            }
            
        case .openHUD:
            PTNSLogConsole("🗣️ [路由引擎] 收到 Siri 指令：开启 HUD")
            let vc = PTDashBoardBaseBoardViewController()
            PTUtils.getCurrentVC()?.navigationController?.pushViewController(vc, animated: true)
        case .confirmGasStationRoute:
            PTNSLogConsole("🗣️ [路由引擎] 收到 Siri 指令：确认前往加油站")
            // 直接调用你写好的确认下发方法
            PTFuelRoutingManager.shared.confirmAndSendGasStationRoute()
            // 贴心小优化：触发语音反馈，让戴着头盔的骑手知道指令已经成功执行了
            SpeechSynthesizer.Shared.speak(PTDashboardConfig.languageFunc(text: "button_done"))
        case .unknown:
            PTNSLogConsole("❓ [路由引擎] 收到无法解析的外部指令")
        }
    }
}
