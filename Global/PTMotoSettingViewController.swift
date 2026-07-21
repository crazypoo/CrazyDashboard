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

class PTMotoSettingViewController: PTBaseViewController {

    open override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        return .solid(.clear)
    }

    lazy var dashBoadColorTitle:UILabel = {
        let view = baseTitle(value: PTDashboardConfig.languageFunc(text: "仪表盘颜色"))
        return view
    }()
    
    lazy var dashBoardColorButton:UIButton = {
        let view = UIButton()
        view.addActionHandlers(handler: { _ in
            let titleItem = PTActionSheetTitleItem()
            titleItem.title = PTDashboardConfig.languageFunc(text: "颜色选择")
            
            let imageSize:CGSize = .init(width: 54, height: 34)
            let contentImtes = PTConfigColor.allCases.map { value in
                let model = PTActionSheetItem(title: "")
                model.imageSize = imageSize
                model.image = value.getColor().createImageWithColor().transformImage(size: imageSize)
                return model
            }
            
            UIAlertController.baseCustomActionSheet(titleItem: titleItem, contentItems: contentImtes, otherBlock: { sheet,index,title in
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
        let view = baseTitle(value: PTDashboardConfig.languageFunc(text: "仪表盘单位"))
        return view
    }()
    
    lazy var dashBoardUniButton:UIButton = {
        let view = UIButton()
        view.titleLabel?.font = .appfont(size: 16)
        view.setTitleColor(.white, for: .normal)
        view.setTitle(PTBluetoothServerManager.shared.latestData3?.unitType.getTypeName() ?? PTConfigUnit.metric.getTypeName(), for: .normal)
        view.addActionHandlers(handler: { _ in
            let titleItem = PTActionSheetTitleItem()
            titleItem.title = PTDashboardConfig.languageFunc(text: "单位选择")
            
            let contentImtes = PTConfigUnit.allCases.map { value in
                let model = PTActionSheetItem(title: value.getTypeName())
                return model
            }
            
            UIAlertController.baseCustomActionSheet(titleItem: titleItem, contentItems: contentImtes, otherBlock: { sheet,index,title in
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
        let view = baseTitle(value: PTDashboardConfig.languageFunc(text: "仪表盘语言"))
        return view
    }()
    
    lazy var dashBoardLanguageButton:UIButton = {
        let view = UIButton()
        view.titleLabel?.font = .appfont(size: 16)
        view.setTitleColor(.white, for: .normal)
        view.setTitle(PTBluetoothServerManager.shared.latestData3?.languageType.getTypeName() ?? PTConfigLanguage.english.getTypeName(), for: .normal)
        view.addActionHandlers(handler: { _ in
            let titleItem = PTActionSheetTitleItem()
            titleItem.title = PTDashboardConfig.languageFunc(text: "单位选择")
            
            let contentImtes = PTConfigLanguage.allCases.map { value in
                let model = PTActionSheetItem(title: value.getTypeName())
                return model
            }
            
            UIAlertController.baseCustomActionSheet(titleItem: titleItem, contentItems: contentImtes, otherBlock: { sheet,index,title in
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
        view.setTitle(PTDashboardConfig.languageFunc(text: "断开连接"), for: .normal)
        view.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        view.addActionHandlers { sender in
            UIAlertController.base_alertVC(title: PTDashboardConfig.languageFunc(text: "要断开连接吗？"),okBtns: [PTDashboardConfig.languageFunc(text: "好的")],cancelBtn: PTDashboardConfig.languageFunc(text: "取消"), moreBtn:  { index, title in
                PTBluetoothServerManager.shared.sendDisconnect()
                let vc = PTBLEConnectViewController()
                let nav = PTBaseNavControl(rootViewController: vc)
                nav.modalPresentationStyle = .fullScreen
                self.navigationController?.present(nav, animated: true)
            })
        }
        return view
    }()
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PTGCDManager.shared.delayOnMain(time: 0.35) {
            self.changeStatusBar(type: .Dark)
        }
    }
        
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        view.addSubviews([dashBoadColorTitle,dashBoardColorButton,dashUniTitle,dashBoardUniButton,dashLanguageTitle,dashBoardLanguageButton,messageTestButton,disconnect])
        dashBoadColorTitle.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total + CGFloat.GlobalItemSpacing)
        }
        
        dashBoardColorButton.snp.makeConstraints { make in
            make.left.equalTo(self.dashBoadColorTitle)
            make.top.equalTo(self.dashBoadColorTitle.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.width.equalTo(54)
            make.height.equalTo(34)
        }
        
        dashUniTitle.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalTo(self.dashBoardColorButton.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
        
        dashBoardUniButton.snp.makeConstraints { make in
            make.height.left.equalTo(self.dashBoardColorButton)
            make.top.equalTo(self.dashUniTitle.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.width.equalTo(self.dashBoardColorButton.sizeFor().width + 32)
        }
        
        dashLanguageTitle.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalTo(self.dashBoardUniButton.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
        
        dashBoardLanguageButton.snp.makeConstraints { make in
            make.height.left.equalTo(self.dashBoardColorButton)
            make.top.equalTo(self.dashLanguageTitle.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.width.equalTo(self.dashBoardLanguageButton.sizeFor().width + 32)
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
            PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "设置成功"))
            self.globalChangeDashBoardData()
        } else {
            PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "设置失败"))
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
        }
    }
}
