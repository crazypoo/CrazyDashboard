//
//  CarPlaySceneDelegate.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 7/6/2026.
//

import UIKit
import CarPlay
import PooTools
import SnapKit
import SwifterSwift

class CarPlaySceneDelegate: UIResponder,CPTemplateApplicationSceneDelegate {
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
        window.rootViewController = dashboardVC
    }
}
