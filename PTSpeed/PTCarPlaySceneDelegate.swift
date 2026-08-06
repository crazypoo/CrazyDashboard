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

class PTCarPlaySceneDelegate: UIResponder,CPTemplateApplicationSceneDelegate,CPInterfaceControllerDelegate {
    var interfaceController: CPInterfaceController?
    var carWindow: CPWindow?

    let dashboardVC = PTCarPlayContainerViewController()
    
    // 当插上数据线，CarPlay 启动时调用
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {
        
        self.interfaceController = interfaceController
        self.carWindow = window
        
        self.interfaceController?.delegate = self
        
        window.rootViewController = dashboardVC
        window.makeKeyAndVisible()

        let rootTemplate = createMainMenuTemplate()
        interfaceController.setRootTemplate(rootTemplate, animated: true, completion: nil)
//        dashboardVC.updateMapModeForCarPlayConnection(isActive: true)
        
        NotificationCenter.default.post(
            name: CarPlayDidConnectNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleCarPlayBack),
                                               name: NSNotification.Name("PTCarPlayNavigateBack"),
                                               object: nil)
    }
    
    private func createMainMenuTemplate() -> CPGridTemplate {
        // 创建按钮 A
        // titleVariants 是一个数组，系统会根据车机屏幕大小自动选择合适的字符串长度
        let buttonA = CPGridButton(titleVariants: ["Normal dashboard", "Dashboard"],
                                   image: UIImage(systemName: "a.circle.fill")!) { [weak self] _ in
            // 点击后的回调执行导航逻辑
            self?.navigateToScreenA()
        }
        
        // 创建按钮 B
        let buttonB = CPGridButton(titleVariants: ["OBD", "OBD"],
                                   image: UIImage(systemName: "b.circle.fill")!) { [weak self] _ in
            self?.navigateToScreenB()
        }
        
        // 将按钮包装成网格模板
        let gridTemplate = CPGridTemplate(title: "Dashboard menu", gridButtons: [buttonA, buttonB])
        return gridTemplate
    }
    
    @objc private func handleCarPlayBack() {
        PTNSLogConsole("🚗 [CarPlay] 收到返回指令，正在退回上一级模板...")
        
        // 1. 让 CarPlay 系统的管家弹出模板 (返回主菜单)
        self.interfaceController?.popTemplate(animated: true, completion: { [weak self] _, _ in
            // 2. 动画结束后，同步清空底层的 UIViewController
            self?.dashboardVC.clearChildVC()
        })
    }

    // MARK: - 2. 界面跳转逻辑
    
    private func navigateToScreenA() {
        PTNSLogConsole("🚗 [CarPlay] 点击了按钮 A，正在跳转...")
        
        // 在 CarPlay 中，界面 A 必须也是一个模板。这里以一个“信息展示模板”为例
        let templateA = CPMapTemplate()
        let changeThemeButton = CPMapButton(handler: { _ in
            PTNSLogConsole("🚗 [CarPlay] 原生悬浮按钮被点击了！")
            // 在这里执行你想要的逻辑
        })
        // 随便用一个原生图标测试
        changeThemeButton.image = UIImage(systemName: "paintbrush.fill")
        
        // 将按钮添加到地图模板上
        templateA.mapButtons = [changeThemeButton]
        
        let aVC = ViewController()
        self.dashboardVC.switchTo(viewController: aVC)
        self.interfaceController?.pushTemplate(templateA, animated: true) { finish, error in }
    }
    
    private func navigateToScreenB() {
        PTNSLogConsole("🚗 [CarPlay] 点击了按钮 B，正在跳转...")
        
        // 这里以一个“列表模板”为例展示界面 B
        let templateB = CPListTemplate(title: "界面 B", sections: [])
        
        self.interfaceController?.pushTemplate(templateB, animated: true, completion: nil)
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        self.carWindow = nil
        // 🌟 拔下线时，也发一个断开的广播，让手机端恢复正常 UI
        NotificationCenter.default.post(
            name: CarPlayDidDisconnectNotification,
            object: nil
        )
        PTNSLogConsole("📱 [CarPlay] Scene已断开，发送恢复通知。")
    }
    
    func templateDidDisappear(_ aTemplate: CPTemplate, animated: Bool) {
            
        // 同步将底层的 UIViewController 也 Pop 出去，恢复到上一层界面
        // 同样禁用动画，交由 CarPlay 模板层处理视觉过渡
//        self.interfaceController?.popTemplate(animated: true)
        
        PTNSLogConsole("🚗 [CarPlay] 检测到返回操作，已同步弹出 ViewController。")
    }
}
