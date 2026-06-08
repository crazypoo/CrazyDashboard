//
//  PTLocationEngine.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 7/6/2026.
//

import Foundation
import CoreLocation
import PooTools

public typealias PTLocationSpeedBlock = (_ speedKmh: Double, _ courseDegree: Double, _ altitude: Double) -> Void

@objcMembers
public class PTLocationEngine: NSObject, CLLocationManagerDelegate {
    
    public static let shared = PTLocationEngine()
    
    public var locationBlock: PTLocationSpeedBlock?
    
    private let locationManager = CLLocationManager()
    
    // 用于缓存最新的罗盘方向和速度
    private var currentHeading: Double = 0.0
    private var currentSpeedKmh: Double = 0.0
    private var currentAltitude: Double = 0.0 // 🌟 新增：缓存海拔高度
    
    private override init() {
        super.init()
        setupManager()
    }
    
    private func setupManager() {
        locationManager.delegate = self
        // 设置最高精度，专为车载导航优化
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        // 设置更新频率，哪怕移动 1 米也更新
        locationManager.distanceFilter = kCLDistanceFilterNone
        // 设置罗盘过滤角度，转动超过 1 度就触发回调
        locationManager.headingFilter = 1.0
    }
    
    public func startTracking() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        // 启动方向罗盘更新 (调用磁力计)
        locationManager.startUpdatingHeading()
    }
    
    public func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }
    
    // MARK: - 1. GPS 位置与速度更新
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        guard location.horizontalAccuracy > 0 && location.horizontalAccuracy < 50 else { return }
        
        // 获取并格式化速度
        var rawSpeed = location.speed
        if rawSpeed < 0 { rawSpeed = 0 }
        currentSpeedKmh = rawSpeed * 3.6
        
        // 【核心融合逻辑】：处理 course 为 -1 的情况
        var finalCourse = location.course
        
        // 如果 GPS 航向无效 (-1)，或者车速低于 5km/h (极低速下 GPS 航向会乱飘)
        // 我们就果断切回手机的物理罗盘方向
        if finalCourse < 0 || currentSpeedKmh < 5.0 {
            finalCourse = currentHeading
        }
        
        currentAltitude = location.altitude
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.locationBlock?(self.currentSpeedKmh, finalCourse, currentAltitude)
        }
    }
    
    // MARK: - 2. 磁力计罗盘更新 (专治停车时找不到北)
    
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // 确保罗盘数据有效
        guard newHeading.headingAccuracy >= 0 else { return }
        
        // trueHeading 代表真北 (需 GPS 辅助)，magneticHeading 代表磁北
        // 优先使用真北，拿不到就用磁北
        let heading = newHeading.trueHeading > 0 ? newHeading.trueHeading : newHeading.magneticHeading
        currentHeading = heading
        
        // 如果当前车停着 (速度很低)，位置回调可能不会频繁触发，我们需要靠转动手机来实时刷新罗盘 UI
        if currentSpeedKmh < 5.0 {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.locationBlock?(self.currentSpeedKmh, self.currentHeading, self.currentAltitude)
            }
        }
    }
    
    // MARK: - 权限处理
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .denied || status == .restricted {
            PTNSLogConsole("GPS 权限被拒绝，无法获取车速！")
        }
    }
}
