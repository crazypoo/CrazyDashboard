//
//  AppDelegate.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 8/6/2026.
//

import UIKit
import UserNotifications
import AMapFoundationKit
import AMapNaviKit
import IQKeyboardToolbarManager
import IQKeyboardManagerSwift
import PooTools
import IQKeyboardToolbar
import DeviceKit
import Bugly
import SafeSFSymbols
import QWeatherSDK

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        PTDebugFunction.registerDefaultsFromSettingsBundle()
        
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
            // EN: Match the first supported app language against the system preference, including region variants.
            // ES: Relaciona el primer idioma compatible con la preferencia del sistema, incluidas las variantes regionales.
            // 中文：首次启动时根据系统首选语言匹配 App 支持的语言，并兼容地区变体。
            PTLanguage.share.language = PTLocale.en.rawValue
            let currentPhoneLanguage = Locale.preferredLanguages.first ?? PTLocale.en.rawValue
            let preferredLanguageCode = Locale(identifier: currentPhoneLanguage).language.languageCode?.identifier
            let findModel = PTDashboardConfig.shared.lauguageModels.first { model in
                let modelLanguageCode = Locale(identifier: model.localozableName).language.languageCode?.identifier
                return currentPhoneLanguage.caseInsensitiveCompare(model.localozableName) == .orderedSame
                    || preferredLanguageCode == modelLanguageCode
            }

            if let findModel {
                PTLanguage.share.language = findModel.localozableName
                PTMotoUserDefaultStruct.userSetLanguage = findModel.keyName
            } else {
                PTLanguage.share.language = PTLocale.en.rawValue
                PTMotoUserDefaultStruct.userSetLanguage = PTLocale.en.rawValue
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
        
        PTAppBaseConfig.share.viewControllerBaseBackgroundColor = .black
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
        PTAppBaseConfig.share.viewControllerBackItemImage = UIImage(.chevron.compactLeft).withTintColor(.white, renderingMode: .alwaysOriginal)
        PTAppBaseConfig.share.navTitleTextColor = .white
        PTAppBaseConfig.share.navTitleFont = .appfont(size: 24,bold: true)
        PTMediaLibUIConfig.share.selectLibTitleFont = .appfont(size: 15)
        PTMediaLibUIConfig.share.selectLibSubTitleFont = .appfont(size: 12)
        PTMediaLibUIConfig.share.albumCellTitleFont = .appfont(size: 18,bold: true)
        PTMediaLibUIConfig.share.albumCellDescFont = .appfont(size: 14)
        PTMediaLibUIConfig.share.selectedBorderColor = PTDashboardConfig.shared.appMainColor
        PTMediaLibUIConfig.share.albumListNavName = PTDashboardConfig.languageFunc(text: "ALbum list")
        appNotifiCenter()

        // EN: Restore alarm records without requesting permission or creating a new alarm at launch.
        // ES: Restaura los registros de alarmas sin solicitar permisos ni crear una alarma al iniciar.
        // 中文：启动时只恢复提醒记录，不申请权限，也不创建新的提醒。
        PTMotoAlarmCoordinator.shared.bootstrap()
        
        // EN: Configure one QWeather actor and inject it into every read-only weather service.
        // ES: Configura un solo actor de QWeather y lo inyecta en todos los servicios meteorológicos de solo lectura.
        // 中文：只初始化一个 QWeather actor，并将它注入所有只读天气服务。
        Task { @MainActor in
            do {
                let jwt = JWTGenerator(privateKey: "MC4CAQAwBQYDK2VwBCIEIE/J2HAiPGXdCgaKWj8V9SNWngayd/UVVqKtdZ6wA4EZ", pid: "2C88VNJQXF", kid: "KMB2ME5R85")
                let configuredService = try await QWeather.getInstance("nj5khxjpk2.re.qweatherapi.com")
                    .setupTokenGenerator(jwt)
                    .setupLogEnable(true)
                PTWeatherManager.shared.configureQWeather(configuredService)
                PTRouteWeatherRiskService.shared.configureQWeather(configuredService)
                PTNSLogConsole("✅ [天气服务] 和风天气备用服务已注入当前天气和路线风险服务")
            } catch {
                PTNSLogConsole("❌ [天气服务] 和风天气备用服务初始化失败，继续使用 WeatherKit: \(error.localizedDescription)")
            }
        }

        // EN: Restore intercom services only after the user opts in; always clear stale activities without starting PTT.
        // ES: Restauramos el intercomunicador solo con consentimiento explícito; limpiamos actividades antiguas sin iniciar PTT.
        // 中文：只有用户显式开启时才恢复对讲服务；默认只清理残留 Activity，不启动 PTT。
        if PTMotoUserDefaultStruct.PTTLaunchAutoRestoreEnabled {
            PTLocalIntercomManager.shared.restoreIntercomStateAtLaunch()
        } else {
            PTLiveActivityManager.shared.reconcileIntercomActivitiesAtLaunch()
        }

        // EN: Install the optional app-owned ANCS-shaped channel before the dashboard connection can start.
        // ES: Instala el canal opcional con forma ANCS antes de que pueda comenzar la conexión con el tablero.
        // 中文：在仪表连接可能开始前安装可选的 App 自有 ANCS 风格通道。
        PTDashboardANCSProvider.shared.install()

        // EN: Start dashboard observation at app launch so garage sync never depends on opening a page.
        // ES: Inicia la observación del tablero al arrancar para que la sincronización no dependa de abrir una página.
        // 中文：应用启动时就开始监听仪表，自动同步不再依赖用户打开某个页面。
        _ = PTVehicleConnectivityCoordinator.shared.snapshot

        // EN: Build the privacy-safe Spotlight index after the app's main stores are available.
        // ES: Construye el índice de Spotlight respetuoso con la privacidad cuando los almacenes principales están disponibles.
        // 中文：在主数据存储可用后建立保护隐私的 Spotlight 索引。
        Task { @MainActor in
            PTMotoSpotlightIndexer.shared.bootstrap()
        }
        
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

    func applicationWillTerminate(_ application: UIApplication) { }

//    private func configureQWeatherIfAvailable() {
//        guard
//            let privateKey = qWeatherValue(forKey: "QWeatherPrivateKey"),
//            let projectID = qWeatherValue(forKey: "QWeatherProjectID"),
//            let keyID = qWeatherValue(forKey: "QWeatherKeyID"),
//            let host = qWeatherValue(forKey: "QWeatherHost")
//        else {
//            PTNSLogConsole("ℹ️ [天气服务] 未配置和风天气密钥，已跳过备用服务初始化。")
//            return
//        }
//
//        Task { @MainActor in
//            do {
//                let jwt = JWTGenerator(privateKey: privateKey, pid: projectID, kid: keyID)
//                let configuredService = try await QWeather.getInstance(host)
//                    .setupTokenGenerator(jwt)
//                    .setupLogEnable(true)
//                PTWeatherManager.shared.configureQWeather(configuredService)
//                PTNSLogConsole("✅ [天气服务] 和风天气备用服务初始化完成")
//            } catch {
//                PTNSLogConsole("❌ [天气服务] 和风天气备用服务初始化失败: \(error.localizedDescription)")
//            }
//        }
//    }

    private func qWeatherValue(forKey key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, !trimmedValue.contains("$(") else { return nil }
        return trimmedValue
    }
}

