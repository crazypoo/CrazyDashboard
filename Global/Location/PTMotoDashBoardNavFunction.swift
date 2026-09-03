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
        let code: UInt8
        switch iconType {
        case .none, .default:
            code = PTManeuverMap.straight
        case .straight:
            code = PTManeuverMap.straight
        case .left:
            code = PTManeuverMap.quiteLeft
        case .right:
            code = PTManeuverMap.quiteRight
        case .leftFront:
            code = PTManeuverMap.lightLeft
        case .rightFront:
            code = PTManeuverMap.lightRight
        case .leftBack:
            code = PTManeuverMap.heavyLeft
        case .rightBack:
            code = PTManeuverMap.heavyRight
        case .entryLeftRingUTurn:
            code = PTManeuverMap.uTurnLeft
        case .entryLeftRingRight:
            code = PTManeuverMap.uTurnRight
        case .arrivedWayPoint:
            code = PTManeuverMap.straight
        case .arrivedDestination:
            code = PTManeuverMap.arrive
        // EN: Use the protocol's roundabout mapping for the supported default exit.
        // ES: Usa el mapeo de rotonda del protocolo para la salida predeterminada compatible.
        // 中文：使用协议规定的环岛映射处理已支持的默认出口。
        case .enterRoundabout:
            // EN: The protocol maps the first right roundabout exit to 0x13.
            // ES: El protocolo asigna 0x13 a la primera salida de una rotonda derecha.
            // 中文：协议规定右侧环岛 1 号出口为 0x13。
            // EN: Use the first-exit mapping as a safe fallback when the map SDK provides no exit count.
            // ES: Usa la primera salida como respaldo seguro cuando el SDK de mapas no proporciona el número.
            // 中文：地图 SDK 未提供出口编号时，使用 1 号出口作为安全回退。
            code = PTManeuverMap.roundaboutRightBase
            
        default:
            code = PTManeuverMap.straight
        }

        return PTXP400BLEProtocol.normalizedManeuverCode(code)
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

        // EN: Build the dashboard navigation payload from the map callback.
        // ES: Construye la carga de navegación del tablero a partir del callback del mapa.
        // 中文：根据地图回调组装仪表盘导航数据。
        // EN: Read the remaining distance to the next maneuver in meters.
        // ES: Lee la distancia restante hasta la próxima maniobra en metros.
        // 中文：获取距离下一个转弯动作的剩余距离（米）。
        let distanceToNextManeuver = naviInfo.segmentRemainDistance
        
        // EN: Convert road names to dashboard-safe Latin text to avoid encoding issues.
        // ES: Convierte los nombres de calles a texto latino compatible para evitar problemas de codificación.
        // 中文：将路名转换为仪表盘可识别的拉丁文本，避免编码问题。
        let rawNextRoad = naviInfo.nextRoadName ?? ""
        let rawCurrentRoad = naviInfo.currentRoadName ?? ""
        let safeNextRoad = rawNextRoad.toMotorcycleCompatiblePinyin()
        let safeCurrentRoad = rawCurrentRoad.toMotorcycleCompatiblePinyin()
        
        // EN: Map the AMap maneuver enum to the dashboard maneuver code.
        // ES: Convierte el enum de maniobra de AMap al código de maniobra del tablero.
        // 中文：将高德转向图标枚举转换为仪表盘动作码。
        let maneuverCode = PTMotoDashBoardNavFunction.convertAMapIconToPTManeuver(iconType: naviInfo.iconType)
        
        // EN: Assemble the dashboard model; the speed limit comes from the caller.
        // ES: Ensambla el modelo del tablero; el límite de velocidad procede del llamador.
        // 中文：组装仪表盘数据模型，限速字段使用调用方传入的值。
        let info = PTNavigationInfo(
            nextManeuver: maneuverCode,
            metersToNextManeuver: UInt32(max(0, distanceToNextManeuver)),
            nameNextRoad: safeNextRoad,
            nameCurrentRoad: safeCurrentRoad,
            currentSpeedLimit: currentSpeedLimit,
            distanceToDestination: UInt32(max(0, naviInfo.routeRemainDistance)),
            estimatedTimeToDestinationSec: max(0, naviInfo.routeRemainTime)
        )
        
        // EN: Send the validated navigation model through the existing BLE core.
        // ES: Envía el modelo de navegación validado mediante el núcleo BLE existente.
        // 中文：通过现有 BLE 核心发送已校验的导航模型。
        PTBluetoothServerManager.shared.sendNavigation(info: info)

    }
}
