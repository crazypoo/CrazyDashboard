//
//  PTNativeTelemetryChartView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 27/7/2026.
//

import UIKit
import PooTools
import SnapKit

// MARK: - 单条折线数据模型
public struct PTChartLineModel {
    public let name: String       // 线条名称
    public let color: UIColor     // 线条与图例颜色
    public let data: [Double]     // 遥测时间轴数据数组
    
    public init(name: String, color: UIColor, data: [Double]) {
        self.name = name
        self.color = color
        self.data = data
    }
}

// MARK: - 原生专业遥测折线图
@objcMembers
public class PTNativeTelemetryChartView: UIView {
    
    // MARK: - UI 组件
    /// 用于装载所有折线、网格和 Y 轴标签的核心容器
    private let chartContainerView = UIView()
    
    /// 底部图例使用横向 ScrollView 嵌套 StackView
    private let legendScrollView = UIScrollView()
    private let legendStackView = UIStackView()
    
    // MARK: - 渲染层缓存 (便于在 Cell 中复用时清理)
    private var chartSublayers: [CALayer] = []
    
    // MARK: - 图表布局参数
    private let yAxisWidth: CGFloat = 40.0   // 给左侧 Y 轴文字预留的宽度
    private let rightPadding: CGFloat = 10.0 // 右侧边距
    private let topPadding: CGFloat = 20.0   // 顶部边距
    private let bottomPadding: CGFloat = 10.0// 底部边距
    private let gridCount: Int = 5           // Y轴划分为几个横向网格区间
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        self.backgroundColor = .clear
        
        // 1. 图例容器设置
        legendScrollView.showsHorizontalScrollIndicator = false
        legendStackView.axis = .horizontal
        legendStackView.alignment = .center
        legendStackView.spacing = 16
        legendStackView.distribution = .fillProportionally
        
        addSubview(legendScrollView)
        legendScrollView.addSubview(legendStackView)
        addSubview(chartContainerView)
        
