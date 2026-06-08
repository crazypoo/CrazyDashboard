//
//  PTCrashWarningView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 8/6/2026.
//

import UIKit
import SnapKit

@objcMembers
public class PTCrashWarningView: UIView {
    
    private let warningIcon = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // 1. 基础背景色：高纯度的半透明血红色，既能透出一点背后的地图，又极具警告意味
        self.backgroundColor = UIColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 0.85)
        
        // 2. 警告图标
        // 这里使用了系统原生的三角形感叹号图标，非常标准化
        warningIcon.image = UIImage(systemName: "exclamationmark.triangle.fill")
        warningIcon.tintColor = .white
        warningIcon.contentMode = .scaleAspectFit
        addSubview(warningIcon)
        
        // 3. 巨型主标题
        titleLabel.text = "🚨 侦测到摔车 / 倒地 🚨"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 32, weight: .heavy)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)
        
        // 4. 副标题说明
        subtitleLabel.text = "车辆姿态极度异常，请立即检查车辆与人员状况\n（扶正车身将自动解除警报）"
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        subtitleLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        addSubview(subtitleLabel)
        
        // MARK: - SnapKit 布局 (全居中对齐)
        
        warningIcon.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(-40)
            make.width.height.equalTo(120)
        }
        
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(warningIcon.snp.bottom).offset(20)
            make.centerX.equalToSuperview()
            make.left.right.equalToSuperview().inset(20)
        }
        
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(15)
            make.centerX.equalToSuperview()
            make.left.right.equalToSuperview().inset(20)
        }
        
        // 启动危险呼吸动画
        startEmergencyFlashing()
    }
    
    // MARK: - 极客视效：紧急警报灯呼吸动画
    private func startEmergencyFlashing() {
        // 利用 autoreverse 和 repeat 实现无限来回的脉冲动画
        UIView.animate(withDuration: 0.6,
                       delay: 0,
                       options: [.autoreverse, .repeat, .curveEaseInOut, .allowUserInteraction],
                       animations: {
            
            // 颜色在 0.85 的暗红和 0.95 的亮红之间来回切换，模拟警灯
            self.backgroundColor = UIColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 0.95)
            
            // 图标心跳式放大
            self.warningIcon.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            
        }, completion: nil)
    }
}
