//
//  PTMOTOParkingManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 22/7/2026.
//

import UIKit
import PooTools

class PTMOTOParkingManager: NSObject {
    public static let shared = PTMOTOParkingManager()
        
    private override init() {
        super.init()
    }
    
    // MARK: - 核心方法：后台保存停车位置
    public func saveCurrentLocationAsParkingSpot() {
        // 策略 2：如果没有缓存位置，立刻请求单次定位（系统会在后台分配短暂时间执行此操作）
        PTLocationEngine.shared.saveCurrentLocationAsParkingSpot()
    }
    
    // MARK: - 读取和清理方法
    /// 获取上次停车的坐标
    public func getLastParkedLocation() -> CLLocationCoordinate2D? {
        return PTLocationEngine.shared.getLastParkedLocation()
    }
    
    /// 清除停车记录 (例如骑手重新启动车辆时)
    public func clearParkingSpot() {
        PTLocationEngine.shared.clearParkingSpot()
    }
    
    // MARK: - 🚨 新增：专供防盗系统使用的后台单次快速定位
    /// 请求单次高精度定位 (带超时机制，非常适合后台断连瞬间的抓取)
    public func requestSingleLocationForAntiTheft(completion: @escaping (CLLocation?) -> Void) {
        PTLocationEngine.shared.requestSingleLocationForAntiTheft(completion: completion)
    }
}
