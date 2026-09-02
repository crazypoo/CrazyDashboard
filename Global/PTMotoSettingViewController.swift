//
//  PTMotoSettingViewController.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 19/7/2026.
//

import UIKit
import UserNotifications
import PooTools
import SwifterSwift
import SnapKit
import SafeSFSymbols

class PTMotoSettingViewController: PTMotoBaseViewController {

    lazy var appLogo:UIImageView = {
        let view = UIImageView()
        view.image = UIImage(named: "app_inside_logo")
        view.bounds = .init(origin: .zero, size: .init(width: 108.adapter, height: PTAppBaseConfig.share.navBarButtonSize))
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = false
        return view
    }()

    lazy var dashBoadColorTitle:UILabel = {
        let view = baseTitle(value: PTDashboardConfig.languageFunc(text: "dashboard_color_set_title"))
        return view
    }()
    
    lazy var dashBoardColorButton:UIButton = {
        let view = UIButton()
        view.addActionHandlers(handler: { _ in
            let titleItem = PTActionSheetTitleItem()
            titleItem.title = PTDashboardConfig.languageFunc(text: "dashboard_color_set_title")
            
            let imageSize:CGSize = .init(width: 54, height: 34)
            let contentImtes = PTConfigColor.allCases.map { value in
                let model = PTActionSheetItem(title: "")
                model.imageSize = imageSize
                model.image = value.getColor().createImageWithColor().transformImage(size: imageSize)
                return model
            }
            
            UIAlertController.baseCustomActionSheet(titleItem: titleItem,cancelItem: PTActionSheetItem(title: PTDashboardConfig.languageFunc(text: "button_cancel")), contentItems: contentImtes, otherBlock: { sheet,index,title in
                let colorCase = PTConfigColor.allCases[index]
                let uniConfig = PTBluetoothServerManager.shared.latestData3?.unitType ?? .metric
                let language = PTBluetoothServerManager.shared.latestData3?.languageType ?? .english
                PTBluetoothServerManager.shared.sendConfiguration(color: colorCase, unit: uniConfig, language: language) { finish in
                    self.dashBoardSetResult(finish: finish)
                }
            })
        })
        return view
    }()
    
    lazy var dashUniTitle:UILabel = {
        let view = baseTitle(value: PTDashboardConfig.languageFunc(text: "dashboard_set_title"))
        return view
    }()
    
    lazy var dashBoardUniButton:UIButton = {
        let view = UIButton()
        view.titleLabel?.font = .appfont(size: 16)
        view.setTitleColor(.white, for: .normal)
        view.setTitle(PTBluetoothServerManager.shared.latestData3?.unitType.getTypeName() ?? PTConfigUnit.metric.getTypeName(), for: .normal)
        view.addActionHandlers(handler: { _ in
            let titleItem = PTActionSheetTitleItem()
            titleItem.title = PTDashboardConfig.languageFunc(text: "dashboard_set_title")
            
            let contentImtes = PTConfigUnit.allCases.map { value in
                let model = PTActionSheetItem(title: value.getTypeName())
                return model
            }
            
            UIAlertController.baseCustomActionSheet(titleItem: titleItem,cancelItem: PTActionSheetItem(title: PTDashboardConfig.languageFunc(text: "button_cancel")), contentItems: contentImtes, otherBlock: { sheet,index,title in
                let colorType:PTConfigColor = PTBluetoothServerManager.shared.latestData3?.dashboardColor ?? .blue
                let uniConfig = PTConfigUnit.allCases[index]
                let language = PTConfigLanguage(rawValue: UInt8((PTBluetoothServerManager.shared.latestData3?.language ?? 1)))!
                PTBluetoothServerManager.shared.sendConfiguration(color: colorType, unit: uniConfig, language: language) { finish in
                    self.dashBoardSetResult(finish: finish)
                }
            })
        })
        return view
    }()
    
    lazy var dashLanguageTitle:UILabel = {
        let view = baseTitle(value: PTDashboardConfig.languageFunc(text: "casa_card_lan"))
        return view
    }()
    
