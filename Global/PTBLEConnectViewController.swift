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

class PTBLEConnectViewController: PTBaseViewController {
    
    var bleSuccessCallback:PTActionTask?
    lazy var connectBLE:UIButton = {
        let view = UIButton(type: .custom)
        view.backgroundColor = .systemBlue
        view.titleLabel?.font = .appfont(size: 14)
        view.titleLabel?.numberOfLines = 0
        view.setTitleColor(.white, for: .normal)
        view.setTitle(PTDashboardConfig.languageFunc(text: "1.如果手机没连接摩托仪表盘的蓝牙，请先点击我去连接,摩托车仪表盘蓝牙名字大致有PEUGEOT字样"), for: .normal)
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
        view.setTitle(PTDashboardConfig.languageFunc(text: "2.手机连接了摩托车仪表盘蓝牙后，点我开启蓝牙扫描,当该APP连接摩托车仪表盘成功后，则自动跳转到主界面"), for: .normal)
        view.addActionHandlers { sender in
            PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "加载中，请稍候"))
            PTBluetoothServerManager.shared.startBaseStationAndScan()
        }
        view.backgroundColor = .systemBlue
        return view
    }()
    
    lazy var appLogo:UIImageView = {
        let view = UIImageView()
        view.backgroundColor = .random
        view.bounds = .init(origin: .zero, size: .init(width: 108.adapter, height: PTAppBaseConfig.share.navBarButtonSize))
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
        view.text = PTDashboardConfig.languageFunc(text: "操作步骤，请务必按照下面的操作步骤，以免出现无法连接摩托车蓝牙")
        return view
    }()

    open override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        return .solid(.clear)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setLeftButtons(views: [appLogo])
        PTGCDManager.shared.delayOnMain(time: 0.35) {
            self.changeStatusBar(type: .Dark)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        let buttonWidth = CGFloat.kSCREEN_WIDTH - PTAppBaseConfig.share.defaultViewSpace * 2
        view.addSubviews([stepInfo,connectBLE,bleScanButton])
        stepInfo.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total + CGFloat.GlobalItemSpacing)
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
    }
    
    @objc func handleAuthSuccess() {
        PTGCDManager.shared.delayOnMain(time: 3) {
            PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "连接成功"))
            self.bleSuccessCallback?()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
