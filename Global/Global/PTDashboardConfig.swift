//
//  PTDashboardConfig.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 19/7/2026.
//

import UIKit
import PooTools
import AttributedString
import FlagKit
import SwifterSwift
import SnapKit
import SafeSFSymbols

let RPMUnit = "x1000 r/min"

enum PTCollectionEmptyType {
    case Normal
    case Loading
    case Empty
}

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
    
    var naving:Bool = false
    var blueConnected:Bool = false
    var appInBackground:Bool = false
    
    var currentRouteDistance:Double = 0
    
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

    var lauguageModels:[PTLanguageModel] {
        let cn = PTLanguageModel()
        cn.name = "简体中文"
        cn.keyName = "zh"
        cn.localozableName = "zh-Hans"
        cn.isSelected = PTMotoUserDefaultStruct.userSetLanguage == cn.keyName
        cn.flag = Flag(countryCode: "CN")!.originalImage
        cn.voiceValue = "zh-CN"
        
        let cn_tw = PTLanguageModel()
        cn_tw.name = "繁體中文"
        cn_tw.keyName = "tw"
        cn_tw.localozableName = "zh-Hant"
        cn_tw.isSelected = PTMotoUserDefaultStruct.userSetLanguage == cn_tw.keyName
        cn_tw.flag = Flag(countryCode: "TW")!.originalImage
        cn_tw.voiceValue = "zh-TW"

        let en = PTLanguageModel()
        en.name = "English"
        en.keyName = "en"
        en.localozableName = "en"
        en.isSelected = PTMotoUserDefaultStruct.userSetLanguage == en.keyName
        en.flag = Flag(countryCode: "US")!.originalImage
        en.voiceValue = "en-US"

        let tr = PTLanguageModel()
        tr.name = "Turkish"
        tr.keyName = "tr"
        tr.localozableName = "tr"
        tr.isSelected = PTMotoUserDefaultStruct.userSetLanguage == tr.keyName
        tr.flag = Flag(countryCode: "TR")!.originalImage
        tr.voiceValue = "tr-TR"

        return [cn,cn_tw,tr,en]
    }
    
    static func appIsInChinese() ->Bool {
        switch PTMotoUserDefaultStruct.userSetLanguage {
        case "zh","tw":
            return true
        default:
            return false
        }
    }

    static func globalLanguageAlert() {
        let map = PTDashboardConfig.shared.lauguageModels.map { value in
            return value.name
        }
        UIAlertController.base_alertVC(title: PTDashboardConfig.languageFunc(text: "language_set_title"), titleColor: PTDashboardConfig.shared.appMainColor, titleFont: .appfont(size: 16), okBtns: map, cancelBtn: PTDashboardConfig.languageFunc(text: "button_cancel"), showIn: PTUtils.getCurrentVC(), cancelBtnColor: .systemBlue, doneBtnColors: [.systemBlue], moreBtn:  { index, title in
            PTMotoUserDefaultStruct.userSetLanguage = PTDashboardConfig.shared.lauguageModels[index].keyName
            PTLanguage.share.language = PTDashboardConfig.shared.lauguageModels[index].localozableName
        })
    }
    
}

//MARK: Language
extension PTDashboardConfig {
    /// EN: Resolve a key from the compiled String Catalog using the app-selected locale.
    /// ES: Resuelve una clave del String Catalog compilado usando el locale elegido por la app.
    /// 中文：使用 App 当前选择的语言，从编译后的 String Catalog 解析文案。
    class func languageFunc(text:String) ->String {
        text.localized(using: "Localizable", in: .main)
    }
    
    static func language(key: String, _ args: CVarArg...) -> String {
        // EN: Format the collected arguments directly; optional parameters after a variadic parameter can box the array as one value.
        // ES: Formatear directamente los argumentos reunidos; los parámetros opcionales después de un variádico pueden empaquetar el array como un solo valor.
        // 中文：直接格式化收集到的参数；可变参数后面的可选参数可能会把整个数组错误地装箱成一个值。
        let localizedText = key.localized(using: "Localizable", in: .main)
        guard !args.isEmpty else { return localizedText }
        return String(format: localizedText,
                      locale: PTLanguage.share.locale,
                      arguments: args)
    }
}

extension PTDashboardConfig {
    @MainActor class func baseCollectionConfig(footerRefresh:Bool = true,emptyConfig:PTEmptyDataViewConfig? = nil) ->PTCollectionViewConfig {
        let collectionConfig = PTCollectionViewConfig()
        collectionConfig.emptyShowType = .ThirtyParty
        collectionConfig.emptyViewConfig = emptyConfig ?? PTDashboardConfig.gobalListEmptySet()
        collectionConfig.showEmptyAlert = true
        collectionConfig.footerRefresh = footerRefresh
        if footerRefresh {
            collectionConfig.footerRefreshTextColor = .gray7F
            collectionConfig.footerRefreshTextFont = .appfont(size: 13)
            collectionConfig.footerRefreshNoMoreData = PTDashboardConfig.languageFunc(text: "list_nomore")
        }
        return collectionConfig
    }
    
