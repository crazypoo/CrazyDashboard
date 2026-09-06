//
//  PTPeugeotLashBoardNavView.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 14/8/2026.
//

import UIKit
import AMapNaviKit
import PooTools
import SnapKit
import SwifterSwift
import SafeSFSymbols
import AttributedString

class PTPeugeotDashBoardNavView: UIView {
    
    var navSuccess:PTActionTask?
    var currentRoadName:String = ""

    var currentSpeedLimit:UInt8 = 0

    lazy var navIcon:UIImageView = {
        let view = UIImageView()
        return view
    }()
    
    lazy var limitedSpeedLabel:UILabel = {
        let view = UILabel()
        view.textAlignment = .center
        view.font = .appfont(size: 16)
        view.textColor = .black
        view.backgroundColor = .white
        view.text = "0"
        return view
    }()
    
    lazy var finalIcon:UIImageView = {
        let view = UIImageView()
        view.image = UIImage(.location.fill)
        return view
    }()
    
    lazy var routeDistanceLabel:UILabel = {
        let view = UILabel()
        view.textAlignment = .right
        view.font = .appfont(size: 13)
        view.textColor = .white
        view.text = "0 km"
        return view
    }()
    
    lazy var arrivedTimeLabel:UILabel = {
        let view = UILabel()
        view.textAlignment = .left
        view.font = .appfont(size: 13)
        view.textColor = .white
        view.text = "00:00"
        return view
    }()
    
    lazy var segmentRemainDistanceLabel:UILabel = {
        let view = UILabel()
        return view
    }()
    
    lazy var routeNameLabel:UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNavigationGuidance(_:)),
            name: PTNavigationSessionCoordinator.guidanceDidUpdateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNavigationStateChange(_:)),
            name: PTNavigationSessionCoordinator.stateDidChangeNotification,
            object: nil
        )
        
        addSubviews([navIcon,limitedSpeedLabel,finalIcon,routeDistanceLabel,arrivedTimeLabel,segmentRemainDistanceLabel,routeNameLabel])
        navIcon.snp.makeConstraints { make in
            make.width.equalToSuperview().multipliedBy(0.3)
            make.height.equalTo(self.navIcon.snp.width)
            make.centerY.equalToSuperview()
            make.left.equalToSuperview().inset(CGFloat.GlobalItemSpacing * 3)
        }
        
        limitedSpeedLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(30)
            make.right.equalToSuperview().inset(CGFloat.GlobalItemSpacing * 3)
            make.size.equalTo(54)
        }
        limitedSpeedLabel.layoutIfNeeded()
        limitedSpeedLabel.viewCorner(radius: 27,borderWidth: 3,borderColor: .systemRed)
        
        finalIcon.snp.makeConstraints { make in
            make.size.equalTo(44)
            make.centerX.equalToSuperview()
            make.top.equalToSuperview()
        }
        
        routeDistanceLabel.snp.makeConstraints { make in
            make.right.equalTo(self.finalIcon.snp.left).offset(-(CGFloat.GlobalItemSpacing * 1.5))
            make.centerY.equalTo(self.finalIcon)
        }
        
        arrivedTimeLabel.snp.makeConstraints { make in
            make.left.equalTo(self.finalIcon.snp.right).offset((CGFloat.GlobalItemSpacing * 1.5))
            make.centerY.equalTo(self.finalIcon)
        }
        
        segmentRemainDistanceLabel.snp.makeConstraints { make in
            make.right.equalTo(self.limitedSpeedLabel)
            make.top.equalTo(self.limitedSpeedLabel.snp.bottom)
        }
        
        routeNameLabel.snp.makeConstraints { make in
            make.left.equalTo(self.navIcon)
            make.right.equalTo(self.limitedSpeedLabel)
            make.bottom.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleNavigationGuidance(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let naviInfo = userInfo["naviInfo"] as? AMapNaviInfo else { return }
        let speedLimit: UInt8
        if let value = userInfo["speedLimit"] as? UInt8 {
            speedLimit = value
        } else if let value = userInfo["speedLimit"] as? NSNumber {
            speedLimit = UInt8(clamping: value.intValue)
        } else {
            return
        }
        render(naviInfo: naviInfo, speedLimit: speedLimit)
    }

    @objc private func handleNavigationStateChange(_ notification: Notification) {
        guard let state = notification.userInfo?["state"] as? PTNavigationSessionState else { return }
        if case .arrived = state {
            navSuccess?()
        } else if case .idle = state {
            navIcon.image = nil
            routeNameLabel.text = nil
            segmentRemainDistanceLabel.text = nil
            routeDistanceLabel.text = "0 km"
        }
    }

    private func render(naviInfo: AMapNaviInfo, speedLimit: UInt8) {
        currentSpeedLimit = speedLimit
        currentRoadName = naviInfo.currentRoadName
        let routeDistanceLeast = CGFloat(naviInfo.routeRemainDistance) / 1000
        routeDistanceLabel.text = String(format: "%.1f km", routeDistanceLeast)
        let estimatedArrivalDate = Date().addingTimeInterval(TimeInterval(naviInfo.routeRemainTime))
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        arrivedTimeLabel.text = formatter.string(from: estimatedArrivalDate)
        segmentRemainDistance(naviInfo: naviInfo)
        routeNameSet(naviInfo: naviInfo)
        navIcon.image = naviInfo.iconImage
        limitedSpeedLabel.text = speedLimit == 0 ? "--" : "\(speedLimit)"
    }
}

extension PTPeugeotDashBoardNavView {

    func segmentRemainDistance(naviInfo: AMapNaviInfo) {
        let segmentRemainDistance = CGFloat(naviInfo.segmentRemainDistance) / 1000
        let segmentRemainDistanceString = String(format: "%.1f", segmentRemainDistance)

        let att: ASAttributedString = """
                    \(wrap: .embedding("""
                    \(segmentRemainDistanceString,.foreground(.white),.font(.appfont(size: 24,bold:true)))\(" km",.foreground(.white),.font(.appfont(size: 12)))
                    """),.paragraph(.alignment(.right)))
                    """
        segmentRemainDistanceLabel.attributed.text = att
    }
    
    func routeNameSet(naviInfo: AMapNaviInfo) {
        var att: ASAttributedString = """
        """

        if naviInfo.segmentRemainDistance > 100 {
            let top: ASAttributedString = """
                        \(wrap: .embedding("""
                        \(PTDashboardConfig.languageFunc(text: "navigation_in_progress"),.foreground(.white),.font(.appfont(size: 12)))
                        """),.paragraph(.alignment(.center)))
                        """
            att += top
        } else {
            let top: ASAttributedString = """
                        \(wrap: .embedding("""
                        \(PTDashboardConfig.languageFunc(text: "next_road_name_prefix") + naviInfo.nextRoadName,.foreground(.white),.font(.appfont(size: 12)))
                        """),.paragraph(.alignment(.center)))
                        """
            att += top
        }
        let current: ASAttributedString = """
                    \(wrap: .embedding("""
                    \("\n" + PTDashboardConfig.languageFunc(text: "current_road_name_prefix") + naviInfo.currentRoadName,.foreground(.white),.font(.appfont(size: 12)))
                    """),.paragraph(.alignment(.center)))
                    """
        att += current
        routeNameLabel.attributed.text = att
    }
    
    func errorRouteNameSet(value:String) {
        let att: ASAttributedString = """
                    \(wrap: .embedding("""
                    \(value,.foreground(.white),.font(.appfont(size: 12)))
                    """),.paragraph(.alignment(.center)))
                    """
        routeNameLabel.attributed.text = att
    }
}
