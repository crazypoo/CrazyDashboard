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

// MARK: - 1. 字符串扩展：摩托车仪表盘 ASCII 兼容处理
extension String {
    /// 将包含中文的字符串转换为无声调的拼音，并自动优化常用导航词汇为英文
    func toMotorcycleCompatiblePinyin() -> String {
        let mutableString = NSMutableString(string: self)
        
        // 1. 汉字转带声调拉丁字母
        CFStringTransform(mutableString, nil, kCFStringTransformToLatin, false)
        // 2. 剥离声调
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        
        var result = String(mutableString)
        
        // 3. 常用导航术语与路名的体验优化字典
        let optimizeDictionary: [String: String] = [
            "dao da": "Arrive",
            "zhong dian": "Destination",
            "zhi xing": "Straight",
            "ji xu": "Continue",
            "zuo zhuan": "Turn Left",
            "xiang zuo": "Turn Left",
            "you zhuan": "Turn Right",
            "xiang you": "Turn Right",
            "diao tou": "U-Turn",
            "kao zuo": "Keep Left",
            "kao you": "Keep Right",
            "da dao": "Blvd",
            "lu": "Rd",
            "jie": "St",
            "qiao": "Bridge"
        ]
        
        // 4. 执行关键词英文润色
        for (pinyin, english) in optimizeDictionary {
            result = result.replacingOccurrences(of: pinyin, with: english, options: .caseInsensitive)
        }
        
        return result
    }
}

// MARK: - 2. 核心导航助手类
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
    
    // MARK: - 导航控制
    
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
        request.transportType = .automobile // 摩托车通常使用汽车路线计算
        
        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            guard let route = response?.routes.first, error == nil else {
                PTProgressHUD.show(text: "❌ 路线规划失败: \(error?.localizedDescription ?? "未知错误")")
                return
            }
            
            PTProgressHUD.show(text: "✅ 路线规划成功！总距: \(route.distance)m, 耗时: \(Int(route.expectedTravelTime))s")
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
        // 可以在这里发送一个断开导航或清空仪表盘的蓝牙指令
    }
    
    // MARK: - 核心转换：提取 MapKit 数据给摩托车
    
    /// 根据当前位置和路线，生成发送给车机的数据模型
    private func buildNavigationInfo(currentLocation: CLLocation) -> PTNavigationInfo? {
        guard let route = currentRoute, currentStepIndex < route.steps.count else { return nil }
        
        let currentStep = route.steps[currentStepIndex]
        
        // 1. 判断是否需要切换到下一个指令 (距离目标点小于 15 米则认为已通过)
        let stepCoordinate = currentStep.polyline.coordinate
        let stepLocation = CLLocation(latitude: stepCoordinate.latitude, longitude: stepCoordinate.longitude)
        let distanceToNextTurn = currentLocation.distance(from: stepLocation)
        
        // 步进逻辑：如果距离下一转弯点足够近，且不是最后一步，则切换到下一指令
        if distanceToNextTurn < 15 && currentStepIndex < route.steps.count - 1 {
            currentStepIndex += 1
            return buildNavigationInfo(currentLocation: currentLocation)
        }
        
        // 2. 提取文本指令并安全地转换为拼音/英文
        let rawNextRoad = currentStep.instructions
        let nextRoadSafeText = rawNextRoad.toMotorcycleCompatiblePinyin()
        let currentRoadSafeText = "Navigating" // 可以通过逆地理编码获取当前路名，这里为了性能直接使用固定英文
        
        // 3. 提取转弯图标码 (传入原始中文或英文进行匹配)
        let maneuverCode = mapInstructionToManeuverCode(instruction: rawNextRoad)
        
        // 4. 计算剩余总距离和时间
        var remainingDistance = distanceToNextTurn
        for i in (currentStepIndex + 1)..<route.steps.count {
            remainingDistance += route.steps[i].distance
        }
        
        let totalDistance = route.distance
        let progress = 1.0 - (remainingDistance / totalDistance)
        let remainingTimeSec = Int(route.expectedTravelTime * (1.0 - progress))
        
        // 5. 组装最终发给摩托车的数据 (严格确保不含中文字符)
        let info = PTNavigationInfo(
            nextManeuver: maneuverCode,
            metersToNextManeuver: UInt32(max(0, distanceToNextTurn)),
            nameNextRoad: nextRoadSafeText,
            nameCurrentRoad: currentRoadSafeText,
            currentSpeedLimit: 50, // MapKit SDK 无法直接提供限速，默认给 50
            distanceToDestination: UInt32(max(0, remainingDistance)),
            estimatedTimeToDestinationSec: max(0, remainingTimeSec)
        )
        
        return info
    }
    
    // MARK: - 转弯指令图标签译
    
    /// 将 MapKit 的中文/英文文本指令转换为摩托车仪表盘的枚举代码
    private func mapInstructionToManeuverCode(instruction: String) -> UInt8 {
        let text = instruction.lowercased()
        
        if text.contains("straight") || text.contains("continue") || text.contains("keep on") ||
           text.contains("直行") || text.contains("继续") {
            return PTManeuverMap.straight
        }
        else if text.contains("u-turn") || text.contains("掉头") {
            return PTManeuverMap.uTurnLeft // 国内一般是左掉头
        }
        else if text.contains("keep left") || text.contains("靠左") {
            return PTManeuverMap.keepLeft
        }
        else if text.contains("keep right") || text.contains("靠右") {
            return PTManeuverMap.keepRight
        }
        else if text.contains("slight left") || text.contains("左前方") || text.contains("偏左") {
            return PTManeuverMap.lightLeft
        }
        else if text.contains("slight right") || text.contains("右前方") || text.contains("偏右") {
            return PTManeuverMap.lightRight
        }
        else if text.contains("turn left") || text.contains("left") || text.contains("左转") || text.contains("向左") {
            return PTManeuverMap.quiteLeft
        }
        else if text.contains("turn right") || text.contains("right") || text.contains("右转") || text.contains("向右") {
            return PTManeuverMap.quiteRight
        }
        else if text.contains("arrive") || text.contains("destination") || text.contains("到达") || text.contains("终点") {
            return PTManeuverMap.arrive
        }
        
        return PTManeuverMap.straight // 默认直行
    }
}

// MARK: - 3. CoreLocation 代理实现
extension PTMapKitNavigationHelper: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isNavigating, let currentLocation = locations.last else { return }
        
        // 当 GPS 位置更新时，生成最新的导航数据包
        if let navInfo = buildNavigationInfo(currentLocation: currentLocation) {
            
            // 可视化调试日志，方便开发时确认生成的数据
            PTProgressHUD.show(text: "🚀 导航更新 -> 动作: \(navInfo.nextManeuver), 距离: \(navInfo.metersToNextManeuver)m, 下一条路: \(navInfo.nameNextRoad)")
            
            // 核心调用：通过蓝牙基站将纯净的导航数据发送给摩托车！
            PTBluetoothServerManager.shared.sendNavigation(info: navInfo)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}
