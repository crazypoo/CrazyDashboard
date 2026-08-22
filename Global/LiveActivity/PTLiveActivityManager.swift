//
//  PTLiveActivityManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 30/7/2026.
//

import UIKit
import ActivityKit
import Foundation

//MRAK: NAV
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
    private var currentIntercomActivity: Activity<MotoIntercomAttributes>?
    private var intercomActivityGeneration = 0
    
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
    
    public func startIntercomActivity(channel: String) {
        // 保留旧 API，但零成员时不再创建 Activity。
        syncIntercomActivity(channel: channel, isTalking: false, status: "正在组网...", peers: [])
    }
    
    public func updateIntercomActivity(isTalking: Bool, status: String, peers: [PeerLiveState]) {
        syncIntercomActivity(channel: "机车通讯", isTalking: isTalking, status: status, peers: peers)
    }

    /// PTT Activity 的唯一同步入口：只有存在已连接成员时才允许显示。
    public func syncIntercomActivity(channel: String, isTalking: Bool, status: String, peers: [PeerLiveState]) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            self.intercomActivityGeneration += 1
            let generation = self.intercomActivityGeneration
            let existingActivities = Activity<MotoIntercomAttributes>.activities

            guard !peers.isEmpty else {
                self.currentIntercomActivity = nil
                for activity in existingActivities {
                    guard self.intercomActivityGeneration == generation else { return }
                    await activity.end(activity.content, dismissalPolicy: .immediate)
                }
                return
            }

            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            let activity: Activity<MotoIntercomAttributes>
            if let current = self.currentIntercomActivity,
               existingActivities.contains(where: { $0.id == current.id }) {
                activity = current
            } else if let existing = existingActivities.first {
                activity = existing
                self.currentIntercomActivity = existing
            } else {
                let attributes = MotoIntercomAttributes(channelName: channel)
                let initialState = MotoIntercomAttributes.ContentState(
                    isLocalTalking: isTalking,
                    statusText: status,
                    activePeers: peers
                )

                do {
                    let content = ActivityContent(state: initialState, staleDate: nil)
                    activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                    self.currentIntercomActivity = activity
                } catch {
                    print("❌ [LiveActivity] 对讲机开启失败: \(error.localizedDescription)")
                    return
                }
            }

            let duplicateActivities = existingActivities.filter { $0.id != activity.id }
            let updatedState = MotoIntercomAttributes.ContentState(
                isLocalTalking: isTalking,
                statusText: status,
                activePeers: peers
            )

            guard self.intercomActivityGeneration == generation else { return }
            let content = ActivityContent(state: updatedState, staleDate: nil)
            await activity.update(content, alertConfiguration: nil)
            for duplicate in duplicateActivities {
                guard self.intercomActivityGeneration == generation else { return }
                await duplicate.end(duplicate.content, dismissalPolicy: .immediate)
            }
        }
    }

    public func stopIntercomActivity() {
        syncIntercomActivity(channel: "机车通讯", isTalking: false, status: "", peers: [])
    }
}

//MARK: PTT
public struct PeerLiveState: Codable, Hashable {
    public var peerID: String
    public var peerName: String
    public var avatarFileName: String // 存放在 App Group 中的文件名，如果为空 ""，则使用系统默认头像
    public var isSpeaking: Bool       // 用来触发绿色光晕动画
    
    public init(peerID: String, peerName: String, avatarFileName: String, isSpeaking: Bool) {
        self.peerID = peerID
        self.peerName = peerName
        self.avatarFileName = avatarFileName
        self.isSpeaking = isSpeaking
    }
}

public struct MotoIntercomAttributes: ActivityAttributes {
    
    // 动态变化的属性
    public struct ContentState: Codable, Hashable {
        public var isLocalTalking: Bool          // 自己是否在说话
        public var statusText: String            // 当前对讲机底部的状态文字
        public var activePeers: [PeerLiveState]  // 当前在线的所有车友
        
        public init(isLocalTalking: Bool, statusText: String, activePeers: [PeerLiveState]) {
            self.isLocalTalking = isLocalTalking
            self.statusText = statusText
            self.activePeers = activePeers
        }
    }

    // 静态属性：如频道名称
    public var channelName: String
    public init(channelName: String) {
        self.channelName = channelName
    }
}
