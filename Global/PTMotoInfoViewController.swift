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

class PTMotoInfoViewController: PTBaseViewController {

    lazy var bleButton:UIButton = {
        let view = UIButton(type: .custom)
        view.setImage(UIImage(.gear), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
        })
        return view
    }()
    
    // 状态提示标签
    let statusLabel = UILabel()
    // 发送指令测试按钮
    let sendCommandButton = UIButton(type: .system)
    lazy var statusLabel1 = baseDataLabel()
    lazy var statusLabel2 = baseDataLabel()
    lazy var statusLabel3 = baseDataLabel()
    lazy var statusLabelControl = baseDataLabel()
    lazy var statusLabelABS = baseDataLabel()

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
        setCustomRightButtons(buttons: [bleButton])
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
        view.backgroundColor = .white
        pt_Title = "摩托车蓝牙测试"
        
        // 状态标签配置
        statusLabel.text = "等待操作..."
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.textColor = .darkGray
        statusLabel.frame = CGRect(x: 20, y: 150, width: view.bounds.width - 40, height: 60)
        view.addSubview(statusLabel)
        
        // 启动广播按钮
        let startServerButton = UIButton(type: .system)
        startServerButton.setTitle("1. 启动手机蓝牙基站", for: .normal)
        startServerButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        startServerButton.addTarget(self, action: #selector(startServerTapped), for: .touchUpInside)
        startServerButton.frame = CGRect(x: 50, y: 250, width: view.bounds.width - 100, height: 50)
        startServerButton.backgroundColor = .systemBlue
        startServerButton.setTitleColor(.white, for: .normal)
        startServerButton.layer.cornerRadius = 10
        view.addSubview(startServerButton)
        
        // 发送测试指令按钮
        sendCommandButton.setTitle("2. 发送仪表盘配置指令", for: .normal)
        sendCommandButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        sendCommandButton.addTarget(self, action: #selector(sendTestCommandTapped), for: .touchUpInside)
        sendCommandButton.frame = CGRect(x: 50, y: 330, width: view.bounds.width - 100, height: 50)
        sendCommandButton.backgroundColor = .systemGray // 默认灰色，连接成功后变色
        sendCommandButton.setTitleColor(.white, for: .normal)
        sendCommandButton.layer.cornerRadius = 10
        sendCommandButton.isEnabled = false // 默认禁用，直到认证成功
        view.addSubview(sendCommandButton)
        
        view.addSubviews([statusLabel1,statusLabel2,statusLabel3,statusLabelControl,statusLabelABS,logTextView])
        statusLabel1.snp.makeConstraints { make in
            make.left.right.height.equalTo(statusLabel)
            make.top.equalTo(self.sendCommandButton.snp.bottom).offset(8)
        }
        
        statusLabel2.snp.makeConstraints { make in
            make.left.right.height.equalTo(statusLabel)
            make.top.equalTo(self.statusLabel1.snp.bottom).offset(8)
        }
        
        statusLabel3.snp.makeConstraints { make in
            make.left.right.height.equalTo(statusLabel)
            make.top.equalTo(self.statusLabel2.snp.bottom).offset(8)
        }
        
        statusLabelControl.snp.makeConstraints { make in
            make.left.right.height.equalTo(statusLabel)
            make.top.equalTo(self.statusLabel3.snp.bottom).offset(8)
        }
        
        statusLabelABS.snp.makeConstraints { make in
            make.left.right.height.equalTo(statusLabel)
            make.top.equalTo(self.statusLabelControl.snp.bottom).offset(8)
        }
        
        logTextView.backgroundColor = .clear
        logTextView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalTo(self.sendCommandButton.snp.bottom).offset(8)
            make.bottom.equalToSuperview().inset(CGFloat.kTabbarHeight_Total + 8)
        }
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
                // 假设你有一个 label 叫 statusLabel
                self.statusLabel1.text = """
                里程: \(tripKm)km
                总里程: \(odoKm)km
                fuelLevelPct: \(fuelLevelPct)
                avgConsumptionLt: \(avgConsumptionLt)
                """
            }
        } else if let data2 = notification.object as? PTDashboardData2 {
            
            // 2. ✅ 正确做法：使用【点语法】直接访问属性名称
            let volt = data2.batteryVolt
            let temp = data2.outsideTempC
            let engineStatus = data2.engineStatus
            
            // 3. 结合我们之前写的状态标签工具，更新到主线程的 UI 上
            DispatchQueue.main.async {
                // 假设你有一个 label 叫 statusLabel
                self.statusLabel2.text = """
                电池电压: \(volt)V
                外部温度: \(temp)°C
                引擎状态: \(PTDashboardLabels.engineStatusLabel(raw: engineStatus))
                """
            }
        } else if let data3 = notification.object as? PTDashboardData3 {
            
            let autonomyKm = data3.autonomyKm
            let distToMaintenance = data3.distToMaintenance
            let colorMeasur = data3.colorMeasur
            let language = data3.language
            
            // 3. 结合我们之前写的状态标签工具，更新到主线程的 UI 上
            DispatchQueue.main.async {
                // 假设你有一个 label 叫 statusLabel
                self.statusLabel3.text = """
                autonomyKm: \(autonomyKm)km
                distToMaintenance: \(distToMaintenance)km
                colorMeasur: \(colorMeasur)
                language: \(language)
                """
            }
        } else if let control = notification.object as? PTDashboardControl {
            
            let vehicleSpeedKmh = control.vehicleSpeedKmh
            let engineRpm = control.engineRpm

            // 3. 结合我们之前写的状态标签工具，更新到主线程的 UI 上
            DispatchQueue.main.async {
                // 假设你有一个 label 叫 statusLabel
                self.statusLabelControl.text = """
                vehicleSpeedKmh: \(vehicleSpeedKmh)km
                engineRpm: \(engineRpm)rpm
                """
            }
        } else if let abs = notification.object as? PTAbsStatus {
            
            let absRaw = abs.absRaw

            // 3. 结合我们之前写的状态标签工具，更新到主线程的 UI 上
            DispatchQueue.main.async {
                // 假设你有一个 label 叫 statusLabel
                self.statusLabelABS.text = """
                abs: \(absRaw)
                """
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
