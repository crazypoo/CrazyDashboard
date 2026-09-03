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
        
        AMapNaviDriveManager.sharedInstance().delegate = self
        AMapNaviDriveManager.sharedInstance().allowsBackgroundLocationUpdates = true
        AMapNaviDriveManager.sharedInstance().pausesLocationUpdatesAutomatically = false
        AMapNaviDriveManager.sharedInstance().addDataRepresentative(self)
        
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
}

extension PTPeugeotDashBoardNavView:AMapNaviDriveManagerDelegate {
    func driveManager(onArrivedDestination driveManager: AMapNaviDriveManager) {
        navSuccess?()
    }
    
    func driveManagerDidEndEmulatorNavi(_ driveManager: AMapNaviDriveManager) {
        navSuccess?()
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, error: Error) {
        let error = error as NSError
        PTNSLogConsole("error:{%d - %@}", error.code, error.localizedDescription)
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, onCalculateRouteFailure error: Error) {
        let error = error as NSError
        PTNSLogConsole("CalculateRouteFailure:{%d - %@}", error.code, error.localizedDescription)
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, postRouteNotification notifyData: AMapNaviRouteNotifyData) {
        PTNSLogConsole(">>>>>>>>>>>>>>>>\(String(describing: notifyData.roadName))")
    }
    
    func driveManager(_ manager: AMapNaviDriveManager?, onUpdateNaviSpeedLimitSection speed: Int) {
        PTNSLogConsole(">>>>>>>>>>>>>>>>>>>>>>>>>>>>\(speed)")
        self.currentSpeedLimit = UInt8(speed)
        limitedSpeedLabel.text = "\(speed)"
    }
    
    func driveManagerIsNaviSoundPlaying(_ driveManager: AMapNaviDriveManager) -> Bool {
        return SpeechSynthesizer.Shared.isSpeaking()
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, playNaviSound soundString: String, soundStringType: AMapNaviSoundType) {
        if PTMotoUserDefaultStruct.NavMute {
            SpeechSynthesizer.Shared.speak(soundString)
        }
    }
            
    func driveManager(_ driveManager: AMapNaviDriveManager, onCalculateRouteSuccessWith type: AMapNaviRoutePlanType) {
        errorRouteNameSet(value: "Rerouting...")
        PTBluetoothServerManager.shared.sendWelcomeMessage(next: "Rerouting...", title: "",nextManeuver: PTXP400BLEProtocol.returnToRouteManeuverCode)
    }
        
    func driveManager(_ driveManager: AMapNaviDriveManager, update gpsSignalStrength: AMapNaviGPSSignalStrength) {
        switch gpsSignalStrength {
        case .smartPos:
            break
        default:
            errorRouteNameSet(value: "Searching GPS...")
            PTBluetoothServerManager.shared.sendWelcomeMessage(next: "Searching GPS...", title: "",nextManeuver: PTXP400BLEProtocol.noValidActionManeuverCode)
        }
    }
}

extension PTPeugeotDashBoardNavView:AMapNaviDriveDataRepresentable {
         
    func driveManager(_ driveManager: AMapNaviDriveManager, updateCruiseElecCameraInfos cameraInfos: [AMapNaviTrafficFacilityInfo]) {
        if let firstCamera = cameraInfos.first {
            // cameraSpeed 通常代表该路段限速，为 0 时表示无限速或未知
            if firstCamera.limitSpeed > 0 {
                self.limitedSpeedLabel.text = "\(firstCamera.limitSpeed)"
                self.currentSpeedLimit = UInt8(firstCamera.limitSpeed)
            } else {
                self.limitedSpeedLabel.text = "--"
            }
        }
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, update cameraInfos: [AMapNaviCameraInfo]?) {
        if let firstCamera = cameraInfos?.first {
            // cameraSpeed 通常代表该路段限速，为 0 时表示无限速或未知
            if firstCamera.cameraSpeed > 0 {
                self.limitedSpeedLabel.text = "\(firstCamera.cameraSpeed)"
                self.currentSpeedLimit = UInt8(firstCamera.cameraSpeed)
            } else {
                self.limitedSpeedLabel.text = "--"
            }
        }
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, update naviInfo: AMapNaviInfo?) {
        guard let naviInfo = naviInfo else {
            return
        }
        currentRoadName = naviInfo.currentRoadName
//        PTNSLogConsole("\(naviInfo)")
        let routeDistanceLeast = CGFloat(naviInfo.routeRemainDistance) / 1000
        routeDistanceLabel.text = String(format: "%.1f km", routeDistanceLeast)
        let currentDate = Date()
        let estimatedArrivalDate = currentDate.addingTimeInterval(TimeInterval(naviInfo.routeRemainTime))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        arrivedTimeLabel.text = formatter.string(from: estimatedArrivalDate)
        segmentRemainDistance(naviInfo: naviInfo)
        routeNameSet(naviInfo: naviInfo)
        navIcon.image = naviInfo.iconImage
        PTMotoDashBoardNavFunction.sendNavDataToDashboard(naviInfo: naviInfo, currentSpeedLimit: self.currentSpeedLimit)
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, update naviLocation: AMapNaviLocation?) {
        if PTMotoNavigationViewController.shared.startEmulatorNavi,let naviLocation = naviLocation {
            PTLocationEngine.shared.amapEmulatorNavi(naviLocation: naviLocation,roadName: currentRoadName)
        }
    }
    
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
