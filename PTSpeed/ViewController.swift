//
//  ViewController.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 8/6/2026.
//

import UIKit
import SnapKit
import SwifterSwift

class ViewController: UIViewController {
    
    lazy var dashBoard:PTDashBoardView = {
        let view = PTDashBoardView()
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubviews([dashBoard])
        dashBoard.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        dashBoard.speedometer.playStartupSweep(duration: 1.5)
    }
}

