//
//  PTMotoInfoViewController.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 19/7/2026.
//

import UIKit
import PooTools
import SafeSFSymbols
import SwifterSwift
import SnapKit
import Instructions
import SwiftOBD2

fileprivate extension String {
    static let TRIPSECTION = "TRIPSECTION"
    static let MOTOSECTION = "MOTOSECTION"
}

class PTMotoInfoViewController: PTMotoBaseViewController {

    fileprivate var instructionsModels:[PTInstructionsModel] = {
        
        let fitstTime = PTInstructionsModel()
        fitstTime.infoString = "If you first time to use this app tap here"
        fitstTime.buttonName = "ok"

        return [fitstTime]
    }()

    let coachMarksController = CoachMarksController()

    let buttonCount:Int = 4
    let stackHeight:CGFloat = 54.adapter
    let headerHeight:CGFloat = 32
    
    var isFirstLoad:Bool = true
    
    lazy var actionStack:UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center // 或 .fill，看你是否要垂直方向撑满
        stackView.distribution = .fill
        stackView.spacing = CGFloat.GlobalItemSpacing
        return stackView
    }()
    
    lazy var voltageLabel:PTMainProgressView = {
        let view = baseStackSubView()
        return view
    }()
    
    lazy var distToMaintenanceLabel:PTMainProgressView = {
        let view = baseStackSubView()
        return view
    }()

    func baseStackSubView() ->PTMainProgressView {
        let view = PTMainProgressView()
        view.bounds = .init(origin: .zero, size: .init(width: (CGFloat.kSCREEN_WIDTH - PTAppBaseConfig.share.defaultViewSpace * 2) / 2, height: stackHeight))
        return view
    }
    
    lazy var speedometer:PTSpeedometerView = {
        let view = PTSpeedometerView(frame: .zero)
        view.gaugeType = .speedometer
        view.direction = .bottomOpening
        view.sweepDirection = .standard
        view.altitudeLabel.isHidden = true
        view.pressureLabel.isHidden = true
        view.unitLabel.text = PTDashboardConfig.shared.appShowUniLabel
        view.maxSpeed = PTDashboardConfig.shared.appUniIsMetric ? 180 : 110
        view.tickStep = 5
        view.progressColor = PTDashboardConfig.shared.appMainColor
        view.needleColor = PTDashboardConfig.shared.appMainColor
        view.majorTickStep = 20
        return view
    }()
    
    lazy var speedometerReversed:PTSpeedometerView = {
        let view = PTSpeedometerView(frame: .zero)
        view.gaugeType = .tachometer
        view.direction = .bottomOpening
        view.sweepDirection = .reversed
        view.altitudeLabel.isHidden = true
        view.pressureLabel.isHidden = true
        view.unitLabel.text = "x1000 r/min"
        view.maxSpeed = 10000
        view.tickStep = 500
        view.majorTickStep = 1000
        view.progressColor = PTDashboardConfig.shared.appMainColor
        view.needleColor = PTDashboardConfig.shared.appMainColor
        view.redlineRange = 9000...10000
        return view
    }()
        
    var bleStatusConnectImage:UIImage {
        let imageSize:CGFloat = 5
        let image = UIColor.systemGreen.createImageWithColor().transformImage(size: .init(width: imageSize, height: imageSize)).withRoundedCorners(radius: imageSize / 2) ?? UIImage()
        return image
    }
    
    var bleStatusNoConnectImage:UIImage {
        let imageSize:CGFloat = 5
        let image = UIColor.systemRed.createImageWithColor().transformImage(size: .init(width: imageSize, height: imageSize)).withRoundedCorners(radius: imageSize / 2) ?? UIImage()
        return image
    }
    
    lazy var bleConnectStatusLabel:PTBaseButton = {
        
        let baseImage = UIImage(.dot.radiowavesLeftAndRight)
        let view = PTBaseButton()
        view.setImage(baseImage.withTintColor(.systemRed, renderingMode: .alwaysOriginal), for: .normal)
        view.setImage(baseImage.withTintColor(.systemGreen, renderingMode: .alwaysOriginal), for: .selected)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers { sender in
            if !PTDashboardConfig.shared.blueConnected {
                PTGCDManager.shared.runOnMain {
                    let vc = PTBLEConnectViewController()
                    let nav = PTBaseNavControl(rootViewController: vc)
                    nav.modalPresentationStyle = .fullScreen
                    self.navigationController?.present(nav, animated: true)
                }
            }
        }
        view.isSelected = false
        return view
    }()
    
    lazy var appLogo:UIImageView = {
        let view = UIImageView()
        view.image = UIImage(named: "app_inside_logo")
        view.bounds = .init(origin: .zero, size: .init(width: 108.adapter, height: PTAppBaseConfig.share.navBarButtonSize))
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = false
        return view
    }()
                            
    lazy var lightControl:PTIndicatorPanel = {
        let view = PTIndicatorPanel()
        return view
    }()
    
    lazy var fuelModelView:PTMotoFuelInfoView = {
        let view = PTMotoFuelInfoView()
        return view
    }()
    
    lazy var tripItem:PTStatusItemView = {
        let view = PTStatusItemView()
        view.configure(systemIcon: UIImage(.point.topleftDownToPointBottomrightCurvepath),
                       iconColor: PTDashboardConfig.shared.appMainColor,
                                   title: PTDashboardConfig.languageFunc(text: "casa_card_little_trip"),
                                   value: "0\(PTDashboardConfig.shared.appShowUniLabel)")
        return view
    }()
        
    lazy var odoItem:PTStatusItemView = {
        let view = PTStatusItemView()
        view.configure(systemIcon: UIImage(systemName: "speedometer")!,
                                   iconColor: PTDashboardConfig.shared.appMainColor,
                                   title: PTDashboardConfig.languageFunc(text: "casa_card_odo_trip"),
                                   value: "0\(PTDashboardConfig.shared.appShowUniLabel)")
        return view
    }()

    lazy var engineItem:PTStatusItemView = {
        let view = PTStatusItemView()
        view.configure(systemIcon: UIImage(.engine.combustion),
                                   iconColor: PTDashboardConfig.shared.appMainColor,
                                   title: PTDashboardConfig.languageFunc(text: "casa_card_engine"),
                                   value: "-")
        return view
    }()

    lazy var temItem:PTStatusItemView = {
        let view = PTStatusItemView()
        view.configure(systemIcon: UIImage(.thermometer),
                                   iconColor: PTDashboardConfig.shared.appMainColor,
                                   title: PTDashboardConfig.languageFunc(text: "casa_card_tem"),
                                   value: "0°C")
        return view
    }()

    lazy var globeItem:PTStatusItemView = {
        let view = PTStatusItemView()
        view.configure(systemIcon: UIImage(.globe),
                                   iconColor: PTDashboardConfig.shared.appMainColor,
                                   title: PTDashboardConfig.languageFunc(text: "casa_card_lan"),
                                   value: PTConfigLanguage.english.getTypeName())
        return view
    }()
    
    lazy var obdButton:PTBaseButton = {
        let baseImage = UIImage(.engine.combustionBadgeExclamationmarkFill)
        let view = PTBaseButton()
        view.setImage(baseImage.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.setImage(baseImage.withTintColor(PTDashboardConfig.shared.appMainColor, renderingMode: .alwaysOriginal), for: .selected)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.isSelected = PTMotoTelemetryManager.shared.isConnected
        view.addActionHandlers(handler: { sender in
            if !sender.isSelected {
                let actions = ["Input OBD id","Connect"]
                UIAlertController.base_alertVC(title: PTDashboardConfig.languageFunc(text: "OBD info"), titleColor: PTDashboardConfig.shared.appMainColor, titleFont: .appfont(size: 16),msg: PTDashboardConfig.languageFunc(text: "If you have about elm327 obd2 moudle,you can connect it."), okBtns: actions, cancelBtn: PTDashboardConfig.languageFunc(text: "button_cancel"), showIn: PTUtils.getCurrentVC(), cancelBtnColor: .systemBlue, doneBtnColors: [.systemBlue], moreBtn:  { index, title in
                    switch index {
                    case 0:
                        UIAlertController.base_textfield_alertVC(title:PTDashboardConfig.languageFunc(text: "If you already have OBD2 moudle id,here can remember your OBD2 moudle id"),okBtn: PTDashboardConfig.languageFunc(text: "button_confirm"),cancelBtn: PTDashboardConfig.languageFunc(text: "button_cancel"),placeHolders: [PTDashboardConfig.languageFunc(text: "In put your OBD2 moudle id")],textFieldTexts:[PTMotoUserDefaultStruct.OBDID],keyboardType: [.default],textFieldDelegate: self) { result in
                            PTMotoUserDefaultStruct.OBDID = result[PTDashboardConfig.languageFunc(text: "In put your OBD2 moudle id")] ?? ""
                        }
                    case 1:
                        PTMotoTelemetryManager.shared.connectToMotorcycle()
                        PTMotoTelemetryManager.shared.addDelegate(self)
                    default:
                        break
                    }
                })
            } else {
                let actions = ["Error Code","Disconnect","Data","ECU info"]
                UIAlertController.base_alertVC(title: PTDashboardConfig.languageFunc(text: "OBD"), titleColor: PTDashboardConfig.shared.appMainColor, titleFont: .appfont(size: 16), okBtns: actions, cancelBtn: PTDashboardConfig.languageFunc(text: "button_cancel"), showIn: PTUtils.getCurrentVC(), cancelBtnColor: .systemBlue, doneBtnColors: [.systemBlue], moreBtn:  { index, title in
                    switch index {
                    case 0:
                        Task {
                            do {
                                let result = await PTMotoTelemetryManager.shared.getDiagnosticTroubleCodes()
                                var msgData = ""
                                if result.isEmpty {
                                    msgData = "Good"
                                } else {
                                    msgData = result.joined(separator: "\n")
                                }
                                UIAlertController.base_alertVC(title: PTDashboardConfig.languageFunc(text: "OBD error code"), titleColor: PTDashboardConfig.shared.appMainColor, titleFont: .appfont(size: 16),msg: msgData, cancelBtn: PTDashboardConfig.languageFunc(text: "button_cancel"), showIn: PTUtils.getCurrentVC(), cancelBtnColor: .systemBlue)
                            }
                        }
                    case 1:
                        PTMotoTelemetryManager.shared.disconnect()
                        PTGCDManager.shared.delayOnMain(time: 0.5) {
                            self.obdButton.isSelected = false
                        }
                    case 2:
                        let vc = PTOBDDataViewController()
                        self.navigationController?.pushViewController(vc, animated: true)
                    case 3:

                        let supprotCommandsString = PTMotoTelemetryManager.shared.obdInfo.supportCommand.map { value in
                            value.properties.description
                        }
                        
                        let msgData = "Moudle info:\n\(PTMotoTelemetryManager.shared.obdInfo.moudleInfo.company)\n\(PTMotoTelemetryManager.shared.obdInfo.moudleInfo.version)\n\(PTMotoTelemetryManager.shared.obdInfo.moudleInfo.deviceType)\n\(PTMotoTelemetryManager.shared.obdInfo.moudleInfo.deviceName)\n\(PTMotoTelemetryManager.shared.obdInfo.moudleInfo.deviceMac)\n\(PTMotoTelemetryManager.shared.obdInfo.moudleInfo.interfase)\n\(PTMotoTelemetryManager.shared.obdInfo.moudleInfo.cust)\n\(PTMotoTelemetryManager.shared.obdInfo.moudleInfo.crypt)\nATZ:\n\(PTMotoTelemetryManager.shared.obdInfo.atzName)\nATI:\n\(PTMotoTelemetryManager.shared.obdInfo.aitName)\nProtocol:\n\(PTMotoTelemetryManager.shared.obdInfo.atdpName.description)\nVIN:\n\(PTMotoTelemetryManager.shared.obdInfo.vin)\nECU info:\n\(PTMotoTelemetryManager.shared.obdInfo.ecuVersion)\nCVN:\n\(PTMotoTelemetryManager.shared.obdInfo.cvn)\nSupprot commands:\n\(supprotCommandsString.joined(separator: "\n"))"
                        UIAlertController.base_alertVC(title: PTDashboardConfig.languageFunc(text: "ECU info"), titleColor: PTDashboardConfig.shared.appMainColor, titleFont: .appfont(size: 16),msg: msgData, cancelBtn: PTDashboardConfig.languageFunc(text: "button_cancel"), showIn: PTUtils.getCurrentVC(), cancelBtnColor: .systemBlue)

                    default:
                        break
                    }
                })
            }
        })
        return view
    }()

    lazy var motionDeviceButton:PTBaseButton = {
        let view = PTBaseButton()
        view.titleLabel?.font = .appfont(size: 24)
        view.setTitle(PTMotionDataSource.iphone.rawValue, for: .normal)
        view.setTitle(PTMotionDataSource.airpods.rawValue, for: .selected)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.isSelected = false
        view.addActionHandlers(handler: { _ in
            UIAlertController.base_alertVC(title: PTDashboardConfig.languageFunc(text: "Motion device"), titleColor: PTDashboardConfig.shared.appMainColor, titleFont: .appfont(size: 16),msg: PTDashboardConfig.languageFunc(text: "This icon is mean,user use the motion device to show the drive data source."),cancelBtn: PTDashboardConfig.languageFunc(text: "button_cancel"), showIn: PTUtils.getCurrentVC(), cancelBtnColor: .systemBlue)
        })
        return view
    }()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setLeftButtons(views: [appLogo])
        setCustomRightButtons(buttons: [motionDeviceButton,obdButton,bleConnectStatusLabel],buttonSpacing: CGFloat.GlobalItemSpacing)
        
        self.bleConnectStatusLabel.isSelected = PTDashboardConfig.shared.blueConnected
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.bleConnectStatusLabel.isSelected = PTDashboardConfig.shared.blueConnected
        if !vcDidLoad {
            speedometer.playStartupSweep(duration: 1.5)
            speedometerReversed.playStartupSweep(duration: 1.5)
            vcDidLoad = true
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataNotification), name: MotorcycleDATA1, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataNotification), name: MotorcycleDATA2, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataNotification), name: MotorcycleDATA3, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataNotification), name: MotorcycleCONTROL, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(dashBoardReload), name: MotorcycleDashBoardChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataNotification), name: MotorcycleRawDataTCSShow, object: nil)

        if PTMotoUserDefaultStruct.MotoLinkedAPP {
            NotificationCenter.default.addObserver(self, selector: #selector(handleAuthSuccess), name: BLEConnectSuccess, object: nil)
        }
        
        if PTMotoUserDefaultStruct.MotoLinkedAPP,!PTDashboardConfig.shared.blueConnected {
            PTGCDManager.shared.delayOnMain(time: 3) {
                PTBluetoothServerManager.shared.startBaseStationAndScan()
            }
        }
        
        if PTMotoUserDefaultStruct.CoachFirst {
            coachMarksController.overlay.isUserInteractionEnabled = true
            coachMarksController.delegate = self
            coachMarksController.dataSource = self
            coachMarksController.animationDelegate = self
            PTGCDManager.shared.delayOnMain(time: 0.5) {
                self.coachMarksController.start(in: .window(over: self))
            }
        } else {
            PTGCDManager.shared.delayOnMain(time: 0.5) {
                self.showWahtsnews()
            }
        }
        
        PTMotion.shared.addDelegate(self)
    }
        
    @objc func handleAuthSuccess() {
        PTDashboardConfig.shared.blueConnected = true
        PTMOTOParkingManager.shared.clearParkingSpot()
        PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "connect_success")) {
            self.bleConnectStatusLabel.isSelected = PTDashboardConfig.shared.blueConnected
            self.speedometer.playStartupSweep(duration: 1.5)
            self.speedometerReversed.playStartupSweep(duration: 1.5)
        }
    }
    
    override func handleMotorcycleDisconnect() {
        super.handleMotorcycleDisconnect()
        PTGCDManager.shared.delayOnMain(time: 0.35) {
            self.bleConnectStatusLabel.isSelected = PTDashboardConfig.shared.blueConnected
            self.speedometer.resetToZeroWithAnimation()
            self.speedometerReversed.resetToZeroWithAnimation()
        }
    }
    
    // MARK: - 界面布局
    private func setupUI() {
        view.backgroundColor = .black
        
        view.addSubviews([actionStack,speedometer,speedometerReversed,lightControl,fuelModelView,tripItem,odoItem,engineItem,temItem,globeItem])
        actionStack.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.height.equalTo(54)
            make.top.equalToSuperview().inset(CGFloat.GlobalItemSpacing + CGFloat.kNavBarHeight_Total)
        }
        
        actionStack.addArrangedSubview(voltageLabel)
        actionStack.addArrangedSubview(distToMaintenanceLabel)
        actionStack.arrangedSubviews.forEach { value in
            value.snp.makeConstraints { make in
                make.size.equalTo(value.bounds.size)
                make.centerY.equalToSuperview()
            }
        }
        
        self.voltageLabel.modelSet = modelvoltageSet(currentValue: 0)
        self.distToMaintenanceLabel.modelSet = distToMaintenancemodelSet(max: 2500, current: 0)

        speedometer.snp.makeConstraints { make in
            make.top.equalTo(self.actionStack.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.left.equalToSuperview()
            make.right.equalTo(self.view.snp.centerX)
            make.height.equalTo(self.speedometer.snp.width)
        }
        speedometer.layoutIfNeeded()
        speedometer.viewCorner(radius: speedometer.bounds.size.height / 2)
        
        speedometerReversed.snp.makeConstraints { make in
            make.top.height.equalTo(self.speedometer)
            make.right.equalToSuperview()
            make.left.equalTo(self.view.snp.centerX)
        }
        speedometerReversed.layoutIfNeeded()
        speedometerReversed.viewCorner(radius: speedometerReversed.bounds.size.height / 2)
                                
        lightControl.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.height.equalTo(44)
            make.top.equalTo(self.speedometer.snp.bottom)
            make.centerX.equalToSuperview()
        }
        
        fuelModelView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalTo(self.lightControl.snp.bottom)
            make.height.equalTo(70)
        }
        
        tripItem.snp.makeConstraints { make in
            make.left.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.height.equalTo(60)
            make.right.equalTo(self.view.snp.centerX).offset(-(CGFloat.GlobalItemSpacing / 2))
            make.top.equalTo(self.fuelModelView.snp.bottom)
        }
        
        odoItem.snp.makeConstraints { make in
            make.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.height.equalTo(self.tripItem)
            make.left.equalTo(self.view.snp.centerX).offset((CGFloat.GlobalItemSpacing / 2))
            make.top.equalTo(self.tripItem)
        }
        
        engineItem.snp.makeConstraints { make in
            make.height.left.right.equalTo(self.tripItem)
            make.top.equalTo(self.tripItem.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
        
        temItem.snp.makeConstraints { make in
            make.height.equalTo(self.tripItem)
            make.right.left.equalTo(self.odoItem)
            make.top.equalTo(self.engineItem)
        }
        
        globeItem.snp.makeConstraints { make in
            make.height.left.right.equalTo(self.tripItem)
            make.top.equalTo(self.temItem.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
            
        if isFirstLoad {
            isFirstLoad.toggle()
            PTGCDManager.shared.delayOnMain(time: 1) {
                if let tab = self.tabBarController as? PTMotoBaseTabbarController {
                    tab.dashBoardReload()
                }
            }
        }
        
        pt_observerLanguage {
            if self.vcDidLoad {
                self.voltageLabel.modelSet = self.modelvoltageSet(currentValue: 0)
                self.distToMaintenanceLabel.modelSet = self.distToMaintenancemodelSet(max: 2500, current: 0)
                
                self.tripItem.configure(systemIcon: UIImage(.point.topleftDownToPointBottomrightCurvepath),
                                           iconColor: PTDashboardConfig.shared.appMainColor,
                                           title: PTDashboardConfig.languageFunc(text: "casa_card_little_trip"),
                                           value: "\(PTDashboardConfig.shared.appShowMileageValueString(PTBluetoothServerManager.shared.latestData1?.tripKm ?? 0))\(PTDashboardConfig.shared.appShowUniLabel)")
                
                self.odoItem.configure(systemIcon: UIImage(systemName: "speedometer")!,
                                           iconColor: PTDashboardConfig.shared.appMainColor,
                                           title: PTDashboardConfig.languageFunc(text: "casa_card_odo_trip"),
                                           value: "\(PTDashboardConfig.shared.appShowMileageValueString(PTBluetoothServerManager.shared.latestData1?.odoKm ?? 0))\(PTDashboardConfig.shared.appShowUniLabel)")
                
                var engineStatus = "-"
                if let engineStatusValue = PTBluetoothServerManager.shared.latestData2?.engineStatus {
                    engineStatus = PTDashboardLabels.engineStatusLabel(raw: engineStatusValue)
                }
                self.engineItem.configure(systemIcon: UIImage(.engine.combustion),
                                           iconColor: PTDashboardConfig.shared.appMainColor,
                                           title: PTDashboardConfig.languageFunc(text: "casa_card_engine"),
                                           value: engineStatus)
                
                self.temItem.configure(systemIcon: UIImage(.thermometer),
                                           iconColor: PTDashboardConfig.shared.appMainColor,
                                           title: PTDashboardConfig.languageFunc(text: "casa_card_tem"),
                                           value: "\(PTBluetoothServerManager.shared.latestData2?.outsideTempC ?? 0)°C")
                
                self.globeItem.configure(systemIcon: UIImage(.globe),
                                           iconColor: PTDashboardConfig.shared.appMainColor,
                                           title: PTDashboardConfig.languageFunc(text: "casa_card_lan"),
                                           value: PTBluetoothServerManager.shared.latestData3?.languageType.getTypeName() ?? PTConfigLanguage.english.getTypeName())
            }
        }
        
        setupDeveloperGesture()
        
        if !PTDashboardConfig.shared.blueConnected {
            PTMotion.shared.calibrateZeroPoint()
            PTTripManager.shared.handleConnect()
        }
    }
    
    
    func modelvoltageSet(currentValue:Double) ->PTMainProgressViewModel {
        let modelvoltage = PTMainProgressViewModel()
        modelvoltage.name = PTDashboardConfig.languageFunc(text: "casa_batt")
        modelvoltage.currentValue = currentValue
        modelvoltage.maxValue = 14.5
        modelvoltage.uni = "V"
        return modelvoltage
    }
    
    func distToMaintenancemodelSet(max:Double,current:Double) ->PTMainProgressViewModel {
        let distToMaintenancemodel = PTMainProgressViewModel()
        distToMaintenancemodel.name = PTDashboardConfig.languageFunc(text: "casa_dist_to_maintenance")
        distToMaintenancemodel.currentValue = current
        distToMaintenancemodel.maxValue = max
        distToMaintenancemodel.uni = PTDashboardConfig.shared.appShowUniLabel
        return distToMaintenancemodel
    }
            
    // MARK: - 状态回调
    @objc func handleDataNotification(_ notification: Notification) {
        if let data1 = notification.object as? PTDashboardData1 {
            let tripKm = data1.tripKm
            let odoKm = data1.odoKm
            
            DispatchQueue.main.async {
                let newTripDesc = "\(PTDashboardConfig.shared.appShowMileageValueString(tripKm))\(PTDashboardConfig.shared.appShowUniLabel)"
                let newOdoDesc = "\(PTDashboardConfig.shared.appShowMileageValueString(odoKm))\(PTDashboardConfig.shared.appShowUniLabel)"
                
                self.tripItem.configure(systemIcon: UIImage(.point.topleftDownToPointBottomrightCurvepath),
                                           iconColor: PTDashboardConfig.shared.appMainColor,
                                           title: PTDashboardConfig.languageFunc(text: "casa_card_little_trip"),
                                           value: newTripDesc)
                self.odoItem.configure(systemIcon: UIImage(systemName: "speedometer")!,
                                           iconColor: PTDashboardConfig.shared.appMainColor,
                                           title: PTDashboardConfig.languageFunc(text: "casa_card_odo_trip"),
                                           value: newOdoDesc)
                self.fuelModelView.viewModel = data1
            }
        } else if let data2 = notification.object as? PTDashboardData2 {
            let volt = data2.batteryVolt
            let temp = data2.outsideTempC
            let engineStatus = data2.engineStatus
            
            DispatchQueue.main.async {
                let newEngineDesc = PTDashboardLabels.engineStatusLabel(raw: engineStatus)
                let newTempDesc = "\(temp)°C"
                self.voltageLabel.modelSet = self.modelvoltageSet(currentValue: volt)
                
                self.engineItem.configure(systemIcon: UIImage(.engine.combustion),
                                           iconColor: PTDashboardConfig.shared.appMainColor,
                                           title: PTDashboardConfig.languageFunc(text: "casa_card_engine"),
                                           value: newEngineDesc)
                
                self.temItem.configure(systemIcon: UIImage(.thermometer),
                                           iconColor: PTDashboardConfig.shared.appMainColor,
                                           title: PTDashboardConfig.languageFunc(text: "casa_card_tem"),
                                           value: newTempDesc)
            }
        } else if let data3 = notification.object as? PTDashboardData3 {
            let distToMaintenance = data3.distToMaintenance
            let language = data3.languageType.getTypeName()
            
            DispatchQueue.main.async {
                
                self.distToMaintenanceLabel.modelSet = self.distToMaintenancemodelSet(
                    max: PTDashboardConfig.shared.appShowMileage(2500),
                    current: PTDashboardConfig.shared.appShowMileage(Double(distToMaintenance))
                )
                
                self.fuelModelView.fuelTripModel = data3
                
                self.globeItem.configure(systemIcon: UIImage(.globe),
                                           iconColor: PTDashboardConfig.shared.appMainColor,
                                           title: PTDashboardConfig.languageFunc(text: "casa_card_lan"),
                                           value: language)
                self.fuelModelView.dataProgress.barColor = data3.dashboardColor.getColor()
                self.speedometer.progressColor = data3.dashboardColor.getColor()
                self.speedometerReversed.progressColor = data3.dashboardColor.getColor()

            }
        } else if let control = notification.object as? PTDashboardControl {
            let vehicleSpeedKmh = control.vehicleSpeedKmh
            let engineRpm = control.engineRpm

            // 💡 车速和转速驱动的是 CoreAnimation 动画指针（PTSpeedometerView），本身不会闪烁，直接驱动即可
            DispatchQueue.main.async {
                self.speedometer.updateSpeed(vehicleSpeedKmh)
                self.speedometerReversed.updateSpeed(CGFloat(engineRpm))
                self.speedometerReversed.applyShiftLightLogic(currentRpm: engineRpm)
            }
        } 
    }

    @objc func dashBoardReload() {
        PTGCDManager.shared.runOnMain {
            self.distToMaintenanceLabel.modelSet = self.distToMaintenancemodelSet(max: PTDashboardConfig.shared.appShowMileage(2500), current: PTDashboardConfig.shared.appShowMileage(Double(PTBluetoothServerManager.shared.latestData3?.distToMaintenance ?? 0)))
            self.speedometer.unitLabel.text = PTDashboardConfig.shared.appShowUniLabel
            self.speedometer.maxSpeed = PTDashboardConfig.shared.appUniIsMetric ? 180 : 110
            self.speedometer.progressColor = PTDashboardConfig.shared.appMainColor
            self.speedometer.needleColor = PTDashboardConfig.shared.appMainColor
            self.speedometerReversed.progressColor = PTDashboardConfig.shared.appMainColor
            self.speedometerReversed.needleColor = PTDashboardConfig.shared.appMainColor
            self.voltageLabel.dataProgress.barColor = PTDashboardConfig.shared.appMainColor
            self.distToMaintenanceLabel.dataProgress.barColor = PTDashboardConfig.shared.appMainColor
        }
    }
}

extension PTMotoInfoViewController {

    private func setupDeveloperGesture() {
        // 创建长按手势识别器，绑定触发事件
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleDeveloperGesture(_:)))
        
        // 🚨 核心配置 1：强制要求 4 根手指同时按下
        longPressGesture.numberOfTouchesRequired = 4
        
        // 🚨 核心配置 2：至少长按 1.5 秒才会触发，完美避开日常操作
        longPressGesture.minimumPressDuration = 1.5
        
        // 将手势添加到最底层的 view 上
        view.addGestureRecognizer(longPressGesture)
    }
    
    @objc private func handleDeveloperGesture(_ gesture: UILongPressGestureRecognizer) {
        // UILongPressGestureRecognizer 在其生命周期内会触发多次（began, changed, ended 等）
        // 我们只需要在它刚判定成功 (.began) 时执行一次即可
        if gesture.state == .began {
            PTNSLogConsole("🛠️ [手势触发] 侦测到四指长按，正在唤醒开发者模式！")
            
            // 给出厚重的物理震动反馈 (Heavy 级别能穿透机车手套的触感)
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.prepare()
            impact.impactOccurred()
            
            // 调用嗅探器的纯动画展示方法
            if !PTMotoUserDefaultStruct.BleTestDataGet {
                if let scene = PTWindowSceneDelegate.sceneDelegate() as? SceneDelegate {
                    scene.snifferOverlay.showSniffer()
                    PTMotoUserDefaultStruct.BleTestDataGet = true
                }
            }
        }
    }
}

