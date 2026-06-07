//
//  PTLocationEngine.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 7/6/2026.
//

import Foundation
import CoreLocation

public typealias PTLocationSpeedBlock = (_ speedKmh: Double, _ courseDegree: Double) -> Void

@objcMembers
public class PTLocationEngine: NSObject, CLLocationManagerDelegate {
    
    public static let shared = PTLocationEngine()
    
    public var locationBlock: PTLocationSpeedBlock?
    
    private let locationManager = CLLocationManager()
    
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
    }
    
    public func startTracking() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        // 可选：启动方向罗盘更新
        locationManager.startUpdatingHeading()
    }
    
    public func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // 【核心过滤逻辑】
        // 1. 如果 horizontalAccuracy 为负数，说明该定位数据无效
        // 2. 如果精度大于 50 米，说明 GPS 信号太弱（比如在隧道里），直接丢弃
        guard location.horizontalAccuracy > 0 && location.horizontalAccuracy < 50 else { return }
        
        // 获取真实速度 (单位是 米/秒)
        var rawSpeed = location.speed
        
        // 当你停止时，系统可能会返回负数速度，强制归零
        if rawSpeed < 0 {
            rawSpeed = 0
        }
        
        // 将 米/秒 转换为 公里/小时 (km/h)
        // 如果你需要英里 (mph)，请乘以 2.23694
        let speedKmh = rawSpeed * 3.6
        
        // 获取车头真实朝向 (0.0 到 359.9 度)
        var course = location.course
        if course < 0 {
            course = 0 // 如果获取不到方向，默认朝北
        }
        
        // 回调给仪表盘 UI
        DispatchQueue.main.async { [weak self] in
            self?.locationBlock?(speedKmh, course)
        }
    }
    
    // 处理权限拒绝的情况
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .denied || status == .restricted {
            print("GPS 权限被拒绝，无法获取车速！")
        }
    }
}
