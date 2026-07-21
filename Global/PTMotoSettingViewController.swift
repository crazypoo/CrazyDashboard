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
                let uniConfig = PTConfigUnit(rawValue: (PTBluetoothServerManager.shared.latestData3?.isMetric ?? false) ? 1 : 2)!
                let language = PTConfigLanguage(rawValue: UInt8((PTBluetoothServerManager.shared.latestData3?.language ?? 1)))!
                PTBluetoothServerManager.shared.sendConfiguration(color: colorCase, unit: uniConfig, language: language) { finish in
                    
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
                    PTProgressHUD.show(text: "?????????????\(finish)")
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
                    
                }
            })
        })
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
        view.addSubviews([dashBoadColorTitle,dashBoardColorButton,dashUniTitle,dashBoardUniButton,dashLanguageTitle,dashBoardLanguageButton])
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
        
        dashBoardColorButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        dashBoardUniButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        dashBoardLanguageButton.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        dashBoardColorButton.layoutIfNeeded()
        dashBoardColorButton.viewCorner(radius: 4)
        dashBoardUniButton.layoutIfNeeded()
        dashBoardUniButton.viewCorner(radius: 4)
        dashBoardLanguageButton.layoutIfNeeded()
        dashBoardLanguageButton.viewCorner(radius: 4)
    }
    
    func baseTitle(value:String) -> UILabel {
        let view = UILabel()
        view.text = value
        view.font = .appfont(size: 16)
        view.textAlignment = .left
        view.textColor = PTDashboardConfig.shared.appMainColor
        return view
    }
}
