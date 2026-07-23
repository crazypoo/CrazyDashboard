//
//  SceneDelegate.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 8/6/2026.
//

import UIKit
import PooTools
import SwifterSwift

class SceneDelegate: PTWindowSceneDelegate {
    
    lazy var snifferOverlay: PTECUSnifferOverlay = {
        let view = PTECUSnifferOverlay(frame: AppWindows?.bounds ?? .zero)
        return view
    }()

    lazy var lightFeedbackOverlay: PTLightFeedbackOverlay = {
        let view = PTLightFeedbackOverlay(frame: AppWindows?.bounds ?? .zero)
        return view
    }()
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let scene = (scene as? UIWindowScene) else { return }
        self.makeKeyAndVisible(in: scene, viewController: PTMotoBaseTabbarController(), tint: .white)
        
        PTGCDManager.shared.delayOnMain(time: 0.5) {
            AppWindows?.addSubviews([self.snifferOverlay,self.lightFeedbackOverlay])
            if PTMotoUserDefaultStruct.BleTestDataGet {
                self.snifferOverlay.showSniffer()
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
            guard let url = URLContexts.first?.url else { return }
            
            // 🚨 将系统传进来的 URL 交给我们的路由引擎处理
            let handled = PTRoutingManager.shared.handle(url: url)
            
            if handled {
                PTNSLogConsole("✅ 成功通过 URL Scheme 唤醒 App 并执行指令")
            }
        }
}

