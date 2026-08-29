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
    
    var vcLoaded:Bool = false
    // EN: Keep each navigation controller alive and rebuild only lightweight tab metadata on refresh.
    // ES: Conservamos cada controlador de navegación y reconstruimos solo la configuración ligera al actualizar.
    // 中文：缓存每个导航控制器，刷新时只重建轻量级 Tab 配置。
    private lazy var tabbarViewControllers: [UIViewController] = {
        let homeNav = PTBaseNavControl(rootViewController: PTMotoInfoViewController())
        let navigationNav = PTBaseNavControl(rootViewController: PTMotoNavigationViewController())
        let collectedNav = PTBaseNavControl(rootViewController: PTDataCollectedViewController())
        let pttNav = PTBaseNavControl(rootViewController: PTPTTViewController())
        let settingNav = PTBaseNavControl(rootViewController: PTMotoSettingViewController())
        return [homeNav, navigationNav, collectedNav, pttNav, settingNav]
    }()

//    text.document
    func tabbarItems() -> [PTTabBarItemConfig] {
        let homeNormalImage = UIImage(.bicycle).withTintColor(.grayCA, renderingMode: .alwaysOriginal)
        let homeSelectedImage = UIImage(.bicycle).withTintColor(PTDashboardConfig.shared.appMainColor, renderingMode: .alwaysOriginal)
        let homeTitle = "Moto"
        let homeTab = PTTabBarItemConfig(title: homeTitle, content: PTTabBarImageContent(normal: homeNormalImage, selected: homeSelectedImage),viewController: tabbarViewControllers[0])
        
        let navigationNormalImage = UIImage(.map).withTintColor(.grayCA, renderingMode: .alwaysOriginal)
        let navigationSelectedImage = UIImage(.map).withTintColor(PTDashboardConfig.shared.appMainColor, renderingMode: .alwaysOriginal)
        let navigationTitle = PTDashboardConfig.languageFunc(text: "tab_navigation")
        let navigationTab = PTTabBarItemConfig(title: navigationTitle, content: PTTabBarImageContent(normal: navigationNormalImage, selected: navigationSelectedImage),viewController: tabbarViewControllers[1])
                
        let collectedNormalImage = UIImage(.folder).withTintColor(.grayCA, renderingMode: .alwaysOriginal)
        let collectedSelectedImage = UIImage(.folder).withTintColor(PTDashboardConfig.shared.appMainColor, renderingMode: .alwaysOriginal)
        let collectedTitle = PTDashboardConfig.languageFunc(text: "Data")
        let collectedTab = PTTabBarItemConfig(title: collectedTitle, content: PTTabBarImageContent(normal: collectedNormalImage, selected: collectedSelectedImage),viewController: tabbarViewControllers[2])
        
        let pttNormalImage = UIImage(.radio).withTintColor(.grayCA, renderingMode: .alwaysOriginal)
        let pttSelectedImage = UIImage(.radio).withTintColor(PTDashboardConfig.shared.appMainColor, renderingMode: .alwaysOriginal)
        let pttTitle = PTDashboardConfig.languageFunc(text: "PTT")
        let pttTab = PTTabBarItemConfig(title: pttTitle, content: PTTabBarImageContent(normal: pttNormalImage, selected: pttSelectedImage),viewController: tabbarViewControllers[3])

        let settingNormalImage = UIImage(.gear).withTintColor(.grayCA, renderingMode: .alwaysOriginal)
        let settingSelectedImage = UIImage(.gear).withTintColor(PTDashboardConfig.shared.appMainColor, renderingMode: .alwaysOriginal)
        let settingTitle = PTDashboardConfig.languageFunc(text: "tab_setting")
        let settingTab = PTTabBarItemConfig(title: settingTitle, content: PTTabBarImageContent(normal: settingNormalImage, selected: settingSelectedImage),viewController: tabbarViewControllers[4])

        return [homeTab,navigationTab,collectedTab,pttTab,settingTab]
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        // 让系统读取我们 Manager 中维护的当前状态
        return StatusBarManager.shared.style
    }

    override var prefersStatusBarHidden: Bool {
        return StatusBarManager.shared.isHidden
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return StatusBarManager.shared.animation
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configure(items: tabbarItems())
        
        ptCustomBar.didSelectIndex = { [weak self] index in
            self?.selectedIndex = index
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(dashBoardReload), name: MotorcycleDashBoardChange, object: nil)
        
        pt_observerLanguage {
            if self.vcLoaded {
                PTAppBaseConfig.share.tabSelectedColor = PTDashboardConfig.shared.appMainColor
                self.setCenter(items: self.tabbarItems())
            }
        }
        vcLoaded = true
    }
    
    override func configure(items: [PTTabBarItemConfig]) {
        super.configure(items: items)
        self.setCenter(items: items)
    }
    
    private func setCenter(items: [PTTabBarItemConfig]) {
//        let centerButton = PTTabBarImageContent(normal: LottieAnimation.named("camera") as Any, selected: LottieAnimation.named("camera"))
        ptCustomBar.setup(configs: items,layoutStyle: .normal)
    }
    
    @objc func dashBoardReload() {
        PTAppBaseConfig.share.tabSelectedColor = PTDashboardConfig.shared.appMainColor
        ptCustomBar.setup(configs: tabbarItems())
    }
}
