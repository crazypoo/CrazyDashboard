//
//  PTLocationEngine.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 7/6/2026.
//

import Foundation
import AMapLocationKit // 🌟 引入高德定位 SDK
import PooTools
import AMapSearchKit

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
    private var lastLocation: CLLocation?

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
        lastLocation = nil
    }
    
    // MARK: - 高德地图位置更新回调
    public func amapLocationManager(_ manager: AMapLocationManager!, didUpdate location: CLLocation!, reGeocode: AMapLocationReGeocode!) {
        guard let location = location else { return }
        self.lastLocation = location
        PTWeatherManager.shared.fetchCurrentWeather(for: location)
        if currentMode == .antiTheft {
            return
        }
        
        currentAltitude = location.altitude
        let tripData = PTTripData(
            courseDegree: location.course,
            altitude: location.altitude,
            currentLocation: location
        )
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: PTLocationEngineDidUpdate, object: tripData)
        }
    }
    
    // MARK: - 高德地图方向 (罗盘) 回调
    public func amapLocationManager(_ manager: AMapLocationManager!, didUpdate newHeading: CLHeading!) {
        guard let newHeading = newHeading, newHeading.headingAccuracy >= 0 else { return }
        
        currentHeading = newHeading.trueHeading > 0 ? newHeading.trueHeading : newHeading.magneticHeading
        
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
    
    // MARK: - 错误处理
    public func amapLocationManager(_ manager: AMapLocationManager!, didFailWithError error: Error!) {
        PTNSLogConsole("❌ [PTLocationEngine] 引擎定位失败: \(error.localizedDescription)")
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
