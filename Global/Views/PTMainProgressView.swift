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

    // EN: Keep unavailable dashboard readings out of the numeric presentation.
    // ES: Mantén las lecturas no disponibles del tablero fuera de la presentación numérica.
    // 中文：让不可用的仪表读数不再以数字形式展示。
    var isValueAvailable = true
    
}

class PTMainProgressView: UIView {

    var modelSet:PTMainProgressViewModel! {
        didSet {
            let currentValue = modelSet.isValueAvailable
                ? String(format: "%.2f", modelSet.currentValue)
                : PTDashboardConfig.languageFunc(text: "ride_not_available")
            let nameAtt: ASAttributedString = """
                        \(wrap: .embedding("""
                        \(modelSet.name,.foreground(.lightGray),.font(.appfont(size: 13)))
                        \(currentValue,.foreground(.white),.font(.appfont(size: 16,bold:true)))\(modelSet.isValueAvailable ? modelSet.uni : "",.foreground(.white),.font(.appfont(size: 16,bold:true)))
                        """),.paragraph(.alignment(.left)))
                        """
            infoLabel.attributed.text = nameAtt
            let progress = modelSet.isValueAvailable && modelSet.maxValue > 0
                ? modelSet.currentValue / modelSet.maxValue
                : 0
            dataProgress.animationProgress(duration: 0.35, value: progress)
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
            let unavailable = PTDashboardConfig.languageFunc(text: "ride_not_available")
            var fuelValue = unavailable
            var fuelDouble:Double = 0
            if let viewModel = viewModel {
                if viewModel.fuelLevelAvailability.isAvailable {
                    fuelValue = "\(viewModel.fuelLevelPct)"
                    fuelDouble = Double(viewModel.fuelLevelPct)
                }
            }
            fuelValueLabel.text = fuelValue == unavailable
                ? fuelValue
                : "\(fuelValue)%"
            
            dataProgress.animationProgress(duration: 0.35, value: fuelDouble / 100)

            self.fuelModelStringSet(avgFuel: self.viewModel)
        }
    }
    
    var fuelTripModel:PTDashboardData3? {
        didSet {
            self.fuelTripStringSet(fuelTripModel: self.fuelTripModel)
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
        view.text = PTDashboardConfig.languageFunc(text: "casa_card_avg_oil") + " 0.0L/\(PTDashboardConfig.shared.appShowMileageValueString(100))\(PTDashboardConfig.shared.appShowUniLabel)"
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
                self.fuelTripStringSet(fuelTripModel: self.fuelTripModel)
                self.fuelModelStringSet(avgFuel: self.viewModel)
            }
        })
        viewLoaded = true
    }
    
    func fuelTripStringSet(fuelTripModel:PTDashboardData3?) {
        var value: String
        if let fuelTripModel = self.fuelTripModel, fuelTripModel.autonomyAvailability.isAvailable {
            value = PTDashboardConfig.shared.appShowMileageValueString(fuelTripModel.autonomyKm)
        } else {
            value = PTDashboardConfig.languageFunc(text: "ride_not_available")
        }
        let suffix = value == PTDashboardConfig.languageFunc(text: "ride_not_available")
            ? ""
            : PTDashboardConfig.shared.appShowUniLabel
        self.fuelTripLabel.text = PTDashboardConfig.languageFunc(text: "casa_card_oil_trip") + "\(value)\(suffix)"
    }
    
    func fuelModelStringSet(avgFuel:PTDashboardData1?) {
        var avgFuelValue: String
        if let avgFuel = self.viewModel, avgFuel.averageConsumptionAvailability.isAvailable {
            avgFuelValue = String(format: "%.1f", avgFuel.avgConsumptionLt)
        } else {
            avgFuelValue = PTDashboardConfig.languageFunc(text: "ride_not_available")
        }
        let suffix = avgFuelValue == PTDashboardConfig.languageFunc(text: "ride_not_available")
            ? ""
            : "L/\(PTDashboardConfig.shared.appShowMileageValueString(100))\(PTDashboardConfig.shared.appShowUniLabel)"
        self.avgFuelLabel.text = PTDashboardConfig.languageFunc(text: "casa_card_avg_oil") + " \(avgFuelValue)\(suffix)"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
