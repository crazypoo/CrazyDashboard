//
//  PTGlobalActionHeader.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 20/7/2026.
//

import UIKit
import PooTools
import SwifterSwift
import SnapKit

class PTGlobalActionHeader: PTBaseCollectionReusableView {
    static let ID = "PTGlobalActionHeader"

    lazy var titleName:UILabel = {
        let view = UILabel()
        view.font = .appfont(size: 14)
        view.textAlignment = .left
        view.textColor = PTDashboardConfig.shared.appMainColor
        return view
    }()
    
    lazy var newActionButton:PTActionLayoutButton = {
        let view = PTActionLayoutButton()
        view.layoutStyle = .image
        view.imageSize = CGSize(width: 16, height: 16)
        view.midSpacing = 0
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }()
    
    lazy var actionButton:PTLayoutButton = {
        let view = PTLayoutButton()
        view.layoutStyle = .leftTitleRightImage
        view.imageSize = CGSize(width: 16, height: 16)
        view.midSpacing = 0
        view.normalTitleFont = .appfont(size: 12)
//        view.normalImage = UIImage(named: "arrow_right_gray")
        view.isHidden = true
        view.isUserInteractionEnabled = false
        view.normalTitleColor = .red
        return view
    }()
    
    lazy var backgroundImage:UIImageView = {
        let view = UIImageView()
        view.isHidden = true
        return view
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addSubviews([backgroundImage,titleName,actionButton,newActionButton])
        backgroundImage.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        titleName.snp.makeConstraints { make in
            make.left.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
        }
        
        actionButton.snp.makeConstraints { make in
            make.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.centerY.equalTo(self.titleName)
        }
        
        newActionButton.snp.makeConstraints { make in
            make.centerY.equalTo(self.titleName)
            make.width.equalTo(self.newActionButton.getKitCurrentDimension())
            make.height.equalTo(self.newActionButton.imageSize.height)
            make.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
