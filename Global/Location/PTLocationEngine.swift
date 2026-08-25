//
//  PTLocationEngine.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 7/6/2026.
//

import Foundation
import AMapLocationKit
import PooTools
import AMapSearchKit
import AMapNaviKit

public let PTLocationEngineDidUpdate = NSNotification.Name("PTLocationEngineDidUpdate")

// 🌟 引擎运行模式
public enum PTLocationEngineMode {
    case riding      // 骑行模式：注重行程统计，允许系统在长时间静止时自动挂起以省电
    case antiTheft   // 防盗模式：注重后台保活，禁止系统挂起，随时抓取最新位置
}

public struct PTTripData: Sendable {
    public var courseDegree: Double = 0.0
    public var altitude: Double = 0.0
    public var currentLocation: CLLocation?
}

@objcMembers
public class PTLocationEngine: NSObject, AMapLocationManagerDelegate { // 🌟 修改代理协议为高德
    
    public static let shared = PTLocationEngine()
    
    private var lastWidgetUpdateTime: Date?
    // 🌟 核心替换：使用高德定位管理器
    private let locationManager = AMapLocationManager()
    
    // 防抖：防止重复启动导致数据被清零
    var isTracking = false
    
    public private(set) var currentMode: PTLocationEngineMode = .riding
    
    // 🌟 停车位置的 UserDefaults Keys
    private let parkingLatKey = "PTLastParkedLatitude"
    private let parkingLonKey = "PTLastParkedLongitude"

    // MARK: - 数据缓存池
    private var currentHeading: Double = 0.0
    private var currentAltitude: Double = 0.0
    
    // MARK: - 行程统计核心变量
    public private(set) var lastLocation: CLLocation?

    private var searchAPI: AMapSearchAPI?
    
    private override init() {
        super.init()
        setupManager()
    }
    
    private func setupManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        // 针对机车业务，不进行连续的逆地理编码（省电、省流量）
        locationManager.locatingWithReGeocode = false
        locationManager.locationTimeout = 10   // 定位超时时间设为 10 秒
        locationManager.reGeocodeTimeout = 10  // 逆地理编码超时设为 10 秒
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
        
        let request = AMapReGeocodeSearchRequest()
        request.location = AMapGeoPoint.location(withLatitude: lat, longitude: lon)
        
        // 是否需要返回附近的 POI (兴趣点) 信息。如果只是为了获取街道地址，设为 false 可以加快请求速度
        request.requireExtension = false
        
