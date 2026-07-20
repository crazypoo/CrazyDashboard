//
//  PTMotoNavigationViewController.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 19/7/2026.
//

import UIKit
import PooTools
import SwifterSwift
import SnapKit

class PTMotoNavigationViewController: PTBaseViewController {

    lazy var tap:UIButton = {
        let view = UIButton(type: .custom)
        view.addActionHandlers { sender in
            // 假设你要导航到某个坐标 (比如北京天安门)
            let destinationCoordinate = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)

            // 触发导航路线计算。一旦计算成功，它会自动在后台监听 GPS 并向摩托车发数据！
            PTMapKitNavigationHelper.shared.startNavigation(to: destinationCoordinate)
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
    }
}
