//
//  PTStatusItemView.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 2/8/2026.
//

import UIKit
import SnapKit
import SafeSFSymbols
import PooTools
import AttributedString

/// 仪表盘状态数据基础条目组件
class PTStatusItemView: UIView {
    
    // MARK: - UI 组件
    private let iconContainer = UIView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
        
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setupUI() {
        // 1. 图标容器 (苹果风：带背景色的圆角小方块)
        iconContainer.layer.cornerRadius = 8
        addSubview(iconContainer)
        
        iconImageView.tintColor = .white
        iconImageView.contentMode = .scaleAspectFit
        iconContainer.addSubview(iconImageView)
        
        // 2. 标题
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        addSubview(titleLabel)
                        
        // MARK: - SnapKit 布局
        iconContainer.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
            make.width.height.equalTo(32) // 图标底座大小
        }
        
        iconImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(20) // 内部实际图标大小
        }
        
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(iconContainer.snp.right).offset(CGFloat.GlobalItemSpacing)
            make.right.equalToSuperview()
            make.centerY.equalToSuperview()
        }
    }
    
    // MARK: - 注入数据的方法
    /// 配置条目的内容和样式
    /// - Parameters:
    ///   - systemIcon: SF Symbols 图标名称
    ///   - iconColor: 图标底座的颜色
    ///   - title: 标题文本
    ///   - value: 数值文本
    ///   - hideSeparator: 是否隐藏底部分割线
    public func configure(systemIcon: UIImage, iconColor: UIColor, title: String, value: String) {
        iconImageView.image = systemIcon
        iconContainer.backgroundColor = iconColor
        
        let infoText: ASAttributedString = """
                    \(wrap: .embedding("""
                    \(title,.foreground(.white),.font(.appfont(size: 16,bold: true)))
                    \(value,.foreground(.systemGray),.font(.appfont(size: 16)))
                    """),.paragraph(.alignment(.left),.lineSpacing(1)))
                    """
        titleLabel.attributed.text = infoText
    }
}
