//
//  CarPlaySceneDelegate.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 7/6/2026.
//

import UIKit
import CarPlay
//import PooTools

class CarPlaySceneDelegate: UIResponder,CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    var carWindow: CPWindow?

    // 当插上数据线，CarPlay 启动时调用
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {
        
        self.interfaceController = interfaceController
        self.carWindow = window
        
        // 1. 创建地图模板作为底层（这是拿到 Window 权限的前提）
        let mapTemplate = CPMapTemplate()
        interfaceController.setRootTemplate(mapTemplate, animated: true, completion: nil)
        
        // 2. 在 Window 上叠加你的自定义视图！
        setupDashboardUI()
        
        // 3. 启动 pootools 的数据引擎
        startPootoolsEngines()
    }
    
    private func setupDashboardUI() {
        guard let window = carWindow else { return }
        
        // 实例化你封装好的仪表盘视图
        let speedometer = PTSpeedometerView(frame: CGRect(x: 20, y: window.bounds.height / 2 - 150, width: 300, height: 300))
        window.addSubview(speedometer)
        
        // 将视图保存为实例属性以便后续更新...
    }
    
    private func startPootoolsEngines() {
        // 调用你 pootools 里的引擎
        PTLocationEngine.shared.startTracking()
        PTLocationEngine.shared.locationBlock = { speed, course in
            // 更新 UI...
        }
    }
    
    // 拔掉数据线时调用
    private func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController) {
        PTLocationEngine.shared.stopTracking()
    }
}
