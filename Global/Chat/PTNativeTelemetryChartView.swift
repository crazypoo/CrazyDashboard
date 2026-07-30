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
    private let chartContainerView = UIView()
    private let legendScrollView = UIScrollView()
    private let legendStackView = UIStackView()
    
    // MARK: - 渲染层缓存
    private var chartSublayers: [CALayer] = []
    
    // 🚨 修复 1：增加数据缓存，等待视图布局完成后再绘制
    private var currentLines: [PTChartLineModel] = []
    
    // MARK: - 图表布局参数
    private let yAxisWidth: CGFloat = 40.0
    private let rightPadding: CGFloat = 10.0
    private let topPadding: CGFloat = 20.0
    private let bottomPadding: CGFloat = 10.0
    private let gridCount: Int = 5
    
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
        
        legendScrollView.showsHorizontalScrollIndicator = false
        legendStackView.axis = .horizontal
        legendStackView.alignment = .center
        legendStackView.spacing = 16
        legendStackView.distribution = .fillProportionally
        
        addSubview(legendScrollView)
        legendScrollView.addSubview(legendStackView)
        addSubview(chartContainerView)
        
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
        self.currentLines = lines
        buildLegend(with: lines)
        
        // 标记需要重新布局，系统会在下一个渲染周期自动调用 layoutSubviews
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
    
    // 🚨 修复 1：利用 layoutSubviews 确保能够拿到真实准确的 Bounds
    public override func layoutSubviews() {
        super.layoutSubviews()
        // 每次视图 Frame 发生变化（或初次渲染）时，触发重绘
        drawChart(with: currentLines)
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
        chartSublayers.forEach { $0.removeFromSuperlayer() }
        chartSublayers.removeAll()
        
        let width = chartContainerView.bounds.width
        let height = chartContainerView.bounds.height
        // 防止 bounds 尚未成型时执行无效绘制
        guard width > yAxisWidth, height > topPadding + bottomPadding, !lines.isEmpty else { return }
        
        var globalMin: Double = Double.greatestFiniteMagnitude
        var globalMax: Double = -Double.greatestFiniteMagnitude
        
        // 🚨 修复 2：移除全局 maxDataCount，只计算极值
        for line in lines {
            if let minVal = line.data.min(), minVal < globalMin { globalMin = minVal }
            if let maxVal = line.data.max(), maxVal > globalMax { globalMax = maxVal }
        }
        
        if globalMin == Double.greatestFiniteMagnitude { return }
        if globalMin == globalMax {
            globalMax += 1.0
            globalMin -= 1.0
        }
        
        let drawWidth = width - yAxisWidth - rightPadding
        let drawHeight = height - topPadding - bottomPadding
        let valueRange = globalMax - globalMin
        
        drawYAxisAndGrid(drawWidth: drawWidth, drawHeight: drawHeight, globalMin: globalMin, globalMax: globalMax)
        
        // 3. 绘制折线
        for line in lines {
            let count = line.data.count
            // 确保至少有两个点才能连成线
            guard count > 1 else { continue }
            
            // 🚨 修复 2：每一条线独立计算自己的 stepX，确保无论多少个点都能铺满 X 轴
            let stepX = drawWidth / CGFloat(count - 1)
            
            let path = UIBezierPath()
            
            for (index, value) in line.data.enumerated() {
                let x = yAxisWidth + CGFloat(index) * stepX
                let yRatio = CGFloat((value - globalMin) / valueRange)
                let y = topPadding + drawHeight - (yRatio * drawHeight)
                
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = path.cgPath
            shapeLayer.strokeColor = line.color.cgColor
            shapeLayer.fillColor = UIColor.clear.cgColor
            shapeLayer.lineWidth = 2.0
            shapeLayer.lineJoin = .round
            shapeLayer.lineCap = .round
            
            chartContainerView.layer.addSublayer(shapeLayer)
            chartSublayers.append(shapeLayer)
            
            // 动画保留，赛道科技感非常棒
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
        
        for i in 0...gridCount {
            let ratio = CGFloat(i) / CGFloat(gridCount)
            let value = globalMin + range * Double(ratio)
            let y = topPadding + drawHeight - (ratio * drawHeight)
            
            let gridPath = UIBezierPath()
            gridPath.move(to: CGPoint(x: yAxisWidth, y: y))
            gridPath.addLine(to: CGPoint(x: yAxisWidth + drawWidth, y: y))
            
            let gridLayer = CAShapeLayer()
            gridLayer.path = gridPath.cgPath
            gridLayer.strokeColor = UIColor.white.withAlphaComponent(0.15).cgColor
            gridLayer.lineWidth = 1.0
            gridLayer.lineDashPattern = [2, 4]
            
            chartContainerView.layer.addSublayer(gridLayer)
            chartSublayers.append(gridLayer)
            
            let textLayer = CATextLayer()
            textLayer.string = String(format: "%.1f", value)
            textLayer.font = UIFont.systemFont(ofSize: 10, weight: .regular)
            textLayer.fontSize = 10
            textLayer.foregroundColor = UIColor.lightGray.cgColor
            textLayer.alignmentMode = .right
            textLayer.contentsScale = UIScreen.main.scale
            
            let textHeight: CGFloat = 14
            textLayer.frame = CGRect(x: 0, y: y - textHeight / 2, width: yAxisWidth - 6, height: textHeight)
            
            chartContainerView.layer.addSublayer(textLayer)
            chartSublayers.append(textLayer)
        }
    }
}
