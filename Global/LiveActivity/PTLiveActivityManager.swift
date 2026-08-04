//
//  PTLiveActivityManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 30/7/2026.
//

import UIKit
import ActivityKit

public struct MotoNaviAttributes: ActivityAttributes {
    
    // 动态数据：随着高德导航回调不断刷新的数据
    public struct ContentState: Codable, Hashable {
        public var progress: Double             // 导航进度 (0.0 到 1.0)
        public var remainingDistanceKm: Double  // 剩余距离 (公里)
        public var estimatedArrivalTime: Date     // 预估到达时间
    }

    // 静态数据：活动开启后就不会改变的数据
    public var destinationName: String
    
    public init(destinationName: String) {
        self.destinationName = destinationName
    }
}

@objcMembers
public class PTLiveActivityManager: NSObject {
    
    public static let shared = PTLiveActivityManager()
    
    // 保持对当前活动实例的引用
    private var currentNaviActivity: Activity<MotoNaviAttributes>?
    
    private override init() { super.init() }
    
    /// 开始导航 Live Activity
    public func startNavigationActivity(destination: String, expectedArrival: Date) {
        // 确保设备支持且用户未在系统设置中关闭权限
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let attributes = MotoNaviAttributes(destinationName: destination)
        // 初始状态
        let initialState = MotoNaviAttributes.ContentState(progress: 0, remainingDistanceKm: 0, estimatedArrivalTime: Date())
        
        do {
            // 请求开启实时活动
            let content = ActivityContent(state: initialState, staleDate: nil)
            currentNaviActivity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            print("🚀 [LiveActivity] 导航实时活动已成功开启！")
        } catch {
            print("❌ [LiveActivity] 开启失败: \(error.localizedDescription)")
        }
    }
    
    /// 刷新导航实时数据 (在 AMapNaviDriveManager 的回调中调用)
    public func updateNavigationActivity(progress: Double, remainingKm: Double, expectedArrival: Date) {
        guard let activity = currentNaviActivity else { return }
        
        let updatedState = MotoNaviAttributes.ContentState(
            progress: max(0.0, min(1.0, progress)), // 限制在 0~1 之间，防止 UI 溢出
            remainingDistanceKm: remainingKm,
            estimatedArrivalTime: expectedArrival
        )
        
        Task { @MainActor in
            let content = ActivityContent(state: updatedState, staleDate: nil)
            await activity.update(content, alertConfiguration: nil)
        }
    }

    /// 结束导航 Live Activity
    public func stopNavigationActivity() {
        guard let activity = currentNaviActivity else { return }
        Task {  @MainActor in
            // 立即结束并从锁屏移除
            await activity.end(activity.content, dismissalPolicy: .immediate)
            currentNaviActivity = nil
            print("🛑 [LiveActivity] 导航实时活动已结束。")
        }
    }
}
