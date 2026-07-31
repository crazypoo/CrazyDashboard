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
public let MotorcycleStartRealNavigation = NSNotification.Name("MotorcycleStartRealNavigation")

@objcMembers
public class PTFuelRoutingManager: NSObject, AMapSearchDelegate {
    
    public static let shared = PTFuelRoutingManager()
    
    private var findFuelStationSelf:Bool = false
    private let lowFuelThreshold: Int = 15
    private var hasTriggeredLowFuel: Bool = false
    private lazy var searchAPI: AMapSearchAPI = {
        let api = AMapSearchAPI()
        api?.delegate = self
        return api!
    }()
    private var currentLocationForSearch: CLLocation?
    
    // 🚨 新增：用于暂存即将发送的导航指令，等待骑手点击确认
    private var pendingGasStationCoordinate: CLLocationCoordinate2D?
    private var pendingGasStationName: String?
    
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
        pendingGasStationCoordinate = nil
        pendingGasStationName = nil
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
        PTLocationEngine.shared.switchEngineMode(to: .riding)
        if !PTDashboardConfig.shared.blueConnected {
            PTLocationEngine.shared.startTracking()
        }
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
        let stationLoc = CLLocationCoordinate2D(latitude: CLLocationDegrees(nearestStation.location.latitude),
                                                longitude: CLLocationDegrees(nearestStation.location.longitude))
        let distanceMeters = currentLoc.distance(from: CLLocation(latitude: stationLoc.latitude, longitude: stationLoc.longitude))
        
        // 🚨 核心逻辑：缓存真实坐标，推送纯文本给 UI 或 HUD
        self.pendingGasStationCoordinate = stationLoc
        self.pendingGasStationName = stationName
        
        let promptText = "油量告急，点击导航至: \(stationName) (\(Int(distanceMeters))米)"
        
        PTNSLogConsole("⛽️ [加油管家] 已找到加油站，正在等待骑手手动确认...")
        if findFuelStationSelf {
            guard let coordinate = pendingGasStationCoordinate, let name = pendingGasStationName else {
                PTNSLogConsole("⚠️ [加油管家] 没有缓存的救援坐标可发送")
                return
            }
            
            // 🚨 完美衔接：发送全局通知，把坐标和名字丢给高德导航引擎去真实规划！
            
            if let vc = PTUtils.getCurrentVC() as? PTMotoBaseViewController,let tabbar = vc.tabBarController as? PTMotoBaseTabbarController {
                tabbar.ptCustomBar.select(1)
                PTGCDManager.shared.delayOnMain(time: 0.55, block: {
                    let targetDict: [String: Any] = ["coordinate": coordinate, "title": name]
                    NotificationCenter.default.post(name: MotorcycleStartRealNavigation, object: targetDict)
                })
            }
            
            // 发送完毕后清空缓存
            pendingGasStationCoordinate = nil
            pendingGasStationName = nil
            findFuelStationSelf = false
            PTNSLogConsole("🚀 [加油管家] 骑手已确认！已唤醒高德地图真实导航引擎！")
        }
    }
    
    public func aMapSearchRequest(_ request: Any!, didFailWithError error: Error!) {
        PTNSLogConsole("❌ [加油管家] 搜索失败: \(error.localizedDescription)")
    }
    
    // MARK: - 🚨 暴露给 UI 调用的确认接口
    /// 当骑手在 HUD 上点击了提示容器后，调用此方法真正下发导航
    public func confirmAndSendGasStationRoute() {
        findFuelStationSelf = true
        startSearchingNearbyGasStation()
    }
}
