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

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
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
            title: PTDashboardConfig.languageFunc(text: "完成")
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
        PTAppBaseConfig.share.tabSelectedColor = .MainColor

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


}

