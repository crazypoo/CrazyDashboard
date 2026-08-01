//
//  PTLiDARCollisionManager.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 2/8/2026.
//

import Foundation
import ARKit
import PooTools

// MARK: - 📍 1. 定义盲区方位枚举
public enum PTBlindSpotZone {
    case left
    case center
    case right
}

// MARK: - 状态回调协议
public protocol PTLiDARCollisionDelegate: AnyObject {
    /// 实时返回左、中、右三个区域的具体距离 (单位：米)
    func lidarManager(_ manager: PTLiDARCollisionManager, didUpdateDistances left: Float, center: Float, right: Float)
    
    /// 当有障碍物进入危险距离时触发，返回危险所在的区域数组
    func lidarManager(_ manager: PTLiDARCollisionManager, didTriggerWarningIn zones: [PTBlindSpotZone])
}

@objcMembers
public class PTLiDARCollisionManager: NSObject {
    
    public static let shared = PTLiDARCollisionManager()
    public weak var delegate: PTLiDARCollisionDelegate?
    
    // AR 引擎组件
    private let arSession = ARSession()
    public private(set) var isRunning: Bool = false
    
    // ⚙️ 可调整的变量：危险距离阈值 (单位：米)
    public var warningThreshold: Float = 1.2
    
    private override init() {
        super.init()
        arSession.delegate = self
    }
    
    public func startScanning() {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            PTNSLogConsole("❌ [LiDAR] 设备不支持激光雷达！")
            return
        }
        guard !isRunning else { return }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = .sceneDepth
        
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
        PTNSLogConsole("🟢 [LiDAR] 三区盲区防碰撞检测已启动")
    }
    
    public func stopScanning() {
        guard isRunning else { return }
        arSession.pause()
        isRunning = false
        PTNSLogConsole("🔴 [LiDAR] 已关闭")
    }
}

// MARK: - 2. 深度数据解析与三区矩阵算法
extension PTLiDARCollisionManager: ARSessionDelegate {
    
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let depthData = frame.sceneDepth else { return }
        let depthPixelBuffer = depthData.depthMap
        
        let width = CVPixelBufferGetWidth(depthPixelBuffer)
        let height = CVPixelBufferGetHeight(depthPixelBuffer)
        
        // 🚨 核心逻辑：横向切分屏幕，设定左、中、右三个采样点
        // (Y 轴取 1/2 高度，即车头正前方水平线)
        let leftPoint = CGPoint(x: CGFloat(width) * 0.25, y: CGFloat(height) * 0.5)
        let centerPoint = CGPoint(x: CGFloat(width) * 0.5, y: CGFloat(height) * 0.5)
        let rightPoint = CGPoint(x: CGFloat(width) * 0.75, y: CGFloat(height) * 0.5)
        
        // 读取三个区域的真实距离
        let leftDist = getDistance(from: depthPixelBuffer, at: leftPoint)
        let centerDist = getDistance(from: depthPixelBuffer, at: centerPoint)
        let rightDist = getDistance(from: depthPixelBuffer, at: rightPoint)
        
        // 通知 UI 实时距离数字
        DispatchQueue.main.async {
            self.delegate?.lidarManager(self, didUpdateDistances: leftDist, center: centerDist, right: rightDist)
        }
        
        // 🚨 判断哪些区域进入了危险阈值
        var dangerousZones: [PTBlindSpotZone] = []
        
        // 过滤条件：大于 0.1 米防止镜头灰尘噪点，小于 warningThreshold 视为危险
        if leftDist > 0.1 && leftDist <= warningThreshold { dangerousZones.append(.left) }
        if centerDist > 0.1 && centerDist <= warningThreshold { dangerousZones.append(.center) }
        if rightDist > 0.1 && rightDist <= warningThreshold { dangerousZones.append(.right) }
        
        // 如果有危险区域，立刻触发报警
        if !dangerousZones.isEmpty {
            DispatchQueue.main.async {
                self.delegate?.lidarManager(self, didTriggerWarningIn: dangerousZones)
            }
        }
    }
    
    // 内存安全读取深度的方法 (与之前保持一致)
    private func getDistance(from depthMap: CVPixelBuffer, at point: CGPoint) -> Float {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let x = Int(point.x)
        let y = Int(point.y)
        guard x >= 0, x < CVPixelBufferGetWidth(depthMap), y >= 0, y < CVPixelBufferGetHeight(depthMap) else { return 0.0 }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return 0.0 }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        let bufferPointer = baseAddress.advanced(by: y * bytesPerRow + x * MemoryLayout<Float32>.stride)
        let distancePointer = bufferPointer.bindMemory(to: Float32.self, capacity: 1)
        
        return distancePointer.pointee
    }
}
