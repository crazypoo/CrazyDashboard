//
//  PTMainProgressView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 20/7/2026.
//

import UIKit
import PooTools
import SwifterSwift
import SnapKit
import AttributedString

class PTMainProgressViewModel:NSObject {
    var name:String = ""
    var currentValue:Double = 0.0
    var maxValue:Double = 0.0
    var uni:String = ""
    
}

class PTMainProgressView: UIView {

    var modelSet:PTMainProgressViewModel! {
        didSet {
            let nameAtt: ASAttributedString = """
                        \(wrap: .embedding("""
                        \(modelSet.name,.foreground(.lightGray),.font(.appfont(size: 13)))
                        \(String(format: "%.2f", modelSet.currentValue),.foreground(.white),.font(.appfont(size: 16,bold:true)))\(modelSet.uni,.foreground(.white),.font(.appfont(size: 16,bold:true)))
                        """),.paragraph(.alignment(.left)))
                        """
            infoLabel.attributed.text = nameAtt
            dataProgress.animationProgress(duration: 0.35, value: modelSet.currentValue / modelSet.maxValue)
        }
    }
    
    lazy var dataProgress:PTProgressBar = {
        let view = PTProgressBar(showType: .Horizontal)
        view.barColor = .MainColor
        return view
    }()
    
    lazy var infoLabel:UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        return view
    }()
        

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addSubviews([dataProgress,infoLabel])
        dataProgress.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalToSuperview()
            make.height.equalTo(4.adapter)
        }
        
        infoLabel.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.bottom.equalTo(self.dataProgress.snp.top)
        }        
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