    lazy var dashBoardLanguageButton:UIButton = {
        let view = UIButton()
        view.titleLabel?.font = .appfont(size: 16)
        view.setTitleColor(.white, for: .normal)
        view.setTitle(PTBluetoothServerManager.shared.latestData3?.languageType.getTypeName() ?? PTConfigLanguage.english.getTypeName(), for: .normal)
        view.addActionHandlers(handler: { _ in
            let titleItem = PTActionSheetTitleItem()
            titleItem.title = PTDashboardConfig.languageFunc(text: "language_set_title")
            let contentImtes = PTConfigLanguage.allCases.map { value in
                let model = PTActionSheetItem(title: value.getTypeName())
                return model
            }
            
            UIAlertController.baseCustomActionSheet(titleItem: titleItem,cancelItem: PTActionSheetItem(title: PTDashboardConfig.languageFunc(text: "button_cancel")), contentItems: contentImtes, otherBlock: { sheet,index,title in
                let colorType:PTConfigColor = PTBluetoothServerManager.shared.latestData3?.dashboardColor ?? .blue
                let uniConfig = PTBluetoothServerManager.shared.latestData3?.unitType ?? .metric
                let language = PTConfigLanguage.allCases[index]
                PTBluetoothServerManager.shared.sendConfiguration(color: colorType, unit: uniConfig, language: language) { finish in
                    self.dashBoardSetResult(finish: finish)
                }
            })
        })
        return view
    }()

    private lazy var pttRestoreTitle: UILabel = {
        let view = baseTitle(value: PTDashboardConfig.languageFunc(text: "ptt_restore_on_launch"))
        return view
    }()

