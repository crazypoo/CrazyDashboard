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

@MainActor
final class PTWeatherManager {
    public static let shared = PTWeatherManager()
        
    // 实例化官方的天气服务对象
    private let weatherService = WeatherService.shared

    // EN: Keep the configured QWeather actor optional so an unavailable fallback never crashes the app.
    // ES: Mantiene opcional el actor de QWeather para que una reserva no disponible nunca bloquee la app.
    // 中文：将已配置的 QWeather actor 保持为可选，备用服务不可用时不会让 App 崩溃。
    private var qWeatherService: QWeather?
    
    // MARK: - 🌟 节流(Throttling) 核心属性
    private let kLastFetchTime = "PTWeather_LastFetchTime"
    private let kLastFetchLat = "PTWeather_LastFetchLat"
    private let kLastFetchLon = "PTWeather_LastFetchLon"
    private let kLastWeatherEffect = "PTWeather_LastEffectCode" // 缓存上一次播放的特效代码

    /// 时间阈值：15分钟 (15 * 60 秒)。15分钟内不再重复请求。
    private let timeThreshold: TimeInterval = 30 * 60
    /// 距离阈值：10000米 (10公里)。如果机车跨区行驶超过10公里，即使没到15分钟也重新请求。
    private let distanceThreshold: CLLocationDistance = 10000

    /// 连续请求失败的次数记录
    private var retryCount: Int = 0
    /// 最大允许连续失败次数
    private let maxRetryLimit: Int = 5

    private init() {}

    // EN: Both current-weather animation and route-risk analysis receive the same initialized service.
    // ES: La animación meteorológica actual y el análisis de ruta reciben el mismo servicio inicializado.
    // 中文：当前天气动画和路线风险分析共用同一个已经初始化完成的服务。
    func configureQWeather(_ service: QWeather) {
        qWeatherService = service
    }
    
    private var lastFetchTime: Date? {
        return UserDefaults.standard.object(forKey: kLastFetchTime) as? Date
    }

    private var lastFetchLocation: CLLocation? {
        let lat = UserDefaults.standard.double(forKey: kLastFetchLat)
        let lon = UserDefaults.standard.double(forKey: kLastFetchLon)
        // 0.0, 0.0 表示可能从未存过
        if lat == 0.0 && lon == 0.0 { return nil }
        return CLLocation(latitude: lat, longitude: lon)
    }

    // MARK: - 🌟 新增：强制刷新天气
    /// 无视时间和距离限制，立刻强制请求最新天气
    public func forceRefreshWeather(for location: CLLocation) {
        PTNSLogConsole("🔄 [天气服务] 用户触发强制刷新天气...")
        // 1. 清空本地记录的时间，强制突破节流阀
        UserDefaults.standard.removeObject(forKey: kLastFetchTime)
        // 2. 清零重试次数
        self.retryCount = 0
        // 3. 正常走请求逻辑
        self.fetchCurrentWeather(for: location)
    }