extension AppDelegate:UNUserNotificationCenterDelegate {
    func appNotifiCenter() {
        let center = UNUserNotificationCenter.current()
        // EN: Register the delegate and categories only; permission is requested from an explicit user action.
        // ES: Registra el delegado y las categorías; el permiso solo se solicita mediante una acción explícita del usuario.
        // 中文：这里只注册代理和通知分类，权限必须由用户的明确操作触发。
        center.delegate = self
        PTNotificationCenter.registerCategories()
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    // EN: Notification actions operate on the existing local state machine and never send a vehicle command.
    // ES: Las acciones de notificación usan la máquina de estados local y nunca envían comandos al vehículo.
    // 中文：通知操作只作用于现有本地状态机，不会向车辆发送指令。
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            switch response.actionIdentifier {
            case PTNotificationCenter.acknowledgeActionIdentifier:
                PTAntiTheftManager.shared.acknowledgeLatestAlarm()
            case PTNotificationCenter.snoozeActionIdentifier:
                PTAntiTheftManager.shared.snooze(for: 30 * 60)
            case PTNotificationCenter.openActionIdentifier:
                let notificationKind = response.notification.request.content.userInfo["pt_notification_kind"] as? String
                if notificationKind == PTAppNotificationKind.alarm.rawValue {
                    let alarmID = (response.notification.request.content.userInfo["pt_alarm_id"] as? String)
                        .flatMap(UUID.init(uuidString:))
                    _ = PTRoutingManager.shared.execute(action: .openAlarmCenter(id: alarmID))
                } else {
                    _ = PTRoutingManager.shared.execute(action: .openSafety)
                }
            // EN: Tapping an alarm notification body opens the same alarm center as its explicit action.
            // ES: Tocar el cuerpo de una notificación de alarma abre el mismo centro que su acción explícita.
            // 中文：直接点击提醒通知正文时，也进入与显式按钮相同的提醒中心。
            case UNNotificationDefaultActionIdentifier:
                let notificationKind = response.notification.request.content.userInfo["pt_notification_kind"] as? String
                guard notificationKind == PTAppNotificationKind.alarm.rawValue else { break }
                let alarmID = (response.notification.request.content.userInfo["pt_alarm_id"] as? String)
                    .flatMap(UUID.init(uuidString:))
                _ = PTRoutingManager.shared.execute(action: .openAlarmCenter(id: alarmID))
            default:
                break
            }
            completionHandler()
        }
    }
}
