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
import SwiftOBD2

class PTTelemetryItemView: UIView {
    
    // 标题标签 (如: "转速 RPM")
    let titleLabel = UILabel()
    // 动画数值标签
    let valueLabel = PTCountingLabel()
    
    private var valueFormat: String = "%d"
    
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
        titleLabel.font = .appfont(size: 14, bold:true)
        titleLabel.textAlignment = .center
        
        // 数值标签
        valueLabel.textColor = .white
        valueLabel.font = .appfont(size: 28, bold:true)
        valueLabel.textAlignment = .center
        valueLabel.format = "%d"
        valueLabel.countFromZero(toValue: 0)
        
        self.addSubviews([titleLabel,valueLabel])
        
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
        self.valueFormat = format
        valueLabel.format = format
    }
    
    func updateValue(_ newValue: Double) {
        // 高频刷新下，直接设置 text 防抖动；如果你的库支持平滑过渡，也可保留 countFrom
        valueLabel.countFromCurrentValue(toValue: newValue)
    }
}

class PTOBDDataView: UIView {
    
    // 🌟 1. UI 字典：通过指令字符串(Key)快速找到对应的 View
    private var itemViews: [String: PTTelemetryItemView] = [:]
    
    // 🌟 2. 大容器：用于承载所有动态生成的行 StackView
    private let mainGridStack = UIStackView()
    
    // 🌟 3. 核心改进：利用 SwiftOBD2 枚举构建标准指令格式清单
    // 在这里我们只绑定具体的枚举对象和 UI 数值显示格式
    private let standardCommands: [(command: OBDCommand, format: String)] = [
        (.mode1(.speed), "%d"),
        (.mode1(.rpm), "%d"),
        (.mode1(.throttlePos), "%d"),
        (.mode1(.coolantTemp), "%d"),
        (.mode1(.controlModuleVoltage), "%.1f"),
        (.mode1(.intakeTemp), "%d"),
        (.mode1(.intakePressure), "%d"),
        (.mode1(.timingAdvance), "%.1f"),
        (.mode1(.maf), "%.1f"),
        (.mode1(.runTime), "%d"),
        (.mode1(.fuelLevel), "%d"),
        (.mode1(.fuelRate), "%.1f"),
        (.mode1(.barometricPressure), "%d"),
        (.mode1(.distanceSinceDTCCleared), "%d")
    ]
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.backgroundColor = UIColor(white: 0.05, alpha: 1.0)
        
        // 配置大容器属性
        mainGridStack.axis = .vertical
        mainGridStack.distribution = .fillEqually
        mainGridStack.spacing = 10
        self.addSubview(mainGridStack)
        mainGridStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(CGFloat.GlobalItemSpacing)
        }
        
        // 自动注册为 OBD 数据监听者
        PTMotoTelemetryManager.shared.addDelegate(self)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // MARK: - 🌟 核心：根据支持的指令动态构建网格
    private func buildDynamicGrid(with commands: [String]) {
        // 1. 清理旧的视图，防止重复添加
        mainGridStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        
        // 2. 筛选并创建所有被支持的 View
        var activeItems: [UIView] = []
        
        for commandString in commands {
            var title = ""
            var format = "%d"
            var isConfigured = false
            
            // 💡 匹配逻辑 A：首先拦截非标准库的自定义直读指令
            if commandString == "ATRV" {
                title = "Battery Voltage (ATRV)" // 自定义标题
                format = "%.1f"
                isConfigured = true
            }
            // 💡 匹配逻辑 B：在 SwiftOBD2 标准库配置中寻找匹配项
            else if let match = standardCommands.first(where: { $0.command.properties.command == commandString }) {
                // 直接提取 SwiftOBD2 内置的描述名称作为标题！
                title = match.command.properties.description
                format = match.format
                isConfigured = true
            }
            
            // 如果成功配置，则生成对应的格子
            if isConfigured {
                let itemView = PTTelemetryItemView()
                itemView.configure(title: title, format: format)
                
                // 将创建好的 View 存入字典，以便后续更新数据
                itemViews[commandString] = itemView
                activeItems.append(itemView)
            }
        }
        
        // 3. 经典的自动切块与排版算法 (4列)
        let maxColumns = 4
        var rowStacks: [UIStackView] = []
        
        for i in stride(from: 0, to: activeItems.count, by: maxColumns) {
            let endIndex = min(i + maxColumns, activeItems.count)
            let rowItems = Array(activeItems[i..<endIndex])
            
            let rowStack = UIStackView(arrangedSubviews: rowItems)
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = 10
            
            // 完美对齐黑魔法：补齐透明的空 UIView
            if rowItems.count < maxColumns {
                let emptySpaces = maxColumns - rowItems.count
                for _ in 0..<emptySpaces {
                    let dummyView = UIView()
                    dummyView.backgroundColor = .clear
                    rowStack.addArrangedSubview(dummyView)
                }
            }
            rowStacks.append(rowStack)
        }
        
        // 4. 将生成的所有行加入到主容器中
        for stack in rowStacks {
            mainGridStack.addArrangedSubview(stack)
        }
    }
}

extension PTOBDDataView: PTMotoTelemetryDelegate {
    // MARK: - 接收代理数据并驱动动画
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateMeasurements measurements: [String: Any]) {
        // 数据高频更新
        for (command, value) in measurements {
            // 1. 从字典中提取对应的 Double 值
            var doubleValue: Double = 0.0
            if let v = value as? Double {
                doubleValue = v
            } else if let strV = value as? String, let v = Double(strV) {
                doubleValue = v
            } else {
                continue
            }
            
            // 2. 找到对应指令的 UI 组件并瞬间触发更新
            if let itemView = itemViews[command] {
                itemView.updateValue(doubleValue)
            }
        }
    }
    
    func telemetryManager(_ manager: PTMotoTelemetryManager, didDiscoverSupportedCommands commands: [String]) {
        DispatchQueue.main.async { [weak self] in
            self?.buildDynamicGrid(with: commands)
        }
    }
}
