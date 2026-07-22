//
//  PTRoutePlantCell.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 22/7/2026.
//

import UIKit
import PooTools
import SwifterSwift
import AttributedString
import SnapKit

class PTRoutePlantCell: PTBaseNormalCell {
    static let ID = "PTRoutePlantCell"
    
    var info:RouteCollectionViewInfo! {
        didSet {
            if info.isSelected {
                self.viewCorner(radius: 4,borderWidth: 2.5,borderColor: PTDashboardConfig.shared.appMainColor)
            } else {
                self.viewCorner(radius: 4,borderWidth: 2.5,borderColor: .clear)
            }
            
            let infoText: ASAttributedString = """
                        \(wrap: .embedding("""
                        \(info.title,.foreground(PTDashboardConfig.shared.appMainColor),.font(.appfont(size: 14)))
                        \(info.subTitle,.foreground(PTDashboardConfig.shared.appMainColor),.font(.appfont(size: 10)))
                        """),.paragraph(.alignment(.left),.lineSpacing(1)))
                        """
            infoLabel.attributed.text = infoText
        }
    }
    
    lazy var infoLabel:UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        return view
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.backgroundColor = .white
        contentView.addSubviews([infoLabel])
        infoLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(2)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
