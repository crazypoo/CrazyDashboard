//
//  PTWeatherManager.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 30/7/2026.
//

import Foundation
import WeatherKit
import CoreLocation
import PooTools
import QWeatherSDK

class PTWeatherManager {
    public static let shared = PTWeatherManager()
        
    // 实例化官方的天气服务对象
    private let weatherService = WeatherService.shared
    
    // MARK: - 🌟 节流(Throttling) 核心属性
    /// 记录上一次成功请求天气的时间
    private var lastFetchTime: Date?
    /// 记录上一次请求天气时的具体位置
    private var lastFetchLocation: CLLocation?

    /// 时间阈值：15分钟 (15 * 60 秒)。15分钟内不再重复请求。
    private let timeThreshold: TimeInterval = 15 * 60
    /// 距离阈值：10000米 (10公里)。如果机车跨区行驶超过10公里，即使没到15分钟也重新请求。
    private let distanceThreshold: CLLocationDistance = 10000

    /// 连续请求失败的次数记录
    private var retryCount: Int = 0
    /// 最大允许连续失败次数
    private let maxRetryLimit: Int = 5

    private init() {}
    
    /// 获取指定坐标的当前实时天气
    /// - Parameter location: 传入一个 CLLocation 坐标 (包含经纬度)
    /// - Returns: 返回包含温度、天气状态等信息的 CurrentWeather 对象
    public func fetchCurrentWeather(for location: CLLocation) {
        // 🚨 第一步：拦截逻辑 (节流阀)
        if let lastTime = lastFetchTime, let lastLoc = lastFetchLocation {
            let timeElapsed = Date().timeIntervalSince(lastTime)
            let distanceMoved = location.distance(from: lastLoc)
            
            if timeElapsed < timeThreshold && distanceMoved < distanceThreshold {
                // 没有超时，也没有超出距离，直接拦截请求
                return
            } else {
                // 🌟 正常经过 15 分钟或移动 10 公里后，说明已经度过了休眠期
                // 此时重置失败次数，给它重新尝试的 5 次机会
                self.retryCount = 0
            }
        }
        
        // 🚨 第二步：更新记录，准备放行请求
        self.lastFetchTime = Date()
        self.lastFetchLocation = location
        
        PTNSLogConsole("🛰️ [天气服务] 准备向 Apple 索取最新天气... (当前重试次数: \(retryCount))")
        
        // 第三步：发起异步网络请求
        Task {
            do {
                let weather = try await weatherService.weather(for: location)
                let currentCondition = weather.currentWeather.condition
                PTNSLogConsole("🌤️ 实时天气获取成功: \(currentCondition.description)")
                
                // 🌟 成功获取到数据，立刻将失败次数清零
                self.retryCount = 0
                
                DispatchQueue.main.async {
                    self.applyWeatherAnimation(for: currentCondition)
                }
            } catch {
                PTNSLogConsole("❌ [天气服务] 请求失败: \(error.localizedDescription)")
                
                // 🌟 第四步：失败与重试逻辑的智能分流
                self.retryCount += 1
                
                if self.retryCount < self.maxRetryLimit {
                    // 情况 A：如果失败次数小于 5 次
                    // 我们主动清空记录的时间，让下一次 GPS 定位回调能立刻突破拦截阀，实现快速重试
                    self.lastFetchTime = nil
                    PTNSLogConsole("⚠️ [天气服务] 启动快速重试，准备进行第 \(self.retryCount + 1) 次尝试。")
                } else {
                    // 情况 B：如果已经连续失败 5 次
                    // 我们保留 lastFetchTime 原封不动，让系统强制进入 15 分钟或 10 公里的休眠期
                    PTNSLogConsole("⛔ [天气服务] 已连续失败 \(self.maxRetryLimit) 次！触发熔断保护，等待 15 分钟或移动 10 公里后重试。")
                    self.fetchQWeatherFallback(for: location)
                }
            }
        }
    }
    
    // MARK: - 和风天气 (QWeather) 降级方案
    
    /// 使用和风天气 API 获取备用天气数据
    private func fetchQWeatherFallback(for location: CLLocation) {
        Task {
            do {
                let lon = String(format: "%.2f", location.coordinate.longitude)
                let lat = String(format: "%.2f", location.coordinate.latitude)
                let locationString = "\(lon),\(lat)"
                let parameter = WeatherParameter(location: locationString)
                
                let response =  try await QWeather.instance.weatherNow(parameter)
                self.applyQWeatherAnimation(iconCode: response.code)
            } catch QWeatherError.errorResponse(let error) {
                PTNSLogConsole(error)
            } catch {
                PTNSLogConsole(error)
            }

        }
    }

    /// 将官方天气状态映射为对应的特效
    private func applyWeatherAnimation(for condition: WeatherCondition) {
        if let scene = PTWindowSceneDelegate.sceneDelegate() as? SceneDelegate {
            switch condition {
            // 下雨的各种状态
            case .rain, .heavyRain, .drizzle, .sunFlurries, .thunderstorms:
                scene.weatherOverlay.showRain()
            // 下雪的各种状态
            case .snow, .heavySnow, .blizzard, .flurries, .sleet:
                scene.weatherOverlay.showSnow()
            // 晴天或多云等不需要强烈粒子动画的状态
            case .clear, .cloudy, .mostlyClear, .mostlyCloudy:
                scene.weatherOverlay.stopWeather()
            default:
                scene.weatherOverlay.stopWeather()
            }
        }
    }
    
    /// 和风天气代号的动画映射
    private func applyQWeatherAnimation(iconCode: String) {
        guard let scene = PTWindowSceneDelegate.sceneDelegate() as? SceneDelegate else { return }
        guard let code = Int(iconCode) else { return }
        
        // 和风天气的图标代码体系：
        // 300 ~ 399: 各种下雨状态 (阵雨, 雷阵雨, 暴雨等)
        // 400 ~ 499: 各种下雪状态 (小雪, 大雪, 暴雪等)
        
        switch code {
        case 300...399:
            scene.weatherOverlay.showRain()
        case 400...499:
            scene.weatherOverlay.showSnow()
        default:
            // 晴天(100-199)、多云等其他状态，关闭特效
            scene.weatherOverlay.stopWeather()
        }
    }
}
