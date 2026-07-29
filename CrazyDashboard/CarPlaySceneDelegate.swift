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
    
    /// 当你的 App 在车机屏幕上重新显示、并获得用户焦点时触发
    func sceneDidBecomeActive(_ scene: UIScene) {
        PTNSLogConsole("🚗 CarPlay 界面回到了车机前台，处于可见状态！")
        
        // 通知全系统：车机屏幕现在在看我们
        NotificationCenter.default.post(name: PTCarPlayDidBecomeActiveNotification, object: nil)
    }
    
    /// 当用户在车机上打开了别的 App，或者回到了 CarPlay 桌面时触发
    func sceneDidEnterBackground(_ scene: UIScene) {
        PTNSLogConsole("🚗 CarPlay 界面被退到了车机后台，处于不可见状态！")
        
        // 通知全系统：车机屏幕现在没看我们
        NotificationCenter.default.post(name: PTCarPlayDidEnterBackgroundNotification, object: nil)
    }
}