    /// 获取指定坐标的当前实时天气
    /// - Parameter location: 传入一个 CLLocation 坐标 (包含经纬度)
    /// - Returns: 返回包含温度、天气状态等信息的 CurrentWeather 对象
    public func fetchCurrentWeather(for location: CLLocation) {
        // 🚨 第一步：拦截逻辑 (带持久化缓存恢复)
        if let lastTime = self.lastFetchTime, let lastLoc = self.lastFetchLocation {
            let timeElapsed = Date().timeIntervalSince(lastTime)
            let distanceMoved = location.distance(from: lastLoc)
            
            if timeElapsed < timeThreshold && distanceMoved < distanceThreshold {
                PTNSLogConsole("🛑 [天气服务] 拦截请求！距离上次请求仅过去 \(Int(timeElapsed/60)) 分钟，移动距离 \(Int(distanceMoved)) 米。")
                
                // 🌟 如果此时 App 是刚刚重启的，界面上可能没有特效，我们需要从本地读出来并恢复
                if let cachedEffect = UserDefaults.standard.string(forKey: kLastWeatherEffect) {
                    DispatchQueue.main.async {
                        self.playCachedAnimation(effectCode: cachedEffect)
                    }
                }
                return
            } else {
                // 超过 30 分钟或移动超过 10 公里，放行！重置失败次数
                self.retryCount = 0
            }
        }
        
        // 🚨 第二步：更新记录，准备放行请求
        UserDefaults.standard.set(Date(), forKey: kLastFetchTime)
        UserDefaults.standard.set(location.coordinate.latitude, forKey: kLastFetchLat)
        UserDefaults.standard.set(location.coordinate.longitude, forKey: kLastFetchLon)
        
        PTNSLogConsole("🛰️ [天气服务] 准备向 Apple 索取最新天气... (当前重试次数: \(retryCount))")
        
        // 第三步：发起异步网络请求
        Task {
            do {
                let weather = try await weatherService.weather(for: location)
                let currentCondition = weather.currentWeather.condition
                PTNSLogConsole("🌤️ 实时天气获取成功: \(currentCondition.description)")
                
                self.retryCount = 0
                
                // 🌟 成功拿到官方天气后，持久化当前天气的特征码，并播放动画
                let effectCode = "Apple_\(currentCondition.description)"
                UserDefaults.standard.set(effectCode, forKey: kLastWeatherEffect)
                
                DispatchQueue.main.async {
                    self.applyWeatherAnimation(for: currentCondition)
                }
                
            } catch {
                PTNSLogConsole("❌ [天气服务] 请求失败: \(error.localizedDescription)")
                
                // 🌟 第四步：失败与重试逻辑的智能分流
                self.retryCount += 1
                
                if self.retryCount < self.maxRetryLimit {
                    // 情况 A：主动清空记录的时间，让下一次定位回调能立刻突破拦截阀，实现快速重试
                    UserDefaults.standard.removeObject(forKey: kLastFetchTime)
                    PTNSLogConsole("⚠️ [天气服务] 启动快速重试，准备进行第 \(self.retryCount + 1) 次尝试。")
                } else {
                    // 情况 B：触发熔断保护，进入 30 分钟休眠期，并开启降级方案
                    PTNSLogConsole("⛔ [天气服务] 已连续失败 \(self.maxRetryLimit) 次！触发熔断保护。")
                    self.fetchQWeatherFallback(for: location)
                }
            }
        }
    }
    
    // MARK: - 和风天气 (QWeather) 降级方案
    /// 使用和风天气 API 获取备用天气数据
    private func fetchQWeatherFallback(for location: CLLocation) {
        guard let qWeatherService else {
            PTNSLogConsole("ℹ️ [和风降级服务] 服务尚未初始化，跳过备用请求。")
            return
        }

        Task { @MainActor [weak self, qWeatherService] in
            guard let self else { return }
            do {
                let lon = String(format: "%.2f", location.coordinate.longitude)
                let lat = String(format: "%.2f", location.coordinate.latitude)
                let parameter = WeatherParameter(location: "\(lon),\(lat)")
                
                let response = try await qWeatherService.weatherNow(parameter)
                let iconCode = response.now.icon
                
                // 🌟 成功拿到和风天气后，持久化和风的特征码，并播放动画
                let effectCode = "QWeather_\(iconCode)"
                UserDefaults.standard.set(effectCode, forKey: kLastWeatherEffect)
                
                DispatchQueue.main.async {
                    self.applyQWeatherAnimation(iconCode: iconCode)
                }
            } catch {
                PTNSLogConsole("❌ [和风降级服务] 请求彻底失败: \(error)")
            }
        }
    }

    private func playCachedAnimation(effectCode: String) {
        guard let scene = PTWindowSceneDelegate.sceneDelegate() as? SceneDelegate else { return }
        
        // 解析缓存的代码
        if effectCode.hasPrefix("QWeather_") {
            let icon = effectCode.replacingOccurrences(of: "QWeather_", with: "")
            scene.weatherOverlay.updateWeatherEffect(by: icon)
        } else if effectCode.hasPrefix("Apple_") {
            // 注意：这里由于你的 SceneDelegate 里的 updateWeatherEffect(for:) 接收的是枚举
            // 如果不好将 String 转回官方枚举，你可以直接让 scene 根据字符串执行动画逻辑
            // 为了安全起见，这里我建议你在 scene 的 weatherOverlay 增加一个方法来接收 String 标识
            scene.weatherOverlay.updateWeatherEffect(byAppleDescription: effectCode.replacingOccurrences(of: "Apple_", with: ""))
        }
    }

    /// 将官方天气状态映射为对应的特效
    private func applyWeatherAnimation(for condition: WeatherCondition) {
        guard let scene = PTWindowSceneDelegate.sceneDelegate() as? SceneDelegate else { return }
        scene.weatherOverlay.updateWeatherEffect(for: condition)
    }
    
    /// 和风天气代号的动画映射
    private func applyQWeatherAnimation(iconCode: String) {
        guard let scene = PTWindowSceneDelegate.sceneDelegate() as? SceneDelegate else { return }        
        scene.weatherOverlay.updateWeatherEffect(by: iconCode)
    }
}
