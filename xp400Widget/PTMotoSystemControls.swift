//
//  PTMotoSystemControls.swift
//  xp400Widget
//
//  EN: Safe iOS 18 system controls that only open existing read-only app routes.
//  ES: Controles seguros de iOS 18 que solo abren rutas existentes de lectura.
//  中文：iOS 18 系统控制只打开现有的只读 App 路由，不直接发送车辆指令。
//

import AppIntents
import SwiftUI
import WidgetKit

#if os(iOS)
@available(iOS 18.0, *)
private enum PTMotoControlURLs {
    nonisolated static let hud = URL(string: "xp400://action/openhud")!
    nonisolated static let readiness = URL(string: "xp400://action/opensafety")!
    nonisolated static let parking = URL(string: "xp400://action/opengarage")!
    nonisolated static let alarms = URL(string: "xp400://action/openalarms")!
}

// EN: HUD control only opens the dashboard screen; it never starts Bluetooth or OBD work.
// ES: El control HUD solo abre la pantalla del tablero; nunca inicia Bluetooth ni OBD.
// 中文：HUD 控件只打开仪表页面，不启动蓝牙或 OBD 操作。
@available(iOS 18.0, *)
struct PTMotoHUDControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.yd.PTSpeed.control.hud") {
            ControlWidgetButton(action: OpenURLIntent(PTMotoControlURLs.hud)) {
                Label(
                    LocalizedStringResource("control_hud", table: "Localizable"),
                    systemImage: "speedometer"
                )
            }
        }
    }
}

// EN: Readiness control opens the cached safety report without changing vehicle state.
// ES: El control de preparación abre el informe de seguridad almacenado sin cambiar el estado del vehículo.
// 中文：出发准备度控件只打开缓存的安全报告，不改变车辆状态。
@available(iOS 18.0, *)
struct PTMotoReadinessControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.yd.PTSpeed.control.readiness") {
            ControlWidgetButton(action: OpenURLIntent(PTMotoControlURLs.readiness)) {
                Label(
                    LocalizedStringResource("control_readiness", table: "Localizable"),
                    systemImage: "checkmark.shield"
                )
            }
        }
    }
}

// EN: Parking control opens the garage and does not request location or vehicle data.
// ES: El control de estacionamiento abre el garaje y no solicita ubicación ni datos del vehículo.
// 中文：停车控件只打开车库，不请求定位或车辆数据。
@available(iOS 18.0, *)
struct PTMotoParkingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.yd.PTSpeed.control.parking") {
            ControlWidgetButton(action: OpenURLIntent(PTMotoControlURLs.parking)) {
                Label(
                    LocalizedStringResource("control_parking", table: "Localizable"),
                    systemImage: "parkingsign.circle"
                )
            }
        }
    }
}

// EN: Alarm control opens the local alarm center and never sends an alarm command to the motorcycle.
// ES: El control de alarmas abre el centro local y nunca envía comandos de alarma a la motocicleta.
// 中文：提醒控件只打开本地提醒中心，绝不向摩托车发送报警指令。
@available(iOS 18.0, *)
struct PTMotoAlarmsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.yd.PTSpeed.control.alarms") {
            ControlWidgetButton(action: OpenURLIntent(PTMotoControlURLs.alarms)) {
                Label(
                    LocalizedStringResource("control_alarms", table: "Localizable"),
                    systemImage: "bell.badge"
                )
            }
        }
    }
}
#endif
