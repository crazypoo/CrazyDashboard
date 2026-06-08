//
//  PTCompassRollerView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 7/6/2026.
//

import UIKit
import SnapKit

@objcMembers
public class PTCompassRollerView: UIView {
    
    private let scaleContainer = UIView()
    private let indicator = UIView()
    private let degreeLabel = UILabel() // 新增：底部固定显示的度数
    
    // 放大物理总宽度，让刻度更稀疏，类似真实游戏/战术仪表盘
    // 1440 意味着 1度 = 4pt
    private let fullCircleWidth: CGFloat = 1440.0
    
    private var containerLeftConstraint: Constraint?
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        // 将圆角稍微改小一点，适应长条形的 HUD 风格
        self.layer.cornerRadius = 12
    }
    
    private func setupUI() {
        self.clipsToBounds = true
        self.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        
        // 1. 标尺容器 (承载刻度和滚动的方向文字)
        insertSubview(scaleContainer, at: 0)
        scaleContainer.snp.makeConstraints { make in
            make.top.equalToSuperview()
            // 底部留出 25pt 的空间，给中央固定的“度数Label”让路
            make.bottom.equalToSuperview().offset(-25)
            make.width.equalTo(fullCircleWidth * 3)
            
            // 初始对准北 (偏移 1个 fullCircleWidth)
            self.containerLeftConstraint = make.leading.equalTo(self.snp.centerX).offset(-fullCircleWidth).constraint
        }
        
        // 2. 核心：绘制高性能的刻度尺和文字
        drawScaleAndLabels()
        
        // 3. 中间的红色指示线 (固定在中央顶部)
        indicator.backgroundColor = .systemRed
        addSubview(indicator)
        indicator.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview()
            make.width.equalTo(2)
            make.height.equalTo(15) // 指针长度，正好盖住长刻度
        }
        
        // 4. 底部固定的精确度数标签 (例如: "351° 北")
        degreeLabel.textColor = .white
        degreeLabel.textAlignment = .center
        degreeLabel.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        degreeLabel.text = "0° 北"
        addSubview(degreeLabel)
        degreeLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().inset(4) // 紧贴底部
        }
    }
    
    private func drawScaleAndLabels() {
        let directions = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        let pixelsPerDegree = fullCircleWidth / 360.0
        
        let tickLayer = CAShapeLayer()
        let tickPath = UIBezierPath()
        
        // 画 3 遍，保证无限丝滑滚动
        for repetition in 0..<3 {
            let offsetX = CGFloat(repetition) * fullCircleWidth
            
            // 每 5 度画一个短刻度，每 45 度画一个长刻度和文字
            for degree in stride(from: 0, to: 360, by: 5) {
                let isMajor = (degree % 45 == 0)
                let xPos = offsetX + CGFloat(degree) * pixelsPerDegree
                
                // 画刻度线 (顶部对齐往下方画)
                let tickHeight: CGFloat = isMajor ? 12.0 : 6.0
                tickPath.move(to: CGPoint(x: xPos, y: 0))
                tickPath.addLine(to: CGPoint(x: xPos, y: tickHeight))
                
                // 如果是 45 度的倍数，添加方向文字
                if isMajor {
                    let index = degree / 45
                    let label = UILabel()
                    label.text = directions[index]
                    // 文字用稍微暗一点的灰色，凸显底部的纯白精确度数
                    label.textColor = UIColor.white.withAlphaComponent(0.7)
                    label.textAlignment = .center
                    label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
                    scaleContainer.addSubview(label)
                    
                    label.snp.makeConstraints { make in
                        make.top.equalToSuperview().offset(16) // 挂在刻度线的下方
                        make.centerX.equalTo(scaleContainer.snp.leading).offset(xPos)
                    }
                }
            }
        }
        
        tickLayer.path = tickPath.cgPath
        tickLayer.strokeColor = UIColor.white.withAlphaComponent(0.8).cgColor
        tickLayer.lineWidth = 1.5
        scaleContainer.layer.addSublayer(tickLayer)
    }
    
    // 传入 0.0 ~ 359.9 度的车头朝向
    public func updateHeading(_ degree: Double) {
        let safeDegree = degree.truncatingRemainder(dividingBy: 360.0)
        let progress = CGFloat(safeDegree / 360.0)
        
        // 1. 移动标尺容器
        let targetOffset = -(fullCircleWidth * (1.0 + progress))
        self.containerLeftConstraint?.update(offset: targetOffset)
        
        // 2. 更新底部的精确度数文字
        let directionText = getDirectionString(safeDegree)
        self.degreeLabel.text = "\(Int(safeDegree))° \(directionText)"
        
        // 3. 执行动画
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveLinear, .beginFromCurrentState], animations: {
            self.layoutIfNeeded()
        }, completion: nil)
    }
    
    // 辅助方法：根据度数智能计算方向中文
    private func getDirectionString(_ degree: Double) -> String {
        let directions = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        // 加上 22.5 度来实现四舍五入的完美区间划分
        let index = Int((degree + 22.5) / 45.0) & 7
        return directions[index]
    }
}
