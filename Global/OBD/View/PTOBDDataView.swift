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
    
    private var valueFormat: String = "%.0f"
    
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
        titleLabel.numberOfLines = 0
        
        // 数值标签
        valueLabel.textColor = .white
        valueLabel.font = .appfont(size: 28, bold:true)
        valueLabel.textAlignment = .center
        valueLabel.format = "%.0f"
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
            make.left.right.equalToSuperview()
        }
    }
    
    /// 便捷配置方法
    func configure(title: String, format: String = "%.0f") {
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
    
    // 🌟 UI 字典：通过指令字符串(Key)快速找到对应的 View
    private var itemViews: [String: PTTelemetryItemView] = [:]
    
    // 🌟 大容器：用于承载所有动态生成的行 StackView
    private let mainGridStack = UIStackView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.backgroundColor = UIColor(white: 0.05, alpha: 1.0)
        
        // 配置大容器属性
        mainGridStack.axis = .vertical
        mainGridStack.distribution = .fillEqually
        mainGridStack.spacing = CGFloat.GlobalItemSpacing
        self.addSubview(mainGridStack)
        mainGridStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(CGFloat.GlobalItemSpacing)
        }
        
        // 自动注册为 OBD 数据监听者
        PTMotoTelemetryManager.shared.addDelegate(self)
        
        // 如果初始化时已经有缓存的支持指令，直接构建
        if !PTMotoTelemetryManager.shared.obdInfo.supportCommand.isEmpty {
            let map = PTMotoTelemetryManager.shared.obdInfo.supportCommand.map { value in
                value.properties.command
            }
            self.buildDynamicGrid(with: map)
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        PTMotoTelemetryManager.shared.removeDelegate(self)
    }
    
    // MARK: - 全频段动态构建网格
    private func buildDynamicGrid(with commands: [String]) {
        // 1. 清理旧的视图，防止重复添加
        mainGridStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        
        // 2. 筛选并创建所有被支持的 View
        var activeItems: [UIView] = []
        
        for commandString in commands {
            var title = ""
            var format = "%.0f"
            var isConfigured = false
            
            // 拦截非标准库的自定义直读指令 (如电压)
            if commandString == "ATRV" {
                title = "Battery Voltage"
                format = "%.1f"
                isConfigured = true
            }
            // 利用 SwiftOBD2 的全局检索方法，动态提取属性！
            else if let obdCommand = OBDCommand.from(command: commandString) {
                // 直接提取标准库里写的精准英文描述
                title = obdCommand.properties.description
                
                // 🤖 智能推断小数点精度
                let unit = obdCommand.unitString
                                
                // 智能推断小数点精度，并将单位直接拼接到格式字符串的尾部！
                let desc = title.lowercased()
                if desc.contains("voltage") && desc.contains("o2") {
                    format = "%.2f \(unit)" // 如： 0.45 V
                } else if desc.contains("voltage") || desc.contains("rate") || desc.contains("advance") || desc.contains("maf") {
                    format = "%.1f \(unit)" // 如： 14.1 V, 3.2 g/s
                } else {
                    format = "%.0f \(unit)" // 如： 1600 RPM, 95 ℃
                }

                isConfigured = true
            }
            // 💡 匹配逻辑 C：探索未知的厂家私有指令，绝不放过任何一个数据！
            else {
                title = "Unknown [\(commandString)]"
                format = "%.1f" // 未知数据保留 1 位小数方便观察
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
        
        // 经典的自动切块与排版算法 (4列)
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
        
        // 将生成的所有行加入到主容器中
        for stack in rowStacks {
            mainGridStack.addArrangedSubview(stack)
        }
    }
}

extension PTOBDDataView: PTMotoTelemetryDelegate {
    
    // EN: Rebuild the grid after dynamic command discovery, while keeping UIKit work on the main thread.
    // ES: Reconstruye la cuadrícula después de descubrir comandos dinámicos y mantiene UIKit en el hilo principal.
    // 中文：动态发现支持指令后重建网格，并确保所有 UIKit 操作在主线程执行。
    func telemetryManager(_ manager: PTMotoTelemetryManager, didDiscoverSupportedCommands commands: [String]) {
        var seen = Set<String>()
        let normalizedCommands = commands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }

        guard !normalizedCommands.isEmpty else { return }

        let rebuild: () -> Void = { [weak self] in
            guard let self else { return }
            self.buildDynamicGrid(with: normalizedCommands)
        }
        if Thread.isMainThread {
            rebuild()
        } else {
            DispatchQueue.main.async(execute: rebuild)
        }
    }
    
    // MARK: - 接收代理数据并驱动动画
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateMeasurements measurements: [String: Any]) {
        // 数据高频更新
        for (command, value) in measurements {
            // 从字典中提取对应的 Double 值
            var doubleValue: Double = 0.0
            if let v = value as? Double {
                doubleValue = v
            } else if let strV = value as? String, let v = Double(strV) {
                doubleValue = v
            } else {
                continue
            }
            
            // 找到对应指令的 UI 组件并瞬间触发更新
            if let itemView = itemViews[command] {
                itemView.updateValue(doubleValue)
            }
        }
    }
}
