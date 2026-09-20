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

// EN: Describes the dashboard values that must be echoed by Data3 before a setting is considered applied.
// ES: Describe los valores del tablero que Data3 debe devolver antes de considerar aplicada la configuración.
// 中文：描述必须由 Data3 回读的仪表值，只有匹配后才认为设置已生效。
struct PTDashboardConfigurationExpectation {
    let color: PTConfigColor
    let unit: PTConfigUnit
    let language: PTConfigLanguage

    // EN: Compare decoded dashboard values instead of the raw mixed bit fields.
    // ES: Compara los valores decodificados del tablero y no los campos de bits mezclados sin procesar.
    // 中文：比较已经解码的仪表值，避免直接比较混合位字段。
    func matches(_ data3: PTDashboardData3) -> Bool {
        guard data3.configurationAvailability.isAvailable,
              data3.languageAvailability.isAvailable else {
            return false
        }
        return data3.dashboardColor.rawValue == color.rawValue &&
        data3.unitType.rawValue == unit.rawValue &&
        data3.languageType.rawValue == language.rawValue
    }
}

class PTMotoSettingViewController: PTMotoBaseViewController {

    // EN: Keep only the latest configuration request while waiting for a Data3 echo.
    // ES: Conserva solo la última solicitud mientras esperamos el eco Data3.
    // 中文：等待 Data3 回读期间只保留最后一次配置请求。
    private var pendingDashboardConfiguration: (token: UUID, expectation: PTDashboardConfigurationExpectation, isSent: Bool)?

    // EN: Cancels the five-second confirmation timeout when the request finishes early.
    // ES: Cancela el tiempo de espera de cinco segundos cuando la solicitud termina antes.
    // 中文：配置提前完成时取消 5 秒确认超时任务。
    private var dashboardConfigurationTimeout: DispatchWorkItem?
    private var dashboardConfigurationSafetyTimer: Timer?
    private var dashboardConfigurationSafetyStableSince: Date?
    private var dashboardConfigurationSafetyDeadline: Date?
    private var pendingDashboardConfigurationCandidate: PTDashboardConfigurationExpectation?
    private var dashboardConfigurationTipViewController: UIViewController?

    // EN: Keep the settings page scrollable as new controls are added.
    // ES: Mantén desplazable la página de ajustes cuando se añadan nuevos controles.
    // 中文：随着设置项增加，保证设置页始终可以滚动展示。
    private let settingsScrollView = UIScrollView()
    private let settingsContentStack = UIStackView()
    private let settingsRowsStack = UIStackView()

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
                self.requestDashboardConfiguration(color: colorCase, unit: uniConfig, language: language)
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
                let language = PTBluetoothServerManager.shared.latestData3?.languageType ?? .english
                self.requestDashboardConfiguration(color: colorType, unit: uniConfig, language: language)
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
                self.requestDashboardConfiguration(color: colorType, unit: uniConfig, language: language)
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

    // EN: Online lyrics are opt-in because song metadata is sent to the third-party matcher.
    // ES: Las letras en línea requieren consentimiento porque se envían metadatos al servicio externo.
    // 中文：在线歌词需要用户同意，因为歌曲元数据会发送给第三方匹配服务。
    private lazy var lyricsOnlineTitle: UILabel = {
        baseTitle(value: PTDashboardConfig.languageFunc(text: "lyrics_online_toggle"))
    }()

