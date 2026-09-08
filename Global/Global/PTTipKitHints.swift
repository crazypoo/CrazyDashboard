//
//  PTTipKitHints.swift
//  CrazyDashboard
//
//  EN: Small contextual TipKit hints for the safe rider workflows.
//  ES: Pequeñas sugerencias contextuales de TipKit para los flujos seguros del piloto.
//  中文：为安全骑手流程提供小型上下文 TipKit 提示。
//

import SwiftUI
import TipKit
import UIKit

@available(iOS 17.0, *)
struct PTVehicleBindingTip: Tip {
    var title: Text {
        Text("tip_vehicle_binding_title")
    }

    var message: Text? {
        Text("tip_vehicle_binding_message")
    }

    var image: Image? {
        Image(systemName: "motorcycle")
    }
}

@available(iOS 17.0, *)
struct PTMountCalibrationTip: Tip {
    var title: Text {
        Text("tip_mount_calibration_title")
    }

    var message: Text? {
        Text("tip_mount_calibration_message")
    }

    var image: Image? {
        Image(systemName: "gyroscope")
    }
}

@available(iOS 17.0, *)
struct PTDashboardConfigurationTip: Tip {
    var title: Text {
        Text("tip_dashboard_configuration_title")
    }

    var message: Text? {
        Text("tip_dashboard_configuration_message")
    }

    var image: Image? {
        Image(systemName: "checkmark.shield")
    }
}

@available(iOS 17.0, *)
enum PTTipKitHintFactory {
    // EN: Embed TipView in UIKit without exposing SwiftUI state to the surrounding controllers.
    // ES: Inserta TipView en UIKit sin exponer el estado de SwiftUI a los controladores.
    // 中文：在 UIKit 中嵌入 TipView，不把 SwiftUI 状态暴露给外层控制器。
    static func makeViewController<T: Tip>(_ tip: T) -> UIViewController {
        let rootView = TipView(tip)
            .padding(.horizontal, 4)
            .background(Color.clear)
        let controller = UIHostingController(rootView: rootView)
        controller.view.backgroundColor = .clear
        return controller
    }
}
