//
//  PTCarPlaySceneDelegate.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 28/7/2026.
//

import UIKit
import CarPlay
import PooTools
import SnapKit
import SwifterSwift

let CarPlayDidDisconnectNotification = NSNotification.Name("CarPlayDidDisconnectNotification")
let CarPlayDidConnectNotification = NSNotification.Name("CarPlayDidConnectNotification")

class PTCarPlaySceneDelegate: UIResponder,CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    var carWindow: CPWindow?

    let dashboardVC = ViewController()
    
    // 当插上数据线，CarPlay 启动时调用
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {
        
        self.interfaceController = interfaceController
        self.carWindow = window
        
        // 1. 创建地图模板作为底层（这是拿到 Window 权限的前提）
        let mapTemplate = CPMapTemplate()
        interfaceController.setRootTemplate(mapTemplate, animated: true, completion: nil)
        
        dashboardVC.updateMapModeForCarPlayConnection(isActive: true)
        window.rootViewController = dashboardVC
        
        NotificationCenter.default.post(
            name: CarPlayDidConnectNotification,
            object: nil
        )
    }
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        
        // 🌟 拔下线时，也发一个断开的广播，让手机端恢复正常 UI
        NotificationCenter.default.post(
            name: CarPlayDidDisconnectNotification,
            object: nil
        )
        PTNSLogConsole("📱 [CarPlay] Scene已断开，发送恢复通知。")
    }
}
