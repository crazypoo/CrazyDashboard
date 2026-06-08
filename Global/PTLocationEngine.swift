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
    
    public var runTime: TimeInterval = 0.0    // 运行时长 (秒)
    public var totalDistance: Double = 0.0    // 总行驶距离 (米)
    public var avgSpeed: Double = 0.0         // 平均速度 (km/h)
    public var maxSpeed: Double = 0.0         // 最高速度 (km/h)
    public var minSpeed: Double = 0.0         // 最低速度 (km/h)
    
    // 🌟 新增：怠速时长与 0-100 最佳成绩
    public var idleTime: TimeInterval = 0.0       // 怠速/拥堵时长 (秒)
    public var best0To100Time: TimeInterval? = nil // 0-100 最佳加速成绩 (秒)
}

public typealias PTLocationTripBlock = (_ data: PTTripData) -> Void

@objcMembers
public class PTLocationEngine: NSObject, CLLocationManagerDelegate {
    
    public static let shared = PTLocationEngine()
    public var locationBlock: PTLocationTripBlock?
    private let locationManager = CLLocationManager()
    
    // 防抖：防止重复启动导致数据被清零
    private var isTracking = false
    
    // MARK: - 数据缓存池
    private var currentHeading: Double = 0.0
    private var currentAltitude: Double = 0.0
    
    // MARK: - 行程统计核心变量
    private var startTime: Date?
    private var lastLocation: CLLocation?
    private var totalDistance: Double = 0.0
    private var maxSpeed: Double = 0.0
    private var minSpeed: Double = 999.0 // 初始极高值
    
    // MARK: - 行程统计核心变量 (在类中补充这些属性)
    private var lastUpdateTime: Date?
    private var idleTime: TimeInterval = 0.0
    private var zeroToHundredStartTime: Date?
    private var best0To100: TimeInterval?

    private override init() {
        super.init()
        setupManager()
    }
    
    private func setupManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.headingFilter = 1.0
    }
    
    public func startTracking() {
        // 🌟 修复 1：防止外部重复调用导致行程被清空
        guard !isTracking else { return }
        isTracking = true
        
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    public func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }
    
    // 🌟 新增：手动清空行程的接口，你可以把它绑定到界面上的一个“重置”按钮
    public func resetTrip() {
        startTime = nil
        lastLocation = nil
        totalDistance = 0.0
        maxSpeed = 0.0
        minSpeed = 999.0
    }
    
    // MARK: - GPS 位置与速度核心逻辑
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // 🌟 修复 2：放宽一点精度限制（80米）。在城市高楼或走路放口袋里时，50米可能太严格了，会导致一直在丢弃数据
        guard location.horizontalAccuracy > 0 && location.horizontalAccuracy < 80 else { return }
        
        let now = Date()
        
        // 🌟 修复 3：直到拿到真正的第一个有效定位，才开始计算“运行时长”
        if startTime == nil {
            startTime = Date()
        }
        
        // 1. 累加行驶距离 (核心防漂移)
        if let last = lastLocation {
            let distance = location.distance(from: last)
            // 🌟 修复 4：GPS 抗噪！只有当两次定位距离移动超过 1.5 米，才算作有效行驶，防止等红灯时原地漂移增加里程。
            // 同时限制异常瞬移（如 > 2000米）
            if distance > 1.5 && distance < 2000.0 {
                totalDistance += distance
            }
        }
        // 无论有没有被过滤，lastLocation 必须更新为最新位置！
        lastLocation = location
        
        // 2. 速度处理
        var rawSpeed = location.speed
        if rawSpeed < 0 { rawSpeed = 0 }
        let currentSpeedKmh = rawSpeed * 3.6
        
        if let lastTime = lastUpdateTime {
            let timeDelta = now.timeIntervalSince(lastTime)
            if currentSpeedKmh < 2.0 {
                idleTime += timeDelta
            }
        }
        lastUpdateTime = now

        // 🌟 核心 2：0-100 km/h 自动计时逻辑
        if currentSpeedKmh <= 2.0 {
            // 车停稳了，随时准备弹射起步，重置起跑时间
            zeroToHundredStartTime = now
        } else if currentSpeedKmh >= 100.0 {
            // 速度破百！计算成绩
            if let start = zeroToHundredStartTime {
                let achievedTime = now.timeIntervalSince(start)
                // 过滤掉异常数据 (比如 GPS 瞬移导致的 1 秒破百)
                if achievedTime > 2.0 {
                    if best0To100 == nil || achievedTime < best0To100! {
                        best0To100 = achievedTime // 刷新最好成绩
                    }
                }
                zeroToHundredStartTime = nil // 成绩已出，清空起跑线，直到下次停稳
            }
        } else if currentSpeedKmh > 2.0 && zeroToHundredStartTime == nil {
            // 正常行驶中，未停稳，不参与测速
        }

        // 3. 统计极值
        if currentSpeedKmh > maxSpeed {
            maxSpeed = currentSpeedKmh
        }
        
        // 🌟 修复 5：只要速度大于 1.0 km/h (证明车在动或者人在走)，就开始考核最低速度
        if currentSpeedKmh > 1.0 && currentSpeedKmh < minSpeed {
            minSpeed = currentSpeedKmh
        }
        
        // 4. 计算运行时长和平均速度
        let runTime = now.timeIntervalSince(startTime!)
        // 平均速度 = (总距离 / 总时间) 转 km/h
        let avgSpeed = runTime > 0 ? (totalDistance / runTime) * 3.6 : 0.0
        
        currentAltitude = location.altitude
        
        var finalCourse = location.course
        if finalCourse < 0 || currentSpeedKmh < 5.0 {
            finalCourse = currentHeading
        }
        
        // 5. 组装数据并回调
        let tripData = PTTripData(
            speedKmh: currentSpeedKmh,
            courseDegree: finalCourse,
            altitude: currentAltitude,
            runTime: runTime,
            totalDistance: totalDistance,
            avgSpeed: avgSpeed,
            maxSpeed: maxSpeed,
            // 保证 UI 初始显示为 0 而不是 999
            minSpeed: minSpeed == 999.0 ? 0.0 : minSpeed,
            idleTime: idleTime,           // 传出怠速时间
            best0To100Time: best0To100    // 传出最佳加速成绩
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.locationBlock?(tripData)
        }
    }
    
    // MARK: - 磁力计罗盘更新
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        currentHeading = newHeading.trueHeading > 0 ? newHeading.trueHeading : newHeading.magneticHeading
        
        // 如果极低速，主动触发一次 UI 刷新罗盘
        if (locationBlock != nil) && (lastLocation != nil) {
            let speed = max(0, (lastLocation?.speed ?? 0) * 3.6)
            if speed < 5.0 {
                // 利用已经缓存的数据单独刷新罗盘朝向
                let runTime = Date().timeIntervalSince(startTime ?? Date())
                let avg = runTime > 0 ? (totalDistance / runTime) * 3.6 : 0.0
                let tripData = PTTripData(
                    speedKmh: speed,
                    courseDegree: currentHeading,
                    altitude: currentAltitude,
                    runTime: runTime,
                    totalDistance: totalDistance,
                    avgSpeed: avg,
                    maxSpeed: maxSpeed,
                    minSpeed: minSpeed == 999.0 ? 0.0 : minSpeed,
                    idleTime: idleTime,           // 传出怠速时间
                    best0To100Time: best0To100    // 传出最佳加速成绩
                )
                DispatchQueue.main.async { [weak self] in
                    self?.locationBlock?(tripData)
                }
            }
        }
    }
}