    private lazy var pttRestoreSwitch: UISwitch = {
        let view = UISwitch()
        view.isOn = PTMotoUserDefaultStruct.PTTLaunchAutoRestoreEnabled
        view.onTintColor = PTDashboardConfig.shared.appMainColor
        view.addTarget(self, action: #selector(pttRestoreSwitchChanged(_:)), for: .valueChanged)
        return view
    }()

    // EN: This row opens the read-only XP400 phone, message and notification setup guide.
    // ES: Esta fila abre la guía de configuración de solo lectura para llamadas, mensajes y avisos del XP400.
    // 中文：此行打开 XP400 电话、短信和通知的只读配置指引。
    private lazy var dashboardNotificationTitle: UILabel = {
        let view = baseTitle(value: PTDashboardConfig.languageFunc(text: "dashboard_notification_title"))
        view.numberOfLines = 0
        return view
    }()

    // EN: The button exposes setup and a delayed local test without claiming that ANCS is active.
    // ES: El botón ofrece configuración y una prueba local diferida sin afirmar que ANCS esté activo.
    // 中文：按钮提供设置和延迟本地测试，但不会伪称 ANCS 已激活。
    private lazy var dashboardNotificationButton: UIButton = {
        let view = UIButton(type: .system)
        view.titleLabel?.font = .appfont(size: 16)
        view.setTitleColor(.white, for: .normal)
        view.setTitle(PTDashboardConfig.languageFunc(text: "dashboard_notification_setup"), for: .normal)
        view.addActionHandlers { [weak self] _ in
            self?.presentDashboardNotificationSupport()
        }
        return view
    }()
    
    lazy var disconnect:UIButton = {
        let view = UIButton(type: .custom)
        view.titleLabel?.font = .appfont(size: 16)
        view.setTitleColor(.white, for: .normal)
        view.setTitle(PTDashboardConfig.languageFunc(text: "button_dis_connect"), for: .normal)
        view.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        view.addActionHandlers { sender in
            if PTDashboardConfig.shared.blueConnected {
                UIAlertController.base_alertVC(title: PTDashboardConfig.languageFunc(text: "button_dis_connect") + "?",okBtns: [PTDashboardConfig.languageFunc(text: "button_confirm")],cancelBtn: PTDashboardConfig.languageFunc(text: "button_cancel"), moreBtn:  { index, title in
                    PTVehicleConnectivityCoordinator.shared.disconnectDashboard()
                })
            } else {
                let vc = PTBLEConnectViewController()
                let nav = PTBaseNavControl(rootViewController: vc)
                nav.modalPresentationStyle = .fullScreen
                self.navigationController?.present(nav, animated: true)
            }
        }
        return view
    }()

    private lazy var garageButton: UIButton = {
        let view = UIButton(type: .system)
        view.titleLabel?.font = .appfont(size: 16)
        view.setTitleColor(.white, for: .normal)
        view.setTitle(PTDashboardConfig.languageFunc(text: "garage_open"), for: .normal)
        view.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        view.addActionHandlers { [weak self] _ in
            let garageViewController = PTMotorcycleGarageViewController()
            self?.navigationController?.pushViewController(garageViewController, animated: true)
        }
        return view
    }()
    
    lazy var globalButton:PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setImage(UIImage(.globe).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            PTDashboardConfig.globalLanguageAlert()
        })
        return view
    }()
                
    lazy var shortCut:UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        view.font = .appfont(size: 13)
        view.textColor = .lightGray
        return view
    }()

    private lazy var shortcutsButton: UIButton = {
        let view = UIButton(type: .system)
        view.titleLabel?.font = .appfont(size: 14)
        view.setTitleColor(PTDashboardConfig.shared.appMainColor, for: .normal)
        view.contentHorizontalAlignment = .left
        view.addActionHandlers { [weak self] _ in
            let guideViewController = PTAutomationGuideViewController()
            self?.navigationController?.pushViewController(guideViewController, animated: true)
        }
        return view
    }()
        
    lazy var versionLabel: UILabel = {
        let label = UILabel()
        // 自动读取 Xcode 中的版本号配置
        let version = kAppVersion ?? "1.0.0"
        let build = kAppBuildVersion ?? "0"
        label.text = "Version \(version) (\(build))"
        label.font = .appfont(size: 12)
        label.textColor = .systemGray
        label.textAlignment = .center
        return label
    }()

    lazy var socialStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.spacing = 25
        return stack
    }()
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setLeftButtons(views: [appLogo])
        setCustomRightButtons(buttons: [globalButton])
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        // MARK: - 1. 创建现代 iOS 风格的设置卡片容器
        let settingsContainer = UIView()
        // 使用半透明白色作为暗黑模式下的卡片底色
        settingsContainer.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        settingsContainer.layer.cornerRadius = 12
        view.addSubview(settingsContainer)
        
        settingsContainer.addSubviews([dashBoadColorTitle, dashBoardColorButton,
                                        dashUniTitle, dashBoardUniButton,
                                        dashLanguageTitle, dashBoardLanguageButton,
                                        pttRestoreTitle, pttRestoreSwitch,
                                        dashboardNotificationTitle, dashboardNotificationButton])
        
        view.addSubviews([garageButton, shortCut, shortcutsButton, disconnect, socialStackView, versionLabel])
        
        setupSocialButtons()
                
        settingsContainer.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total + CGFloat.GlobalItemSpacing)
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
        }
        
        dashBoadColorTitle.snp.makeConstraints { make in
            make.left.equalToSuperview().inset(16)
            make.centerY.equalTo(dashBoardColorButton)
        }
        dashBoardColorButton.snp.makeConstraints { make in
            make.right.equalToSuperview().inset(16)
            make.top.equalToSuperview().inset(16)
            make.height.equalTo(34)
            make.width.greaterThanOrEqualTo(54) // 允许按钮根据文字自动加宽
        }
        
        dashUniTitle.snp.makeConstraints { make in
            make.left.equalToSuperview().inset(16)
            make.centerY.equalTo(dashBoardUniButton)
        }
        dashBoardUniButton.snp.makeConstraints { make in
            make.right.equalToSuperview().inset(16)
            make.top.equalTo(dashBoardColorButton.snp.bottom).offset(20)
            make.height.equalTo(34)
            make.width.greaterThanOrEqualTo(54)
        }
        
        dashLanguageTitle.snp.makeConstraints { make in
            make.left.equalToSuperview().inset(16)
            make.centerY.equalTo(dashBoardLanguageButton)
        }
        dashBoardLanguageButton.snp.makeConstraints { make in
            make.right.equalToSuperview().inset(16)
            make.top.equalTo(dashBoardUniButton.snp.bottom).offset(20)
            make.height.equalTo(34)
            make.width.greaterThanOrEqualTo(dashBoardLanguageButton.sizeFor().width + CGFloat.GlobalItemSpacing * 2)
        }

        pttRestoreTitle.snp.makeConstraints { make in
            make.left.equalToSuperview().inset(16)
            make.right.lessThanOrEqualTo(pttRestoreSwitch.snp.left).offset(-12)
            make.centerY.equalTo(pttRestoreSwitch)
        }
        pttRestoreSwitch.snp.makeConstraints { make in
            make.right.equalToSuperview().inset(16)
            make.top.equalTo(dashBoardLanguageButton.snp.bottom).offset(20)
        }

        dashboardNotificationTitle.snp.makeConstraints { make in
            make.left.equalToSuperview().inset(16)
            make.right.lessThanOrEqualTo(dashboardNotificationButton.snp.left).offset(-12)
            make.centerY.equalTo(dashboardNotificationButton)
        }
        dashboardNotificationButton.snp.makeConstraints { make in
            make.right.equalToSuperview().inset(16)
            make.top.equalTo(pttRestoreSwitch.snp.bottom).offset(20)
            make.height.equalTo(34)
            make.width.greaterThanOrEqualTo(110)
            make.bottom.equalToSuperview().inset(16)
        }
        
        garageButton.snp.makeConstraints { make in
            make.top.equalTo(settingsContainer.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.height.equalTo(44)
        }

        shortCut.snp.makeConstraints { make in
            make.top.equalTo(garageButton.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
        }

        shortcutsButton.snp.makeConstraints { make in
            make.top.equalTo(shortCut.snp.bottom).offset(8)
            make.left.equalTo(shortCut)
            make.height.equalTo(32)
        }

        versionLabel.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.kTabbarHeight_Total + CGFloat.GlobalItemSpacing)
            make.centerX.equalToSuperview()
        }
        
        socialStackView.snp.makeConstraints { make in
            make.bottom.equalTo(versionLabel.snp.top).offset(-CGFloat.GlobalItemSpacing)
            make.centerX.equalToSuperview()
            make.height.equalTo(40)
        }
        
        disconnect.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.height.equalTo(44)
            make.bottom.equalTo(socialStackView.snp.top).offset(-30)
        }
        
        updateShortcutGuide()
        shortcutsButton.setTitle(PTDashboardConfig.languageFunc(text: "automation_guide_open"), for: .normal)
                
        dashBoardColorButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        dashBoardUniButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        dashBoardLanguageButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        dashboardNotificationButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        garageButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        disconnect.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        
        DispatchQueue.main.async {
            self.dashBoardColorButton.viewCorner(radius: 4)
            self.dashBoardUniButton.viewCorner(radius: 4)
            self.dashBoardLanguageButton.viewCorner(radius: 4)
            self.dashboardNotificationButton.viewCorner(radius: 4)
            self.garageButton.viewCorner(radius: 4)
            self.disconnect.viewCorner(radius: 4)
        }

        pt_observerLanguage {
            if self.vcDidLoad {
                self.dashLanguageTitle.text = PTDashboardConfig.languageFunc(text: "casa_card_lan")
                self.dashBoadColorTitle.text = PTDashboardConfig.languageFunc(text: "dashboard_color_set_title")
                self.dashUniTitle.text = PTDashboardConfig.languageFunc(text: "dashboard_set_title")
                self.pttRestoreTitle.text = PTDashboardConfig.languageFunc(text: "ptt_restore_on_launch")
                self.dashboardNotificationTitle.text = PTDashboardConfig.languageFunc(text: "dashboard_notification_title")
                self.dashboardNotificationButton.setTitle(PTDashboardConfig.languageFunc(text: "dashboard_notification_setup"), for: .normal)
                self.disconnect.setTitle(PTDashboardConfig.languageFunc(text: "button_dis_connect"), for: .normal)
                self.garageButton.setTitle(PTDashboardConfig.languageFunc(text: "garage_open"), for: .normal)
                self.updateShortcutGuide()
                self.shortcutsButton.setTitle(PTDashboardConfig.languageFunc(text: "automation_guide_open"), for: .normal)
            }
        }
        vcDidLoad = true
    }
    
    private func setupSocialButtons() {
        let socials = [
            ("X", "https://twitter.com/crazypeepoo", "icon_x"),
            ("IG", "https://instagram.com/jaxdeng_", "icon_ig"),
            ("TG", "https://t.me/JaxTsang", "icon_tg"),
            ("GitHub", "https://github.com/crazypoo", "icon_github"),
            ("FB", "https://facebook.com/jiehao.deng", "icon_fb"),
            ("WA", "https://wa.me/8615336934140", "icon_wa")
        ]
        
        for social in socials {
            let btn = PTBaseButton(type: .custom)
            
            let iconImage = UIImage(named: social.2) ?? UIImage(systemName: "globe")
            
            btn.setImage(iconImage?.withRenderingMode(.alwaysOriginal).transformImage(size: .init(width: 32, height: 32)), for: .normal)
            btn.tintColor = .white // 图标颜色统一设为白色，更具极客感
            
            btn.snp.makeConstraints { make in
                make.width.height.equalTo(36)
            }
            
            // 点击事件：跳转 Safari
            btn.addActionHandlers { _ in
                if let url = URL(string: social.1) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
            
            socialStackView.addArrangedSubview(btn)
        }
    }

    @objc private func pttRestoreSwitchChanged(_ sender: UISwitch) {
        // EN: Persist the opt-in flag; it is evaluated on the next process launch.
        // ES: Guardamos la opción; se evalúa en el siguiente lanzamiento del proceso.
        // 中文：保存用户选择，并在下一次进程启动时读取该开关。
        PTMotoUserDefaultStruct.PTTLaunchAutoRestoreEnabled = sender.isOn
    }

    func baseTitle(value:String) -> UILabel {
        let view = UILabel()
        view.text = value
        view.font = .appfont(size: 16)
        view.textAlignment = .left
        view.textColor = PTDashboardConfig.shared.appMainColor
        return view
    }

    // EN: Present the supported Siri and Shortcuts actions without exposing raw test URLs in the production settings page.
    // ES: Presenta las acciones compatibles de Siri y Atajos sin exponer URL de prueba en los ajustes de producción.
    // 中文：在正式设置页展示支持的 Siri 与快捷指令操作，不再暴露原始测试 URL。
    private func updateShortcutGuide() {
        let title = PTDashboardConfig.languageFunc(text: "shortcuts_title")
        let help = PTDashboardConfig.languageFunc(text: "shortcuts_help")
        shortCut.text = "\(title)\n\(help)"
    }

    // EN: Read the iOS notification permission and dashboard state before showing the support actions.
    // ES: Lee el permiso de notificaciones de iOS y el estado del tablero antes de mostrar las acciones.
    // 中文：显示支持操作前，先读取 iOS 通知权限和仪表连接状态。
    private func presentDashboardNotificationSupport() {
        PTNotificationCenter.authorizationStatus { [weak self] status in
            let authorizationRawValue = status.rawValue
            Task { @MainActor [weak self] in
                guard let self else { return }
                let isDashboardConnected = PTVehicleConnectivityCoordinator.shared.snapshot.isDashboardConnected
                self.showDashboardNotificationSupport(
                    authorizationStatus: UNAuthorizationStatus(rawValue: authorizationRawValue) ?? .notDetermined,
                    isDashboardConnected: isDashboardConnected
                )
            }
        }
    }

    // EN: Explain the native ANCS boundary and expose only safe, read-only actions.
    // ES: Explica el límite de ANCS nativo y expone únicamente acciones seguras de solo lectura.
    // 中文：说明系统 ANCS 的边界，只提供安全的只读操作。
    @MainActor
    private func showDashboardNotificationSupport(
        authorizationStatus: UNAuthorizationStatus,
        isDashboardConnected: Bool
    ) {
        let dashboardStateKey = isDashboardConnected
            ? "dashboard_notification_connected"
            : "dashboard_notification_disconnected"
        let permissionState = notificationPermissionText(authorizationStatus)
        let statusTemplate = PTDashboardConfig.languageFunc(text: "dashboard_notification_status")
        let statusMessage = String(
            format: statusTemplate,
            PTDashboardConfig.languageFunc(text: dashboardStateKey),
            permissionState,
            PTDashboardConfig.languageFunc(text: "dashboard_notification_system_managed")
        )

        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "dashboard_notification_alert_title"),
            message: statusMessage,
            preferredStyle: .actionSheet
        )

        switch authorizationStatus {
        case .notDetermined:
            alert.addAction(UIAlertAction(
                title: PTDashboardConfig.languageFunc(text: "dashboard_notification_request_permission"),
                style: .default
            ) { [weak self] _ in
                self?.requestDashboardNotificationPermission()
            })
        case .denied:
            alert.addAction(UIAlertAction(
                title: PTDashboardConfig.languageFunc(text: "dashboard_notification_open_settings"),
                style: .default
            ) { [weak self] _ in
                self?.openDashboardNotificationSettings()
            })
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            break
        }

        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "dashboard_notification_send_test"),
            style: .default
        ) { [weak self] _ in
            self?.sendDashboardNotificationTest()
        })
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "dashboard_notification_guide"),
            style: .default
        ) { [weak self] _ in
            self?.showDashboardNotificationGuide()
        })
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_cancel"),
            style: .cancel
        ))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = dashboardNotificationButton
            popover.sourceRect = dashboardNotificationButton.bounds
        }
        present(alert, animated: true)
    }

    // EN: Map the system permission to a user-facing state without exposing a false ANCS status.
    // ES: Convierte el permiso del sistema en un estado visible sin inventar un estado de ANCS.
    // 中文：把系统权限映射成用户可理解的状态，不虚构 ANCS 状态。
    @MainActor
    private func notificationPermissionText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return PTDashboardConfig.languageFunc(text: "dashboard_notification_permission_authorized")
        case .denied:
            return PTDashboardConfig.languageFunc(text: "dashboard_notification_permission_denied")
        case .notDetermined:
            return PTDashboardConfig.languageFunc(text: "dashboard_notification_permission_pending")
        case .provisional, .ephemeral:
            return PTDashboardConfig.languageFunc(text: "dashboard_notification_permission_limited")
        @unknown default:
            return PTDashboardConfig.languageFunc(text: "dashboard_notification_permission_unknown")
        }
    }

    // EN: Request permission only after an explicit user action; system ANCS remains independent.
    // ES: Solicita permiso solo tras una acción explícita; el ANCS del sistema sigue siendo independiente.
    // 中文：仅在用户明确操作后申请权限；系统 ANCS 仍由系统独立管理。
    private func requestDashboardNotificationPermission() {
        PTNotificationCenter.requestAuthorization { [weak self] granted, error in
            let errorMessage = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                let message: String
                if let errorMessage, !errorMessage.isEmpty {
                    message = "\(PTDashboardConfig.languageFunc(text: "dashboard_notification_permission_failed")): \(errorMessage)"
                } else if granted {
                    message = PTDashboardConfig.languageFunc(text: "dashboard_notification_permission_updated")
                } else {
                    message = PTDashboardConfig.languageFunc(text: "dashboard_notification_test_denied")
                }
                PTProgressHUD.show(text: message)
                self.dashboardNotificationButton.isEnabled = true
            }
        }
    }

    // EN: Open only the public notification settings URL supplied by iOS.
    // ES: Abre únicamente la URL pública de ajustes de notificaciones proporcionada por iOS.
    // 中文：只打开 iOS 提供的公开通知设置 URL。
    @MainActor
    private func openDashboardNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:])
    }

    // EN: Schedule one delayed local notification so the owner can verify the complete system path.
    // ES: Programa un aviso local retrasado para que el propietario pueda verificar toda la ruta del sistema.
    // 中文：安排一条延迟本地通知，方便用户验证完整的系统通知链路。
    private func sendDashboardNotificationTest() {
        let request = PTNotificationRequest(
            kind: .generic,
            title: PTDashboardConfig.languageFunc(text: "dashboard_notification_test_title"),
            body: PTDashboardConfig.languageFunc(text: "dashboard_notification_test_body"),
            identifier: "pt.dashboard.notification.test.\(UUID().uuidString)",
            interruptionLevel: .active,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )

        PTNotificationCenter.schedule(request) { result in
            Task { @MainActor in
                let message: String
                switch result {
                case .scheduled:
                    message = PTDashboardConfig.languageFunc(text: "dashboard_notification_test_scheduled")
                case .denied:
                    message = PTDashboardConfig.languageFunc(text: "dashboard_notification_test_denied")
                case .notDetermined:
                    message = PTDashboardConfig.languageFunc(text: "dashboard_notification_test_not_determined")
                case .suppressed:
                    message = PTDashboardConfig.languageFunc(text: "dashboard_notification_test_suppressed")
                case .failed(let reason):
                    message = "\(PTDashboardConfig.languageFunc(text: "dashboard_notification_test_failed")): \(reason)"
                }
                PTProgressHUD.show(text: message)
            }
        }
    }

    // EN: Keep the hardware instructions explicit because iOS cannot query or toggle XP400 ANCS sharing.
    // ES: Mantiene instrucciones claras porque iOS no puede consultar ni cambiar el uso de ANCS del XP400.
    // 中文：明确展示硬件设置步骤，因为 iOS 无法读取或切换 XP400 的 ANCS 分享状态。
    @MainActor
    private func showDashboardNotificationGuide() {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "dashboard_notification_guide_title"),
            message: PTDashboardConfig.languageFunc(text: "dashboard_notification_guide_body"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_confirm"),
            style: .default
        ))
        present(alert, animated: true)
    }
    
    func dashBoardSetResult(finish:Bool) {
        if finish {
            PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "set_success"))
            self.globalChangeDashBoardData()
        } else {
            PTGCDManager.shared.delayOnMain(time: 0.55) {
                PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "set_bad"))
            }
        }
    }
    
    func globalChangeDashBoardData() {
        NotificationCenter.default.post(name: MotorcycleDashBoardChange, object: nil)
        PTGCDManager.shared.delayOnMain(time: 0.5) {
            self.dashBoardColorButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
            self.dashBoardUniButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
            self.dashBoardUniButton.setTitle(PTBluetoothServerManager.shared.latestData3?.unitType.getTypeName() ?? PTConfigUnit.metric.getTypeName(), for: .normal)
            self.dashBoardLanguageButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
            self.dashBoardLanguageButton.setTitle(PTBluetoothServerManager.shared.latestData3?.languageType.getTypeName() ?? PTConfigLanguage.english.getTypeName(), for: .normal)
            self.dashBoardLanguageButton.snp.updateConstraints { make in
                make.width.greaterThanOrEqualTo(self.dashBoardLanguageButton.sizeFor().width + CGFloat.GlobalItemSpacing * 2)
            }
            self.dashBoadColorTitle.textColor = PTDashboardConfig.shared.appMainColor
            self.dashUniTitle.textColor = PTDashboardConfig.shared.appMainColor
            self.dashLanguageTitle.textColor = PTDashboardConfig.shared.appMainColor
            self.pttRestoreTitle.textColor = PTDashboardConfig.shared.appMainColor
            self.dashboardNotificationTitle.textColor = PTDashboardConfig.shared.appMainColor
            self.pttRestoreSwitch.onTintColor = PTDashboardConfig.shared.appMainColor
            self.garageButton.setTitle(PTDashboardConfig.languageFunc(text: "garage_open"), for: .normal)
                        
            self.garageButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
            self.dashboardNotificationButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
            self.disconnect.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        }
    }
}
