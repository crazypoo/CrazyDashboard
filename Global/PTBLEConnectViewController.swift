//
//  PTBLEConnectViewController.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 20/7/2026.
//

import UIKit
import PooTools
import SnapKit
import SwifterSwift
import SafeSFSymbols

class PTBLEConnectViewController: PTMotoBaseViewController,@unchecked Sendable {
    
    var bleSuccessCallback:PTActionTask?
    lazy var connectBLE:UIButton = {
        let view = UIButton(type: .custom)
        view.backgroundColor = .systemBlue
        view.titleLabel?.font = .appfont(size: 14)
        view.titleLabel?.numberOfLines = 0
        view.setTitleColor(.white, for: .normal)
        view.setTitle(PTDashboardConfig.languageFunc(text: "connect_step_1"), for: .normal)
        view.addActionHandlers(handler: { _ in
            let config = PTOpenSystemConfig()
            config.types = .Setting
            PTOpenSystemFunction.openSystemFunction(config: config)
        })
        return view
    }()
    
    lazy var bleScanButton:UIButton = {
        let view = UIButton(type: .custom)
        view.backgroundColor = .systemBlue
        view.titleLabel?.font = .appfont(size: 14)
        view.titleLabel?.numberOfLines = 0
        view.setTitleColor(.white, for: .normal)
        view.setTitle(PTDashboardConfig.languageFunc(text: "connect_step_2"), for: .normal)
        view.addActionHandlers { sender in
            PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "alert_loading")) {
                PTBluetoothServerManager.shared.startBaseStationAndScan()
            }
        }
        view.backgroundColor = .systemBlue
        return view
    }()
    
    lazy var appLogo:UIImageView = {
        let view = UIImageView()
        view.image = UIImage(named: "app_inside_logo")
        view.bounds = .init(origin: .zero, size: .init(width: 108.adapter, height: PTAppBaseConfig.share.navBarButtonSize))
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = false
        return view
    }()
    
    lazy var appMotoLogo:UIImageView = {
        let view = UIImageView()
        view.image = UIImage(named: "app_connect_logo")
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = false
        return view
    }()
    
    lazy var stepInfo:UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        view.font = .appfont(size: 16)
        view.textColor = .white
        view.textAlignment = .left
        view.text = PTDashboardConfig.languageFunc(text: "connect_step_title")
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

    open override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        return .solid(.clear)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setLeftButtons(views: [appLogo])
        setCustomRightButtons(buttons: [globalButton])
        PTGCDManager.shared.delayOnMain(time: 0.35) {
            self.changeStatusBar(type: .Dark)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        let buttonWidth = CGFloat.kSCREEN_WIDTH - PTAppBaseConfig.share.defaultViewSpace * 2
        view.addSubviews([appMotoLogo,stepInfo,connectBLE,bleScanButton])
        appMotoLogo.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total + CGFloat.GlobalItemSpacing)
            make.height.equalTo(200.adapter)
        }
        stepInfo.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalTo(self.appMotoLogo.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
        connectBLE.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.height.equalTo(self.connectBLE.getButtonHeight(width: buttonWidth) + 16)
            make.top.equalTo(self.stepInfo.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
        
        bleScanButton.snp.makeConstraints { make in
            make.left.right.equalTo(self.connectBLE)
            make.height.equalTo(self.bleScanButton.getButtonHeight(width: buttonWidth) + 16)
            make.top.equalTo(self.connectBLE.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
        
        connectBLE.layoutIfNeeded()
        connectBLE.viewCorner(radius: 8)
        bleScanButton.layoutIfNeeded()
        bleScanButton.viewCorner(radius: 8)
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleAuthSuccess), name: BLEConnectSuccess, object: nil)
        
        pt_observerLanguage {
            if self.vcDidLoad {
                self.stepInfo.text = PTDashboardConfig.languageFunc(text: "connect_step_title")
                self.connectBLE.setTitle(PTDashboardConfig.languageFunc(text: "connect_step_1"), for: .normal)
                self.connectBLE.snp.updateConstraints { make in
                    make.height.equalTo(self.connectBLE.getButtonHeight(width: buttonWidth) + 16)
                }
                self.bleScanButton.setTitle(PTDashboardConfig.languageFunc(text: "connect_step_2"), for: .normal)
                self.bleScanButton.snp.updateConstraints { make in
                    make.height.equalTo(self.bleScanButton.getButtonHeight(width: buttonWidth) + 16)
                }
            }
        }
        self.vcDidLoad = true
    }
    
    @objc func handleAuthSuccess() {
        PTGCDManager.shared.delayOnMain(time: 3) {
            PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "connect_success")) {
                self.bleSuccessCallback?()
            }
        }
    }
    
    @MainActor deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
