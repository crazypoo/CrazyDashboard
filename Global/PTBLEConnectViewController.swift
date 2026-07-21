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
    
    lazy var tap:UIButton = {
        let view = UIButton(type: .custom)
        view.addActionHandlers { sender in
            PTBluetoothServerManager.shared.startBaseStationAndScan()
        }
        view.backgroundColor = .systemBlue
        return view
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubviews([tap])
        tap.snp.makeConstraints { make in
            make.size.equalTo(64)
            make.center.equalToSuperview()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleAuthSuccess), name: BLEConnectSuccess, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataNotification), name: MotorcycleDATA3, object: nil)
    }
    
    @objc func handleAuthSuccess() {
        view.backgroundColor = .systemRed
        bleSuccessCallback?()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func handleDataNotification(_ notification: Notification) {
        if let data3 = notification.object as? PTDashboardData3 {
            let isMetric = data3.isMetric
            let dashboardColor = data3.dashboardColor
            // 3. 结合我们之前写的状态标签工具，更新到主线程的 UI 上
            DispatchQueue.main.async {
            }
        }
    }
}
