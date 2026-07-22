//
//  AppDelegate.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 8/6/2026.
//

import UIKit
import AMapFoundationKit
import AMapNaviKit
import IQKeyboardToolbarManager
import IQKeyboardManagerSwift
import PooTools
import IQKeyboardToolbar
import DeviceKit
import Bugly
import BackgroundTasks

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        
        var debugDevice = false
        let buglyConfig = BuglyConfig()
        #if DEBUG
        debugDevice = true
        buglyConfig.debugMode = debugDevice
        #else
        buglyConfig.debugMode = debugDevice
        #endif
        buglyConfig.channel = "iOS"
        buglyConfig.blockMonitorEnable = debugDevice
        buglyConfig.blockMonitorTimeout = 2
        buglyConfig.consolelogEnable = !debugDevice
        buglyConfig.deviceIdentifier = ""
        buglyConfig.unexpectedTerminatingDetectionEnable = !debugDevice
        buglyConfig.viewControllerTrackingEnable = !debugDevice
        Bugly.start(withAppId: "d4ef3cd7ec",
                    developmentDevice: debugDevice,
                    config: buglyConfig)

        if PTMotoUserDefaultStruct.appFirst {
            PTLanguage.share.language = PTLocale.en.rawValue
            let currentPhoneLanguage = PTLanguage.defaultLanguage()
            let keyName = PTLocale.en.rawValue
            let localozableName = PTLocale.en.rawValue
            
            if let findModel = PTDashboardConfig.shared.lauguageModels.first(where: { $0.localozableName == currentPhoneLanguage }) {
                PTLanguage.share.language = findModel.localozableName
                PTMotoUserDefaultStruct.userSetLanguage = findModel.keyName
            } else {
                PTLanguage.share.language = localozableName
                PTMotoUserDefaultStruct.userSetLanguage = keyName
            }
            
            PTMotoUserDefaultStruct.appFirst.toggle()
        }
        
        AMapNaviManagerConfig.shared().updatePrivacyShow(AMapPrivacyShowStatus.didShow, privacyInfo: AMapPrivacyInfoStatus.didContain)
        AMapNaviManagerConfig.shared().updatePrivacyAgree(.didAgree)
        AMapServices.shared().apiKey = "b634e7bfe8637676248d4360bd6ee65c"
        AMapServices.shared().enableHTTPS = true
        
        IQKeyboardManager.shared.isEnabled = true
        IQKeyboardToolbarManager.shared.isEnabled = true
        IQKeyboardToolbarManager.shared.toolbarConfiguration.placeholderConfiguration.font = .appfont(size: 14)
        IQKeyboardToolbarManager.shared.toolbarConfiguration.placeholderConfiguration.color = .lightGray
        IQKeyboardToolbarManager.shared.toolbarConfiguration.useTextInputViewTintColor = false
        IQKeyboardToolbarManager.shared.toolbarConfiguration.doneBarButtonConfiguration = IQBarButtonItemConfiguration(
            title: PTDashboardConfig.languageFunc(text: "button_done")
        )
        
        PTAppBaseConfig.share.tab26Mode = true
        PTAppBaseConfig.share.tabbarMetailMode = true
        PTAppBaseConfig.share.tabSelectedMetailColor = .grayCA
        PTAppBaseConfig.share.tabTopSpacing = Gobal_device_info.isFaceIDCapable ? 12 : 2.5
        PTAppBaseConfig.share.tabBottomSpacing = Gobal_device_info.isFaceIDCapable ? 12 : 2.5
        PTAppBaseConfig.share.tab26BottomSpacing = Gobal_device_info.isFaceIDCapable ? PTAppBaseConfig.share.tab26BottomSpacing : 0
        PTAppBaseConfig.share.tabContentSpacing = 2
        PTAppBaseConfig.share.tabNormalFont = .appfont(size: 10.adapter)
        PTAppBaseConfig.share.tabSelectedFont = .appfont(size: 10.adapter,bold:true)
        PTAppBaseConfig.share.tabNormalColor = .gray7F
        PTAppBaseConfig.share.tabSelectedColor = PTDashboardConfig.shared.appMainColor

        registerBackgroundTasks()
        
        _ = PTTripManager.shared
        _ = PTAntiTheftManager.shared
        _ = PTMaintenanceManager.shared
        _ = PTGPXRecorder.shared
        _ = PTDiagnosticManager.shared
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return PTRotationManager.shared.orientationMask
    }

    func registerBackgroundTasks() {
        // 这里的 "com.yourcompany.yourapp.refresh" 就是你的 Identifier
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.yd.PTSpeed.refresh", using: nil) { task in
            // 处理后台任务的逻辑
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    func handleAppRefresh(task: BGAppRefreshTask) {
        // 因超时或其他问题而不得不被系统终止时，将调用该回调
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Data Fetching

        DispatchQueue.main.async {
//            if let currentVC = PTUtils.getCurrentVC() as? PTMotoNavigationViewController {
//                
//            }
        }

        // 告知后台任务调度器任务已完成
        task.setTaskCompleted(success: true)
    }
}

