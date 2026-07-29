//
//  PTDashboardBaseView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 29/7/2026.
//

import UIKit

public class PTDashboardBaseView: UIView {

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 先调用系统的默认实现，找出当前点击的到底是哪个子视图
        let hitView = super.hitTest(point, with: event)
        
        // 如果点中的是我们这个全屏的透明底层容器自身，而不是里面的面板或按钮
        if hitView == self {
            // 返回 nil，让触摸事件直接穿透到后面的 Window 或 ViewController 上
            return nil
        }
        
        // 如果点中的是黑色的 backgroundView，或者是关闭/过滤按钮，就正常返回它，拦截触摸
        return hitView
    }
}
