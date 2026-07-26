//
//  PTLocationEngine.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 7/6/2026.
//

import Foundation
import AMapLocationKit // 🌟 引入高德定位 SDK
import PooTools

// 🌟 引擎运行模式
public enum PTLocationEngineMode {
    case riding      // 骑行模式：注重行程统计，允许系统在长时间静止时自动挂起以省电
    case antiTheft   // 防盗模式：注重后台保活，禁止系统挂起，随时抓取最新位置
}

public struct PTTripData: Sendable {
    public var speedKmh: Double = 0.0
    public var courseDegree: Double = 0.0
    public var altitude: Double = 0.0
    
    public var runTime: TimeInterval = 0.0    // 运行时长 (秒)
    public var totalDistance: Double = 0.0    // 总行驶距离 (米)
    public var avgSpeed: Double = 0.0         // 平均速度 (km/h)
    public var maxSpeed: Double = 0.0         // 最高速度 (km/h)
    public var minSpeed: Double = 0.0         // 最低速度 (km/h)
    
    public var idleTime: TimeInterval = 0.0       // 怠速/拥堵时长 (秒)
    public var best0To100Time: TimeInterval? = nil // 0-100 最佳加速成绩 (秒)
    
    public var currentLocation: CLLocation?
}

public typealias PTLocationTripBlock = (_ data: PTTripData) -> Void

@objcMembers
public class PTLocationEngine: NSObject, AMapLocationManagerDelegate { // 🌟 修改代理协议为高德
    
    public static let shared = PTLocationEngine()
    public var locationBlock: PTLocationTripBlock?
    
    // 🌟 核心替换：使用高德定位管理器
    private let locationManager = AMapLocationManager()
    
    // 防抖：防止重复启动导致数据被清零
    private var isTracking = false
    
    public private(set) var currentMode: PTLocationEngineMode = .riding
    
    // 🌟 停车位置的 UserDefaults Keys
    private let parkingLatKey = "PTLastParkedLatitude"
    private let parkingLonKey = "PTLastParkedLongitude"

    // MARK: - 数据缓存池
    private var currentHeading: Double = 0.0
    private var currentAltitude: Double = 0.0
    