extension PTMotoInfoViewController:CoachMarksControllerDataSource {
    func numberOfCoachMarks(for coachMarksController: CoachMarksController) -> Int {
        return instructionsModels.count
    }
    
    func coachMarksController(_ coachMarksController: CoachMarksController,
                              coachMarkAt index: Int) -> CoachMark {
        return coachMarksController.helper.makeCoachMark(for: bleConnectStatusLabel)
    }
    
    func coachMarksController(_ coachMarksController: CoachMarksController, coachMarkViewsAt index: Int, madeFrom coachMark: CoachMark) -> (bodyView: UIView & CoachMarkBodyView, arrowView: (UIView & CoachMarkArrowView)?) {
        let coachViews = coachMarksController.helper.makeDefaultCoachViews(
            withArrow: true,
            arrowOrientation: coachMark.arrowOrientation
        )

        coachViews.bodyView.hintLabel.font = .appfont(size: 16)
        coachViews.bodyView.hintLabel.text = instructionsModels[index].infoString
        coachViews.bodyView.nextLabel.font = .appfont(size: 16)
        coachViews.bodyView.nextLabel.text = instructionsModels[index].buttonName

        return (bodyView: coachViews.bodyView, arrowView: coachViews.arrowView)
    }
}

extension PTMotoInfoViewController: CoachMarksControllerAnimationDelegate {
    public func coachMarksController(_ coachMarksController: CoachMarksController,
                                     fetchAppearanceTransitionOfCoachMark coachMarkView: UIView,
                                     at index: Int,
                                     using manager: CoachMarkTransitionManager) {
        manager.parameters.options = [.beginFromCurrentState]
        manager.animate(.regular, animations: { _ in
            coachMarkView.transform = .identity
            coachMarkView.alpha = 1
        }, fromInitialState: {
            coachMarkView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            coachMarkView.alpha = 0
        })
    }

