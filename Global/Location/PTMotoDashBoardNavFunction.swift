//
//  PTMotoDashBoardNavFunction.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 29/7/2026.
//

import UIKit
import AMapNaviKit

class PTMotoDashBoardNavFunction: NSObject {
    static func convertAMapIconToPTManeuver(iconType: AMapNaviIconType) -> UInt8 {
        switch iconType {
        case .none, .default:
            return PTManeuverMap.straight
        case .straight:
            return PTManeuverMap.straight
        case .left:
            return PTManeuverMap.quiteLeft
        case .right:
            return PTManeuverMap.quiteRight
        case .leftFront:
            return PTManeuverMap.lightLeft
        case .rightFront:
            return PTManeuverMap.lightRight
        case .leftBack:
            return PTManeuverMap.heavyLeft // 0x0C 急左转
        case .rightBack:
            return PTManeuverMap.heavyRight // 0x07 急右转
        case .entryLeftRingUTurn:
            return PTManeuverMap.uTurnLeft
        case .entryLeftRingRight:
            return PTManeuverMap.uTurnRight
        case .arrivedWayPoint:
            return PTManeuverMap.straight
        case .arrivedDestination:
            return PTManeuverMap.arrive // 0x2C 到达
        // 🚨 新增：环岛处理逻辑
        case .enterRoundabout:
            // 协议规定右侧环岛 1 号出口为 0x13。
            // 如果高德在 AMapNaviInfo 中提供了环岛出口编号 (ringRoundaboutExitCount)，你可以动态加上该编号减 1。
            // 这里提供基础的 1 号出口映射作为安全回退机制。
            return PTManeuverMap.roundaboutRightBase
            
        default:
            return PTManeuverMap.straight
        }
    }
    
    static func sendNavDataToDashboard(naviInfo: AMapNaviInfo,currentSpeedLimit:UInt8) {
        let remainDistanceMeters = Double(naviInfo.routeRemainDistance)
        let remainingKm = remainDistanceMeters / 1000.0
        let progress = (Double(naviInfo.travelRealPathLength) - Double(naviInfo.travelDrivedRealLength)) / Double(naviInfo.travelRealPathLength)
        let eta = Date().addingTimeInterval(TimeInterval(naviInfo.routeRemainTime))
        Task { @MainActor in
            PTLiveActivityManager.shared.updateNavigationActivity(
                progress: progress,
                remainingKm: remainingKm,
                expectedArrival: eta
            )
        }

        // --- 核心逻辑开始 ---
        // 1. 获取距离下一个转弯动作的剩余距离 (米)
        let distanceToNextManeuver = naviInfo.segmentRemainDistance
        
        // 2. 提取路名，并强制转为无声调拼音/英文，防止车机乱码
        let rawNextRoad = naviInfo.nextRoadName ?? ""
        let rawCurrentRoad = naviInfo.currentRoadName ?? ""
        let safeNextRoad = rawNextRoad.toMotorcycleCompatiblePinyin()
        let safeCurrentRoad = rawCurrentRoad.toMotorcycleCompatiblePinyin()
        
        // 3. 将高德的转向图标枚举转换为车机的动作码
        let maneuverCode = PTMotoDashBoardNavFunction.convertAMapIconToPTManeuver(iconType: naviInfo.iconType)
        
        // 4. 组装车机数据模型 (限速字段使用全局变量 currentSpeedLimit)
        let info = PTNavigationInfo(
            nextManeuver: maneuverCode,
            metersToNextManeuver: UInt32(max(0, distanceToNextManeuver)),
            nameNextRoad: safeNextRoad,
            nameCurrentRoad: safeCurrentRoad,
            currentSpeedLimit: currentSpeedLimit,
            distanceToDestination: UInt32(max(0, naviInfo.routeRemainDistance)),
            estimatedTimeToDestinationSec: max(0, naviInfo.routeRemainTime)
        )
        
        // 5. 核心动作：通过蓝牙将数据泵送给摩托车！
        PTBluetoothServerManager.shared.sendNavigation(info: info)

    }
}