        // 2. 布局 (使用 SnapKit)
        legendScrollView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(30)
        }
        
        legendStackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalToSuperview()
        }
        
        chartContainerView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.bottom.equalTo(legendScrollView.snp.top).offset(-8)
        }
    }
    
    // MARK: - 核心入口：绑定并绘制数据
    public func bindData(lines: [PTChartLineModel]) {
        buildLegend(with: lines)
        
        // 必须让视图完成布局，获取准确的 bounds 进行绘制
        self.layoutIfNeeded()
        
        drawChart(with: lines)
    }
    
    // MARK: - 动态生成底部图例
    private func buildLegend(with lines: [PTChartLineModel]) {
        legendStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        for line in lines {
            let itemStack = UIStackView()
            itemStack.axis = .horizontal
            itemStack.alignment = .center
            itemStack.spacing = 6
            
            let dotView = UIView()
            dotView.backgroundColor = line.color
            dotView.layer.cornerRadius = 4
            dotView.snp.makeConstraints { make in
                make.width.height.equalTo(8)
            }
            
            let nameLabel = UILabel()
            nameLabel.text = line.name
            nameLabel.textColor = .lightGray
            nameLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
            
            itemStack.addArrangedSubview(dotView)
            itemStack.addArrangedSubview(nameLabel)
            
            legendStackView.addArrangedSubview(itemStack)
        }
    }
    
    // MARK: - 核心原生绘制算法
    private func drawChart(with lines: [PTChartLineModel]) {
        // 清理上一次的残余图层 (Cell 复用机制必须这一步)
        chartSublayers.forEach { $0.removeFromSuperlayer() }
        chartSublayers.removeAll()
        
        let width = chartContainerView.bounds.width
        let height = chartContainerView.bounds.height
        guard width > yAxisWidth, height > topPadding + bottomPadding else { return }
        
        // 1. 计算全局极值
        var globalMin: Double = Double.greatestFiniteMagnitude
        var globalMax: Double = -Double.greatestFiniteMagnitude
        var maxDataCount: Int = 0 // 找出最长的那条线，用于划分 X 轴
        
        for line in lines {
            if line.data.count > maxDataCount { maxDataCount = line.data.count }
            if let minVal = line.data.min(), minVal < globalMin { globalMin = minVal }
            if let maxVal = line.data.max(), maxVal > globalMax { globalMax = maxVal }
        }
        
        // 容错处理：没有数据或所有数据相等
        if globalMin == Double.greatestFiniteMagnitude { return }
        if globalMin == globalMax {
            globalMax += 1.0 // 防止除以0
            globalMin -= 1.0
        }
        
        // 可绘制区域的真实宽高
        let drawWidth = width - yAxisWidth - rightPadding
        let drawHeight = height - topPadding - bottomPadding
        
        // 2. 绘制 Y 轴辅助网格和数值标签
        drawYAxisAndGrid(drawWidth: drawWidth, drawHeight: drawHeight, globalMin: globalMin, globalMax: globalMax)
        
        // 3. 绘制折线
        guard maxDataCount > 1 else { return }
        let stepX = drawWidth / CGFloat(maxDataCount - 1)
        let valueRange = globalMax - globalMin
        
        for line in lines {
            let path = UIBezierPath()
            
            for (index, value) in line.data.enumerated() {
                let x = yAxisWidth + CGFloat(index) * stepX
                // 坐标映射：按比例计算 Y，注意 iOS 坐标系向下为正，所以用 drawHeight 减去
                let yRatio = CGFloat((value - globalMin) / valueRange)
                let y = topPadding + drawHeight - (yRatio * drawHeight)
                
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            
            // 生成原生线条 Layer
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = path.cgPath
            shapeLayer.strokeColor = line.color.cgColor
            shapeLayer.fillColor = UIColor.clear.cgColor
            shapeLayer.lineWidth = 2.0
            shapeLayer.lineJoin = .round
            shapeLayer.lineCap = .round
            
            chartContainerView.layer.addSublayer(shapeLayer)
            chartSublayers.append(shapeLayer)
            
            // 添加生长动画 (首次渲染时极具赛道科技感)
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = 0.0
            animation.toValue = 1.0
            animation.duration = 0.8
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            shapeLayer.add(animation, forKey: "grow")
        }
    }
    
    // MARK: - 绘制 Y 轴与背景网格
    private func drawYAxisAndGrid(drawWidth: CGFloat, drawHeight: CGFloat, globalMin: Double, globalMax: Double) {
        let range = globalMax - globalMin
        
        // 循环划分为网格
        for i in 0...gridCount {
            let ratio = CGFloat(i) / CGFloat(gridCount)
            let value = globalMin + range * Double(ratio)
            
            // 从下往上画，i=0 是最底部，i=gridCount 是最顶部
            let y = topPadding + drawHeight - (ratio * drawHeight)
            
            // 1. 画横向辅助线
            let gridPath = UIBezierPath()
            gridPath.move(to: CGPoint(x: yAxisWidth, y: y))
            gridPath.addLine(to: CGPoint(x: yAxisWidth + drawWidth, y: y))
            
            let gridLayer = CAShapeLayer()
            gridLayer.path = gridPath.cgPath
            gridLayer.strokeColor = UIColor.white.withAlphaComponent(0.15).cgColor
            gridLayer.lineWidth = 1.0
            // 设置虚线效果 (实线2像素，空白4像素)
            gridLayer.lineDashPattern = [2, 4]
            
            chartContainerView.layer.addSublayer(gridLayer)
            chartSublayers.append(gridLayer)
            
            // 2. 画 Y 轴数字标签 (使用原生的 CATextLayer 保证滚动极度流畅)
            let textLayer = CATextLayer()
            // 简单格式化数值 (如果数值较大可以取整，较小可以保留1位小数)
            textLayer.string = String(format: "%.1f", value)
            textLayer.font = UIFont.systemFont(ofSize: 10, weight: .regular)
            textLayer.fontSize = 10
            textLayer.foregroundColor = UIColor.lightGray.cgColor
            textLayer.alignmentMode = .right
            // 关键抗锯齿设置
            textLayer.contentsScale = UIScreen.main.scale
            
            // 计算文字位置 (在 Y 轴中心偏上一点，以便对齐网格线)
            let textHeight: CGFloat = 14
            textLayer.frame = CGRect(x: 0, y: y - textHeight / 2, width: yAxisWidth - 6, height: textHeight)
            
            chartContainerView.layer.addSublayer(textLayer)
            chartSublayers.append(textLayer)
        }
    }
}
