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

        // EN: A new scene never restores the developer console or its high-risk permission from stale process state.
        // ES: Una escena nueva nunca restaura la consola de desarrollador ni su permiso de riesgo desde un estado obsoleto.
        // 中文：新场景绝不从过期进程状态恢复开发者控制台或高风险权限。
        PTMotoUserDefaultStruct.BleTestDataGet = false
        if PTDeveloperSafetyGate.shared.isEnabled {
            PTDeveloperSafetyGate.shared.disable(reason: .lifecycleReset)
        }
        self.makeKeyAndVisible(in: scene, viewController: PTMotoBaseTabbarController(), tint: .white)
        PTLaunchAnimationPresenter.present(in: scene)
        connectionOptions.urlContexts.forEach { enqueueExternalURL($0.url) }
        
        PTGCDManager.shared.delayOnMain(time: 0.5) {
            // EN: Add the sniffer last so the compact developer control stays above the weather surface.
            // ES: Añade el sniffer al final para que su control compacto quede encima de la superficie meteorológica.
            // 中文：最后添加嗅探器，确保紧凑开发者按钮位于天气界面之上。
            AppWindows?.addSubviews([self.weatherOverlay, self.snifferOverlay])
            PTLaunchAnimationPresenter.bringToFrontIfVisible(in: scene)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
        if let windowScene = scene as? UIWindowScene {
            PTLaunchAnimationPresenter.dismiss(in: windowScene)
        }
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
        if let windowScene = scene as? UIWindowScene {
            PTLaunchAnimationPresenter.dismiss(in: windowScene)
        }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
        PTNSLogConsole(">>>>>>>>>>>>>>>>>>>>>sceneWillEnterForeground")
        PTDashboardConfig.shared.appInBackground = false

        // EN: Reconcile requested peripheral advertising after the scene returns; the operation is idempotent.
        // ES: Reconcilia la publicidad solicitada al volver la escena; la operación es idempotente.
        // 中文：场景回到前台后校正用户请求的外设广播，重复执行不会重复添加服务或广播。
        PTBluetoothServerManager.shared.reconcilePeripheralLifecycle()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
        PTNSLogConsole(">>>>>>>>>>>>>>>>>>>>>sceneDidEnterBackground")
        PTDashboardConfig.shared.appInBackground = true
        NotificationCenter.default.post(name: PTAppEnterBackgroundNotification, object: nil)

        // EN: Keep an active peripheral session alive in the declared Bluetooth background mode.
        // ES: Mantén activa una sesión periférica en el modo Bluetooth de background declarado.
        // 中文：依靠工程声明的蓝牙后台模式保持已请求的外设会话，不因界面进入后台主动停止广播。
        PTBluetoothServerManager.shared.reconcilePeripheralLifecycle()
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
