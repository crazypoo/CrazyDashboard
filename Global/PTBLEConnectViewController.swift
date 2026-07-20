//
//  PTBLEConnectViewController.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 20/7/2026.
//

import UIKit
import PooTools

class PTBLEConnectViewController: PTBaseViewController {

    var bleSuccessCallback:PTActionTask?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        PTBluetoothServerManager.shared.startBaseStationAndScan()
        NotificationCenter.default.addObserver(self, selector: #selector(handleAuthSuccess), name: BLEConnectSuccess, object: nil)
    }
    
    @objc func handleAuthSuccess() {
        bleSuccessCallback?()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
