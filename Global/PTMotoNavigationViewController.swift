//
//  PTMotoNavigationViewController.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 19/7/2026.
//

import UIKit
import PooTools

class PTMotoNavigationViewController: PTBaseViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // 假设你要导航到某个坐标 (比如北京天安门)
        let destinationCoordinate = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)

        // 触发导航路线计算。一旦计算成功，它会自动在后台监听 GPS 并向摩托车发数据！
        PTMapKitNavigationHelper.shared.startNavigation(to: destinationCoordinate)
    }
}
