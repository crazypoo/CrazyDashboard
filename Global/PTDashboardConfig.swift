//
//  PTDashboardConfig.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 19/7/2026.
//

import UIKit
import PooTools
import AttributedString

extension UIColor {
    static let grayCA = DynamicColor(hexString: "cacaca")!
    static let gray7F = DynamicColor(hexString: "7f7f7f")!
}

extension CGFloat {
    static let GlobalItemSpacing:CGFloat = 8.adapter
}

extension PTProgressHUD {
    class func show(text:String,delay: TimeInterval = 1.5,showedFinish:PTActionTask? = nil) {
        let hud = PTProgressHUD.showOnWindow()
        hud?.titleFont = .appfont(size: 14)
        hud?.title = text
        hud?.titleColor = .white
        hud?.mode = .text
        hud?.dimBackground = false
        hud?.blurEffectStyle = .dark
        hud?.bezelColor = .black.withAlphaComponent(0.6)
        hud?.hide(animated: true, afterDelay: delay)
        hud?.completionBlock = {
            showedFinish?()
        }
    }
    
    class func showLogo(text:String = "",image:UIImage? = nil,showedFinish:PTActionTask? = nil) {
        let layoutView = PTLayoutButton()
        layoutView.layoutStyle = .leftImageRightTitle
        layoutView.midSpacing = 0
        var imageSize:CGFloat = 0
        if let image = image {
            layoutView.imageSize = CGSize(width: 24, height: 24)
            layoutView.normalImage = image
            imageSize = 24
        }
        layoutView.normalTitle = text
        layoutView.normalTitleFont = .appfont(size: 14)
        layoutView.normalTitleColor = .white
        var buttonW = UIView.sizeFor(string: text, font: layoutView.normalTitleFont,height: 24).width + imageSize + layoutView.midSpacing + 40
        let maxWidth = (CGFloat.kSCREEN_WIDTH - PTAppBaseConfig.share.defaultViewSpace * 2)
        var baseHeight:CGFloat = 56
        if buttonW >= maxWidth {
            buttonW = maxWidth
            let buttonHeight = UIView.sizeFor(string: text, font: layoutView.normalTitleFont,width: maxWidth).height
            if buttonHeight > 56 {
                baseHeight = buttonHeight + 32
            }
        }
        
        layoutView.frame = CGRectMake(0, 0, buttonW, baseHeight)
        layoutView.isUserInteractionEnabled = false
        
        let hud = PTProgressHUD.showOnWindow()
        hud?.mode = .customView(layoutView)
        hud?.blurEffectStyle = .dark
        hud?.bezelColor = .black.withAlphaComponent(0.6)
        hud?.hide(animated: true, afterDelay: 1.5)
        hud?.completionBlock = {
            showedFinish?()
        }
    }
}

class PTDashboardConfig: NSObject,@unchecked Sendable  {
    static let shared = PTDashboardConfig()
    
    var appMainColor:DynamicColor {
        return PTBluetoothServerManager.shared.latestData3?.dashboardColor.getColor() ?? PTConfigColor.blue.getColor()
    }
    
    var appUniIsMetric:Bool {
        return PTBluetoothServerManager.shared.latestData3?.isMetric ?? true
    }
    
    var appShowUniLabel:String {
        return PTDashboardConfig.shared.appUniIsMetric ? PTConfigUnit.metric.getTypeName() : PTConfigUnit.imperial.getTypeName()
    }
    
    func appShowMileage(_ km:Double) -> Double {
        let value = appUniIsMetric ? km : (km * kmToMilOffset)
        return value
    }
    
    func appShowMileageValueString(_ km:Double) -> String{
        let value = PTDashboardConfig.shared.appShowMileage(km)
        return String(format: "%.2f", value)
    }
    
    @MainActor class func baseNormalCellModel(leftSpacing:CGFloat? = nil,
                                              contentLeftSpacing:CGFloat = 0,
                                              name:String = "",
                                              nameFont:UIFont = .appfont(size: 13),
                                              nameColor:DynamicColor? = .gray,
                                              nameAtt:ASAttributedString? = nil,
                                              desc:String = "",
                                              descTextColor:DynamicColor = .white,
                                              descFont:UIFont = .appfont(size: 16),
                                              content:String = "",
                                              contentTextColor:DynamicColor = .lightGray,
                                              contentFont:UIFont = .appfont(size: 16),
                                              contentAtt:ASAttributedString? = nil,
                                              leftIcon:Any? = nil,
                                              imageTopOffset:CGFloat = 0,
                                              imageBottomOffset:CGFloat = 0,
                                              accessoryType:PTFusionShowAccessoryType = .NoneAccessoryView,
                                              accessoryImage:Any? = nil,
                                              accessorySize:CGSize = CGSizeMake(14, 14),
                                              switchThumbTintColor:DynamicColor? = nil,
                                              switchOnTinColor:DynamicColor = .lightGray,
                                              switchTintColor:DynamicColor = .lightGray,
                                              rightSapcing:CGFloat = 0,
                                              contentRightSpacing:CGFloat = 0,
                                              lineType:PTFusionLineType = .NO,
                                              bottomColor:DynamicColor = .lightGray,
                                              bottomlineHeight:CGFloat = 1) -> PTFusionCellModel {
        let model = PTFusionCellModel()
        model.leftSpace = leftSpacing ?? PTAppBaseConfig.share.defaultViewSpace
        if let nameAtt = nameAtt {
            model.nameAttr = nameAtt
        } else if !name.stringIsEmpty() {
            model.name = name
            model.cellFont = nameFont
            model.nameColor = nameColor ?? .white
        }
        
        if !desc.stringIsEmpty() {
            model.cellDescFont = descFont
            model.desc = desc
            model.descColor = descTextColor
        }
        
        if let contentAtt = contentAtt {
            model.contentAttr = contentAtt
        } else if !content.stringIsEmpty() {
            model.contentFont = contentFont
            model.content = content
            model.contentTextColor = contentTextColor
        }
            
        if let leftIcon = leftIcon {
            model.leftImage = leftIcon
            model.contentLeftSpace = contentLeftSpacing
        }
        model.imageTopOffset = imageTopOffset
        model.imageBottomOffset = imageBottomOffset
        
        model.accessoryType = accessoryType
        switch accessoryType {
        case .Switch:
            model.switchThumbTintColor = switchThumbTintColor ?? PTDashboardConfig.shared.appMainColor
            model.switchOnTinColor = switchOnTinColor
            model.switchTintColor = switchTintColor
        case .DisclosureIndicator:
            model.disclosureIndicatorImage = accessoryImage
            model.moreDisclosureIndicatorSize = accessorySize
        default:
            break
        }
        
        model.rightSpace = rightSapcing
        model.contentRightSpace = contentRightSpacing

        model.haveLine = lineType
        model.bottomLineColor = bottomColor
        model.bottomLineHeight = bottomlineHeight

        return model
    }

}

//MARK: Language
extension PTDashboardConfig {
    class func languageFunc(text:String) ->String {
        return text.localized(using: nil,in: Bundle.main)
    }
    
    static func language(key:String, _ args: CVarArg...) ->String {
        String(format: PTDashboardConfig.languageFunc(text: key), args)
    }
}
