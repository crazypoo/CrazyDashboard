//
//  PTMotoUserDefaultStruct.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 21/7/2026.
//

import UIKit
import PooTools

struct PTMotoUserDefaultStruct {
    @PTUserDefault(withKey: "PTAppFirst", defaultValue: true) public static var appFirst:Bool
    @PTUserDefault(withKey: "PTUserLanguage", defaultValue: "zh") public static var userSetLanguage:String
    @PTUserDefault(withKey: "ble_data_hex_get", defaultValue: false) public static var BleTestDataGet:Bool
    @PTUserDefault(withKey: "NavMute", defaultValue: false) public static var NavMute:Bool
    @PTUserDefault(withKey: "MotoLinkedAPP", defaultValue: false) public static var MotoLinkedAPP:Bool
    @PTUserDefault(withKey: "CoachFirst", defaultValue: true) public static var CoachFirst:Bool
    @PTUserDefault(withKey: "OBDID", defaultValue: "") public static var OBDID:String
    // EN: Automatic OBD connection is opt-in so app launch never starts a scan implicitly.
    // ES: La conexión OBD automática requiere activación explícita para que el lanzamiento no inicie un escaneo.
    // 中文：OBD 自动连接必须显式开启，确保 App 启动不会隐式开始扫描。
    @PTUserDefault(withKey: "OBDAutoConnectEnabled", defaultValue: false) public static var OBDAutoConnectEnabled:Bool

    // EN: Intercom restoration is opt-in so a cold launch never starts peer discovery or audio services.
    // ES: La restauración del intercomunicador requiere activación explícita para que el arranque no inicie descubrimiento ni audio.
    // 中文：对讲状态恢复必须显式开启，确保冷启动不会自动组网或启动音频服务。
    @PTUserDefault(withKey: "PTTLaunchAutoRestoreEnabled", defaultValue: false) public static var PTTLaunchAutoRestoreEnabled:Bool

    // EN: Keep the explicit PTT nickname in the shared preference layer without starting audio services.
    // ES: Conserva el apodo explícito de PTT en preferencias compartidas sin iniciar servicios de audio.
    // 中文：将用户明确设置的 PTT 昵称放在共享偏好层，读取时不会启动音频服务。
    @PTUserDefault(withKey: "PT_CustomUserName", defaultValue: "") public static var PTTCustomUserName:String

    // EN: Anti-theft monitoring is a user opt-in and never arms from stale launch data.
    // ES: La vigilancia antirrobo requiere consentimiento del usuario y nunca se arma con datos antiguos al iniciar.
    // 中文：防盗监控必须由用户主动开启，冷启动不会依据旧数据自动布防。
    @PTUserDefault(withKey: "PTAntiTheftMonitoringEnabled", defaultValue: false) public static var PTAntiTheftMonitoringEnabled:Bool
    
    @PTUserDefault(withKey: "PTMotoSafteyMileValue", defaultValue: 2500) public static var PTMotoSafteyMileValue:Double
}
