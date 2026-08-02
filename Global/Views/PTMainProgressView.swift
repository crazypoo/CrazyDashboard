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
import SafeSFSymbols

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
        view.barColor = PTDashboardConfig.shared.appMainColor
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

class PTMotoFuelInfoView:UIView {
    
    var viewModel:PTDashboardData1? {
        didSet {
            var fuelValue = "0"
            var fuelDouble:Double = 0
            if let viewModel = viewModel {
                fuelValue = "\(viewModel.fuelLevelPct)"
                fuelDouble = Double(viewModel.fuelLevelPct)
            }
            fuelValueLabel.text = "\(fuelValue)%"
            
            dataProgress.animationProgress(duration: 0.35, value: fuelDouble / 100)

            var avgFuelValue = "0"
            if let avgFuel = self.viewModel {
                avgFuelValue = "\(avgFuel.avgConsumptionLt)"
            }
            self.avgFuelLabel.text = PTDashboardConfig.languageFunc(text: "casa_card_avg_oil") + " \(avgFuelValue)L/\(PTDashboardConfig.shared.appShowMileageValueString(100))\(PTDashboardConfig.shared.appShowUniLabel)"
        }
    }
    
    var fuelTripModel:PTDashboardData3? {
        didSet {
            var value:String = ""
            if let fuelTripModel = self.fuelTripModel {
                value = PTDashboardConfig.shared.appShowMileageValueString(fuelTripModel.autonomyKm)
            } else {
                value = "0"
            }
            self.fuelTripLabel.text = PTDashboardConfig.languageFunc(text: "casa_card_oil_trip") + "\(value)\(PTDashboardConfig.shared.appShowUniLabel)"
        }
    }
    
    lazy var fuelImage:UIImageView = {
        let view = UIImageView()
        view.image = UIImage(.fuelpump).withTintColor(.white, renderingMode: .alwaysOriginal).transformImage(size: .init(width: 34, height: 34))
        view.contentMode = .scaleAspectFit
        return view
    }()
    
    lazy var dataProgress:PTProgressBar = {
        let view = PTProgressBar(showType: .Horizontal)
        view.barColor = PTDashboardConfig.shared.appMainColor
        return view
    }()
    
    lazy var fuelValueLabel:UILabel = {
        let view = UILabel()
        view.font = .appfont(size: 16,bold: true)
        view.textAlignment = .right
        view.textColor = .white
        view.text = "0%"
        return view
    }()
    
    lazy var fuelTripLabel:UILabel = {
        let view = UILabel()
        view.font = .appfont(size: 14)
        view.textAlignment = .left
        view.textColor = .white
        view.text = PTDashboardConfig.languageFunc(text: "casa_card_oil_trip") + "0\(PTDashboardConfig.shared.appShowUniLabel)"
        return view
    }()
    
    lazy var avgFuelLabel:UILabel = {
        let view = UILabel()
        view.font = .appfont(size: 14)
        view.textAlignment = .right
        view.textColor = .white
        view.text = PTDashboardConfig.languageFunc(text: "casa_card_avg_oil") + " 0L/\(PTDashboardConfig.shared.appShowMileageValueString(100))\(PTDashboardConfig.shared.appShowUniLabel)"
        return view
    }()
    
    var viewLoaded:Bool = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addSubviews([fuelImage,fuelValueLabel,dataProgress,fuelTripLabel,avgFuelLabel])
        fuelImage.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.top.equalToSuperview().inset(CGFloat.GlobalItemSpacing)
            make.size.equalTo(34)
        }
        
        fuelValueLabel.snp.makeConstraints { make in
            make.bottom.equalTo(self.fuelImage)
            make.right.equalToSuperview()
            make.width.equalTo(UIView.sizeFor(string: "100%", font: self.fuelValueLabel.font).width + 5)
        }
        
        dataProgress.snp.makeConstraints { make in
            make.left.equalTo(self.fuelImage.snp.right).offset(CGFloat.GlobalItemSpacing)
            make.right.equalTo(self.fuelValueLabel.snp.left)
            make.bottom.equalTo(self.fuelImage)
            make.height.equalTo(4.adapter)
        }
        
        fuelTripLabel.snp.makeConstraints { make in
            make.left.equalTo(self.fuelImage)
            make.right.equalTo(self.snp.centerX).offset(-(CGFloat.GlobalItemSpacing / 2))
            make.top.equalTo(self.dataProgress.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
        
        avgFuelLabel.snp.makeConstraints { make in
            make.right.equalTo(self.fuelValueLabel)
            make.left.equalTo(self.snp.centerX).offset((CGFloat.GlobalItemSpacing / 2))
            make.top.equalTo(self.fuelTripLabel)
        }
        
        pt_viewObserverLanguage(didChanged: {
            if self.viewLoaded {
                var value:String = "0"
                if let fuelTripModel = self.fuelTripModel {
                    value = PTDashboardConfig.shared.appShowMileageValueString(fuelTripModel.autonomyKm)
                }
                self.fuelTripLabel.text = PTDashboardConfig.languageFunc(text: "casa_card_oil_trip") + "\(value)\(PTDashboardConfig.shared.appShowUniLabel)"
                
                var avgFuelValue = "0"
                if let avgFuel = self.viewModel {
                    avgFuelValue = "\(avgFuel.avgConsumptionLt)"
                }
                self.avgFuelLabel.text = PTDashboardConfig.languageFunc(text: "casa_card_avg_oil") + " \(avgFuelValue)L/\(PTDashboardConfig.shared.appShowMileageValueString(100))\(PTDashboardConfig.shared.appShowUniLabel)"
            }
        })
        viewLoaded = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