    public func coachMarksController(_ coachMarksController: CoachMarksController,
                                     fetchDisappearanceTransitionOfCoachMark coachMarkView: UIView,
                                     at index: Int,
                                     using manager: CoachMarkTransitionManager) {
        manager.parameters.keyframeOptions = [.beginFromCurrentState]
        manager.animate(.keyframe, animations: { _ in
            UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 1.0, animations: {
                coachMarkView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            })

            UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5, animations: {
                coachMarkView.alpha = 0
            })
        })
    }

    public func coachMarksController(_ coachMarksController: CoachMarksController,
                                     fetchIdleAnimationOfCoachMark coachMarkView: UIView,
                                     at index: Int,
                                     using manager: CoachMarkAnimationManager) {
        manager.parameters.options = [.repeat, .autoreverse, .allowUserInteraction]
        manager.parameters.duration = 0.7

        manager.animate(.regular, animations: { context in
            let offset: CGFloat = context.coachMark.arrowOrientation == .top ? 10 : -10
            coachMarkView.transform = CGAffineTransform(translationX: 0, y: offset)
        })
    }
}

extension PTMotoInfoViewController : CoachMarksControllerDelegate {
    func coachMarksController(_ coachMarksController: CoachMarksController, didHide coachMark: CoachMark, at index: Int) {
        if index == (instructionsModels.count - 1) {
            PTMotoUserDefaultStruct.CoachFirst = false
            showWahtsnews()
        }
    }
    