    @MainActor class public func gobalListEmptySet(image:String = "placeholder",emptyString:String? = nil,width:CGFloat? = nil,emptyTap:PTActionTask? = nil) -> PTEmptyDataViewConfig {
        let emptyStringValue = emptyString ?? PTDashboardConfig.languageFunc(text: "empty_data_normal")
        let newWidth = width ?? (CGFloat.kSCREEN_WIDTH - 24)
        let emptyConfig = PTEmptyDataViewConfig()
        let emptyHeight:CGFloat = 188
        let emptyView = PTDashboardConfig.emptyEmptyView(image: image, emptyString: emptyStringValue,viewWidth: newWidth,emptyTap: emptyTap)
        emptyView.frame = CGRectMake(0, 0, newWidth, emptyHeight)
        emptyConfig.customerView = emptyView
        emptyConfig.verticalOffSet = -(emptyHeight / 2)
        emptyConfig.image = nil
        return emptyConfig
    }
    
    @MainActor class func emptyEmptyView(image:String = "placeholder",emptyString:String? = nil,viewWidth:CGFloat? = nil,emptyTap:PTActionTask? = nil) ->UIView {
        
        let emptyStringValue = emptyString ?? PTDashboardConfig.languageFunc(text: "empty_data_normal")

        let newWidth = viewWidth ?? (CGFloat.kSCREEN_WIDTH - 24)
        let view = UIView()
        
        let couponImage = UIImageView(image: UIImage(named: image))
        couponImage.contentMode = .scaleAspectFill
        couponImage.clipsToBounds = true
        
        let emptyLabel = UILabel()
        emptyLabel.font = .appfont(size: 14)
        emptyLabel.text = emptyStringValue
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .gray7F
        emptyLabel.numberOfLines = 0
        
        view.addSubviews([couponImage,emptyLabel])
        couponImage.snp.makeConstraints { make in
            if newWidth > 160 {
                make.size.equalTo(160)
            } else {
                make.size.equalTo(newWidth * 0.75)
            }
            make.centerX.equalToSuperview()
            make.top.equalToSuperview()
        }
        
        emptyLabel.snp.makeConstraints { make in
            make.top.equalTo(couponImage.snp.bottom).offset(8)
            make.left.right.equalToSuperview().inset(10)
        }
        
        let tap = UITapGestureRecognizer { sender in
            PTGCDManager.shared.runOnMain {
                emptyTap?()
            }
        }
        view.addGestureRecognizer(tap)
        return view
    }
    
    @MainActor static func setEmptyConfig(empty:PTCollectionEmptyType,loadCallback:PTActionTask? = nil) -> PTEmptyDataViewConfig {
        let imageName = "placeholder"
        var emptyString = ""
        switch empty {
        case .Normal:
            emptyString = PTDashboardConfig.languageFunc(text: "empty_data_normal")
        case .Loading:
            emptyString = PTDashboardConfig.languageFunc(text: "alert_loading")
        case .Empty:
            emptyString = PTDashboardConfig.languageFunc(text: "empty_data_empty")
        }
        let listEmptyConfig = PTDashboardConfig.gobalListEmptySet(image:imageName,emptyString: emptyString,emptyTap:loadCallback)
        return listEmptyConfig
    }
}

extension PTDashboardConfig {
    @MainActor class func gobalMediaBrowserConfig() -> PTMediaBrowserConfig {
        let share = PTMediaBrowserConfig.share
        share.closeViewerImage = UIImage(.chevron.compactLeft).withTintColor(.white, renderingMode: .alwaysOriginal)
        share.viewerFont = .appfont(size: 13)
        share.titleFont = PTAppBaseConfig.share.navTitleFont
        share.imageReloadButton = PTDashboardConfig.languageFunc(text: "Image reload fail")
        share.playButtonImage = UIImage(.play.fill)
        share.playButtonImageSize = .init(width: 64, height: 64)
        return share
    }
    
    @MainActor
    static func globalImageBrowser(mediaModels:[PTMediaBrowserModel],
                                   showIndex:Int = 0,
                                   dismissBarStatus:VCStatusBarChangeStatusType = .Auto,
                                   customAction:[String] = [],
                                   customActionCallback:PTViewerEXIndexBlock? = nil,
                                   currentDataIndexCallback:((Int)->Void)? = nil,
                                   showed:PTActionTask? = nil) {
        let dismissBarStatusRawValue = dismissBarStatus.rawValue
        let mediaBroswer = PTDashboardConfig.gobalMediaBrowserConfig()
        if customAction.count > 0 {
            mediaBroswer.actionType = .DIY
            mediaBroswer.moreActionEX = customAction
        } else {
            mediaBroswer.actionType = .Empty
        }
        mediaBroswer.dynamicBackground = true
        mediaBroswer.showMore = PTDashboardConfig.languageFunc(text: "More")
        mediaBroswer.moreActionImage = UIImage(.ellipsis.circleFill)

        let vc = PTMediaBrowserController(mediaData: mediaModels)
        vc.defaultIndex = showIndex
        vc.viewDismissBlock = {
            Task { @MainActor in
                if let current = PTUtils.getCurrentVC() as? PTMotoBaseViewController {
                    let status = VCStatusBarChangeStatusType(rawValue: dismissBarStatusRawValue) ?? .Auto
                    current.changeStatusBar(type: status)
                }
            }
        }
        vc.viewMoreActionBlock = customActionCallback
        vc.browserCurrentDataBlock = currentDataIndexCallback
        let nav = PTBaseNavControl(rootViewController: vc)
        UIViewController.currentPresentToSheet(vc: nav,sizes: [.fullscreen],completion: {
            showed?()
        }, dismissPanGes: false)
    }

}
