//
//  PTCustomRouteManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 23/7/2026.
//

import Foundation
import CoreLocation
import PooTools

/// 巡航节点模型
public struct PTCruiseWaypoint {
    public let coordinate: CLLocationCoordinate2D
    public let instruction: String // 将显示在仪表盘上的自定义文本（最多 50 字节）
    public let maneuverCode: UInt8 // 转向图标代码（复用 PTManeuverMap）
}

/// 自定义巡航路线分发引擎
@objcMembers
public class PTCustomRouteManager: NSObject {
    
    public static let shared = PTCustomRouteManager()
    
    // 当前激活的巡航路线
    private var activeRoute: [PTCruiseWaypoint] = []
    // 当前正前往的节点索引
    private var currentTargetIndex: Int = 0
    private var isCruising: Bool = false
    
    private override init() {
        super.init()
    }
    
    /// 加载一条自定义路线并开始巡航
    public func startCruise(route: [PTCruiseWaypoint]) {
        guard !route.isEmpty else { return }
        self.activeRoute = route
        self.currentTargetIndex = 0
        self.isCruising = true
        PTNSLogConsole("🗺️ [巡航引擎] 成功加载路线，共 \(route.count) 个节点，开始巡航！")
    }
    
    public func stopCruise() {
        self.isCruising = false
        self.activeRoute.removeAll()
        PTNSLogConsole("🗺️ [巡航引擎] 巡航已结束。")
    }
    
    /// 将此方法接入你的高德定位回调 (amapLocationManager:didUpdate:reGeocode:) 中
    public func processCurrentLocation(_ currentLocation: CLLocation) {
        guard isCruising, currentTargetIndex < activeRoute.count else { return }
        
        let targetWaypoint = activeRoute[currentTargetIndex]
        let targetLocation = CLLocation(latitude: targetWaypoint.coordinate.latitude,
                                        longitude: targetWaypoint.coordinate.longitude)
        
        // 计算距离
        let distance = currentLocation.distance(from: targetLocation)
        
        // 组装要发送给仪表盘的导航数据
        let navInfo = PTNavigationInfo(
            nextManeuver: targetWaypoint.maneuverCode,
            metersToNextManeuver: UInt32(distance),
            nameNextRoad: targetWaypoint.instruction, // 🚨 核心：将路名替换为自定义指令
            nameCurrentRoad: "自定义巡航模式",
            currentSpeedLimit: 0,
            distanceToDestination: UInt32(distance), // 这里简化为到当前节点的距离
            estimatedTimeToDestinationSec: Int(distance / 10.0) // 粗略估算到达时间
        )
        
        // 发送给摩托车仪表盘
        PTBluetoothServerManager.shared.sendNavigation(info: navInfo)
        
        // 当距离小于 30 米时，认为已到达该节点，自动切换到下一个节点
        if distance < 30.0 {
            PTNSLogConsole("✅ [巡航引擎] 已到达节点：\(targetWaypoint.instruction)")
            currentTargetIndex += 1
            
            if currentTargetIndex >= activeRoute.count {
                PTNSLogConsole("🎉 [巡航引擎] 路线全部完成！")
                stopCruise()
            }
        }
    }
}
