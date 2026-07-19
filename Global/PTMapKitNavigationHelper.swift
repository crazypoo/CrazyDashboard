//
//  PTMapKitNavigationHelper.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 19/7/2026.
//

import UIKit
import MapKit
import CoreLocation
import PooTools

class PTMapKitNavigationHelper: NSObject {
    
    static let shared = PTMapKitNavigationHelper()
    
    private let locationManager = CLLocationManager()
    
    // 当前导航状态
    private var currentRoute: MKRoute?
    private var currentStepIndex: Int = 0
    private var isNavigating: Bool = false
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5 // 每移动 5 米更新一次
    }
    
    /// 开始导航到指定坐标
    func startNavigation(to destinationCoordinate: CLLocationCoordinate2D) {
        guard let currentLocation = locationManager.location else {
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
            PTProgressHUD.show(text: "正在获取当前位置...")
            return
        }
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destinationCoordinate))
        request.transportType = .automobile // 摩托车通常使用汽车路线
        
        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            guard let route = response?.routes.first, error == nil else {
                PTProgressHUD.show(text: "❌ 路线规划失败: \(error?.localizedDescription ?? "未知错误")")
                return
            }
            
            PTProgressHUD.show(text: "✅ 路线规划成功！总距离: \(route.distance)米，预计耗时: \(route.expectedTravelTime)秒")
            self?.currentRoute = route
            self?.currentStepIndex = 0 // 从第一个动作开始 (通常是起步)
            self?.isNavigating = true
            
            // 开启实时定位跟踪
            self?.locationManager.startUpdatingLocation()
        }
    }
    
    /// 停止导航
    func stopNavigation() {
        isNavigating = false
        locationManager.stopUpdatingLocation()
        currentRoute = nil
    }
    
    // MARK: - 核心转换：提取 MapKit 数据给摩托车
    
    /// 根据当前位置和路线，生成发送给车机的数据模型
    private func buildNavigationInfo(currentLocation: CLLocation) -> PTNavigationInfo? {
        guard let route = currentRoute, currentStepIndex < route.steps.count else { return nil }
        
        let currentStep = route.steps[currentStepIndex]
        
        // 1. 判断是否需要切换到下一个指令 (简单逻辑：距离目标点小于 15 米则认为已通过)
        // 实际开发中，需要更复杂的坐标系投影判断，这里用最简单的距离逼近法
        let stepCoordinate = currentStep.polyline.coordinate
        let stepLocation = CLLocation(latitude: stepCoordinate.latitude, longitude: stepCoordinate.longitude)
        let distanceToNextTurn = currentLocation.distance(from: stepLocation)
        
        if distanceToNextTurn < 15 && currentStepIndex < route.steps.count - 1 {
            currentStepIndex += 1 // 进入下一个指令
            return buildNavigationInfo(currentLocation: currentLocation)
        }
        
        // 2. 提取下一条道路名称和当前道路名称
        // MapKit 并不直接区分当前路和下一条路，通常 step.instructions 就是下一条路的提示
        let nextRoad = currentStep.instructions
        let currentRoad = "导航中" // 或者使用 CLGeocoder 逆地理编码获取当前路名
        
        // 3. 将 MapKit 文字指令转为摩托车的转弯图标码
        let maneuverCode = mapInstructionToManeuverCode(instruction: currentStep.instructions)
        
        // 4. 计算剩余总距离和时间 (减去已经走过的步骤)
        var remainingDistance = distanceToNextTurn
        for i in (currentStepIndex + 1)..<route.steps.count {
            remainingDistance += route.steps[i].distance
        }
        
        // 简单的剩余时间估算 (假设平均速度，或按照总时间比例)
        let totalDistance = route.distance
        let progress = 1.0 - (remainingDistance / totalDistance)
        let remainingTimeSec = Int(route.expectedTravelTime * (1.0 - progress))
        
        // 5. 组装最终发给摩托车的数据
        let info = PTNavigationInfo(
            nextManeuver: maneuverCode,
            metersToNextManeuver: UInt32(max(0, distanceToNextTurn)),
            nameNextRoad: nextRoad,
            nameCurrentRoad: currentRoad,
            currentSpeedLimit: 50, // MapKit 无法直接提供，默认 50
            distanceToDestination: UInt32(max(0, remainingDistance)),
            estimatedTimeToDestinationSec: max(0, remainingTimeSec)
        )
        
        return info
    }
    
    // 关键字匹配器：将文字翻译成车机图标
    private func mapInstructionToManeuverCode(instruction: String) -> UInt8 {
        let text = instruction.lowercased()
        
        if text.contains("直行") || text.contains("继续") {
            return PTManeuverMap.straight
        } else if text.contains("左转") || text.contains("向左") {
            return PTManeuverMap.quiteLeft
        } else if text.contains("右转") || text.contains("向右") {
            return PTManeuverMap.quiteRight
        } else if text.contains("掉头") {
            return PTManeuverMap.uTurnLeft // 国内一般是左掉头
        } else if text.contains("到达") || text.contains("终点") {
            return PTManeuverMap.arrive
        }
        
        return PTManeuverMap.straight // 默认直行
    }
}

// MARK: - CLLocationManagerDelegate
extension PTMapKitNavigationHelper: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isNavigating, let currentLocation = locations.last else { return }
        
        // 当 GPS 位置更新时，生成最新的导航数据包
        if let navInfo = buildNavigationInfo(currentLocation: currentLocation) {
            
            // 打印调试信息
            PTProgressHUD.show(text: "🚀 更新导航 -> 动作: \(navInfo.nextManeuver), 距离转弯: \(navInfo.metersToNextManeuver)m, 下一条路: \(navInfo.nameNextRoad), 剩余总距: \(navInfo.distanceToDestination)m")
            
            // 核心调用：通过你之前写的蓝牙基站发送给摩托车！
            PTBluetoothServerManager.shared.sendNavigation(info: navInfo)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}
