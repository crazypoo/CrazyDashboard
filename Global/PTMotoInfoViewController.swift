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

fileprivate extension String {
    static let TRIPSECTION = "TRIPSECTION"
    static let MOTOSECTION = "MOTOSECTION"
}

class PTMotoInfoViewController: PTBaseViewController {

    let buttonCount:Int = 4
    let stackHeight:CGFloat = 54.adapter
    
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
        view.altitudeLabel.isHidden = true
        view.pressureLabel.isHidden = true
        return view
    }()
    
    lazy var speedometerReversed:PTReversedSpeedometerView = {
        let view = PTReversedSpeedometerView(frame: .zero)
        view.altitudeLabel.isHidden = true
        view.pressureLabel.isHidden = true
        view.unitLabel.text = "RPM"
        view.maxSpeed = 9000
        return view
    }()
    
    var tripModels:[PTFusionCellModel] {
        get {
            let oilModel = PTDashboardConfig.baseNormalCellModel(name: "油量",desc: "0%")
            let oilTrip = PTDashboardConfig.baseNormalCellModel(name: "油量里程",desc: "0KM")
            let littleTrip = PTDashboardConfig.baseNormalCellModel(name: "小计里程",desc: "0KM")
            let ODOTrip = PTDashboardConfig.baseNormalCellModel(name: "总里程",desc: "0KM")
            return [oilModel,oilTrip,littleTrip,ODOTrip]
        } set{ }
    }
    
    var motoModels:[PTFusionCellModel] {
        get {
            let motoModel = PTDashboardConfig.baseNormalCellModel(name: "发动机",desc: "-")
            let absModel = PTDashboardConfig.baseNormalCellModel(name: "ABS",desc: "-")
            let temModel = PTDashboardConfig.baseNormalCellModel(name: "温度",desc: "0°C")
            let lanTrip = PTDashboardConfig.baseNormalCellModel(name: "语言",desc: "EN")
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
            return UICollectionView.girdCollectionLayout(data: section.rows, itemHeight: 64,cellRowCount: 2,originalX: PTAppBaseConfig.share.defaultViewSpace,cellLeadingSpace: CGFloat.GlobalItemSpacing,cellTrailingSpace: CGFloat.GlobalItemSpacing)
        }
        view.cellInCollection = { collectionView,sectionModel,indexPath in
            if let itemRow = sectionModel.rows?[indexPath.row] {
                let getCell = collectionView.dequeueReusableCell(withReuseIdentifier: itemRow.ID, for: indexPath)
                if let cell = getCell as? PTFusionCell,let cellModel = itemRow.dataModel as? PTFusionCellModel {
                    cell.cellModel = cellModel
                    cell.backgroundColor = .lightGray
                    return cell
                }
            }
            return nil
        }
        view.collectionDidSelect = { collectionView,sectionModel,indexPath in
        }
        return view
    }()

    
    // 状态提示标签
    let statusLabel = UILabel()
    // 发送指令测试按钮
    let sendCommandButton = UIButton(type: .system)

    let logTextView = UITextView()
    
    func baseDataLabel() ->UILabel {
        let view = UILabel()
        view.numberOfLines = 0
        view.font = .appfont(size: 14)
        view.textColor = .black
        return view
    }
    
    open override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        return .solid(.clear)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
