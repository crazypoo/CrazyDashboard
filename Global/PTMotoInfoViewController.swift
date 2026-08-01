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
    
    var tripModels:[PTFusionCellModel] {
        get {
            let oilModel = PTDashboardConfig.baseNormalCellModel(name: PTDashboardConfig.languageFunc(text: "casa_card_oil"),desc: "0%")
            let oilTrip = PTDashboardConfig.baseNormalCellModel(name: PTDashboardConfig.languageFunc(text: "casa_card_oil_trip"),desc: "0\(PTDashboardConfig.shared.appShowUniLabel)")
            let littleTrip = PTDashboardConfig.baseNormalCellModel(name: PTDashboardConfig.languageFunc(text: "casa_card_little_trip"),desc: "0\(PTDashboardConfig.shared.appShowUniLabel)")
            let ODOTrip = PTDashboardConfig.baseNormalCellModel(name: PTDashboardConfig.languageFunc(text: "casa_card_odo_trip"),desc: "0\(PTDashboardConfig.shared.appShowUniLabel)")
            let avgOil = PTDashboardConfig.baseNormalCellModel(name: PTDashboardConfig.languageFunc(text: "casa_card_avg_oil"),desc: "0L/\(PTDashboardConfig.shared.appShowMileageValueString(100))\(PTDashboardConfig.shared.appShowUniLabel)")
            return [oilModel,oilTrip,littleTrip,ODOTrip,avgOil]
        } set{ }
    }
    
    var motoModels:[PTFusionCellModel] {
        get {
            let motoModel = PTDashboardConfig.baseNormalCellModel(name: PTDashboardConfig.languageFunc(text: "casa_card_engine"),desc: "-")
            let absModel = PTDashboardConfig.baseNormalCellModel(name: "ABS",desc: "-")
            let temModel = PTDashboardConfig.baseNormalCellModel(name: PTDashboardConfig.languageFunc(text: "casa_card_tem"),desc: "0°C")
            let lanTrip = PTDashboardConfig.baseNormalCellModel(name: PTDashboardConfig.languageFunc(text: "casa_card_lan"),desc: "\(PTConfigLanguage.english.getTypeName())")
            return [motoModel,absModel,temModel,lanTrip]
        } set{ }
    }

    lazy var detailCollection:PTCollectionView = {
                                
        let collectionConfig = PTCollectionViewConfig()
        collectionConfig.viewType = .Custom
        collectionConfig.footerRefresh = false
        collectionConfig.topRefresh = false

        let view = PTCollectionView(viewConfig: collectionConfig)
        view.registerClassCells(classs: [PTFusionCell.ID:PTFusionCell.self])
        view.registerHeaderIdsNClasss(ids: [.TRIPSECTION,.MOTOSECTION], viewClass: PTGlobalActionHeader.self, kind: UICollectionView.elementKindSectionHeader)
        view.headerInCollection = { kind,collectionView,model,index in
            if let headerID = model.headerID,!headerID.stringIsEmpty() {
                if let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: headerID, for: index) as? PTGlobalActionHeader {
                    header.titleName.text = model.headerTitle
                    header.titleName.snp.updateConstraints { make in
                        make.left.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
                    }
                    return header
                }
            }
            return nil
        }
        view.customerLayout = { sectionIndex,section in
            return UICollectionView.girdCollectionLayout(data: section.rows, itemHeight: 60,cellRowCount: 2,originalX: PTAppBaseConfig.share.defaultViewSpace,cellLeadingSpace: CGFloat.GlobalItemSpacing,cellTrailingSpace: CGFloat.GlobalItemSpacing)
        }
        view.cellInCollection = { collectionView,sectionModel,indexPath in
            if let itemRow = sectionModel.rows?[indexPath.row] {
                let getCell = collectionView.dequeueReusableCell(withReuseIdentifier: itemRow.ID, for: indexPath)
                if let cell = getCell as? PTFusionCell,let cellModel = itemRow.dataModel as? PTFusionCellModel {
                    cell.cellModel = cellModel
                    cell.dataContent.backgroundColor = .white.withAlphaComponent(0.1)
                    cell.dataContent.layoutIfNeeded()
                    cell.dataContent.viewCorner(radius: 4)
                    return cell
                }
            }
            return nil
        }
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
    
    lazy var bleConnectStatusLabel:PTActionLayoutButton = {
        let view = PTActionLayoutButton()
        view.layoutStyle = .leftImageRightTitle
        view.midSpacing = CGFloat.GlobalItemSpacing / 2
        view.imageSize = .init(width: 5, height: 5)
        view.setImage(bleStatusConnectImage, state: .normal)
        view.setImage(bleStatusNoConnectImage, state: .selected)
        view.setTitleFont(.appfont(size: 14), state: .normal)
        view.setTitleFont(.appfont(size: 14), state: .selected)
        view.setTitleColor(.white, state: .normal)
        view.setTitleColor(.white, state: .selected)
        view.setTitle(PTDashboardConfig.languageFunc(text: "casa_bluetooth_status"), state: .normal)
        view.setTitle(PTDashboardConfig.languageFunc(text: "casa_bluetooth_status"), state: .selected)
        view.bounds = .init(origin: .zero, size: .init(width:view.getKitCurrentDimension() + 5, height:PTAppBaseConfig.share.navBarButtonSize))
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
        
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setLeftButtons(views: [appLogo])
        setCustomRightButtons(buttons: [bleConnectStatusLabel])
        
        self.bleConnectStatusLabel.isSelected = !PTDashboardConfig.shared.blueConnected
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.bleConnectStatusLabel.isSelected = !PTDashboardConfig.shared.blueConnected
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataNotification), name: MotorcycleABS, object: nil)
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
    }
        
    @objc func handleAuthSuccess() {
        PTDashboardConfig.shared.blueConnected = true
        PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "connect_success")) {
            self.bleConnectStatusLabel.isSelected = !PTDashboardConfig.shared.blueConnected
        }
    }
    
    override func handleMotorcycleDisconnect() {
        super.handleMotorcycleDisconnect()
        PTGCDManager.shared.delayOnMain(time: 0.35) {
            self.bleConnectStatusLabel.isSelected = !PTDashboardConfig.shared.blueConnected
            self.speedometer.updateSpeed(0)
            self.speedometerReversed.updateSpeed(0)
        }
    }
    
    // MARK: - 界面布局
    private func setupUI() {
        view.backgroundColor = .black
        
        let collectionInset:CGFloat = CGFloat.kTabbarHeight_Total
        detailCollection.contentCollectionView.contentInsetAdjustmentBehavior = .never
        detailCollection.contentCollectionView.contentInset.bottom = collectionInset
        detailCollection.contentCollectionView.verticalScrollIndicatorInsets.bottom = collectionInset

        view.addSubviews([actionStack,speedometer,speedometerReversed,detailCollection,lightControl])
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
        
        detailCollection.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(self.speedometer.snp.bottom)
            make.bottom.equalToSuperview()
        }
                        
        lightControl.snp.makeConstraints { make in
            make.width.equalTo(250)
            make.height.equalTo(34)
            make.top.equalTo(self.speedometer.snp.bottom).offset(-35)
            make.centerX.equalToSuperview()
        }
        
        listSet()
        
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
                self.bleConnectStatusLabel.setTitle(PTDashboardConfig.languageFunc(text: "casa_bluetooth_status"), state: .normal)
                self.bleConnectStatusLabel.setTitle(PTDashboardConfig.languageFunc(text: "casa_bluetooth_status"), state: .disabled)
                self.bleConnectStatusLabel.bounds = .init(origin: .zero, size: .init(width:self.bleConnectStatusLabel.getKitCurrentDimension() + 5, height:PTAppBaseConfig.share.navBarButtonSize))
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
    
    func listSet(finishTask:PTCollectionCallback? = nil) {
        var sections = [PTSection]()
        let rowsTrip = tripModels.map { value in
            let row = PTRows(ID:PTFusionCell.ID,dataModel: value)
            return row
        }
        let sectionTrip = PTSection(headerTitle: PTDashboardConfig.languageFunc(text: "casa_card_distance_title"),headerID: .TRIPSECTION,headerHeight: self.headerHeight,rows: rowsTrip)
        sections.append(sectionTrip)
        
        let rowsMoto = motoModels.map { value in
            let row = PTRows(ID:PTFusionCell.ID,dataModel: value)
            return row
        }
        let sectionMoto = PTSection(headerTitle: PTDashboardConfig.languageFunc(text: "MOTO"),headerID: .MOTOSECTION,headerHeight: self.headerHeight,rows: rowsMoto)
        sections.append(sectionMoto)

        detailCollection.showCollectionDetail(collectionData: sections,finishTask: finishTask)
    }
        
    // MARK: - 状态回调
    @objc func handleDataNotification(_ notification: Notification) {
        if let data1 = notification.object as? PTDashboardData1 {
            let tripKm = data1.tripKm
            let odoKm = data1.odoKm
            let fuelLevelPct = data1.fuelLevelPct
            let avgConsumptionLt = data1.avgConsumptionLt
            
            DispatchQueue.main.async {
                let sectionTrip = 0
                let rows = self.detailCollection.getAllRows(in: sectionTrip)
                guard rows.count > 4 else { return }
                
                // 💡 优化点：对比当前 Cell 的旧数据，如果内容没变就不做无用渲染，彻底消除闪烁
                let newFuelDesc = "\(fuelLevelPct)%"
                let newTripDesc = "\(PTDashboardConfig.shared.appShowMileageValueString(tripKm))\(PTDashboardConfig.shared.appShowUniLabel)"
                let newOdoDesc = "\(PTDashboardConfig.shared.appShowMileageValueString(odoKm))\(PTDashboardConfig.shared.appShowUniLabel)"
                let newAvgDesc = "\(avgConsumptionLt)L/\(PTDashboardConfig.shared.appShowMileageValueString(100))\(PTDashboardConfig.shared.appShowUniLabel)"
                
                if let oldModel = rows[0].dataModel as? PTFusionCellModel, oldModel.desc == newFuelDesc {
                    return // 数据无变化，直接拦截，防止闪烁！
                }
                
                rows[0].dataModel = PTDashboardConfig.baseNormalCellModel(name: PTDashboardConfig.languageFunc(text: "casa_card_oil"), desc: newFuelDesc)
                rows[2].dataModel = PTDashboardConfig.baseNormalCellModel(name: PTDashboardConfig.languageFunc(text: "casa_card_little_trip"), desc: newTripDesc)
                rows[3].dataModel = PTDashboardConfig.baseNormalCellModel(name: PTDashboardConfig.languageFunc(text: "casa_card_odo_trip"), desc: newOdoDesc)
                rows[4].dataModel = PTDashboardConfig.baseNormalCellModel(name: PTDashboardConfig.languageFunc(text: "casa_card_avg_oil"), desc: newAvgDesc)
                
                // 优先只刷新对应的可见 Cell，而不是粗暴地 reloadRows 整个 Section
                self.detailCollection.reloadRows(rows, in: sectionTrip)
            }
        } else if let data2 = notification.object as? PTDashboardData2 {
            let volt = data2.batteryVolt
            let temp = data2.outsideTempC
            let engineStatus = data2.engineStatus
            
            DispatchQueue.main.async {
                let sectionMoto = 1
                let rows = self.detailCollection.getAllRows(in: sectionMoto)
                guard rows.count > 2 else { return }
                
                let newEngineDesc = PTDashboardLabels.engineStatusLabel(raw: engineStatus)
                let newTempDesc = "\(temp)°C"
                
                if let oldModel = rows[0].dataModel as? PTFusionCellModel, oldModel.desc == newEngineDesc {
                    // 即使文字没变，电压进度条可能变了，单独更新电压
                    self.voltageLabel.modelSet = self.modelvoltageSet(currentValue: volt)
                    return
                }
                
                rows[0].dataModel = PTDashboardConfig.baseNormalCellModel(name: PTDashboardConfig.languageFunc(text: "casa_card_engine"), desc: newEngineDesc)
                rows[2].dataModel = PTDashboardConfig.baseNormalCellModel(name: PTDashboardConfig.languageFunc(text: "casa_card_tem"), desc: newTempDesc)
                
                self.detailCollection.reloadRows(rows, in: sectionMoto)
                self.voltageLabel.modelSet = self.modelvoltageSet(currentValue: volt)
            }
        } else if let data3 = notification.object as? PTDashboardData3 {
            let autonomyKm = data3.autonomyKm
            let distToMaintenance = data3.distToMaintenance
            let language = data3.languageType.getTypeName()
            
            DispatchQueue.main.async {
                if let row = self.detailCollection.getRow(at: IndexPath(row: 1, section: 0)) {
                    let newAutonomyDesc = "\(PTDashboardConfig.shared.appShowMileageValueString(autonomyKm))\(PTDashboardConfig.shared.appShowUniLabel)"
                    if let oldModel = row.dataModel as? PTFusionCellModel, oldModel.desc != newAutonomyDesc {
                        row.dataModel = PTDashboardConfig.baseNormalCellModel(name: PTDashboardConfig.languageFunc(text: "casa_card_oil_trip"), desc: newAutonomyDesc)
                        self.detailCollection.reloadRows([row], in: 0)
                    }
                }
                
                let sectionMoto = 1
                let rows = self.detailCollection.getAllRows(in: sectionMoto)
                if rows.indices.contains(3) {
                    let newLangDesc = language
                    if let oldModel = rows[3].dataModel as? PTFusionCellModel, oldModel.desc != newLangDesc {
                        rows[3].dataModel = PTDashboardConfig.baseNormalCellModel(name: PTDashboardConfig.languageFunc(text: "casa_card_lan"), desc: newLangDesc)
                        self.detailCollection.reloadRows([rows[3]], in: sectionMoto)
                    }
                }
                
                self.distToMaintenanceLabel.modelSet = self.distToMaintenancemodelSet(
                    max: PTDashboardConfig.shared.appShowMileage(2500),
                    current: PTDashboardConfig.shared.appShowMileage(Double(distToMaintenance))
                )
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
        } else if let abs = notification.object as? PTAbsStatus {
            let absRaw = abs.absRaw
            DispatchQueue.main.async {
                let sectionMoto = 1
                let rows = self.detailCollection.getAllRows(in: sectionMoto)
                guard rows.indices.contains(1) else { return }
                
                let newAbsDesc = PTDashboardLabels.absLabel(raw: absRaw)
                if let oldModel = rows[1].dataModel as? PTFusionCellModel, oldModel.desc != newAbsDesc {
                    rows[1].dataModel = PTDashboardConfig.baseNormalCellModel(name: "ABS", desc: newAbsDesc)
                    self.detailCollection.reloadRows([rows[1]], in: sectionMoto)
                }
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
