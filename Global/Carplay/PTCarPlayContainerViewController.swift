//
//  PTCarPlayContainerViewController.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 6/8/2026.
//

import UIKit
import PooTools

class PTCarPlayPassThroughView: UIView {
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 先让系统按照常规逻辑找出当前被点击的 View
        let hitView = super.hitTest(point, with: event)
        
        if hitView == self {
            return nil
        }
        
        if let childRootView = self.subviews.first, hitView == childRootView {
            return nil
        }        
        return hitView
    }
}

class PTCarPlayContainerViewController: UIViewController {

    // 记录当前正在显示的界面
    private var currentChildVC: UIViewController?
    
    override func loadView() {
        self.view = PTCarPlayPassThroughView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.isUserInteractionEnabled = true
    }
    
    /// 无缝切换到底层 UIViewController
    func switchTo(viewController: UIViewController) {
        // 1. 如果盒子里已经有其他界面，先把它安全地请出去
        if let oldVC = currentChildVC {
            oldVC.willMove(toParent: nil)
            oldVC.view.removeFromSuperview()
            oldVC.removeFromParent()
        }
        
        // 2. 把新界面请进盒子
        addChild(viewController)
        viewController.view.frame = self.view.bounds
        // 确保新界面的大小始终跟随容器变化 (应对 CarPlay 的分屏模式)
        viewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        self.view.addSubview(viewController.view)
        viewController.didMove(toParent: self)
        
        // 更新当前界面记录
        currentChildVC = viewController
    }
    
    func clearChildVC() {
        if let oldVC = currentChildVC {
            oldVC.willMove(toParent: nil)
            oldVC.view.removeFromSuperview()
            oldVC.removeFromParent()
            currentChildVC = nil
            PTNSLogConsole("🧹 [CarPlay] 底层容器已清空。")
        }
    }
}
