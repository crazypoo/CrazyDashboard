//
//  PTCarPlayContainerViewController.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 6/8/2026.
//

import UIKit
import PooTools
import SnapKit

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

@MainActor
final class PTCarPlayContainerViewController: UIViewController {

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
        // EN: Forward appearance transitions because this controller is inserted after the CarPlay scene is visible.
        // ES: Reenviamos las transiciones de apariencia porque este controlador se inserta después de mostrar la escena de CarPlay.
        // 中文：CarPlay 场景已经显示后才插入子控制器，因此必须显式转发生命周期。
        loadViewIfNeeded()
        let shouldForwardAppearance = view.window != nil

        // 1. 如果盒子里已经有其他界面，先把它安全地请出去
        if let oldVC = currentChildVC {
            if shouldForwardAppearance {
                oldVC.beginAppearanceTransition(false, animated: false)
            }
            oldVC.willMove(toParent: nil)
            oldVC.view.removeFromSuperview()
            oldVC.removeFromParent()
            if shouldForwardAppearance {
                oldVC.endAppearanceTransition()
            }
        }
        
        // 2. 把新界面请进盒子
        addChild(viewController)
        viewController.loadViewIfNeeded()
        if shouldForwardAppearance {
            viewController.beginAppearanceTransition(true, animated: false)
        }
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        
        self.view.addSubview(viewController.view)
        viewController.view.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
        }
        viewController.didMove(toParent: self)
        
        // 更新当前界面记录
        currentChildVC = viewController
        prepareCurrentChildForDisplay()

        if shouldForwardAppearance {
            viewController.endAppearanceTransition()
        }
    }

    // EN: Flush the first layout pass so CarPlay does not wait for the phone scene to wake.
    // ES: Forzamos el primer diseño para que CarPlay no espere a que se despierte la escena del teléfono.
    // 中文：强制完成首轮布局，避免 CarPlay 等待手机场景唤醒后才刷新画面。
    func prepareCurrentChildForDisplay() {
        guard let childVC = currentChildVC else { return }

        loadViewIfNeeded()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        childVC.view.setNeedsLayout()
        childVC.view.layoutIfNeeded()
    }
    
    func clearChildVC() {
        if let oldVC = currentChildVC {
            let shouldForwardAppearance = viewIfLoaded?.window != nil
            if shouldForwardAppearance {
                oldVC.beginAppearanceTransition(false, animated: false)
            }
            oldVC.willMove(toParent: nil)
            oldVC.view.removeFromSuperview()
            oldVC.removeFromParent()
            if shouldForwardAppearance {
                oldVC.endAppearanceTransition()
            }
            currentChildVC = nil
            PTNSLogConsole("🧹 [CarPlay] 底层容器已清空。")
        }
    }
}
