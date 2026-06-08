//
//  ViewController.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 8/6/2026.
//

import UIKit
import PooTools
import SnapKit
import SwifterSwift

class ViewController: UIViewController {

    let lrSpacing:CGFloat = 44
    let topSpacing:CGFloat = 44
    let bottomSpacing:CGFloat = CGFloat.kTabbarSaveAreaHeight + 44
    
    let speedometer = PTSpeedometerView(frame: .zero)
    let musicNowPlaying = PTNowPlayingView(frame: .zero)
    let compassRoller = PTCompassRollerView(frame: .zero)
    let mapView = PTMapView(frame: .zero)

    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // Do any additional setup after loading the view.
        setupDashboardUI()
        startPootoolsEngines()
    }

    private func setupDashboardUI() {
        // 实例化你封装好的仪表盘视图

        self.view.addSubviews([mapView,speedometer,musicNowPlaying,compassRoller])
        mapView.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(10)
            make.bottom.equalToSuperview().inset(CGFloat.kTabbarSaveAreaHeight)
            make.width.equalToSuperview().multipliedBy(0.65)
            make.centerX.equalToSuperview()
        }
        
        speedometer.snp.makeConstraints { make in
            make.top.equalTo(self.mapView.snp.top).offset(44)
            make.bottom.equalTo(self.mapView.snp.bottom).offset(-44)
            make.width.equalTo(self.speedometer.snp.height)
            make.centerX.equalTo(self.mapView.snp.left)
        }
        speedometer.layoutIfNeeded()
        speedometer.viewCorner(radius: speedometer.bounds.size.height / 2)

        
        musicNowPlaying.snp.makeConstraints { make in
            make.top.bottom.width.equalTo(speedometer)
            make.centerX.equalTo(self.mapView.snp.right)
        }
        musicNowPlaying.layoutIfNeeded()
        musicNowPlaying.viewCorner(radius: musicNowPlaying.bounds.size.height / 2)

        
        compassRoller.snp.makeConstraints { make in
            make.left.equalTo(speedometer.snp.right).offset(10)
            make.right.equalTo(musicNowPlaying.snp.left).offset(-10)
            make.bottom.equalTo(self.mapView)
            make.height.equalTo(54)
        }
    }
    
    private func startPootoolsEngines() {
        // 调用你 pootools 里的引擎
        PTLocationEngine.shared.startTracking()
        PTLocationEngine.shared.locationBlock = { speed, course, altitude in
            self.speedometer.updateSpeed(speed)
            self.compassRoller.updateHeading(course)
            self.speedometer.updateEnvironment(altitude: altitude, pressureKpa: nil)
        }
        
        PTMotion.shared.motionBlock = { [weak self] motionData in
            self?.speedometer.updateEnvironment(altitude: nil, pressureKpa: motionData.pressure) // 再更新气压
        }
    }
}

