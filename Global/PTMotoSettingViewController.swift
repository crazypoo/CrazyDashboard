//
//  PTMotoSettingViewController.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 19/7/2026.
//

import UIKit
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
        view.addActionHandlers { _ in
            guard let url = URL(string: "shortcuts://") else { return }
            UIApplication.shared.open(url, options: [:])
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
                                        pttRestoreTitle, pttRestoreSwitch])
        
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
        shortcutsButton.setTitle(PTDashboardConfig.languageFunc(text: "shortcuts_open"), for: .normal)
                
        dashBoardColorButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        dashBoardUniButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        dashBoardLanguageButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        garageButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        disconnect.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        
        DispatchQueue.main.async {
            self.dashBoardColorButton.viewCorner(radius: 4)
            self.dashBoardUniButton.viewCorner(radius: 4)
            self.dashBoardLanguageButton.viewCorner(radius: 4)
            self.garageButton.viewCorner(radius: 4)
            self.disconnect.viewCorner(radius: 4)
        }

        pt_observerLanguage {
            if self.vcDidLoad {
                self.dashLanguageTitle.text = PTDashboardConfig.languageFunc(text: "casa_card_lan")
                self.dashBoadColorTitle.text = PTDashboardConfig.languageFunc(text: "dashboard_color_set_title")
                self.dashUniTitle.text = PTDashboardConfig.languageFunc(text: "dashboard_set_title")
                self.pttRestoreTitle.text = PTDashboardConfig.languageFunc(text: "ptt_restore_on_launch")
                self.disconnect.setTitle(PTDashboardConfig.languageFunc(text: "button_dis_connect"), for: .normal)
                self.garageButton.setTitle(PTDashboardConfig.languageFunc(text: "garage_open"), for: .normal)
                self.updateShortcutGuide()
                self.shortcutsButton.setTitle(PTDashboardConfig.languageFunc(text: "shortcuts_open"), for: .normal)
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
            self.pttRestoreSwitch.onTintColor = PTDashboardConfig.shared.appMainColor
            self.garageButton.setTitle(PTDashboardConfig.languageFunc(text: "garage_open"), for: .normal)
                        
            self.garageButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
            self.disconnect.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        }
    }
}
