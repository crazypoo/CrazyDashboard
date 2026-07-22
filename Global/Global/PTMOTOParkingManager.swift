//
//  PTMOTOParkingManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 22/7/2026.
//

import UIKit
import AMapLocationKit
import PooTools

class PTMOTOParkingManager: NSObject {
    public static let shared = PTMOTOParkingManager()
    
    private lazy var locationManager:AMapLocationManager = {
        let manager = AMapLocationManager()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        return manager
    }()

    // 用于 UserDefaults 的存储 Key
    private let parkingLatKey = "PTLastParkedLatitude"
    private let parkingLonKey = "PTLastParkedLongitude"
    
    private override init() {
        super.init()
    }
    
    // MARK: - 核心方法：后台保存停车位置
    public func saveCurrentLocationAsParkingSpot() {
        // 策略 2：如果没有缓存位置，立刻请求单次定位（系统会在后台分配短暂时间执行此操作）
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    // MARK: - 读取和清理方法
    /// 获取上次停车的坐标
    public func getLastParkedLocation() -> CLLocationCoordinate2D? {
        let lat = UserDefaults.standard.double(forKey: parkingLatKey)
        let lon = UserDefaults.standard.double(forKey: parkingLonKey)
        
        if lat != 0.0 && lon != 0.0 {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return nil
    }
    
    /// 清除停车记录 (例如骑手重新启动车辆时)
    public func clearParkingSpot() {
        UserDefaults.standard.removeObject(forKey: parkingLatKey)
        UserDefaults.standard.removeObject(forKey: parkingLonKey)
    }
    
    // MARK: - 私有存储方法
    private func persistLocation(_ location: CLLocation) {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        
        UserDefaults.standard.set(lat, forKey: parkingLatKey)
        UserDefaults.standard.set(lon, forKey: parkingLonKey)
        
        PTNSLogConsole("📍 [停车打卡] 成功在后台/锁屏状态保存车辆位置: 纬度 \(lat), 经度 \(lon)")
        locationManager.stopUpdatingHeading()
        locationManager.startUpdatingLocation()
    }
    
    // MARK: - 🚨 新增：专供防盗系统使用的后台单次快速定位
    /// 请求单次高精度定位 (带超时机制，非常适合后台断连瞬间的抓取)
    public func requestSingleLocationForAntiTheft(completion: @escaping (CLLocation?) -> Void) {
        // 使用高德提供的单次定位 API，不带逆地理编码以追求极速响应
        locationManager.requestLocation(withReGeocode: false, completionBlock: { (location, reGeocode, error) in
            if let error = error {
                PTNSLogConsole("❌ [单次定位] 获取手机当前位置失败: \(error.localizedDescription)")
                completion(nil)
            } else {
                completion(location)
            }
        })
    }
}

extension PTMOTOParkingManager:AMapLocationManagerDelegate {
    func amapLocationManager(_ manager: AMapLocationManager!, doRequireLocationAuth locationManager: CLLocationManager!) {
        locationManager.requestAlwaysAuthorization()
    }
    
    func amapLocationManager(_ manager: AMapLocationManager!, didChange status: CLAuthorizationStatus) {
    }
    
    func amapLocationManager(_ manager: AMapLocationManager!, didFailWithError error: (any Error)!) {
        PTNSLogConsole("❌ [停车打卡] 后台请求位置失败: \(error.localizedDescription)")
    }
    
    func amapLocationManager(_ manager: AMapLocationManager!, didUpdate location: CLLocation!, reGeocode: AMapLocationReGeocode!) {
        persistLocation(location)
    }
}
