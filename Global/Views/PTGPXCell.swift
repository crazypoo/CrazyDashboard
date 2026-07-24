//
//  PTGPXCell.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 24/7/2026.
//

import UIKit
import PooTools
import SwifterSwift
import SnapKit
import SwiftDate
import AttributedString

class PTGPXCell: PTBaseNormalCell {
    static let ID = "PTGPXCell"

    var cellModel:PTRideHistoryModel! {
        didSet {
            
            let nameAtt: ASAttributedString = """
                        \(wrap: .embedding("""
                        \(cellModel.formattedDate,.foreground(.white),.font(.appfont(size: 14)))
                        \(cellModel.formattedFileSize,.foreground(.white),.font(.appfont(size: 14)))
                        """),.paragraph(.alignment(.left)))
                        """
            timeLabel.attributed.text = nameAtt
        }
    }
    
    lazy var timeLabel:UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        return view
    }()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.addSubviews([timeLabel])
        timeLabel.snp.makeConstraints { make in
            make.left.top.equalToSuperview().inset(CGFloat.GlobalItemSpacing)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