        // 4. 正式发起请求
        self.searchAPI = AMapSearchAPI()
        self.searchAPI?.delegate = self
        self.searchAPI?.aMapReGoecodeSearch(request)
        
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
        if isTracking, let recentLocation = self.lastLocation {
            PTNSLogConsole("⚡️ [单次定位] 当前正在连续定位，直接返回最新缓存位置")
            completion(recentLocation)
            return
        }
        PTNSLogConsole("📡 [单次定位] 正在唤醒 GPS 硬件获取最新单次位置...")
        locationManager.requestLocation(withReGeocode: false, completionBlock: { (location, reGeocode, error) in
            if let error = error {
                PTNSLogConsole("❌ [单次定位] 获取防盗位置失败: \(error.localizedDescription)")
                completion(nil)
            } else {
                if let validLocation = location {
                    PTNSLogConsole("✅ [单次定位] 获取成功: 纬度 \(validLocation.coordinate.latitude), 经度 \(validLocation.coordinate.longitude)")
                    // 顺手更新一下全局缓存
                    self.lastLocation = validLocation
                    completion(validLocation)
                } else {
                    completion(nil)
                }
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
        lastLocation = nil
    }
    
    public func amapEmulatorNavi(naviLocation: AMapNaviLocation,roadName:String) {
        
        if let location = naviLocation.coordinate {
            let newLocation = CLLocation(coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude), altitude: naviLocation.altitude, horizontalAccuracy: naviLocation.accuracy, verticalAccuracy: naviLocation.accuracy, course: naviLocation.accuracy, speed: CLLocationSpeed(naviLocation.speed), timestamp: naviLocation.timestamp)
            self.lastLocation = newLocation
            setTripData(location: newLocation, roadName: roadName.isEmpty ? "Unknown" : roadName)
            setHeadingData(heading: naviLocation.heading, altitude: naviLocation.altitude)
        }
    }
    
    func setTripData(location: CLLocation,roadName:String) {
        // 天气状态统一在主 actor 上串行处理，避免定位回调与重试任务并发修改状态。
        // El estado meteorológico se serializa en MainActor para evitar carreras entre ubicación y reintentos.
        Task { @MainActor in
            PTWeatherManager.shared.fetchCurrentWeather(for: location)
        }
        
        if currentMode == .antiTheft {
            return
        }

        if PTDashboardConfig.shared.blueConnected {
            let now = Date()
            let shouldUpdateWidget: Bool

            if let lastTime = lastWidgetUpdateTime {
                // 计算距离上次更新过去了几秒 (10分钟 = 600秒)
                shouldUpdateWidget = now.timeIntervalSince(lastTime) >= 600.0
            } else {
                // 首次连接或刚启动时，直接允许更新
                shouldUpdateWidget = true
            }

            if shouldUpdateWidget {
                // 刷新时间戳记录
                lastWidgetUpdateTime = now

                // 获取最新的机车数据
                let currentFuel = PTBluetoothServerManager.shared.latestData1?.fuelLevelPct ?? 0
                let currentTrip = PTBluetoothServerManager.shared.latestData1?.tripKm ?? 0
                let isConnected = PTDashboardConfig.shared.blueConnected

                // 🚨 核心修复：安全解包！
                let safeAddress = roadName

                // 调用数据管理器，推送到小组件！
                PTWidgetDataManager.shared.updateWidgetData(
                    fuelLevel: currentFuel,
                    tripKm: currentTrip,
                    isConnected: isConnected,
                    parkedLat: location.coordinate.latitude,
                    parkedLon: location.coordinate.longitude,
                    address: safeAddress
                )

                PTNSLogConsole("⏱️ [小组件同步] 10分钟定时刷新触发成功，当前位置：\(safeAddress)")
            }
        }

        currentAltitude = location.altitude
        
        let currentSpeedKmh = max(0, location.speed * 3.6)
        let validCourse = (location.course >= 0) ? location.course : currentHeading
        PTLocalIntercomManager.shared.broadcastMyLocation(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            course: validCourse,
            speed: currentSpeedKmh
        )

        let tripData = PTTripData(
            courseDegree: location.course,
            altitude: location.altitude,
            currentLocation: location
        )

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: PTLocationEngineDidUpdate, object: tripData)
        }
    }
    
    func setHeadingData(heading:Double,altitude:Double) {
        currentHeading = heading
        currentAltitude = altitude
        
        // 低速状态下主动刷新 UI 指南针
        if (lastLocation != nil) {
            let speed = max(0, (lastLocation?.speed ?? 0) * 3.6)
            if speed < 5.0 {
                let tripData = PTTripData(
                    courseDegree: currentHeading,
                    altitude: currentAltitude,
                    currentLocation: self.lastLocation
                )
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: PTLocationEngineDidUpdate, object: tripData)
                }
            }
        }
    }
    
    // MARK: - 高德地图位置更新回调
    public func amapLocationManager(_ manager: AMapLocationManager!, didUpdate location: CLLocation!, reGeocode: AMapLocationReGeocode!) {
        // 1. 确保定位数据存在
        guard let location = location else { return }
        self.lastLocation = location
        setTripData(location: location, roadName: reGeocode?.formattedAddress ?? "Unknown")
    }
    
    // MARK: - 高德地图方向 (罗盘) 回调
    public func amapLocationManager(_ manager: AMapLocationManager!, didUpdate newHeading: CLHeading!) {
        guard let newHeading = newHeading, newHeading.headingAccuracy >= 0 else { return }
        setHeadingData(heading: newHeading.trueHeading > 0 ? newHeading.trueHeading : newHeading.magneticHeading, altitude: currentAltitude)
    }
    
    // MARK: - 错误处理
    public func amapLocationManager(_ manager: AMapLocationManager!, didFailWithError error: Error!) {
        PTNSLogConsole("❌ [PTLocationEngine] 引擎定位失败: \(error.localizedDescription)")
    }
    
    // MARK: - 小组件状态补救
    /// 车辆断开连接时，强制将最后的缓存数据推送到小组件
    public func forceUpdateWidgetOnDisconnect() {
        // 1. 获取最后一次有效的 GPS 位置
        let lat = lastLocation?.coordinate.latitude ?? 0.0
        let lon = lastLocation?.coordinate.longitude ?? 0.0
        
        // 2. 从蓝牙数据单例中抓取最后一次记录的仪表盘数据
        let finalFuel = PTBluetoothServerManager.shared.latestData1?.fuelLevelPct ?? 0
        let finalTrip = PTBluetoothServerManager.shared.latestData1?.tripKm ?? 0
        
        // 3. 强制推送给小组件管理器 (此时 isConnected 传 false，代表已停车)
        // 地址暂传 "停车打卡中..."，因为逆地理编码需要网络时间
        PTWidgetDataManager.shared.updateWidgetData(
            fuelLevel: finalFuel,
            tripKm: finalTrip,
            isConnected: false,
            parkedLat: lat,
            parkedLon: lon,
            address: PTDashboardConfig.languageFunc(text: "停车定位已更新")
        )
        
        PTNSLogConsole("✅ [小组件同步] 蓝牙已断开，成功强制推送最终骑行数据到小组件！")
    }
}

extension PTLocationEngine:AMapSearchDelegate {
    public func onReGeocodeSearchDone(_ request: AMapReGeocodeSearchRequest!, response: AMapReGeocodeSearchResponse!) {
        guard let regeocode = response.regeocode else { return }
        
        let fullAddress = regeocode.formattedAddress ?? "未知街道"
        
        // 2. 提取经纬度
        let lat = request.location.latitude
        let lon = request.location.longitude
        
        // 获取最新的机车数据 (这取决于你的业务逻辑保存在哪里)
        let currentFuel = PTBluetoothServerManager.shared.latestData1?.fuelLevelPct ?? 0
        let currentTrip = PTBluetoothServerManager.shared.latestData1?.tripKm ?? 0 // 替换为真实的 PTDashboardData1 小计里程
        let isConnected = PTDashboardConfig.shared.blueConnected // 或蓝牙状态
        
        // 🌟 3. 调用数据管理器，推送到小组件！
        PTWidgetDataManager.shared.updateWidgetData(
            fuelLevel: currentFuel,
            tripKm: currentTrip,
            isConnected: isConnected,
            parkedLat: Double(lat),
            parkedLon: Double(lon),
            address: fullAddress
        )
    }
}
