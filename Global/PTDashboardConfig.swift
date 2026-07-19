//
//  PTDashboardConfig.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 19/7/2026.
//

import UIKit
import PooTools

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

class PTDashboardConfig: NSObject {
    static let shared = PTDashboardConfig()
}
