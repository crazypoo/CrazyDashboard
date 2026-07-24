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

    open override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        return .solid(.clear)
    }

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
        view.setImage(UIImage(.globe), for: .normal)
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
        
    lazy var tcsValueLabel:UIButton = {
        let name = PTBluetoothServerManager.shared.latestControl?.tcsMode.description
        let view = UIButton(type: .custom)
        view.titleLabel?.font = .appfont(size: 16)
        view.setTitleColor(PTDashboardConfig.shared.appMainColor, for: .normal)
        view.setTitle("TCS mode:" + (name ?? PTTCSMode.unknown.description), for: .normal)
        view.addActionHandlers(handler: { _ in
            let ids:[UInt8] = [UInt8(2),UInt8(3),UInt8(4),UInt8(5),UInt8(6)]
            let nameMap:[String] = ids.map { value in
                return "\(value)"
            }
            UIAlertController.base_alertVC(title: "Test",okBtns: nameMap,cancelBtn: PTDashboardConfig.languageFunc(text: "button_cancel"), moreBtn:  { index, title in
                PTBluetoothServerManager.shared.sendTCSMode(id: UInt8(7), mode: PTTCSMode.off)
            })
        })
        return view
    }()

    lazy var lightValueLabel:UIButton = {
        let name = PTBluetoothServerManager.shared.latestData2?.backlightMode.description
        let view = UIButton(type: .custom)
        view.titleLabel?.font = .appfont(size: 16)
        view.setTitleColor(PTDashboardConfig.shared.appMainColor, for: .normal)
        view.setTitle("Light mode:" + (name ?? PTBacklightMode.unknown.description), for: .normal)
        view.addActionHandlers(handler: { _ in
            let ids:[UInt8] = [UInt8(2),UInt8(3),UInt8(4),UInt8(5),UInt8(6)]
            let nameMap:[String] = ids.map { value in
                return "\(value)"
            }
            UIAlertController.base_alertVC(title: "Test",okBtns: nameMap,cancelBtn: PTDashboardConfig.languageFunc(text: "button_cancel"), moreBtn:  { index, title in
                PTBluetoothServerManager.shared.sendLightMode(id: ids[index], mode: .led0)
            })
        })
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
        view.addSubviews([dashBoadColorTitle,dashBoardColorButton,dashUniTitle,dashBoardUniButton,dashLanguageTitle,dashBoardLanguageButton,messageTestButton,disconnect,proButton,tcsValueLabel,lightValueLabel])
        dashBoadColorTitle.snp.makeConstraints { make in
            make.left.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.right.equalTo(self.view.snp.centerX)
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total + CGFloat.GlobalItemSpacing)
        }
        
        dashBoardColorButton.snp.makeConstraints { make in
            make.left.equalTo(self.dashBoadColorTitle)
            make.top.equalTo(self.dashBoadColorTitle.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.width.equalTo(54)
            make.height.equalTo(34)
        }
        
        dashUniTitle.snp.makeConstraints { make in
            make.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.left.equalTo(self.view.snp.centerX)
            make.top.equalTo(self.dashBoadColorTitle)
        }
        
        dashBoardUniButton.snp.makeConstraints { make in
            make.height.equalTo(self.dashBoardColorButton)
            make.left.equalTo(self.dashUniTitle)
            make.top.equalTo(self.dashUniTitle.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.width.equalTo(self.dashBoardColorButton.sizeFor().width + 32)
        }
        
        dashLanguageTitle.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalTo(self.dashBoardColorButton.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
        
        dashBoardLanguageButton.snp.makeConstraints { make in
            make.height.left.equalTo(self.dashBoardColorButton)
            make.top.equalTo(self.dashLanguageTitle.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.width.equalTo(self.dashBoardLanguageButton.sizeFor().width + 32)
        }
        
        tcsValueLabel.snp.makeConstraints { make in
            make.left.equalTo(self.dashBoadColorTitle)
            make.top.equalTo(self.dashBoardLanguageButton.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
        
        lightValueLabel.snp.makeConstraints { make in
            make.left.equalTo(self.dashBoadColorTitle)
            make.top.equalTo(self.tcsValueLabel.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
                
        messageTestButton.snp.makeConstraints { make in
            make.size.equalTo(34)
            make.centerX.equalToSuperview()
            make.top.equalTo(self.dashBoardLanguageButton.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
        
        disconnect.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.height.equalTo(44)
            make.bottom.equalToSuperview().inset(CGFloat.kTabbarHeight_Total + CGFloat.GlobalItemSpacing)
        }
        
        proButton.snp.makeConstraints { make in
            make.left.right.height.equalTo(self.disconnect)
            make.bottom.equalTo(self.disconnect.snp.top).offset(-CGFloat.GlobalItemSpacing)
        }
                
        dashBoardColorButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        dashBoardUniButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        dashBoardLanguageButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        disconnect.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        dashBoardColorButton.layoutIfNeeded()
        dashBoardColorButton.viewCorner(radius: 4)
        dashBoardUniButton.layoutIfNeeded()
        dashBoardUniButton.viewCorner(radius: 4)
        dashBoardLanguageButton.layoutIfNeeded()
        dashBoardLanguageButton.viewCorner(radius: 4)
        disconnect.layoutIfNeeded()
        disconnect.viewCorner(radius: 4)
        proButton.layoutIfNeeded()
        proButton.viewCorner(radius: 4)

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
            PTGCDManager.shared.delayOnMain(time: 0.55) {
                PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "set_success"))
                self.globalChangeDashBoardData()
            }
        } else {
            PTGCDManager.shared.delayOnMain(time: 0.55) {
                PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "set_bad"))
            }
        }
    }
    
    func globalChangeDashBoardData() {
        PTGCDManager.shared.delayOnMain(time: 0.5) {
            NotificationCenter.default.post(name: MotorcycleDashBoardChange, object: nil)
            self.dashBoardColorButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
            self.dashBoardUniButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
            self.dashBoardUniButton.setTitle(PTBluetoothServerManager.shared.latestData3?.unitType.getTypeName() ?? PTConfigUnit.metric.getTypeName(), for: .normal)
            self.dashBoardUniButton.snp.updateConstraints { make in
                make.width.equalTo(self.dashBoardColorButton.sizeFor().width + 32)
            }
            self.dashBoardLanguageButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
            self.dashBoardLanguageButton.setTitle(PTBluetoothServerManager.shared.latestData3?.languageType.getTypeName() ?? PTConfigLanguage.english.getTypeName(), for: .normal)
            self.dashBoardLanguageButton.snp.updateConstraints { make in
                make.width.equalTo(self.dashBoardLanguageButton.sizeFor().width + 32)
            }
            self.dashBoadColorTitle.textColor = PTDashboardConfig.shared.appMainColor
            self.dashUniTitle.textColor = PTDashboardConfig.shared.appMainColor
            self.dashLanguageTitle.textColor = PTDashboardConfig.shared.appMainColor
            
            let tcsName = PTBluetoothServerManager.shared.latestControl?.tcsMode.description
            self.tcsValueLabel.setTitle("TCS mode:" + (tcsName ?? PTTCSMode.unknown.description), for: .normal)
            self.tcsValueLabel.setTitleColor(PTDashboardConfig.shared.appMainColor, for: .normal)
            
            let lightName = PTBluetoothServerManager.shared.latestData2?.backlightMode.description
            self.lightValueLabel.setTitle("Light mode:" + (lightName ?? PTBacklightMode.unknown.description), for: .normal)
            self.lightValueLabel.setTitleColor(PTDashboardConfig.shared.appMainColor, for: .normal)
        }
    }
}
