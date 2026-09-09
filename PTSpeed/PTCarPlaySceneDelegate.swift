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

@MainActor
final class PTCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPInterfaceControllerDelegate {
    var interfaceController: CPInterfaceController?
    var carWindow: CPWindow?

    let dashboardVC = PTCarPlayContainerViewController()
    private var carPlayBackObserver: NSObjectProtocol?
    
    // 当插上数据线，CarPlay 启动时调用
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {

        // EN: Initialize the coordinator for CarPlay state observation only; it never starts a scan here.
        // ES: Inicializamos el coordinador solo para observar el estado de CarPlay; aquí nunca iniciamos un escaneo.
        // 中文：CarPlay 这里只初始化协调器用于观察状态，不会在此启动任何扫描。
        _ = PTVehicleConnectivityCoordinator.shared.snapshot
        
        self.interfaceController = interfaceController
        self.carWindow = window
        
        self.interfaceController?.delegate = self
        
        window.rootViewController = dashboardVC
        window.makeKeyAndVisible()
        dashboardVC.loadViewIfNeeded()

        let rootTemplate = createMainMenuTemplate()
        interfaceController.setRootTemplate(rootTemplate, animated: true, completion: nil)
        
        NotificationCenter.default.post(
            name: CarPlayDidConnectNotification,
            object: nil
        )
        
        if carPlayBackObserver == nil {
            // EN: Register once because a CarPlay scene can reconnect without recreating its delegate.
            // ES: Registramos una sola vez porque una escena de CarPlay puede reconectarse sin recrear su delegado.
            // 中文：CarPlay 场景可能重连但不重建代理，因此返回通知只注册一次。
            carPlayBackObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("PTCarPlayNavigateBack"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleCarPlayBack()
            }
        }
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
        
        let dashboardB = CPGridButton(titleVariants: ["Peugeot dashboard", "Peugeot dashboard"],
                                   image: UIImage(systemName: "p.circle.fill")!) { [weak self] _ in
            self?.navigateToScreenP()
        }

        // 将按钮包装成网格模板
        let gridTemplate = CPGridTemplate(title: "Dashboard menu", gridButtons: [buttonA, buttonB,dashboardB])
        return gridTemplate
    }
    
    @objc private func handleCarPlayBack() {
        PTNSLogConsole("🚗 [CarPlay] 收到返回指令，正在退回上一级模板...")
        
        // 1. 让 CarPlay 系统的管家弹出模板 (返回主菜单)
        self.interfaceController?.popTemplate(animated: true, completion: { [weak self] finished, error in
            guard finished, error == nil else {
                PTNSLogConsole("⚠️ [CarPlay] 返回模板未完成，保留当前界面。")
                return
            }
            // 2. 动画结束后，同步清空底层的 UIViewController
            self?.dashboardVC.clearChildVC()
        })
    }

    // EN: Attach the view controller before the transition and flush it again after CarPlay presents the template.
    // ES: Adjuntamos el controlador antes de la transición y volvemos a forzar su diseño después de presentar la plantilla.
    // 中文：在模板切换前挂载控制器，并在 CarPlay 完成展示后再次刷新布局。
    private func presentCarPlayScreen(template: CPTemplate,
                                      viewController: UIViewController,
                                      afterPresentation: (() -> Void)? = nil) {
        guard let interfaceController else {
            PTNSLogConsole("⚠️ [CarPlay] 当前没有可用的 interfaceController。")
            return
        }

        dashboardVC.switchTo(viewController: viewController)
        dashboardVC.prepareCurrentChildForDisplay()

        interfaceController.pushTemplate(template, animated: true) { [weak self] finished, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard finished, error == nil else {
                    PTNSLogConsole("⚠️ [CarPlay] 模板展示失败，清理未完成的界面。")
                    self.dashboardVC.clearChildVC()
                    return
                }

                self.dashboardVC.prepareCurrentChildForDisplay()
                afterPresentation?()
            }
        }
    }

    // MARK: - 2. 界面跳转逻辑
    private func navigateToScreenP() {
        
        let templateA = CPMapTemplate()
        let changeThemeButton = CPMapButton(handler: { _ in
            PTNSLogConsole("🚗 [CarPlay] 原生悬浮按钮被点击了！")
        })
        changeThemeButton.image = UIImage(systemName: "paintbrush.fill")
        templateA.mapButtons = [changeThemeButton]
        
        let aVC = PTPeugeotDashBoardViewController()
        presentCarPlayScreen(template: templateA, viewController: aVC)
    }


    private func navigateToScreenA() {
        PTNSLogConsole("🚗 [CarPlay] 点击了按钮 A，正在跳转...")
        
        let templateA = CPMapTemplate()
        let changeThemeButton = CPMapButton(handler: { _ in
            PTNSLogConsole("🚗 [CarPlay] 原生悬浮按钮被点击了！")
        })
        changeThemeButton.image = UIImage(systemName: "paintbrush.fill")
        templateA.mapButtons = [changeThemeButton]
        
        let aVC = ViewController()
        presentCarPlayScreen(template: templateA, viewController: aVC) {
            aVC.navStart()
        }
    }
    
    private func navigateToScreenB() {
        PTNSLogConsole("🚗 [CarPlay] 点击了按钮 B，正在跳转...")
        
        let templateB = CPMapTemplate()
        let changeThemeButton = CPMapButton(handler: { _ in
            PTNSLogConsole("🚗 [CarPlay] 原生悬浮按钮被点击了！")
        })
        changeThemeButton.image = UIImage(systemName: "paintbrush.fill")
        templateB.mapButtons = [changeThemeButton]

        let bVC = PTOBDDataCarViewController()
        presentCarPlayScreen(template: templateB, viewController: bVC)
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        self.carWindow = nil
        self.dashboardVC.clearChildVC()
        NotificationCenter.default.post(name: PTCarPlayDidEnterBackgroundNotification, object: nil)
        // 🌟 拔下线时，也发一个断开的广播，让手机端恢复正常 UI
        NotificationCenter.default.post(
            name: CarPlayDidDisconnectNotification,
            object: nil
        )
        PTNSLogConsole("📱 [CarPlay] Scene已断开，发送恢复通知。")
    }
    
    func templateDidDisappear(_ aTemplate: CPTemplate, animated: Bool) {
                    
        PTNSLogConsole("🚗 [CarPlay] 检测到返回操作，已同步弹出 ViewController。")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // EN: The scene callback is the reliable point at which CarPlay can be considered active.
        // ES: El callback de la escena es el punto fiable para considerar activo CarPlay.
        // 中文：以场景激活回调作为 CarPlay 真正可渲染的可靠时机。
        dashboardVC.prepareCurrentChildForDisplay()
        NotificationCenter.default.post(name: PTCarPlayDidBecomeActiveNotification, object: nil)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        NotificationCenter.default.post(name: PTCarPlayDidEnterBackgroundNotification, object: nil)
    }

    deinit {
        if let carPlayBackObserver {
            NotificationCenter.default.removeObserver(carPlayBackObserver)
        }
    }
}
