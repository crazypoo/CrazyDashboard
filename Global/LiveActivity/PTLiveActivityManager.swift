//
//  PTLiveActivityManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 30/7/2026.
//

import UIKit
@preconcurrency import ActivityKit
import Foundation
import os

//MRAK: NAV
nonisolated public struct MotoNaviAttributes: ActivityAttributes, Sendable {
    
    // 动态数据：随着高德导航回调不断刷新的数据
    public struct ContentState: Codable, Hashable, Sendable {
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

public enum PTLiveActivitySyncState: String, Equatable, Sendable {
    case idle
    case active
    case ended
    case unavailable
    case failed
}

public struct PTLiveActivityStatus: Equatable, Sendable {
    public let state: PTLiveActivitySyncState
    public let peerCount: Int
    public let message: String
    public let updatedAt: Date

    public init(state: PTLiveActivitySyncState,
                peerCount: Int,
                message: String,
                updatedAt: Date = Date()) {
        self.state = state
        self.peerCount = peerCount
        self.message = message
        self.updatedAt = updatedAt
    }
}

public enum PTLiveActivityEligibility {
    /// EN: PTT may be shown only when the service, audio path, permission and peer list are all valid.
    /// ES: PTT solo puede mostrarse cuando el servicio, el audio, el permiso y la lista de pares son válidos.
    /// 中文：只有 PTT 服务、音频、权限和成员列表同时有效时，才允许展示 Activity。
    public static func shouldDisplayPTT(isRunning: Bool,
                                        connectedPeerCount: Int,
                                        audioOperational: Bool,
                                        microphoneAvailable: Bool) -> Bool {
        isRunning && connectedPeerCount > 0 && audioOperational && microphoneAvailable
    }
}

@MainActor
public final class PTLiveActivityManager: NSObject {
    
    public static let shared = PTLiveActivityManager()
    
    // 保持对当前活动实例的引用
    private var currentNaviActivity: Activity<MotoNaviAttributes>?
    private var currentIntercomActivity: Activity<MotoIntercomAttributes>?
    private var intercomActivityGeneration: UInt = 0
    private var desiredIntercomChannel = "机车通讯"
    private var desiredIntercomTalking = false
    private var desiredIntercomStatus = ""
    private var desiredIntercomPeers: [PeerLiveState] = []
    private var intercomReconciliationTask: Task<Void, Never>?

    public private(set) var latestIntercomStatus = PTLiveActivityStatus(
        state: .idle,
        peerCount: 0,
        message: "未启动"
    )
    public private(set) var latestNavigationStatus = PTLiveActivityStatus(
        state: .idle,
        peerCount: 0,
        message: "未启动"
    )

    private let logger = Logger(subsystem: "com.yd.PTSpeed", category: "LiveActivity")
    
    private override init() { super.init() }
    
    /// 开始导航 Live Activity
    public func startNavigationActivity(destination: String, expectedArrival: Date) {
        // 确保设备支持且用户未在系统设置中关闭权限
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let attributes = MotoNaviAttributes(destinationName: destination)
        // 初始状态
        let initialState = MotoNaviAttributes.ContentState(progress: 0, remainingDistanceKm: 0, estimatedArrivalTime: expectedArrival)
        
        do {
            // 请求开启实时活动
            let content = ActivityContent(state: initialState, staleDate: nil)
            currentNaviActivity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            latestNavigationStatus = PTLiveActivityStatus(state: .active, peerCount: 0, message: "导航已启动")
            logger.info("Navigation activity started")
        } catch {
            latestNavigationStatus = PTLiveActivityStatus(state: .failed, peerCount: 0, message: error.localizedDescription)
            logger.error("Navigation activity start failed: \(error.localizedDescription, privacy: .public)")
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
            self.latestNavigationStatus = PTLiveActivityStatus(state: .active, peerCount: 0, message: "导航更新")
        }
    }

    /// 结束导航 Live Activity
    public func stopNavigationActivity() {
        guard let activity = currentNaviActivity else { return }
        Task {  @MainActor in
            // 立即结束并从锁屏移除
            await activity.end(activity.content, dismissalPolicy: .immediate)
            currentNaviActivity = nil
            latestNavigationStatus = PTLiveActivityStatus(state: .ended, peerCount: 0, message: "导航已结束")
            logger.info("Navigation activity ended")
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
        desiredIntercomChannel = channel
        desiredIntercomTalking = isTalking
        desiredIntercomStatus = status
        desiredIntercomPeers = peers
        intercomActivityGeneration &+= 1
        scheduleIntercomReconciliation()
    }

    public func stopIntercomActivity() {
        syncIntercomActivity(channel: "机车通讯", isTalking: false, status: "", peers: [])
    }

    /// EN: Reconcile system-owned PTT activities once after launch without starting PTT.
    /// ES: Coordina una vez las actividades PTT del sistema después del lanzamiento sin iniciar PTT.
    /// 中文：启动后只协调系统遗留的 PTT Activity，不会启动 PTT。
    public func reconcileIntercomActivitiesAtLaunch() {
        stopIntercomActivity()
    }

    private func scheduleIntercomReconciliation() {
        intercomReconciliationTask?.cancel()
        let generation = intercomActivityGeneration
        intercomReconciliationTask = Task { @MainActor [weak self] in
            await self?.reconcileIntercomActivity(generation: generation)
        }
    }

    private func reconcileIntercomActivity(generation: UInt) async {
        guard generation == intercomActivityGeneration else { return }

        let peers = desiredIntercomPeers
        let existingActivities = Activity<MotoIntercomAttributes>.activities

        guard !peers.isEmpty else {
            for activity in existingActivities {
                await activity.end(activity.content, dismissalPolicy: .immediate)
            }
            guard generation == intercomActivityGeneration else { return }
            currentIntercomActivity = nil
            latestIntercomStatus = PTLiveActivityStatus(state: .ended, peerCount: 0, message: "无已连接成员")
            logger.info("PTT activity reconciled to zero members")
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            for activity in existingActivities {
                await activity.end(activity.content, dismissalPolicy: .immediate)
            }
            currentIntercomActivity = nil
            latestIntercomStatus = PTLiveActivityStatus(state: .unavailable, peerCount: peers.count, message: "Live Activity 权限未开启")
            logger.error("PTT activity unavailable because authorization is disabled")
            return
        }

        let activity: Activity<MotoIntercomAttributes>
        if let current = currentIntercomActivity,
           existingActivities.contains(where: { $0.id == current.id }) {
            activity = current
        } else if let existing = existingActivities.first {
            activity = existing
            currentIntercomActivity = existing
        } else {
            guard generation == intercomActivityGeneration,
                  !desiredIntercomPeers.isEmpty else { return }
            let attributes = MotoIntercomAttributes(channelName: desiredIntercomChannel)
            let initialState = MotoIntercomAttributes.ContentState(
                isLocalTalking: desiredIntercomTalking,
                statusText: desiredIntercomStatus,
                activePeers: peers
            )

            do {
                let content = ActivityContent(state: initialState, staleDate: nil)
                activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                currentIntercomActivity = activity
            } catch {
                latestIntercomStatus = PTLiveActivityStatus(state: .failed, peerCount: peers.count, message: error.localizedDescription)
                logger.error("PTT activity start failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }

        guard generation == intercomActivityGeneration,
              !desiredIntercomPeers.isEmpty else { return }
        let updatedState = MotoIntercomAttributes.ContentState(
            isLocalTalking: desiredIntercomTalking,
            statusText: desiredIntercomStatus,
            activePeers: desiredIntercomPeers
        )
        let content = ActivityContent(state: updatedState, staleDate: nil)
        await activity.update(content, alertConfiguration: nil)

        for duplicate in existingActivities where duplicate.id != activity.id {
            await duplicate.end(duplicate.content, dismissalPolicy: .immediate)
        }
        guard generation == intercomActivityGeneration else { return }
        latestIntercomStatus = PTLiveActivityStatus(state: .active, peerCount: desiredIntercomPeers.count, message: desiredIntercomStatus)
        logger.info("PTT activity synchronized for \(self.desiredIntercomPeers.count) member(s)")
    }
}

//MARK: PTT
nonisolated public struct PeerLiveState: Codable, Hashable, Sendable {
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

nonisolated public struct MotoIntercomAttributes: ActivityAttributes, Sendable {
    
    // 动态变化的属性
    public struct ContentState: Codable, Hashable, Sendable {
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
