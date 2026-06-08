//
//  PTLocationEngine.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 7/6/2026.
//

import Foundation
import CoreLocation
import PooTools

public struct PTTripData: Sendable {
    public var speedKmh: Double = 0.0
    public var courseDegree: Double = 0.0
    public var altitude: Double = 0.0
    
    // 新增的行程统计数据
    public var runTime: TimeInterval = 0.0    // 运行时长 (秒)
    public var totalDistance: Double = 0.0    // 总行驶距离 (米)
    public var avgSpeed: Double = 0.0         // 平均速度 (km/h)
    public var maxSpeed: Double = 0.0         // 最高速度 (km/h)
    public var minSpeed: Double = 0.0         // 最低速度 (km/h)
}

public typealias PTLocationSpeedBlock = (_ data:PTTripData) -> Void

@objcMembers
public class PTLocationEngine: NSObject, CLLocationManagerDelegate {
    
    public static let shared = PTLocationEngine()
    
    public var locationBlock: PTLocationSpeedBlock?
    
    private let locationManager = CLLocationManager()
    
    // 用于缓存最新的罗盘方向和速度
    private var currentHeading: Double = 0.0
    private var currentSpeedKmh: Double = 0.0
    private var currentAltitude: Double = 0.0 // 🌟 新增：缓存海拔高度
    
    private var startTime: Date?
    private var lastLocation: CLLocation?
    private var totalDistance: Double = 0.0
    private var maxSpeed: Double = 0.0
    private var minSpeed: Double = 999.0 // 初始设为极大值方便找最小值

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
        
        startTime = Date()
        lastLocation = nil
        totalDistance = 0.0
        maxSpeed = 0.0
        minSpeed = 999.0
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
        
        // 统计极值
        if currentSpeedKmh > maxSpeed { maxSpeed = currentSpeedKmh }
        // 忽略静止状态(0)对最低速度的干扰，只记录移动中的最低速度
        if currentSpeedKmh > 5.0 && currentSpeedKmh < minSpeed { minSpeed = currentSpeedKmh }
        
        // 计算运行时长和平均速度
        let runTime = Date().timeIntervalSince(startTime ?? Date())
        // 平均速度 = (总距离 / 总时间) 转 km/h
        let avgSpeed = runTime > 0 ? (totalDistance / runTime) * 3.6 : 0.0
        
        // 【核心融合逻辑】：处理 course 为 -1 的情况
        var finalCourse = location.course
        
        // 如果 GPS 航向无效 (-1)，或者车速低于 5km/h (极低速下 GPS 航向会乱飘)
        // 我们就果断切回手机的物理罗盘方向
        if finalCourse < 0 || currentSpeedKmh < 5.0 {
            finalCourse = currentHeading
        }
        
        currentAltitude = location.altitude
        let tripData = PTTripData(
                    speedKmh: currentSpeedKmh,
                    courseDegree: finalCourse,
                    altitude: currentAltitude,
                    runTime: runTime,
                    totalDistance: totalDistance,
                    avgSpeed: avgSpeed,
                    maxSpeed: maxSpeed,
                    minSpeed: minSpeed == 999.0 ? 0.0 : minSpeed
                )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.locationBlock?(tripData)
        }
    }
    
    // MARK: 磁力计罗盘更新 (专治停车时找不到北)
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        currentHeading = newHeading.trueHeading > 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }

    
    // MARK: - 权限处理
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .denied || status == .restricted {
            PTNSLogConsole("GPS 权限被拒绝，无法获取车速！")
        }
    }
}
