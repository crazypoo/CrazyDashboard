//
//  PTTripDataCell.swift
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

class PTTripDataCell: PTBaseNormalCell {
    static let ID = "PTTripDataCell"

    var cellModel:PTTripReport! {
        didSet {
            let startTime = cellModel.startTime.convertTo(region: .local).toFormat("yyyy-MM-dd HH:mm:ss")
            let endTime = cellModel.endTime.convertTo(region: .local).toFormat("yyyy-MM-dd HH:mm:ss")
            let distanceString = PTDashboardConfig.languageFunc(text: "casa_card_little_trip") + ":" + String(format: "%@%@", PTDashboardConfig.shared.appShowMileageValueString(cellModel.distanceKm),PTDashboardConfig.shared.appShowUniLabel)
            let speedRpm = "Max speed:" + String(format: "%@%@", PTDashboardConfig.shared.appShowMileageValueString(cellModel.maxSpeedKmh),PTDashboardConfig.shared.appShowUniLabel) + ",Max Rpm:" + "\(cellModel.maxRpm)"
            let avgOil = PTDashboardConfig.languageFunc(text: "casa_card_avg_oil") + ":\(cellModel.avgConsumption)"
            let nameAtt: ASAttributedString = """
                        \(wrap: .embedding("""
                        \((startTime + " -> " + endTime),.foreground(.white),.font(.appfont(size: 14)))
                        \(distanceString,.foreground(.white),.font(.appfont(size: 14)))
                        \(speedRpm,.foreground(.white),.font(.appfont(size: 14)))
                        \(avgOil,.foreground(.white),.font(.appfont(size: 14)))
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