    private lazy var lyricsOnlineSwitch: UISwitch = {
        let view = UISwitch()
        view.isOn = PTLyricsSettings.onlineLookupEnabled
        view.onTintColor = PTDashboardConfig.shared.appMainColor
        view.addTarget(self, action: #selector(lyricsOnlineSwitchChanged(_:)), for: .valueChanged)
        return view
    }()

    // EN: Artwork theming is opt-in at the presentation layer and never changes vehicle semantics.
    // ES: El tema de portada es opcional en la presentación y nunca cambia la semántica del vehículo.
    // 中文：专辑封面主题只控制展示，并且不会改变车辆语义。
    private lazy var artworkThemeTitle: UILabel = {
        baseTitle(value: PTDashboardConfig.languageFunc(text: "dashboard_artwork_theme_toggle"))
    }()

    private lazy var artworkThemeSwitch: UISwitch = {
        let view = UISwitch()
        view.isOn = PTMotoUserDefaultStruct.PTDashboardArtworkThemeEnabled
        view.onTintColor = PTDashboardConfig.shared.appMainColor
        view.addTarget(self, action: #selector(artworkThemeSwitchChanged(_:)), for: .valueChanged)
        return view
    }()

    // EN: The Pit Wall is an opt-in, read-only second-screen server on the local Wi-Fi network.
    // ES: El Pit Wall es un servidor de segunda pantalla, opcional y de solo lectura, en la red Wi-Fi local.
    // 中文：Pit Wall 是仅局域网、默认关闭、只读的第二屏服务。
    private lazy var pitWallTitle: UILabel = {
        baseTitle(value: PTDashboardConfig.languageFunc(text: "pit_wall_title"))
    }()

    private lazy var pitWallSwitch: UISwitch = {
        let view = UISwitch()
        view.isOn = PTMotoUserDefaultStruct.PTPitWallEnabled
        view.onTintColor = PTDashboardConfig.shared.appMainColor
        view.addTarget(self, action: #selector(pitWallSwitchChanged(_:)), for: .valueChanged)
        return view
    }()

    private lazy var pitWallPairingButton: UIButton = {
        let view = UIButton(type: .system)
        view.titleLabel?.font = .appfont(size: 14)
        view.setTitleColor(.white, for: .normal)
        view.setTitle(PTDashboardConfig.languageFunc(text: "pit_wall_pairing"), for: .normal)
        view.addActionHandlers { [weak self] _ in
            self?.showPitWallPairing()
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
    
    lazy var feedbackButton:PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setImage(UIImage(.pencil).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            let actions = [
                PTDashboardConfig.languageFunc(text: "Feedback"),
                PTDashboardConfig.languageFunc(text: "Notification"),
                PTDashboardConfig.languageFunc(text: "Suggestion")
            ]
            UIAlertController.base_alertVC(title: PTDashboardConfig.languageFunc(text: "Feedback & Notification"), titleColor: PTDashboardConfig.shared.appMainColor, titleFont: .appfont(size: 16), okBtns: actions, cancelBtn: PTDashboardConfig.languageFunc(text: "button_cancel"), showIn: PTUtils.getCurrentVC(), cancelBtnColor: .systemBlue, doneBtnColors: [.systemBlue], moreBtn:  { index, title in
                switch index {
                case 0:
                    self.navigationController?.pushViewController(
                        PTFeedbackCenterViewController(),
                        animated: true
                    )
                case 1:
                    self.navigationController?.pushViewController(
                        PTAnnouncementListViewController(),
                        animated: true
                    )
                case 2:
                    self.navigationController?.pushViewController(
                        PTFeatureSuggestionListViewController(),
                        animated: true
                    )
                default:
                    break
                }
            })
        })
        return view
    }()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setLeftButtons(views: [appLogo])
        setCustomRightButtons(buttons: [feedbackButton,globalButton],buttonSpacing:CGFloat.GlobalItemSpacing)
    }

    // EN: Do not surface a delayed confirmation after leaving the settings screen.
    // ES: No muestres una confirmación retrasada después de abandonar la pantalla de ajustes.
    // 中文：离开设置页后不再显示延迟到达的配置确认。
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelDashboardConfigurationWait()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        // EN: One vertical scroll hierarchy keeps every setting reachable on small screens.
        // ES: Una sola jerarquía vertical desplazable mantiene accesibles todos los ajustes en pantallas pequeñas.
        // 中文：使用统一的纵向滚动层，保证小屏幕也能访问所有设置项。
        let settingsContainer = UIView()
        settingsContainer.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        settingsContainer.layer.cornerRadius = 12

        settingsRowsStack.axis = .vertical
        settingsRowsStack.alignment = .fill
        settingsRowsStack.spacing = 16
        settingsRowsStack.addArrangedSubview(
            makeSettingRow(title: dashBoadColorTitle, control: dashBoardColorButton)
        )
        settingsRowsStack.addArrangedSubview(
            makeSettingRow(title: dashUniTitle, control: dashBoardUniButton)
        )
        settingsRowsStack.addArrangedSubview(
            makeSettingRow(title: dashLanguageTitle, control: dashBoardLanguageButton)
        )
        settingsRowsStack.addArrangedSubview(
            makeSettingRow(title: pttRestoreTitle, control: pttRestoreSwitch)
        )
        settingsRowsStack.addArrangedSubview(
            makeSettingRow(title: dashboardNotificationTitle, control: dashboardNotificationButton)
        )
        settingsRowsStack.addArrangedSubview(
            makeSettingRow(title: lyricsOnlineTitle, control: lyricsOnlineSwitch)
        )
        settingsRowsStack.addArrangedSubview(
            makeSettingRow(title: artworkThemeTitle, control: artworkThemeSwitch)
        )
        settingsRowsStack.addArrangedSubview(
            makeSettingRow(title: pitWallTitle, control: pitWallSwitch)
        )
        settingsRowsStack.addArrangedSubview(makeTrailingButtonRow(pitWallPairingButton))
        settingsContainer.addSubview(settingsRowsStack)
        settingsRowsStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(16)
        }

        settingsScrollView.alwaysBounceVertical = true
        settingsScrollView.showsVerticalScrollIndicator = true
        settingsScrollView.keyboardDismissMode = .onDrag
        settingsScrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(settingsScrollView)
        settingsScrollView.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total)
            make.left.right.equalToSuperview()
            make.bottom.equalToSuperview().inset(CGFloat.kTabbarHeight_Total)
        }

        settingsContentStack.axis = .vertical
        settingsContentStack.alignment = .fill
        settingsContentStack.spacing = CGFloat.GlobalItemSpacing
        settingsContentStack.isLayoutMarginsRelativeArrangement = true
        settingsContentStack.layoutMargins = UIEdgeInsets(
            top: CGFloat.GlobalItemSpacing,
            left: PTAppBaseConfig.share.defaultViewSpace,
            bottom: CGFloat.GlobalItemSpacing,
            right: PTAppBaseConfig.share.defaultViewSpace
        )
        settingsScrollView.addSubview(settingsContentStack)
        settingsContentStack.snp.makeConstraints { make in
            make.edges.equalTo(settingsScrollView.contentLayoutGuide)
            make.width.equalTo(settingsScrollView.frameLayoutGuide)
        }

        setupSocialButtons()

        // EN: Keep the confirmation hint in the same scroll hierarchy as its controls.
        // ES: Mantén la sugerencia de confirmación en la misma jerarquía desplazable que sus controles.
        // 中文：将确认提示放入与仪表设置相同的滚动层级中。
        if #available(iOS 17.0, *) {
            let tipViewController = PTTipKitHintFactory.makeViewController(PTDashboardConfigurationTip())
            addChild(tipViewController)
            tipViewController.view.setContentHuggingPriority(.required, for: .vertical)
            tipViewController.view.setContentCompressionResistancePriority(.required, for: .vertical)
            tipViewController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
            dashboardConfigurationTipViewController = tipViewController
        }

        settingsContentStack.addArrangedSubview(settingsContainer)
        if let tipViewController = dashboardConfigurationTipViewController {
            settingsContentStack.addArrangedSubview(tipViewController.view)
            tipViewController.didMove(toParent: self)
        }
        settingsContentStack.addArrangedSubview(garageButton)
        settingsContentStack.addArrangedSubview(shortCut)
        settingsContentStack.addArrangedSubview(shortcutsButton)
        settingsContentStack.addArrangedSubview(socialStackView)
        settingsContentStack.addArrangedSubview(versionLabel)

        dashBoardColorButton.snp.makeConstraints { make in
            make.height.equalTo(34)
            make.width.greaterThanOrEqualTo(54)
        }
        dashBoardUniButton.snp.makeConstraints { make in
            make.height.equalTo(34)
            make.width.greaterThanOrEqualTo(54)
        }
        dashBoardLanguageButton.snp.makeConstraints { make in
            make.height.equalTo(34)
            make.width.greaterThanOrEqualTo(54)
        }
        dashboardNotificationButton.snp.makeConstraints { make in
            make.height.equalTo(34)
            make.width.greaterThanOrEqualTo(110)
        }
        pitWallPairingButton.snp.makeConstraints { make in
            make.height.equalTo(34)
            make.width.greaterThanOrEqualTo(140)
        }

        garageButton.snp.makeConstraints { make in
            make.height.equalTo(44)
        }
        shortcutsButton.snp.makeConstraints { make in
            make.height.equalTo(32)
        }
        socialStackView.snp.makeConstraints { make in
            make.height.equalTo(40)
        }
                
        updateShortcutGuide()
        shortcutsButton.setTitle(PTDashboardConfig.languageFunc(text: "automation_guide_open"), for: .normal)
                
        dashBoardColorButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        dashBoardUniButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        dashBoardLanguageButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        dashboardNotificationButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        garageButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        artworkThemeSwitch.onTintColor = PTDashboardConfig.shared.appMainColor
        pitWallPairingButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        
        DispatchQueue.main.async {
            self.dashBoardColorButton.viewCorner(radius: 4)
            self.dashBoardUniButton.viewCorner(radius: 4)
            self.dashBoardLanguageButton.viewCorner(radius: 4)
            self.dashboardNotificationButton.viewCorner(radius: 4)
            self.garageButton.viewCorner(radius: 4)
            self.pitWallPairingButton.viewCorner(radius: 4)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pitWallStateChanged),
            name: PTPitWallManager.didChange,
            object: PTPitWallManager.shared
        )

        pt_observerLanguage {
            if self.vcDidLoad {
                self.dashLanguageTitle.text = PTDashboardConfig.languageFunc(text: "casa_card_lan")
                self.dashBoadColorTitle.text = PTDashboardConfig.languageFunc(text: "dashboard_color_set_title")
                self.dashUniTitle.text = PTDashboardConfig.languageFunc(text: "dashboard_set_title")
                self.pttRestoreTitle.text = PTDashboardConfig.languageFunc(text: "ptt_restore_on_launch")
                self.dashboardNotificationTitle.text = PTDashboardConfig.languageFunc(text: "dashboard_notification_title")
                self.dashboardNotificationButton.setTitle(PTDashboardConfig.languageFunc(text: "dashboard_notification_setup"), for: .normal)
                self.lyricsOnlineTitle.text = PTDashboardConfig.languageFunc(text: "lyrics_online_toggle")
                self.artworkThemeTitle.text = PTDashboardConfig.languageFunc(text: "dashboard_artwork_theme_toggle")
                self.pitWallTitle.text = PTDashboardConfig.languageFunc(text: "pit_wall_title")
                self.pitWallPairingButton.setTitle(PTDashboardConfig.languageFunc(text: "pit_wall_pairing"), for: .normal)
                self.garageButton.setTitle(PTDashboardConfig.languageFunc(text: "garage_open"), for: .normal)
                self.updateShortcutGuide()
                self.shortcutsButton.setTitle(PTDashboardConfig.languageFunc(text: "automation_guide_open"), for: .normal)
            }
        }
        vcDidLoad = true
    }

    // EN: Use a reusable row so localized titles can wrap without colliding with controls.
    // ES: Usa una fila reutilizable para que los títulos localizados se ajusten sin chocar con los controles.
    // 中文：使用可复用行，让多语言标题自动换行，避免与控件重叠。
    private func makeSettingRow(title: UILabel, control: UIView) -> UIStackView {
        title.numberOfLines = 0
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [title, control])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .fill
        row.spacing = 12
        return row
    }

    // EN: Keep secondary actions right-aligned while letting the card determine its height.
    // ES: Mantén las acciones secundarias alineadas a la derecha y deja que la tarjeta determine su altura.
    // 中文：让次级操作保持右对齐，并由卡片内容自动决定高度。
    private func makeTrailingButtonRow(_ button: UIButton) -> UIStackView {
        let spacer = UIView()
        let row = UIStackView(arrangedSubviews: [spacer, button])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .fill
        row.spacing = 12
        return row
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

    @objc private func lyricsOnlineSwitchChanged(_ sender: UISwitch) {
        if sender.isOn, !PTLyricsSettings.consentPrompted {
            sender.setOn(false, animated: true)

            // EN: Ask once before sending song metadata to the optional online matcher.
            // ES: Pregunta una vez antes de enviar metadatos de canciones al buscador opcional.
            // 中文：在向可选在线匹配服务发送歌曲元数据前，先进行一次明确确认。
            let alert = UIAlertController(
                title: PTDashboardConfig.languageFunc(text: "lyrics_online_title"),
                message: PTDashboardConfig.languageFunc(text: "lyrics_online_consent"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(
                title: PTDashboardConfig.languageFunc(text: "button_cancel"),
                style: .cancel
            ) { _ in
                PTLyricsSettings.setOnlineLookupEnabled(false)
            })
            alert.addAction(UIAlertAction(
                title: PTDashboardConfig.languageFunc(text: "lyrics_online_enable"),
                style: .default
            ) { [weak self] _ in
                PTLyricsSettings.setOnlineLookupEnabled(true)
                self?.lyricsOnlineSwitch.setOn(true, animated: true)
            })
            present(alert, animated: true)
            return
        }

        PTLyricsSettings.setOnlineLookupEnabled(sender.isOn)
        if !sender.isOn {
            Task {
                await PTLyricsService.shared.clearCache()
            }
        }
    }

    @objc private func artworkThemeSwitchChanged(_ sender: UISwitch) {
        PTDashboardThemeEngine.shared.setEnabled(sender.isOn)
    }

    @objc private func pitWallSwitchChanged(_ sender: UISwitch) {
        PTPitWallManager.shared.setEnabled(sender.isOn)
    }

    @objc private func pitWallStateChanged() {
        pitWallSwitch.setOn(PTPitWallManager.shared.isEnabled, animated: true)
    }

    private func showPitWallPairing() {
        let manager = PTPitWallManager.shared
        guard manager.isEnabled else {
            presentPitWallAlert(
                title: PTDashboardConfig.languageFunc(text: "pit_wall_disabled_title"),
                message: PTDashboardConfig.languageFunc(text: "pit_wall_disabled_message"),
                shareText: nil
            )
            return
        }

        guard let pairingText = manager.pairingText else {
            presentPitWallAlert(
                title: PTDashboardConfig.languageFunc(text: "pit_wall_waiting_title"),
                message: PTDashboardConfig.languageFunc(text: "pit_wall_waiting_message"),
                shareText: nil
            )
            return
        }

        presentPitWallAlert(
            title: PTDashboardConfig.languageFunc(text: "pit_wall_pairing_title"),
            message: pairingText,
            shareText: pairingText
        )
    }

    private func presentPitWallAlert(title: String, message: String, shareText: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if let shareText {
            alert.addAction(UIAlertAction(
                title: PTDashboardConfig.languageFunc(text: "pit_wall_share"),
                style: .default
            ) { [weak self] _ in
                let activity = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
                if let popover = activity.popoverPresentationController {
                    popover.sourceView = self?.pitWallPairingButton
                    popover.sourceRect = self?.pitWallPairingButton.bounds ?? .zero
                }
                self?.present(activity, animated: true)
            })
        }
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_cancel"),
            style: .cancel
        ))
        present(alert, animated: true)
    }

    func baseTitle(value:String) -> UILabel {
        let view = UILabel()
        view.text = value
        view.font = .appfont(size: 16)
        view.textAlignment = .left
        view.textColor = PTDashboardConfig.shared.appMainColor
        return view
    }

    // EN: Accept success only after the dashboard echoes all requested values in Data3.
    // ES: Acepta el éxito solo después de que el tablero devuelva todos los valores solicitados en Data3.
    // 中文：只有仪表通过 Data3 回读全部目标值后才确认成功。
    override func handleMotorcycleData(data: Any?) {
        guard let data3 = data as? PTDashboardData3,
              let pending = pendingDashboardConfiguration,
              pending.isSent,
              pending.expectation.matches(data3) else {
            return
        }

        pendingDashboardConfiguration = nil
        dashboardConfigurationTimeout?.cancel()
        dashboardConfigurationTimeout = nil
        saveDashboardConfigurationProfile(pending.expectation)
        PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "set_success"))
        globalChangeDashBoardData()
    }

    // EN: Ask for confirmation before the stationary safety check and any write attempt.
    // ES: Solicita confirmación antes de comprobar que la moto está parada y de intentar escribir.
    // 中文：在静止安全检查和任何写入尝试前先请求用户确认。
    private func requestDashboardConfiguration(color: PTConfigColor, unit: PTConfigUnit, language: PTConfigLanguage) {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "dashboard_config_safety_title"),
            message: PTDashboardConfig.languageFunc(text: "dashboard_config_safety_message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "dashboard_config_confirm"),
            style: .default
        ) { [weak self] _ in
            self?.startDashboardConfigurationSafetyCheck(
                expectation: PTDashboardConfigurationExpectation(color: color, unit: unit, language: language)
            )
        })
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_cancel"),
            style: .cancel
        ))
        present(alert, animated: true)
    }

    // EN: Require a fresh real-dashboard speed below 1 km/h for three continuous seconds.
    // ES: Exige una velocidad fresca del tablero real inferior a 1 km/h durante tres segundos continuos.
    // 中文：要求真实仪表的新鲜速度连续三秒低于 1 km/h。
    private func startDashboardConfigurationSafetyCheck(expectation: PTDashboardConfigurationExpectation) {
        cancelDashboardConfigurationWait()

        let vehicleSnapshot = PTVehicleConnectivityCoordinator.shared.snapshot
        guard vehicleSnapshot.dashboard.state == .connected,
              vehicleSnapshot.dashboard.transport == .dashboardBluetooth else {
            PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "dashboard_config_safety_real_only"))
            return
        }

        pendingDashboardConfigurationCandidate = expectation
        dashboardConfigurationSafetyStableSince = nil
        dashboardConfigurationSafetyDeadline = Date().addingTimeInterval(10)
        PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "dashboard_config_safety_checking"))

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateDashboardConfigurationSafety()
            }
        }
        dashboardConfigurationSafetyTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        evaluateDashboardConfigurationSafety()
    }

    private func evaluateDashboardConfigurationSafety() {
        guard let expectation = pendingDashboardConfigurationCandidate else { return }
        guard Date() <= (dashboardConfigurationSafetyDeadline ?? .distantPast) else {
            finishDashboardConfigurationSafety(
                messageKey: "dashboard_config_safety_timeout"
            )
            return
        }

        let vehicleSnapshot = PTVehicleConnectivityCoordinator.shared.snapshot
        guard vehicleSnapshot.dashboard.state == .connected,
              vehicleSnapshot.dashboard.transport == .dashboardBluetooth else {
            finishDashboardConfigurationSafety(messageKey: "dashboard_config_safety_real_only")
            return
        }

        guard let speedSample = PTVehicleConnectivityCoordinator.shared.telemetrySnapshot.dashboardSpeedKmh,
              speedSample.source == .dashboardBluetooth,
              speedSample.isFresh(maximumAge: 2) else {
            dashboardConfigurationSafetyStableSince = nil
            return
        }

        guard speedSample.value < 1 else {
            dashboardConfigurationSafetyStableSince = nil
            return
        }

        dashboardConfigurationSafetyStableSince = dashboardConfigurationSafetyStableSince ?? Date()
        guard Date().timeIntervalSince(dashboardConfigurationSafetyStableSince ?? Date()) >= 3 else { return }

        dashboardConfigurationSafetyTimer?.invalidate()
        dashboardConfigurationSafetyTimer = nil
        dashboardConfigurationSafetyStableSince = nil
        dashboardConfigurationSafetyDeadline = nil
        pendingDashboardConfigurationCandidate = nil
        sendDashboardConfiguration(
            color: expectation.color,
            unit: expectation.unit,
            language: expectation.language
        )
    }

    private func finishDashboardConfigurationSafety(messageKey: String) {
        dashboardConfigurationSafetyTimer?.invalidate()
        dashboardConfigurationSafetyTimer = nil
        dashboardConfigurationSafetyStableSince = nil
        dashboardConfigurationSafetyDeadline = nil
        pendingDashboardConfigurationCandidate = nil
        PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: messageKey))
    }

    // EN: Show transport success immediately, then wait up to five seconds for the dashboard echo.
    // ES: Muestra el envío inmediato y espera hasta cinco segundos el eco del tablero.
    // 中文：传输成功后立即显示已发送，并等待仪表最多 5 秒回读确认。
    private func sendDashboardConfiguration(color: PTConfigColor, unit: PTConfigUnit, language: PTConfigLanguage) {
        cancelDashboardConfigurationWait()

        let requestToken = UUID()
        let expectation = PTDashboardConfigurationExpectation(color: color, unit: unit, language: language)
        pendingDashboardConfiguration = (token: requestToken, expectation: expectation, isSent: false)

        PTBluetoothServerManager.shared.sendConfiguration(color: color, unit: unit, language: language) { [weak self] didSend in
            guard let self, var pending = self.pendingDashboardConfiguration, pending.token == requestToken else { return }

            guard didSend else {
                self.pendingDashboardConfiguration = nil
                PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "set_bad"))
                return
            }

            pending.isSent = true
            self.pendingDashboardConfiguration = pending
            // EN: Save the requested values only after the transport accepted the command.
            // ES: Guarda los valores solicitados solo después de que el transporte acepte el comando.
            // 中文：只有传输层接受指令后，才保存本次请求的配置值。
            self.saveDashboardConfigurationProfile(expectation)
            PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "dashboard_config_sent"))
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.pendingDashboardConfiguration?.token == requestToken else { return }
                self.pendingDashboardConfiguration = nil
                self.dashboardConfigurationTimeout = nil
                PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "dashboard_config_unconfirmed"))
            }
            self.dashboardConfigurationTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
        }
    }

    // EN: Keep a per-vehicle last-requested profile for diagnostics and later Data3 comparison.
    // ES: Conserva por vehículo el último perfil solicitado para diagnóstico y comparación posterior con Data3.
    // 中文：按车辆保存最后请求的配置，供诊断和后续 Data3 对比使用。
    private func saveDashboardConfigurationProfile(_ expectation: PTDashboardConfigurationExpectation) {
        PTDashboardConfigurationProfileStore.shared.save(
            PTDashboardConfigurationProfile(
                colorRawValue: expectation.color.rawValue,
                unitRawValue: expectation.unit.rawValue,
                languageRawValue: expectation.language.rawValue
            ),
            for: PTMotorcycleGarageStore.shared.selectedVehicleID
        )
    }

    // EN: Clear the pending request and its timeout as one lifecycle operation.
    // ES: Limpia la solicitud pendiente y su tiempo de espera como una sola operación de ciclo de vida.
    // 中文：将待确认请求和超时任务作为一个生命周期整体清理。
    private func cancelDashboardConfigurationWait() {
        pendingDashboardConfiguration = nil
        dashboardConfigurationTimeout?.cancel()
        dashboardConfigurationTimeout = nil
        dashboardConfigurationSafetyTimer?.invalidate()
        dashboardConfigurationSafetyTimer = nil
        dashboardConfigurationSafetyStableSince = nil
        dashboardConfigurationSafetyDeadline = nil
        pendingDashboardConfigurationCandidate = nil
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
            self?.sendLocalNotificationTest()
        })
        // EN: Offer the real-device verification path separately from the local iPhone test.
        // ES: Ofrece por separado la verificación en dispositivo real de la prueba local del iPhone.
        // 中文：将真机仪表验证与 iPhone 本地通知测试分开提供。
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "dashboard_notification_verify_ancs"),
            style: .default
        ) { [weak self] _ in
            self?.showDashboardANCSVerificationGuide()
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

    // EN: Schedule a local iPhone notification; iOS does not expose dashboard ANCS delivery to this app.
    // ES: Programa una notificación local del iPhone; iOS no expone a esta app la entrega ANCS al tablero.
    // 中文：安排一条 iPhone 本地通知；iOS 不向本 App 暴露仪表 ANCS 投递结果。
    private func sendLocalNotificationTest() {
        let request = PTNotificationRequest(
            kind: .generic,
            title: PTDashboardConfig.languageFunc(text: "dashboard_notification_test_title"),
            body: PTDashboardConfig.languageFunc(text: "dashboard_notification_test_body"),
            identifier: "pt.dashboard.notification.test.\(UUID().uuidString)",
            interruptionLevel: .active,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        )

        Task { @MainActor in
            let result = await PTXP400ANCSCoordinator.shared.scheduleSystemNotification(request)
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

    // EN: Explain the real-device ANCS verification path without claiming that a local notification reaches the instrument.
    // ES: Explica la verificación ANCS en un dispositivo real sin afirmar que una notificación local llega al tablero.
    // 中文：说明真机 ANCS 验证路径，不把本地通知误认为已到达仪表。
    @MainActor
    private func showDashboardANCSVerificationGuide() {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "dashboard_notification_verify_ancs_title"),
            message: PTDashboardConfig.languageFunc(text: "dashboard_notification_verify_ancs_body"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_confirm"),
            style: .default
        ))
        present(alert, animated: true)
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
            self.lyricsOnlineTitle.textColor = PTDashboardConfig.shared.appMainColor
            self.artworkThemeTitle.textColor = PTDashboardConfig.shared.appMainColor
            self.pttRestoreSwitch.onTintColor = PTDashboardConfig.shared.appMainColor
            self.lyricsOnlineSwitch.onTintColor = PTDashboardConfig.shared.appMainColor
            self.artworkThemeSwitch.onTintColor = PTDashboardConfig.shared.appMainColor
            self.garageButton.setTitle(PTDashboardConfig.languageFunc(text: "garage_open"), for: .normal)
                        
            self.garageButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
            self.dashboardNotificationButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        }
    }
}
