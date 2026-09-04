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

// EN: This controller is UI-bound; main-actor isolation is safer than pretending UIKit state is freely Sendable.
// ES: Este controlador pertenece a la UI; el aislamiento del actor principal es más seguro que declarar Sendable para el estado de UIKit.
// 中文：该控制器属于 UI，使用主 actor 隔离比把 UIKit 状态伪装成可 Sendable 更安全。
@MainActor
class PTBLEConnectViewController: PTMotoBaseViewController {
    
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
                Task { @MainActor in
                    _ = PTVehicleConnectivityCoordinator.shared.connectDashboardIfNeeded()
                }
            }
        }
        view.backgroundColor = .systemBlue
        return view
    }()
    
    lazy var appLogo:UIButton = {
        let view = UIButton(type:.custom)
        view.imageView?.contentMode = .scaleAspectFit
        view.imageView?.clipsToBounds = false
        view.setImage(UIImage(named: "app_inside_logo"), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: 108.adapter, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers { sender in
            self.dismissAnimated()
        }
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
        view.setImage(UIImage(.globe).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            PTDashboardConfig.globalLanguageAlert()
        })
        return view
    }()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setLeftButtons(views: [appLogo])
        setCustomRightButtons(buttons: [globalButton])
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
        PTDashboardConfig.shared.blueConnected = true
        PTMOTOParkingManager.shared.clearParkingSpot()
        let successCallback = bleSuccessCallback
        PTGCDManager.shared.delayOnMain(time: 3) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "connect_success")) { [weak self] in
                    successCallback?()
                    guard let self else { return }
                    if self.presentingViewController != nil {
                        self.dismissAnimated()
                    }
                }
            }
        }
    }
    
    override func handleMotorcycleConnect() {
        super.handleMotorcycleConnect()
        self.handleAuthSuccess()
    }
    
    @MainActor deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