    // MARK: - 行程统计核心变量
    private var startTime: Date?
    private var lastLocation: CLLocation?
    private var totalDistance: Double = 0.0
    private var maxSpeed: Double = 0.0
    private var minSpeed: Double = 999.0
    
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
        locationManager.allowsBackgroundLocationUpdates = true
        // 针对机车业务，不进行连续的逆地理编码（省电、省流量）
        locationManager.locatingWithReGeocode = false
        applyModeConfiguration()
    }
    
    public func switchEngineMode(to mode: PTLocationEngineMode) {
        self.currentMode = mode
        applyModeConfiguration()
    }

    private func applyModeConfiguration() {
        switch currentMode {
        case .riding:
            // 骑行时：允许系统在感知不到移动时自动挂起 GPS 硬件，保护手机电量
            locationManager.pausesLocationUpdatesAutomatically = true
            PTNSLogConsole("📍 [全局定位引擎] 切换至【骑行模式】，已开启智能省电")
        case .antiTheft:
            // 停车/防盗时：死死咬住后台，绝不允许系统挂起定位，确保防盗警报随时可查
            locationManager.pausesLocationUpdatesAutomatically = false
            PTNSLogConsole("📍 [全局定位引擎] 切换至【防盗保活模式】，已禁止系统休眠")
        }
    }

    // MARK: - 🌟 融合：停车防盗功能
    
    /// 将当前（或最后一次）有效位置存为停车点
    public func saveCurrentLocationAsParkingSpot() {
        // 如果当前引擎正在运行，直接用最后已知位置；如果没运行，触发一次单次定位
        if let last = self.lastLocation {
            self.persistLocation(last)
        } else {
            // 请求单次定位获取最新停车点
            self.requestSingleLocationForAntiTheft { [weak self] loc in
                if let validLoc = loc {
                    self?.persistLocation(validLoc)
                }
            }
        }
    }
    
    private func persistLocation(_ location: CLLocation) {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        
        UserDefaults.standard.set(lat, forKey: parkingLatKey)
        UserDefaults.standard.set(lon, forKey: parkingLonKey)
        
        PTNSLogConsole("🅿️ [停车打卡] 成功在后台/锁屏状态保存车辆位置: 纬度 \(lat), 经度 \(lon)")
    }
    
    public func getLastParkedLocation() -> CLLocationCoordinate2D? {
        let lat = UserDefaults.standard.double(forKey: parkingLatKey)
        let lon = UserDefaults.standard.double(forKey: parkingLonKey)
        if lat != 0.0 && lon != 0.0 {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return nil
    }
    
    public func clearParkingSpot() {
        UserDefaults.standard.removeObject(forKey: parkingLatKey)
        UserDefaults.standard.removeObject(forKey: parkingLonKey)
        PTNSLogConsole("♻️ [停车打卡] 已清除旧的停车记录")
    }
    
    /// 专供防盗系统使用的后台单次快速定位
    public func requestSingleLocationForAntiTheft(completion: @escaping (CLLocation?) -> Void) {
        // 高德单次定位 API
        locationManager.requestLocation(withReGeocode: false, completionBlock: { (location, reGeocode, error) in
            if let error = error {
                PTNSLogConsole("❌ [单次定位] 获取防盗位置失败: \(error.localizedDescription)")
                completion(nil)
            } else {
                completion(location)
            }
        })
    }
    
    public func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        
        // 注意：高德 SDK 不需要自己调用 requestWhenInUseAuthorization
        // 它会根据你项目的 Info.plist 自动判断并申请权限
        
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        PTNSLogConsole("🚀 [PTLocationEngine] 高德行程引擎已启动")
    }
    
    public func stopTracking() {
        guard isTracking else { return }
        isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        PTNSLogConsole("🛑 [PTLocationEngine] 高德行程引擎已停止")
    }
    
    public func resetTrip() {
        startTime = nil
        lastLocation = nil
        totalDistance = 0.0
        maxSpeed = 0.0
        minSpeed = 999.0
        idleTime = 0.0
        zeroToHundredStartTime = nil
        best0To100 = nil
        PTNSLogConsole("♻️ [PTLocationEngine] 行程数据已清零")
    }
    
    // MARK: - 高德地图位置更新回调
    public func amapLocationManager(_ manager: AMapLocationManager!, didUpdate location: CLLocation!, reGeocode: AMapLocationReGeocode!) {
        guard let location = location else { return }
        
        if currentMode == .antiTheft {
            self.lastLocation = location
            return
       }

        // 过滤低精度垃圾数据 (80米)
        guard location.horizontalAccuracy > 0 && location.horizontalAccuracy < 80 else { return }
        
        let now = Date()
        
        if startTime == nil {
            startTime = Date()
        }
        
        // 1. 累加行驶距离
        if let last = lastLocation {
            let distance = location.distance(from: last)
            // 过滤原地漂移和超级瞬移
            if distance > 1.5 && distance < 2000.0 {
                totalDistance += distance
            }
        }
        lastLocation = location
        
        // 2. 速度处理
        var rawSpeed = location.speed
        if rawSpeed < 0 { rawSpeed = 0 }
        let currentSpeedKmh = rawSpeed * 3.6
        
        if let lastTime = lastUpdateTime {
            let timeDelta = now.timeIntervalSince(lastTime)
            if currentSpeedKmh < 2.0 {
                idleTime += timeDelta // 累加怠速
            }
        }
        lastUpdateTime = now

        // 🌟 核心 2：0-100 km/h 自动计时逻辑
        if currentSpeedKmh <= 2.0 {
            zeroToHundredStartTime = now
        } else if currentSpeedKmh >= 100.0 {
            if let start = zeroToHundredStartTime {
                let achievedTime = now.timeIntervalSince(start)
                if achievedTime > 2.0 {
                    if best0To100 == nil || achievedTime < best0To100! {
                        best0To100 = achievedTime
                        PTNSLogConsole("🏎️💨 [测速突破] 创造新的 0-100km/h 成绩: \(String(format: "%.2f", achievedTime))秒！")
                    }
                }
                zeroToHundredStartTime = nil
            }
        }

        // 3. 统计极值
        if currentSpeedKmh > maxSpeed { maxSpeed = currentSpeedKmh }
        if currentSpeedKmh > 1.0 && currentSpeedKmh < minSpeed { minSpeed = currentSpeedKmh }
        
        // 4. 计算运行时长和平均速度
        let runTime = now.timeIntervalSince(startTime!)
        let avgSpeed = runTime > 0 ? (totalDistance / runTime) * 3.6 : 0.0
        
        currentAltitude = location.altitude
        
        var finalCourse = location.course
        if finalCourse < 0 || currentSpeedKmh < 5.0 {
            finalCourse = currentHeading
        }
        
        // 5. 组装数据并抛给上层 UI
        let tripData = PTTripData(
            speedKmh: currentSpeedKmh,
            courseDegree: finalCourse,
            altitude: currentAltitude,
            runTime: runTime,
            totalDistance: totalDistance,
            avgSpeed: avgSpeed,
            maxSpeed: maxSpeed,
            minSpeed: minSpeed == 999.0 ? 0.0 : minSpeed,
            idleTime: idleTime,
            best0To100Time: best0To100,
            currentLocation: location
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.locationBlock?(tripData)
        }
    }
    
    // MARK: - 高德地图方向 (罗盘) 回调
    public func amapLocationManager(_ manager: AMapLocationManager!, didUpdate newHeading: CLHeading!) {
        guard let newHeading = newHeading, newHeading.headingAccuracy >= 0 else { return }
        
        currentHeading = newHeading.trueHeading > 0 ? newHeading.trueHeading : newHeading.magneticHeading
        
        // 低速状态下主动刷新 UI 指南针
        if (locationBlock != nil) && (lastLocation != nil) {
            let speed = max(0, (lastLocation?.speed ?? 0) * 3.6)
            if speed < 5.0 {
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
                    idleTime: idleTime,
                    best0To100Time: best0To100
                )
                DispatchQueue.main.async { [weak self] in
                    self?.locationBlock?(tripData)
                }
            }
        }
    }
    
    // MARK: - 错误处理
    public func amapLocationManager(_ manager: AMapLocationManager!, didFailWithError error: Error!) {
        PTNSLogConsole("❌ [PTLocationEngine] 引擎定位失败: \(error.localizedDescription)")
    }
}
