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
import AttributedString

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
    
    lazy var messageTestButton:UIButton = {
        let view = UIButton()
        view.backgroundColor = PTDashboardConfig.shared.appMainColor
        view.addActionHandlers { sender in
            PTMessagePusher.pushToDashboard(title: "1111", body: "222222222222")
        }
        view.isHidden = true
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
                    PTBluetoothServerManager.shared.sendDisconnect()
                    PTDashboardConfig.shared.blueConnected = false
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
    
    lazy var globalButton:PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setImage(UIImage(.globe).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            PTDashboardConfig.globalLanguageAlert()
        })
        return view
    }()
    
    lazy var proButton:UIButton = {
        let view = UIButton()
        view.titleLabel?.font = .appfont(size: 16)
        view.setTitleColor(.white, for: .normal)
        view.setTitle(PTDashboardConfig.languageFunc(text: "button_pro"), for: .normal)
        view.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        view.addActionHandlers { sender in
            let vc = PTDashBoardBaseBoardViewController()
            self.navigationController?.pushViewController(vc, animated: true)
        }
        return view
    }()
            
    lazy var shortCut:UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        return view
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
        
        // 将设置项统一加入卡片容器
        settingsContainer.addSubviews([dashBoadColorTitle, dashBoardColorButton,
                                       dashUniTitle, dashBoardUniButton,
                                       dashLanguageTitle, dashBoardLanguageButton])
        
        // 其他独立组件直接加入主视图
        view.addSubviews([shortCut, messageTestButton, proButton, disconnect])
        
        // MARK: - 2. 开始优雅的 SnapKit 布局
        
        // 卡片容器的整体位置
        settingsContainer.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total + 20)
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
        }
        
        // 第一行：仪表盘颜色 (左标题，右按钮)
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
        
        // 第二行：单位设置
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
        
        // 第三行：语言设置
        dashLanguageTitle.snp.makeConstraints { make in
            make.left.equalToSuperview().inset(16)
            make.centerY.equalTo(dashBoardLanguageButton)
        }
        dashBoardLanguageButton.snp.makeConstraints { make in
            make.right.equalToSuperview().inset(16)
            make.top.equalTo(dashBoardUniButton.snp.bottom).offset(20)
            make.height.equalTo(34)
            make.width.greaterThanOrEqualTo(dashBoardLanguageButton.sizeFor().width + CGFloat.GlobalItemSpacing * 2)
            make.bottom.equalToSuperview().inset(16)
        }
        
        // 快捷指令说明 (紧贴卡片下方)
        shortCut.snp.makeConstraints { make in
            make.top.equalTo(settingsContainer.snp.bottom).offset(20)
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
        }
        
        // 底部断开连接按钮 (紧贴底部安全区)
        disconnect.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.height.equalTo(44)
            make.bottom.equalToSuperview().inset(CGFloat.kTabbarHeight_Total + 20)
        }
        
        // 底部高级功能按钮 (在断开连接按钮的上方)
        proButton.snp.makeConstraints { make in
            make.left.right.height.equalTo(disconnect)
            make.bottom.equalTo(disconnect.snp.top).offset(-16)
        }
        
        // 隐藏的测试按钮
        messageTestButton.snp.makeConstraints { make in
            make.size.equalTo(34)
            make.centerX.equalToSuperview()
            make.bottom.equalTo(proButton.snp.top).offset(-20)
        }
        
        // MARK: - 3. 逻辑与样式装配
        
        let shortAtt: ASAttributedString = """
        \(wrap: .embedding("""
        \(PTDashboardConfig.languageFunc(text: "Support shortcut"),.foreground(PTDashboardConfig.shared.appMainColor),.font(.appfont(size: 13)))
        \("xp400://checkFuel",.foreground(PTDashboardConfig.shared.appMainColor),.font(.appfont(size: 13)))
        \("xp400://antiTheft?enable=true OR xp400://antiTheft?enable=false",.foreground(PTDashboardConfig.shared.appMainColor),.font(.appfont(size: 13)))
        \("xp400://openHUD",.foreground(PTDashboardConfig.shared.appMainColor),.font(.appfont(size: 13)))
        \("xp400://confirmGasStationRoute",.foreground(PTDashboardConfig.shared.appMainColor),.font(.appfont(size: 13)))
        \("xp400://navigate?destination=",.foreground(PTDashboardConfig.shared.appMainColor),.font(.appfont(size: 13)))
        """),.paragraph(.alignment(.left)))
        """
        shortCut.attributed.text = shortAtt
                
        dashBoardColorButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        dashBoardUniButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        dashBoardLanguageButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        disconnect.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        
        // 利用异步队列保证 AutoLayout 已经完成 frame 计算，切圆角才不会发生偏移或失效
        DispatchQueue.main.async {
            self.dashBoardColorButton.viewCorner(radius: 4)
            self.dashBoardUniButton.viewCorner(radius: 4)
            self.dashBoardLanguageButton.viewCorner(radius: 4)
            self.disconnect.viewCorner(radius: 4)
            self.proButton.viewCorner(radius: 4)
        }

        pt_observerLanguage {
            if self.vcDidLoad {
                self.dashLanguageTitle.text = PTDashboardConfig.languageFunc(text: "casa_card_lan")
                self.dashBoadColorTitle.text = PTDashboardConfig.languageFunc(text: "dashboard_color_set_title")
                self.dashUniTitle.text = PTDashboardConfig.languageFunc(text: "dashboard_set_title")
                self.disconnect.setTitle(PTDashboardConfig.languageFunc(text: "button_dis_connect"), for: .normal)
                self.proButton.setTitle(PTDashboardConfig.languageFunc(text: "button_pro"), for: .normal)
            }
        }
        vcDidLoad = true
    }
    
    func baseTitle(value:String) -> UILabel {
        let view = UILabel()
        view.text = value
        view.font = .appfont(size: 16)
        view.textAlignment = .left
        view.textColor = PTDashboardConfig.shared.appMainColor
        return view
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
                        
            self.disconnect.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
            self.proButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        }
    }
}
