//
//  PTBaseTabbarController.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 19/7/2026.
//

import UIKit
import PooTools
import SafeSFSymbols

class PTMotoBaseTabbarController: PTBaseTabBarViewController {
    
    func tabbarItems() -> [PTTabBarItemConfig] {
        let homeNormalImage = UIImage(.car)
        let homeSelectedImage = UIImage(.car).withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
        let homeTitle = "Moto"
        let home = PTMotoInfoViewController()
        let homeNav = PTBaseNavControl(rootViewController: home)
        let homeTab = PTTabBarItemConfig(title: homeTitle, content: PTTabBarImageContent(normal: homeNormalImage, selected: homeSelectedImage),viewController: homeNav)
        
        let navigationNormalImage = UIImage(.map)
        let navigationSelectedImage = UIImage(.map).withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
        let navigationTitle = "Navigation"
        let navigation = PTMotoNavigationViewController()
        let navigationNav = PTBaseNavControl(rootViewController: navigation)
        let navigationTab = PTTabBarItemConfig(title: navigationTitle, content: PTTabBarImageContent(normal: navigationNormalImage, selected: navigationSelectedImage),viewController: navigationNav)
                
        let settingNormalImage = UIImage(.gear)
        let settingSelectedImage = UIImage(.gear).withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
        let settingTitle = "Setting"
        let setting = PTMotoSettingViewController()
        let settingNav = PTBaseNavControl(rootViewController: setting)
        let settingTab = PTTabBarItemConfig(title: settingTitle, content: PTTabBarImageContent(normal: settingNormalImage, selected: settingSelectedImage),viewController: settingNav)

        return [homeTab,navigationTab,settingTab]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        configure(items: tabbarItems())
        
        ptCustomBar.didSelectIndex = { [weak self] index in
            self?.selectedIndex = index
        }
    }
    
    override func configure(items: [PTTabBarItemConfig]) {
        super.configure(items: items)
        self.setCenter(items: items)
    }
    
    private func setCenter(items: [PTTabBarItemConfig]) {
//        let centerButton = PTTabBarImageContent(normal: LottieAnimation.named("camera") as Any, selected: LottieAnimation.named("camera"))
        ptCustomBar.setup(configs: items,layoutStyle: .normal)
    }
}
