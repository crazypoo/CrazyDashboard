//
//  PTCompassRollerView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 7/6/2026.
//

import UIKit

@objcMembers
public class PTCompassRollerView: UIView {
    
    private let scaleContainer = UIView()
    // 代表 360 度的总物理宽度
    private let fullCircleWidth: CGFloat = 800.0
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        self.clipsToBounds = true // 隐藏超出边框的部分
        self.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        self.layer.cornerRadius = bounds.height / 2
        
        // 中间的红色指示线
        let indicator = UIView(frame: CGRect(x: bounds.width / 2 - 1, y: 0, width: 2, height: bounds.height))
        indicator.backgroundColor = .red
        addSubview(indicator)
        
        // 标尺容器
        // 宽度设为全周长的 3 倍，这样可以实现丝滑的左右无限滑动错觉
        scaleContainer.frame = CGRect(x: 0, y: 0, width: fullCircleWidth * 3, height: bounds.height)
        insertSubview(scaleContainer, belowSubview: indicator)
        
        drawScaleLabels()
    }
    
    private func drawScaleLabels() {
        let directions = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        let count = directions.count
        
        // 在 3 倍宽度的容器里，重复画 3 遍方向，保证怎么转都不穿帮
        for repetition in 0..<3 {
            let offsetX = CGFloat(repetition) * fullCircleWidth
            
            for i in 0..<count {
                let sectionWidth = fullCircleWidth / CGFloat(count)
                let label = UILabel(frame: CGRect(x: offsetX + CGFloat(i) * sectionWidth - sectionWidth/2,
                                                  y: 0,
                                                  width: sectionWidth,
                                                  height: bounds.height))
                label.text = directions[i]
                label.textColor = .white
                label.textAlignment = .center
                label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
                scaleContainer.addSubview(label)
            }
        }
    }
    
    // 传入 0.0 ~ 359.9 度的车头朝向
    public func updateHeading(_ degree: Double) {
        let safeDegree = degree.truncatingRemainder(dividingBy: 360.0)
        
        // 计算偏移比例
        let progress = CGFloat(safeDegree / 360.0)
        
        // 核心算法：让滚轮的中心点始终对准当前的度数。
        // 我们把核心视图始终保持在第二段（中间那一段），防止滑到尽头
        let centerOffset = bounds.width / 2
        let targetX = -(fullCircleWidth + progress * fullCircleWidth) + centerOffset
        
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveLinear, .beginFromCurrentState], animations: {
            self.scaleContainer.frame.origin.x = targetX
        }, completion: nil)
    }
}
