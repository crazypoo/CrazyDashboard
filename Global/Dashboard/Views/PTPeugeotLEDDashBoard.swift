//
//  PTPeugeotLEDDashBoard.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 14/8/2026.
//

import UIKit
import PooTools
import SnapKit
import SwifterSwift

class PTPeugeotLEDDashBoard: UIView {
    
    let leftFuelGauge = PTArcGaugeView(isLeftAligned: true, color: .systemOrange)
    let rightTempGauge = PTArcGaugeView(isLeftAligned: false, color: .systemRed)
    
    lazy var tempVoltageLabel : UILabel = {
        let view = UILabel()
        view.numberOfLines = 2
        view.textAlignment = .right
        view.font = .appfont(size: 14,bold: true)
        view.textColor = .white
        return view
    }()
    
    lazy var dateTimeLabel : UILabel = {
        let view = UILabel()
        view.numberOfLines = 2
        view.textAlignment = .left
        view.font = .appfont(size: 14,bold: true)
        view.textColor = .white
        return view
    }()

    private var clockTimer: Timer?
    
    private let bottomBar = UIStackView()
    public let odoLabel = UILabel()
    public let rangeLabel = UILabel()
    public let consumptionLabel = UILabel()
    public let tripLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        
        addSubviews([leftFuelGauge,rightTempGauge,tempVoltageLabel,dateTimeLabel,bottomBar])
        leftFuelGauge.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.equalToSuperview()
            // 🌟 必须明确宽度和高度，否则 bounds.height 为 0，无法画圆！
            make.width.equalTo(60)
            make.height.equalTo(150)
        }
        leftFuelGauge.progress = 0
        
        rightTempGauge.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.width.equalTo(60)
            make.height.equalTo(150)
            make.centerY.equalToSuperview()
        }
        
        tempVoltageLabel.snp.makeConstraints { make in
            make.top.right.equalToSuperview()
        }
        
        dateTimeLabel.snp.makeConstraints { make in
            make.top.left.equalToSuperview()
        }
        
        startRealTimeClock()
        
        bottomBar.axis = .horizontal
        bottomBar.distribution = .equalSpacing
        bottomBar.alignment = .center
        let bottomLabels = [odoLabel, rangeLabel, consumptionLabel, tripLabel]
        for label in bottomLabels {
            label.font = .boldSystemFont(ofSize: 13)
            label.textColor = .white
            bottomBar.addArrangedSubview(label)
        }

        bottomBar.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.right.equalToSuperview()
            make.bottom.equalToSuperview()
            make.height.equalTo(44)
        }
    }
    
    public func startRealTimeClock() {
        // 立即刷新一次，避免 UI 出现短暂的空白或旧数据
        updateClockUI()
        
        // 挂载定时器，每 1 秒更新一次 (如果不需要秒级精度，也可以设为 60 秒)
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.updateClockUI()
        }
        
        // 将定时器加入 RunLoop 的 common 模式，保证在滑动其他视图时时钟也不会卡顿
        if let timer = clockTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func updateClockUI() {
        let formatter = DateFormatter()
        
        // 🌟 核心定制：dd(日)/MM(月)/yy(两位年份) \n(换行) HH(24小时制):mm(分钟)
        formatter.dateFormat = "dd/MM/yy\nHH:mm"
        
        // 根据你当前的系统时间 (2026年8月13日 22:45)，它将输出:
        // 13/08/26
        // 22:45
        self.dateTimeLabel.text = formatter.string(from: Date())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
