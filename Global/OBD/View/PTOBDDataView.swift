//
//  PTOBDDataView.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 6/8/2026.
//

import UIKit
import PooTools
import SnapKit
import SwifterSwift

class PTTelemetryItemView: UIView {
    
    // 标题标签 (如: "转速 RPM")
    let titleLabel = UILabel()
    // 动画数值标签
    let valueLabel = PTCountingLabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // 极简风格设置
        titleLabel.textColor = .lightGray
        titleLabel.font = .appfont(size: 14,bold:true)
        titleLabel.textAlignment = .center
        
        // 数值标签：使用等宽字体防抖动，仅显示整数
        valueLabel.textColor = .white
        valueLabel.font = .appfont(size: 28,bold:true)
        valueLabel.textAlignment = .center
        valueLabel.format = "%d"
        valueLabel.countFromZero(toValue: 0)
        
        self.addSubview(titleLabel)
        self.addSubview(valueLabel)
        
        // 紧凑的上下排列约束
        valueLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview().offset(-10)
            make.centerX.equalToSuperview()
        }
        
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(valueLabel.snp.bottom).offset(4)
            make.centerX.equalToSuperview()
        }
    }
    
    /// 便捷配置方法
    func configure(title: String, format: String = "%d") {
        titleLabel.text = title
        valueLabel.format = format
    }
}

class PTOBDDataView: UIView {

    // MARK: - 1. 声明所有的 14 个数据格子
    // 基础
    private let speedItem = PTTelemetryItemView()
    private let rpmItem = PTTelemetryItemView()
    private let throttleItem = PTTelemetryItemView()
    // 健康
    private let coolantItem = PTTelemetryItemView()
    private let voltageItem = PTTelemetryItemView()
    private let airTempItem = PTTelemetryItemView()
    // 进阶
    private let mapItem = PTTelemetryItemView()
    private let timingAdvanceItem = PTTelemetryItemView()
    private let mafItem = PTTelemetryItemView()
    private let runTimeItem = PTTelemetryItemView()
    // 燃油与行程
    private let fuelLevelItem = PTTelemetryItemView()
    private let fuelRateItem = PTTelemetryItemView()
    private let baroItem = PTTelemetryItemView()
    private let tripItem = PTTelemetryItemView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.backgroundColor = UIColor(white: 0.05, alpha: 1.0) // 极简深色背景
                
        setupDynamicGrid()
        