//        setCustomRightButtons(buttons: [bleButton])
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataNotification), name: NSNotification.Name("MotorcycleDATA1"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataNotification), name: NSNotification.Name("MotorcycleDATA2"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataNotification), name: NSNotification.Name("MotorcycleDATA3"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataNotification), name: NSNotification.Name("MotorcycleCONTROL"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataNotification), name: NSNotification.Name("MotorcycleABS"), object: nil)
    }
    
    // MARK: - 界面布局
    private func setupUI() {
        view.backgroundColor = .black
        
        let collectionInset:CGFloat = CGFloat.kTabbarHeight_Total
        detailCollection.contentCollectionView.contentInsetAdjustmentBehavior = .never
        detailCollection.contentCollectionView.contentInset.bottom = collectionInset
        detailCollection.contentCollectionView.verticalScrollIndicatorInsets.bottom = collectionInset

        view.addSubviews([actionStack,speedometer,speedometerReversed,detailCollection])
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
        
        let modelvoltage = PTMainProgressViewModel()
        modelvoltage.name = PTDashboardConfig.languageFunc(text: "casa_batt")
        modelvoltage.currentValue = 0
        modelvoltage.maxValue = 14.5
        modelvoltage.uni = "V"
        self.voltageLabel.modelSet = modelvoltage

        let distToMaintenancemodel = PTMainProgressViewModel()
        distToMaintenancemodel.name = PTDashboardConfig.languageFunc(text: "保养")
        distToMaintenancemodel.currentValue = 0
        distToMaintenancemodel.maxValue = 0
        distToMaintenancemodel.uni = "km"
        self.distToMaintenanceLabel.modelSet = distToMaintenancemodel

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
        
        listSet()
    }
    
    func listSet(finishTask:PTCollectionCallback? = nil) {
        var sections = [PTSection]()
        let rowsTrip = tripModels.map { value in
            let row = PTRows(ID:PTFusionCell.ID,dataModel: value)
            return row
        }
        let sectionTrip = PTSection(headerTitle: PTDashboardConfig.languageFunc(text: "里程"),headerID: .TRIPSECTION,headerHeight: 44,rows: rowsTrip)
        sections.append(sectionTrip)
        
        let rowsMoto = motoModels.map { value in
            let row = PTRows(ID:PTFusionCell.ID,dataModel: value)
            return row
        }
        let sectionMoto = PTSection(headerTitle: PTDashboardConfig.languageFunc(text: "MOTO"),headerID: .MOTOSECTION,headerHeight: 44,rows: rowsMoto)
        sections.append(sectionMoto)

        detailCollection.showCollectionDetail(collectionData: sections,finishTask: finishTask)
    }
    
    // MARK: - 按钮交互逻辑
    
    @objc func startServerTapped() {
        statusLabel.text = "正在启动 TIO 广播...\n请打开摩托车电门并靠近手机"
        
        // 2. 唤醒单例，触发 peripheralManagerDidUpdateState，开始广播
//        PTBluetoothServerManager.shared.startBaseStationAndScan()
        PTBluetoothServerManager.shared.startBaseStationAndScan()
    }
    
    @objc func sendTestCommandTapped() {
        // 3. 构造并发送指令[cite: 2]
        // 假设你要发送的配置为：颜色(Blue=0), 单位(KM=0), 语言(EN=1)[cite: 2]
        let color: UInt8 = 0
        let unit: UInt8 = 0
        let language: UInt8 = 1
        
        PTBluetoothServerManager.shared.sendConfiguration(color: color, unit: unit, language: language)
        statusLabel.text = "配置指令已发送！请观察仪表盘是否发生变化。"
        PTProgressHUD.show(text: "指令发送成功")
    }
    
    // MARK: - 状态回调
    
    @objc func handleAuthSuccess() {
        DispatchQueue.main.async {
            self.statusLabel.text = "✅ 认证成功！数据通道已解锁\n你可以开始发送指令了"
            self.statusLabel.textColor = .systemGreen
            
            // 启用发送指令按钮
            self.sendCommandButton.isEnabled = true
            self.sendCommandButton.backgroundColor = .systemOrange
        }
    }
    
    @objc func handleDataNotification(_ notification: Notification) {
        // 1. 将广播传递过来的 object 安全地向下转型为我们的数据模型
        if let data1 = notification.object as? PTDashboardData1 {
            
            let tripKm = data1.tripKm
            let odoKm = data1.odoKm
            let fuelLevelPct = data1.fuelLevelPct
            let avgConsumptionLt = data1.avgConsumptionLt
            
            // 3. 结合我们之前写的状态标签工具，更新到主线程的 UI 上
            DispatchQueue.main.async {
                let sectionTrip = 0
                let rows = self.detailCollection.getAllRows(in: sectionTrip)
                rows[0].dataModel = PTDashboardConfig.baseNormalCellModel(name: "油量",desc: "\(fuelLevelPct)%")
                rows[2].dataModel = PTDashboardConfig.baseNormalCellModel(name: "小计里程",desc: "\(tripKm)KM")
                rows[3].dataModel = PTDashboardConfig.baseNormalCellModel(name: "总里程",desc: "\(odoKm)KM")
                self.detailCollection.reloadRows(rows, in: sectionTrip)
            }
        } else if let data2 = notification.object as? PTDashboardData2 {
            
            // 2. ✅ 正确做法：使用【点语法】直接访问属性名称
            let volt = data2.batteryVolt
            let temp = data2.outsideTempC
            let engineStatus = data2.engineStatus
            
            // 3. 结合我们之前写的状态标签工具，更新到主线程的 UI 上
            DispatchQueue.main.async {
                let sectionTrip = 1
                let rows = self.detailCollection.getAllRows(in: sectionTrip)
                rows[0].dataModel = PTDashboardConfig.baseNormalCellModel(name: "发动机",desc: PTDashboardLabels.engineStatusLabel(raw: engineStatus))
                rows[2].dataModel = PTDashboardConfig.baseNormalCellModel(name: "温度",desc: "\(temp)°C")
                self.detailCollection.reloadRows(rows, in: sectionTrip)

                let modelvoltage = PTMainProgressViewModel()
                modelvoltage.name = PTDashboardConfig.languageFunc(text: "casa_batt")
                modelvoltage.currentValue = volt
                modelvoltage.maxValue = 14.5
                modelvoltage.uni = "V"
                self.voltageLabel.modelSet = modelvoltage
            }
        } else if let data3 = notification.object as? PTDashboardData3 {
            
            let autonomyKm = data3.autonomyKm
            let distToMaintenance = data3.distToMaintenance
            let colorMeasur = data3.colorMeasur
            let language = data3.language
            
            // 3. 结合我们之前写的状态标签工具，更新到主线程的 UI 上
            DispatchQueue.main.async {
                if let row = self.detailCollection.getRow(at: IndexPath.SubSequence(row: 1, section: 0)) {
                    row.dataModel = PTDashboardConfig.baseNormalCellModel(name: "油量里程",desc: "\(autonomyKm)KM")
                    self.detailCollection.reloadRows([row], in: 0)
                }
                let sectionTrip = 1
                let rows = self.detailCollection.getAllRows(in: sectionTrip)
                rows[3].dataModel = PTDashboardConfig.baseNormalCellModel(name: "语言",desc: PTDashboardLabels.languageLabel(r: language))
                self.detailCollection.reloadRows(rows, in: sectionTrip)
                
                let distToMaintenancemodel = PTMainProgressViewModel()
                distToMaintenancemodel.name = PTDashboardConfig.languageFunc(text: "保养")
                distToMaintenancemodel.currentValue = Double(distToMaintenance)
                distToMaintenancemodel.maxValue = 2500
                distToMaintenancemodel.uni = "km"
                self.distToMaintenanceLabel.modelSet = distToMaintenancemodel

//
//                // 假设你有一个 label 叫 statusLabel
//                self.statusLabel3.text = """
//                autonomyKm: \(autonomyKm)km
//                distToMaintenance: \(distToMaintenance)km
//                colorMeasur: \(colorMeasur)
//                language: \(language)
//                """
            }
        } else if let control = notification.object as? PTDashboardControl {
            
            let vehicleSpeedKmh = control.vehicleSpeedKmh
            let engineRpm = control.engineRpm

            // 3. 结合我们之前写的状态标签工具，更新到主线程的 UI 上
            DispatchQueue.main.async {
                self.speedometer.updateSpeed(vehicleSpeedKmh)
                self.speedometerReversed.updateSpeed(CGFloat(engineRpm))
            }
        } else if let abs = notification.object as? PTAbsStatus {
            
            let absRaw = abs.absRaw

            // 3. 结合我们之前写的状态标签工具，更新到主线程的 UI 上
            DispatchQueue.main.async {
                let sectionTrip = 1
                let rows = self.detailCollection.getAllRows(in: sectionTrip)
                rows[1].dataModel = PTDashboardConfig.baseNormalCellModel(name: "ABS",desc: PTDashboardLabels.absLabel(raw: absRaw))
                self.detailCollection.reloadRows(rows, in: sectionTrip)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