    func coachMarksController(_ coachMarksController: CoachMarksController, didEndShowingBySkipping skipped: Bool) {
        PTMotoUserDefaultStruct.CoachFirst = false
        showWahtsnews()
    }
}

extension PTMotoInfoViewController {
    func showWahtsnews() {
        let showOption:PTWhatsNewsPresentationOption = .always
        if PTWhatsNews.shouldPresent(with: showOption) {
            self.showWhatNews()
        }
    }
    
    func showWhatNews() {
        let titleItem = PTWhatsNewsTitleItem(title: PTDashboardConfig.languageFunc(text: "Whats news!!!!!!!!!!"))
        let welcomeString = PTDashboardConfig.languageFunc(text: "Welcome to \(kAppName!)")
        let item1 = PTWhatsNewsItem()
        item1.newsImage = "🎉".emojiToImage(emojiFont: .appfont(size: 34))
        item1.title = welcomeString
        
        let item2 = PTWhatsNewsItem()
        item2.newsImage = "🏍️".emojiToImage(emojiFont: .appfont(size: 34))
        item2.title = "Moto"
        item2.subTitle = "The same regular functions as the official APP"
        
        let item3 = PTWhatsNewsItem()
        item3.newsImage = "🗺️".emojiToImage(emojiFont: .appfont(size: 34))
        item3.title = "Navigation"
        item3.subTitle = "Replace the official APP's navigation with the brand-new navigation SDK."
        
        let item4 = PTWhatsNewsItem()
        item4.newsImage = "📈".emojiToImage(emojiFont: .appfont(size: 34))
        item4.title = "Data"
        item4.subTitle = "Collect the riding data of motorcycles and present it in a visual form. And it will also be synchronized to one's own iCloud."
        
        let item5 = PTWhatsNewsItem()
        item5.newsImage = "📞".emojiToImage(emojiFont: .appfont(size: 34))
        item5.title = "PTT"
        item5.subTitle = "When there are other car enthusiasts traveling with you and also using the app, and if there is no signal in your area, you can use the PTT function to communicate."


        let iKnowItem = PTWhatsNewsIKnowItem(title:PTDashboardConfig.languageFunc(text: "I Known"))
        let view = PTWhatsNewsViewController(titleItem: titleItem,iKnowItem: iKnowItem,newsItem: [item1,item2,item3,item4,item5])
        view.whatsNewsShow(vc: self)
        view.iKnowTapHandler = { }
    }
}

extension PTMotoInfoViewController:PTMotoTelemetryDelegate {
    func telemetryManager(_ manager: PTMotoTelemetryManager, didChangeConnectionState isConnected: Bool) {
        obdButton.isSelected = isConnected
    }
    
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateMeasurements measurements: [String: Any]) {
        PTNSLogConsole(">>>>>>>>>>>>>>>>>>>>>>>\(measurements)")
    }
    
    func telemetryManager(_ manager: PTMotoTelemetryManager, didDiscoverSupportedCommands commands: [String]) { }
}

extension PTMotoInfoViewController:PTMotionDelegate {
    func motionManager(_ manager: PooTools.PTMotion, didUpdateData data: PooTools.PTMotionData) { }
    
    func motionManager(_ manager: PTMotion, didChangeDataSource source: PTMotionDataSource) {
        switch source {
        case .iphone:
            motionDeviceButton.isSelected = false
        case .airpods:
            motionDeviceButton.isSelected = true
        }
    }
}

extension PTMotoInfoViewController:UITextFieldDelegate {}
