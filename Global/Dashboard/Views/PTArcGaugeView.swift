//
//  PTArcGaugeView.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 14/8/2026.
//

import UIKit

public class PTArcGaugeView: UIView {
    
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    
    // 进度值，范围 0.0 ~ 1.0
    public var progress: CGFloat = 0.5 {
        didSet {
            let safeProgress = max(0.0, min(1.0, progress))
            progressLayer.strokeEnd = safeProgress
        }
    }
    
    private let startAngle: CGFloat
    private let endAngle: CGFloat
    private let gaugeColor: UIColor
    private let isLeftAligned: Bool
    
    public init(isLeftAligned: Bool, color: UIColor = .systemRed) {
        self.isLeftAligned = isLeftAligned
        self.gaugeColor = color
        
        if isLeftAligned {
            self.startAngle = .pi * 0.75
            self.endAngle = .pi * 1.25
        } else {
            self.startAngle = -.pi * 0.25
            self.endAngle = .pi * 0.25
        }
        
        super.init(frame: .zero)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupLayers() {
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = UIColor.darkGray.withAlphaComponent(0.5).cgColor
        trackLayer.lineWidth = 12.0
        trackLayer.lineCap = .butt
        layer.addSublayer(trackLayer)
        
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = gaugeColor.cgColor
        progressLayer.lineWidth = 12.0
        progressLayer.lineCap = .butt
        progressLayer.strokeEnd = 0.0
        layer.addSublayer(progressLayer)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        let radius = self.bounds.height * 0.8
        let centerX = isLeftAligned ? self.bounds.width + (radius * 0.3) : -(radius * 0.3)
        let centerY = self.bounds.height / 2.0
        let centerPoint = CGPoint(x: centerX, y: centerY)
        
        let path = UIBezierPath(arcCenter: centerPoint,
                                radius: radius,
                                startAngle: startAngle,
                                endAngle: endAngle,
                                clockwise: true)
        
        trackLayer.path = path.cgPath
        progressLayer.path = path.cgPath
    }
}
