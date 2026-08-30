//
//  SceneDelegate.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 8/6/2026.
//

import UIKit
import PooTools
import SwifterSwift

@MainActor
class SceneDelegate: PTWindowSceneDelegate {
    
    lazy var snifferOverlay: PTECUSnifferOverlay = {
        let view = PTECUSnifferOverlay(frame: AppWindows?.bounds ?? .zero)
        return view
    }()
    
    lazy var weatherOverlay:PTWeatherOverlayView = {
        let view = PTWeatherOverlayView(frame: AppWindows?.bounds ?? .zero)
        return view
    }()

    // EN: Queue cold-start routes until this application scene is active and owns the UI.
    // ES: Encola las rutas de arranque en frío hasta que esta escena esté activa y sea dueña de la UI.
    // 中文：将冷启动路由排队，直到当前应用场景激活并真正拥有 UI。
    private var pendingExternalURLs: [URL] = []
    private var queuedExternalURLKeys = Set<String>()
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let scene = (scene as? UIWindowScene) else { return }
        self.makeKeyAndVisible(in: scene, viewController: PTMotoBaseTabbarController(), tint: .white)
        connectionOptions.urlContexts.forEach { enqueueExternalURL($0.url) }
        
        PTGCDManager.shared.delayOnMain(time: 0.5) {
            AppWindows?.addSubviews([self.snifferOverlay,self.weatherOverlay])
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
        PTNSLogConsole(">>>>>>>>>>>>>>>>>>>>>sceneDidDisconnect")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        guard let windowScene = scene as? UIWindowScene else { return }
        drainPendingExternalURLs(in: windowScene)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
        PTNSLogConsole(">>>>>>>>>>>>>>>>>>>>>sceneWillEnterForeground")
        PTDashboardConfig.shared.appInBackground = false
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
        PTNSLogConsole(">>>>>>>>>>>>>>>>>>>>>sceneDidEnterBackground")
        PTDashboardConfig.shared.appInBackground = true
        NotificationCenter.default.post(name: PTAppEnterBackgroundNotification, object: nil)
    }
        
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let windowScene = scene as? UIWindowScene else { return }

        for context in URLContexts {
            if windowScene.activationState == .foregroundActive {
                routeExternalURL(context.url, in: windowScene)
            } else {
                enqueueExternalURL(context.url)
            }
        }
    }

    // EN: Keep URL delivery scene-aware and avoid losing a route during a cold launch.
    // ES: Mantén la entrega de URL consciente de la escena y evita perder rutas durante un arranque en frío.
    // 中文：让 URL 投递绑定到具体场景，避免冷启动时丢失路由。
    private func enqueueExternalURL(_ url: URL) {
        let key = url.absoluteString
        guard queuedExternalURLKeys.insert(key).inserted else { return }
        pendingExternalURLs.append(url)
    }

    private func drainPendingExternalURLs(in scene: UIWindowScene) {
        guard scene.activationState == .foregroundActive,
              !pendingExternalURLs.isEmpty else { return }

        // EN: Loading the root view here makes the custom tab selection and navigation observers ready.
        // ES: Cargar aquí la vista raíz deja listos la pestaña personalizada y sus observadores de navegación.
        // 中文：在此加载根视图，确保自定义 Tab 选择和导航观察者已准备好。
        PTSceneContext.rootViewController(in: scene)?.loadViewIfNeeded()
        let urls = pendingExternalURLs
        pendingExternalURLs.removeAll()
        queuedExternalURLKeys.removeAll()

        for url in urls {
            routeExternalURL(url, in: scene)
        }
    }

    private func routeExternalURL(_ url: URL, in scene: UIWindowScene) {
        let handled = PTRoutingManager.shared.handle(url: url, in: scene)
        PTNSLogConsole(handled
                       ? "✅ 成功通过 URL Scheme 唤醒 App 并执行指令"
                       : "⚠️ URL Scheme 未执行或已被拒绝")
    }
}
