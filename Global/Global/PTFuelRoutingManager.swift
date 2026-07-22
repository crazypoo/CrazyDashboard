//
//  PTFuelRoutingManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 23/7/2026.
//

import Foundation
import CoreLocation
import AMapSearchKit
import PooTools

// 🚨 新增：定义一个新的广播通知，专门用于唤起 UI 的手动确认
public let MotorcycleLowFuelActionRequired = NSNotification.Name("MotorcycleLowFuelActionRequired")

@objcMembers
public class PTFuelRoutingManager: NSObject, AMapSearchDelegate {
    
    public static let shared = PTFuelRoutingManager()
    
    private let lowFuelThreshold: Int = 15
    private var hasTriggeredLowFuel: Bool = false
    private lazy var searchAPI: AMapSearchAPI = {
        let api = AMapSearchAPI()
        api?.delegate = self
        return api!
    }()
    private var currentLocationForSearch: CLLocation?
    
    // 🚨 新增：用于暂存即将发送的导航指令，等待骑手点击确认
    private var pendingGasStationNavInfo: PTNavigationInfo?
    
    private override init() {
        super.init()
        setupObservers()
    }
    
    private func setupObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleData1(_:)), name: MotorcycleDATA1, object: nil)
        nc.addObserver(self, selector: #selector(resetFuelState), name: BLEConnectSuccess, object: nil)
    }
    
    @objc private func resetFuelState() {
        hasTriggeredLowFuel = false
        pendingGasStationNavInfo = nil // 重置缓存
    }
    
    @objc private func handleData1(_ notification: Notification) {
        guard let data1 = notification.object as? PTDashboardData1 else { return }
        
        if data1.fuelLevelPct <= lowFuelThreshold && !hasTriggeredLowFuel {
            hasTriggeredLowFuel = true
            PTNSLogConsole("⚠️ [加油管家] 检测到低油量 (\(data1.fuelLevelPct)%)，启动后台搜寻...")
            startSearchingNearbyGasStation()
        }
    }
    
    private func startSearchingNearbyGasStation() {
        // 复用高德单次定位
        PTMOTOParkingManager.shared.requestSingleLocationForAntiTheft { [weak self] location in
            guard let self = self, let currentLoc = location else { return }
            self.currentLocationForSearch = currentLoc
            
            let request = AMapPOIAroundSearchRequest()
            request.location = AMapGeoPoint.location(withLatitude: CGFloat(currentLoc.coordinate.latitude),
                                                     longitude: CGFloat(currentLoc.coordinate.longitude))
            request.keywords = "加油站"
            request.sortrule = 0
            request.radius = 10000
            
            self.searchAPI.aMapPOIAroundSearch(request)
        }
    }
    
    public func onPOISearchDone(_ request: AMapPOISearchBaseRequest!, response: AMapPOISearchResponse!) {
        guard let pois = response.pois, let nearestStation = pois.first, let currentLoc = currentLocationForSearch else {
            return
        }
        
        let stationName = nearestStation.name ?? "未知加油站"
        let stationLoc = CLLocation(latitude: CLLocationDegrees(nearestStation.location.latitude),
                                    longitude: CLLocationDegrees(nearestStation.location.longitude))
        let distanceMeters = currentLoc.distance(from: stationLoc)
        
        // 组装协议帧，但【不立即发送】
        let navInfo = PTNavigationInfo(
            nextManeuver: PTManeuverMap.straight,
            metersToNextManeuver: UInt32(distanceMeters),
            nameNextRoad: "前往: \(stationName)",
            nameCurrentRoad: "⚠️ 燃油告急",
            currentSpeedLimit: 0,
            distanceToDestination: UInt32(distanceMeters),
            estimatedTimeToDestinationSec: Int(distanceMeters / (40.0 * 1000.0 / 3600.0))
        )
        
        // 🚨 核心逻辑：缓存指令，并通过通知将文字推给 UI
        self.pendingGasStationNavInfo = navInfo
        let promptText = "油量告急，点击导航至: \(stationName) (\(Int(distanceMeters))米)"
        
        NotificationCenter.default.post(name: MotorcycleLowFuelActionRequired, object: promptText)
        PTNSLogConsole("⛽️ [加油管家] 已找到加油站，正在等待骑手手动确认...")
    }
    
    public func aMapSearchRequest(_ request: Any!, didFailWithError error: Error!) {
        PTNSLogConsole("❌ [加油管家] 搜索失败: \(error.localizedDescription)")
    }
    
    // MARK: - 🚨 暴露给 UI 调用的确认接口
    /// 当骑手在 HUD 上点击了提示容器后，调用此方法真正下发导航
    public func confirmAndSendGasStationRoute() {
        guard let navInfo = pendingGasStationNavInfo else {
            PTNSLogConsole("⚠️ [加油管家] 没有缓存的救援路线可发送")
            return
        }
        
        // 真正下发给摩托车
        PTBluetoothServerManager.shared.sendNavigation(info: navInfo)
        // 发送完毕后清空缓存
        pendingGasStationNavInfo = nil
        
        PTNSLogConsole("🚀 [加油管家] 骑手已确认！救援路线成功下发至仪表盘！")
    }
}