        // 🌟 自动注册为 OBD 数据监听者
        PTMotoTelemetryManager.shared.addDelegate(self)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // MARK: - 布局构建
    private func setupDynamicGrid() {
        // 配置所有格子的标题和格式
        speedItem.configure(title: "时速 (km/h)")
        rpmItem.configure(title: "转速 (RPM)")
        throttleItem.configure(title: "节气门 (%)")
        fuelLevelItem.configure(title: "燃油量 (%)")
        
        coolantItem.configure(title: "水温 (℃)")
        voltageItem.configure(title: "电压 (V)", format: "%.1f")
        airTempItem.configure(title: "进气温 (℃)")
        baroItem.configure(title: "气压 (kPa)")
        
        mapItem.configure(title: "进气压 (kPa)")
        fuelRateItem.configure(title: "瞬时油耗 (L/h)", format: "%.1f")
        mafItem.configure(title: "空气流量 (g/s)", format: "%.1f")
        tripItem.configure(title: "小计里程 (km)")
        
        // 补齐被遗漏的数据
        timingAdvanceItem.configure(title: "点火提前角 (°)", format: "%.1f")
        runTimeItem.configure(title: "运行时长 (秒)")
        
        // 🌟 将所有 14 个格子放入一个大数组 (你可以随意调整它们在这里的顺序)
        let allItems = [
            speedItem, rpmItem, throttleItem, fuelLevelItem,
            coolantItem, voltageItem, airTempItem, baroItem,
            mapItem, fuelRateItem, mafItem, tripItem,
            timingAdvanceItem, runTimeItem // 第 13、14 个数据
        ]
        
        let maxColumns = 4 // 每行最多 4 个
        var rowStacks: [UIStackView] = []
        
        // 🌟 自动切块算法：每次步进 4，遍历大数组
        for i in stride(from: 0, to: allItems.count, by: maxColumns) {
            
            // 截取当前行的元素 (可能不足 4 个)
            let endIndex = min(i + maxColumns, allItems.count)
            let rowItems = Array(allItems[i..<endIndex])
            
            let rowStack = UIStackView(arrangedSubviews: rowItems)
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = 10
            
            // 🌟 完美对齐黑魔法：如果这一行不足 4 个，补齐透明的空 UIView！
            if rowItems.count < maxColumns {
                let emptySpaces = maxColumns - rowItems.count
                for _ in 0..<emptySpaces {
                    let dummyView = UIView()
                    dummyView.backgroundColor = .clear // 透明不可见
                    rowStack.addArrangedSubview(dummyView)
                }
            }
            
            rowStacks.append(rowStack)
        }
        
        // 将所有生成的行 StackView，放入垂直的 Main StackView 中
        let mainGridStack = UIStackView(arrangedSubviews: rowStacks)
        mainGridStack.axis = .vertical
        mainGridStack.distribution = .fillEqually
        mainGridStack.spacing = 10
        
        self.addSubview(mainGridStack)
        mainGridStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(16)
        }
    }
    
    /// 辅助方法：生成等宽的水平行
    private func createRowStack(items: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: items)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = CGFloat.GlobalItemSpacing // 列间距
        return stack
    }
}

extension PTOBDDataView:PTMotoTelemetryDelegate {
    // MARK: - 接收代理数据并驱动动画
    
    public func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateBaseData rpm: Double, speed: Double, throttle: Double) {
        rpmItem.valueLabel.countFormCurrentValue(toValue: CGFloat(rpm), duration: 0.3)
        speedItem.valueLabel.countFormCurrentValue(toValue: CGFloat(speed), duration: 0.3)
        throttleItem.valueLabel.countFormCurrentValue(toValue: CGFloat(throttle), duration: 0.3)
    }
    
    public func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateHealthData coolantTemp: Int, voltage: Double, intakeAirTemp: Int) {
        coolantItem.valueLabel.countFormCurrentValue(toValue: CGFloat(coolantTemp), duration: 0.5)
        voltageItem.valueLabel.countFormCurrentValue(toValue: CGFloat(voltage), duration: 0.5)
        airTempItem.valueLabel.countFormCurrentValue(toValue: CGFloat(intakeAirTemp), duration: 0.5)
    }
    
    public func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateAdvancedData map: Int, timingAdvance: Double, maf: Double, runTime: Int) {
        mapItem.valueLabel.countFormCurrentValue(toValue: CGFloat(map), duration: 0.5)
        mafItem.valueLabel.countFormCurrentValue(toValue: CGFloat(maf), duration: 0.5)
        
        // 喂给刚刚补回来的 UI
        timingAdvanceItem.valueLabel.countFormCurrentValue(toValue: CGFloat(timingAdvance), duration: 0.5)
        runTimeItem.valueLabel.countFormCurrentValue(toValue: CGFloat(runTime), duration: 0.5)
    }
    
    public func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateTripAndFuelData fuelLevel: Double, fuelRate: Double, barometricPressure: Int, tripDistance: Int) {
        fuelLevelItem.valueLabel.countFormCurrentValue(toValue: CGFloat(fuelLevel), duration: 0.5)
        baroItem.valueLabel.countFormCurrentValue(toValue: CGFloat(barometricPressure), duration: 0.5)
        fuelRateItem.valueLabel.countFormCurrentValue(toValue: CGFloat(fuelRate), duration: 0.5)
        tripItem.valueLabel.countFormCurrentValue(toValue: CGFloat(tripDistance), duration: 0.5)
    }
}
